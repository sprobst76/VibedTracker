/**
 * VibedTracker Time Tracking Manager
 * Handles loading, decrypting, and displaying time entries
 */

const TimeTrackingManager = {
    entries: [],
    key: null,
    currentEditEntry: null,

    /**
     * Initialize the manager - load key and fetch data
     */
    async init() {
        // Load encryption key from session
        this.key = await VTCrypto.loadKey();
        if (!this.key) {
            console.log('No encryption key found');
            return false;
        }

        // Fetch and decrypt entries
        await this.loadEntries();
        return true;
    },

    /**
     * Fetch encrypted entries from server and decrypt them
     */
    async loadEntries() {
        try {
            const response = await fetch('/web/api/data?type=work_entry', {
                credentials: 'same-origin'
            });

            if (!response.ok) {
                throw new Error('Failed to fetch data');
            }

            const data = await response.json();
            this.entries = [];

            // Decrypt each entry
            for (const item of data.items || []) {
                try {
                    const decrypted = await VTCrypto.decrypt(
                        this.key,
                        item.encrypted_blob,
                        item.nonce
                    );
                    this.entries.push({
                        id: item.id,
                        localId: item.local_id,
                        ...decrypted
                    });
                } catch (e) {
                    console.error('Failed to decrypt entry:', e);
                }
            }

            // Sort by start date descending (newest first)
            this.entries.sort((a, b) => new Date(b.start) - new Date(a.start));

            console.log(`Loaded ${this.entries.length} entries`);
            return this.entries;

        } catch (error) {
            console.error('Error loading entries:', error);
            return [];
        }
    },

    /**
     * Save an entry (create or update)
     */
    async saveEntry(entryData) {
        if (!this.key) {
            throw new Error('No encryption key');
        }

        // Generate local ID if new entry
        const localId = entryData.localId || entryData.key?.toString() || Date.now().toString();

        // Prepare data for encryption (match Flutter format)
        const dataToEncrypt = {
            key: parseInt(localId) || Date.now(),
            start: entryData.start,
            stop: entryData.stop || null,
            pauses: entryData.pauses || [],
            notes: entryData.notes || null,
            tags: entryData.tags || [],
            projectId: entryData.projectId || null,
            workModeIndex: entryData.workModeIndex || 0
        };

        // Encrypt
        const encrypted = await VTCrypto.encrypt(this.key, dataToEncrypt);

        // Save to server
        const response = await fetch('/web/api/entry', {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                local_id: localId,
                encrypted_blob: encrypted.blobBase64,
                nonce: encrypted.nonceBase64,
                data_type: 'work_entry'
            })
        });

        if (!response.ok) {
            const err = await response.json();
            throw new Error(err.error || 'Failed to save entry');
        }

        // Reload entries
        await this.loadEntries();
        return true;
    },

    /**
     * Delete an entry
     */
    async deleteEntry(localId) {
        const response = await fetch(`/web/api/entry/${localId}`, {
            method: 'DELETE',
            credentials: 'same-origin'
        });

        if (!response.ok) {
            const err = await response.json();
            throw new Error(err.error || 'Failed to delete entry');
        }

        // Reload entries
        await this.loadEntries();
        return true;
    },

    /**
     * Calculate total work duration for an entry in minutes
     */
    calculateEntryDuration(entry) {
        if (!entry.start) return 0;

        const start = new Date(entry.start);
        const end = entry.stop ? new Date(entry.stop) : new Date();

        let totalMinutes = (end - start) / 60000;

        // Subtract pauses
        if (entry.pauses && entry.pauses.length > 0) {
            for (const pause of entry.pauses) {
                if (pause.start) {
                    const pauseStart = new Date(pause.start);
                    const pauseEnd = pause.end ? new Date(pause.end) : new Date();
                    totalMinutes -= (pauseEnd - pauseStart) / 60000;
                }
            }
        }

        return Math.max(0, totalMinutes);
    },

    /**
     * Calculate statistics for today, this week, and this month
     */
    calculateStats() {
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

        // Start of week (Monday)
        const weekStart = new Date(today);
        const day = weekStart.getDay();
        const diff = weekStart.getDate() - day + (day === 0 ? -6 : 1);
        weekStart.setDate(diff);

        // Start of month
        const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

        let todayMinutes = 0;
        let weekMinutes = 0;
        let monthMinutes = 0;

        for (const entry of this.entries) {
            const entryStart = new Date(entry.start);
            const entryDate = new Date(entryStart.getFullYear(), entryStart.getMonth(), entryStart.getDate());
            const duration = this.calculateEntryDuration(entry);

            // Today
            if (entryDate.getTime() === today.getTime()) {
                todayMinutes += duration;
            }

            // This week
            if (entryDate >= weekStart) {
                weekMinutes += duration;
            }

            // This month
            if (entryDate >= monthStart) {
                monthMinutes += duration;
            }
        }

        return {
            today: this.formatDuration(todayMinutes),
            week: this.formatDuration(weekMinutes),
            month: this.formatDuration(monthMinutes),
            todayMinutes,
            weekMinutes,
            monthMinutes
        };
    },

    /**
     * Format minutes as HH:MM string
     */
    formatDuration(minutes) {
        if (!minutes || minutes < 0) return '0:00';
        const hours = Math.floor(minutes / 60);
        const mins = Math.round(minutes % 60);
        return `${hours}:${mins.toString().padStart(2, '0')}`;
    },

    /**
     * Get entries for a specific date
     */
    getEntriesForDate(date) {
        const targetDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        return this.entries.filter(entry => {
            const entryDate = new Date(entry.start);
            const entryDateOnly = new Date(entryDate.getFullYear(), entryDate.getMonth(), entryDate.getDate());
            return entryDateOnly.getTime() === targetDate.getTime();
        });
    },

    /**
     * Get recent entries (last N days)
     */
    getRecentEntries(days = 7) {
        const cutoff = new Date();
        cutoff.setDate(cutoff.getDate() - days);
        return this.entries.filter(entry => new Date(entry.start) >= cutoff);
    },

    /**
     * Get work mode label
     */
    getWorkModeLabel(index) {
        const modes = ['Arbeit', 'Deep Work', 'Meeting', 'Support', 'Administration'];
        return modes[index] || 'Arbeit';
    },

    /**
     * Get work mode color class
     */
    getWorkModeColor(index) {
        const colors = [
            'bg-blue-500',    // normal
            'bg-purple-500',  // deep work
            'bg-orange-500',  // meeting
            'bg-green-500',   // support
            'bg-gray-500'     // admin
        ];
        return colors[index] || 'bg-blue-500';
    },

    /**
     * Update dashboard statistics
     */
    updateDashboardStats() {
        const stats = this.calculateStats();

        // Update stat cards
        const todayEl = document.querySelector('[data-stat="today"]');
        const weekEl = document.querySelector('[data-stat="week"]');
        const monthEl = document.querySelector('[data-stat="month"]');

        if (todayEl) todayEl.textContent = stats.today;
        if (weekEl) weekEl.textContent = stats.week;
        if (monthEl) monthEl.textContent = stats.month;

        return stats;
    },

    /**
     * Render entries list in a container with edit/delete buttons
     */
    renderEntriesList(containerId, entries = null) {
        const container = document.getElementById(containerId);
        if (!container) return;

        const entriesToRender = entries || this.getRecentEntries(7);

        if (entriesToRender.length === 0) {
            container.innerHTML = `
                <div class="text-center py-8 text-gray-500 dark:text-gray-400">
                    <p>Keine Einträge gefunden</p>
                    <button onclick="openEntryModal()" class="mt-4 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white text-sm font-medium rounded-lg transition-colors">
                        Ersten Eintrag erstellen
                    </button>
                </div>
            `;
            return;
        }

        let currentDate = null;
        let html = '';

        for (const entry of entriesToRender) {
            const entryDate = new Date(entry.start);
            const dateStr = entryDate.toLocaleDateString('de-DE', {
                weekday: 'long',
                day: 'numeric',
                month: 'long'
            });

            // Add date header if new day
            if (dateStr !== currentDate) {
                if (currentDate !== null) {
                    html += '</div>'; // Close previous day's entries
                }
                html += `
                    <div class="mb-4">
                        <h3 class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2">${dateStr}</h3>
                `;
                currentDate = dateStr;
            }

            const duration = this.calculateEntryDuration(entry);
            const startTime = entryDate.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
            const endTime = entry.stop
                ? new Date(entry.stop).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })
                : 'läuft...';
            const modeColor = this.getWorkModeColor(entry.workModeIndex || 0);
            const modeLabel = this.getWorkModeLabel(entry.workModeIndex || 0);
            const localId = entry.localId || entry.key;

            html += `
                <div class="bg-white dark:bg-gray-800 rounded-lg p-4 mb-2 border border-gray-200 dark:border-gray-700 group hover:shadow-md transition-shadow">
                    <div class="flex items-center justify-between">
                        <div class="flex items-center space-x-3 flex-1">
                            <div class="w-2 h-8 ${modeColor} rounded-full"></div>
                            <div class="flex-1 min-w-0">
                                <div class="text-sm font-medium text-gray-900 dark:text-white">
                                    ${startTime} - ${endTime}
                                </div>
                                <div class="text-xs text-gray-500 dark:text-gray-400 truncate">
                                    ${modeLabel}${entry.notes ? ' - ' + this.escapeHtml(entry.notes) : ''}
                                </div>
                            </div>
                        </div>
                        <div class="flex items-center space-x-3">
                            <div class="text-right">
                                <div class="text-sm font-semibold text-gray-900 dark:text-white">
                                    ${this.formatDuration(duration)}
                                </div>
                                ${entry.pauses && entry.pauses.length > 0 ?
                                    `<div class="text-xs text-gray-400">${entry.pauses.length} Pause(n)</div>` : ''}
                            </div>
                            <div class="flex space-x-1 opacity-0 group-hover:opacity-100 transition-opacity">
                                <button onclick="editEntry('${localId}')" class="p-1.5 text-gray-400 hover:text-primary-600 dark:hover:text-primary-400 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors" title="Bearbeiten">
                                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/>
                                    </svg>
                                </button>
                                <button onclick="confirmDeleteEntry('${localId}')" class="p-1.5 text-gray-400 hover:text-red-600 dark:hover:text-red-400 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors" title="Löschen">
                                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                                    </svg>
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            `;
        }

        if (currentDate !== null) {
            html += '</div>'; // Close last day's entries
        }

        container.innerHTML = html;
    },

    /**
     * Escape HTML to prevent XSS
     */
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    },

    /**
     * Find entry by local ID
     */
    findEntry(localId) {
        return this.entries.find(e => e.localId === localId || e.key?.toString() === localId);
    }
};

// ==================== Global Modal Functions ====================

let selectedWorkMode = 0;

function openEntryModal(entry = null) {
    TimeTrackingManager.currentEditEntry = entry;

    // Set modal title
    document.getElementById('modal-title').textContent = entry ? 'Eintrag bearbeiten' : 'Neuer Eintrag';

    // Reset form
    const now = new Date();
    document.getElementById('entry-id').value = entry?.id || '';
    document.getElementById('entry-local-id').value = entry?.localId || entry?.key || '';
    document.getElementById('entry-date').value = entry ? new Date(entry.start).toISOString().split('T')[0] : now.toISOString().split('T')[0];
    document.getElementById('entry-start').value = entry ? new Date(entry.start).toTimeString().slice(0, 5) : now.toTimeString().slice(0, 5);
    document.getElementById('entry-end').value = entry?.stop ? new Date(entry.stop).toTimeString().slice(0, 5) : '';
    document.getElementById('entry-notes').value = entry?.notes || '';
    document.getElementById('entry-error').classList.add('hidden');

    // Set work mode
    selectWorkMode(entry?.workModeIndex || 0);

    // Show modal
    const modalHtml = document.getElementById('entry-modal-container');
    if (modalHtml) {
        modalHtml.classList.remove('hidden');
    } else {
        // Fetch and inject modal if not present
        fetch('/web/api/entry-form')
            .then(r => r.text())
            .then(html => {
                const container = document.createElement('div');
                container.id = 'entry-modal-container';
                container.innerHTML = html;
                document.body.appendChild(container);
            })
            .catch(() => {
                // Fallback: use inline modal
                showInlineModal(entry);
            });
    }
}

function showInlineModal(entry = null) {
    const modal = document.createElement('div');
    modal.id = 'entry-modal-container';
    modal.innerHTML = `
        <div id="entry-modal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
            <div class="bg-white dark:bg-gray-900 rounded-2xl shadow-2xl w-full max-w-lg mx-4 overflow-hidden">
                <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-800 flex items-center justify-between">
                    <h3 class="text-lg font-semibold text-gray-900 dark:text-white" id="modal-title">${entry ? 'Eintrag bearbeiten' : 'Neuer Eintrag'}</h3>
                    <button onclick="closeEntryModal()" class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300">
                        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                        </svg>
                    </button>
                </div>
                <form id="entry-form" onsubmit="return saveEntry(event)" class="p-6 space-y-5">
                    <input type="hidden" id="entry-id" value="${entry?.id || ''}">
                    <input type="hidden" id="entry-local-id" value="${entry?.localId || entry?.key || ''}">
                    <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Datum</label>
                        <input type="date" id="entry-date" required value="${entry ? new Date(entry.start).toISOString().split('T')[0] : new Date().toISOString().split('T')[0]}"
                            class="w-full px-4 py-3 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded-xl text-gray-900 dark:text-white focus:ring-2 focus:ring-primary-500 outline-none">
                    </div>
                    <div class="grid grid-cols-2 gap-4">
                        <div>
                            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Start</label>
                            <input type="time" id="entry-start" required value="${entry ? new Date(entry.start).toTimeString().slice(0, 5) : new Date().toTimeString().slice(0, 5)}"
                                class="w-full px-4 py-3 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded-xl text-gray-900 dark:text-white focus:ring-2 focus:ring-primary-500 outline-none">
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Ende</label>
                            <input type="time" id="entry-end" value="${entry?.stop ? new Date(entry.stop).toTimeString().slice(0, 5) : ''}"
                                class="w-full px-4 py-3 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded-xl text-gray-900 dark:text-white focus:ring-2 focus:ring-primary-500 outline-none">
                        </div>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Arbeitsmodus</label>
                        <div class="grid grid-cols-5 gap-2">
                            ${[['Arbeit', 'blue', 0], ['Deep', 'purple', 1], ['Meeting', 'orange', 2], ['Support', 'green', 3], ['Admin', 'gray', 4]].map(([label, color, idx]) => `
                                <button type="button" onclick="selectWorkMode(${idx})" data-mode="${idx}"
                                    class="work-mode-btn flex flex-col items-center p-3 rounded-xl border-2 ${(entry?.workModeIndex || 0) === idx ? `border-${color}-500 bg-${color}-50 dark:bg-${color}-900/30` : 'border-gray-200 dark:border-gray-700'} hover:border-${color}-500 transition-all">
                                    <div class="w-3 h-3 rounded-full bg-${color}-500 mb-1"></div>
                                    <span class="text-xs text-gray-600 dark:text-gray-400">${label}</span>
                                </button>
                            `).join('')}
                        </div>
                        <input type="hidden" id="entry-work-mode" value="${entry?.workModeIndex || 0}">
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Notizen</label>
                        <textarea id="entry-notes" rows="2" class="w-full px-4 py-3 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded-xl text-gray-900 dark:text-white placeholder-gray-400 focus:ring-2 focus:ring-primary-500 outline-none resize-none"
                            placeholder="Optionale Notizen...">${entry?.notes || ''}</textarea>
                    </div>
                    <div id="entry-error" class="hidden p-3 bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-800 text-red-700 dark:text-red-400 rounded-xl text-sm"></div>
                    <div class="flex space-x-3 pt-2">
                        <button type="button" onclick="closeEntryModal()" class="flex-1 py-3 px-4 bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 text-gray-700 dark:text-gray-300 font-medium rounded-xl transition-colors">Abbrechen</button>
                        <button type="submit" id="entry-submit-btn" class="flex-1 py-3 px-4 bg-primary-600 hover:bg-primary-700 text-white font-medium rounded-xl transition-colors">Speichern</button>
                    </div>
                </form>
            </div>
        </div>
    `;
    document.body.appendChild(modal);
    selectedWorkMode = entry?.workModeIndex || 0;
}

function closeEntryModal() {
    const modal = document.getElementById('entry-modal-container');
    if (modal) {
        modal.remove();
    }
    TimeTrackingManager.currentEditEntry = null;
}

function selectWorkMode(mode) {
    selectedWorkMode = mode;
    const modeInput = document.getElementById('entry-work-mode');
    if (modeInput) modeInput.value = mode;

    // Update button styles
    document.querySelectorAll('.work-mode-btn').forEach(btn => {
        const btnMode = parseInt(btn.dataset.mode);
        const colors = ['blue', 'purple', 'orange', 'green', 'gray'];
        const color = colors[btnMode];

        if (btnMode === mode) {
            btn.classList.remove('border-gray-200', 'dark:border-gray-700');
            btn.classList.add(`border-${color}-500`, `bg-${color}-50`, `dark:bg-${color}-900/30`);
        } else {
            btn.classList.add('border-gray-200', 'dark:border-gray-700');
            btn.classList.remove(`border-${color}-500`, `bg-${color}-50`, `dark:bg-${color}-900/30`);
        }
    });
}

async function saveEntry(event) {
    event.preventDefault();

    const submitBtn = document.getElementById('entry-submit-btn');
    const errorDiv = document.getElementById('entry-error');
    const readySpan = submitBtn.querySelector('.ready');
    const loadingSpan = submitBtn.querySelector('.loading');

    // Show loading
    if (readySpan) readySpan.classList.add('hidden');
    if (loadingSpan) loadingSpan.classList.remove('hidden');
    submitBtn.disabled = true;
    errorDiv.classList.add('hidden');

    try {
        const date = document.getElementById('entry-date').value;
        const startTime = document.getElementById('entry-start').value;
        const endTime = document.getElementById('entry-end').value;
        const notes = document.getElementById('entry-notes').value;
        const localId = document.getElementById('entry-local-id').value;
        const workMode = parseInt(document.getElementById('entry-work-mode').value) || 0;

        // Build datetime strings
        const startDateTime = new Date(`${date}T${startTime}:00`);
        const endDateTime = endTime ? new Date(`${date}T${endTime}:00`) : null;

        // Handle end time crossing midnight
        if (endDateTime && endDateTime < startDateTime) {
            endDateTime.setDate(endDateTime.getDate() + 1);
        }

        const entryData = {
            localId: localId || null,
            start: startDateTime.toISOString(),
            stop: endDateTime ? endDateTime.toISOString() : null,
            notes: notes || null,
            workModeIndex: workMode,
            pauses: TimeTrackingManager.currentEditEntry?.pauses || [],
            tags: TimeTrackingManager.currentEditEntry?.tags || [],
            projectId: TimeTrackingManager.currentEditEntry?.projectId || null
        };

        await TimeTrackingManager.saveEntry(entryData);

        // Close modal and refresh
        closeEntryModal();
        TimeTrackingManager.updateDashboardStats();
        TimeTrackingManager.renderEntriesList('entries-list');

    } catch (error) {
        errorDiv.textContent = error.message || 'Fehler beim Speichern';
        errorDiv.classList.remove('hidden');
    } finally {
        if (readySpan) readySpan.classList.remove('hidden');
        if (loadingSpan) loadingSpan.classList.add('hidden');
        submitBtn.disabled = false;
    }

    return false;
}

function editEntry(localId) {
    const entry = TimeTrackingManager.findEntry(localId);
    if (entry) {
        showInlineModal(entry);
    }
}

function confirmDeleteEntry(localId) {
    if (confirm('Eintrag wirklich löschen?')) {
        deleteEntry(localId);
    }
}

async function deleteEntry(localId) {
    try {
        await TimeTrackingManager.deleteEntry(localId);
        TimeTrackingManager.updateDashboardStats();
        TimeTrackingManager.renderEntriesList('entries-list');
    } catch (error) {
        alert('Fehler beim Löschen: ' + error.message);
    }
}

// ==================== Auto-initialize ====================

document.addEventListener('DOMContentLoaded', async () => {
    // Only run on pages that have the stat elements
    if (document.querySelector('[data-stat]')) {
        const hasKey = typeof VTCrypto !== 'undefined' && VTCrypto.hasKey();
        if (hasKey) {
            const success = await TimeTrackingManager.init();
            if (success) {
                TimeTrackingManager.updateDashboardStats();

                // Also render entries if container exists
                const entriesContainer = document.getElementById('entries-list');
                if (entriesContainer) {
                    TimeTrackingManager.renderEntriesList('entries-list');
                }
            }
        }
    }
});
