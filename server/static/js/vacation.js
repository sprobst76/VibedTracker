/**
 * VibedTracker Vacation Manager
 * Handles loading, decrypting, and displaying vacation/absence entries
 */

const VacationManager = {
    absences: [],
    key: null,
    currentMonth: new Date(),
    selectedType: 0,
    annualEntitlement: 30, // Default

    // Absence types matching Flutter model
    absenceTypes: [
        { label: 'Urlaub', color: 'orange', bgClass: 'bg-orange-500' },
        { label: 'Krankheit', color: 'purple', bgClass: 'bg-purple-500' },
        { label: 'Kind krank', color: 'pink', bgClass: 'bg-pink-500' },
        { label: 'Sonderurlaub', color: 'teal', bgClass: 'bg-teal-500' },
        { label: 'Unbezahlt', color: 'gray', bgClass: 'bg-gray-500' }
    ],

    // German holidays (static for common ones, can be extended)
    holidays: {},

    /**
     * Initialize the manager
     */
    async init() {
        // Load encryption key from session
        this.key = await VTCrypto.loadKey();
        if (!this.key) {
            console.log('No encryption key found');
            this.showNoKeyMessage();
            return false;
        }

        // Load holidays for current and next year
        this.loadHolidays(this.currentMonth.getFullYear());
        this.loadHolidays(this.currentMonth.getFullYear() + 1);

        // Fetch and decrypt absences
        await this.loadAbsences();

        // Render calendar
        this.renderCalendar();
        this.updateStats();
        this.renderAbsencesList();

        return true;
    },

    /**
     * Load German holidays for a given year
     */
    loadHolidays(year) {
        // Fixed holidays
        this.holidays[`${year}-01-01`] = 'Neujahr';
        this.holidays[`${year}-05-01`] = 'Tag der Arbeit';
        this.holidays[`${year}-10-03`] = 'Tag der Deutschen Einheit';
        this.holidays[`${year}-12-25`] = '1. Weihnachtstag';
        this.holidays[`${year}-12-26`] = '2. Weihnachtstag';

        // Calculate Easter-based holidays
        const easter = this.calculateEaster(year);
        const easterDate = new Date(year, easter.month - 1, easter.day);

        // Good Friday (2 days before Easter)
        const goodFriday = new Date(easterDate);
        goodFriday.setDate(easterDate.getDate() - 2);
        this.holidays[this.formatDateKey(goodFriday)] = 'Karfreitag';

        // Easter Monday (1 day after Easter)
        const easterMonday = new Date(easterDate);
        easterMonday.setDate(easterDate.getDate() + 1);
        this.holidays[this.formatDateKey(easterMonday)] = 'Ostermontag';

        // Ascension Day (39 days after Easter)
        const ascension = new Date(easterDate);
        ascension.setDate(easterDate.getDate() + 39);
        this.holidays[this.formatDateKey(ascension)] = 'Christi Himmelfahrt';

        // Whit Monday (50 days after Easter)
        const whitMonday = new Date(easterDate);
        whitMonday.setDate(easterDate.getDate() + 50);
        this.holidays[this.formatDateKey(whitMonday)] = 'Pfingstmontag';
    },

    /**
     * Calculate Easter Sunday for a given year (Anonymous Gregorian algorithm)
     */
    calculateEaster(year) {
        const a = year % 19;
        const b = Math.floor(year / 100);
        const c = year % 100;
        const d = Math.floor(b / 4);
        const e = b % 4;
        const f = Math.floor((b + 8) / 25);
        const g = Math.floor((b - f + 1) / 3);
        const h = (19 * a + b - d - g + 15) % 30;
        const i = Math.floor(c / 4);
        const k = c % 4;
        const l = (32 + 2 * e + 2 * i - h - k) % 7;
        const m = Math.floor((a + 11 * h + 22 * l) / 451);
        const month = Math.floor((h + l - 7 * m + 114) / 31);
        const day = ((h + l - 7 * m + 114) % 31) + 1;
        return { month, day };
    },

    /**
     * Format date as YYYY-MM-DD for holiday lookup
     */
    formatDateKey(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    },

    /**
     * Show message when no encryption key is available
     */
    showNoKeyMessage() {
        const grid = document.getElementById('calendar-grid');
        if (grid) {
            grid.innerHTML = `
                <div class="col-span-7 text-center py-12">
                    <div class="w-16 h-16 mx-auto mb-4 bg-amber-100 dark:bg-amber-900/50 rounded-full flex items-center justify-center">
                        <svg class="w-8 h-8 text-amber-600 dark:text-amber-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
                        </svg>
                    </div>
                    <p class="text-gray-500 dark:text-gray-400 mb-4">Daten entsperren, um Abwesenheiten anzuzeigen</p>
                    <a href="/web/unlock" class="inline-flex items-center px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white font-medium rounded-lg transition-colors">
                        Entsperren
                    </a>
                </div>
            `;
        }
    },

    /**
     * Fetch encrypted absences from server and decrypt them
     */
    async loadAbsences() {
        try {
            const response = await fetch('/web/api/data?type=vacation', {
                credentials: 'same-origin'
            });

            if (!response.ok) {
                throw new Error('Failed to fetch data');
            }

            const data = await response.json();
            this.absences = [];

            // Decrypt each entry
            for (const item of data.items || []) {
                try {
                    const decrypted = await VTCrypto.decrypt(
                        this.key,
                        item.encrypted_blob,
                        item.nonce
                    );
                    this.absences.push({
                        id: item.id,
                        localId: item.local_id,
                        ...decrypted
                    });
                } catch (e) {
                    console.error('Failed to decrypt absence:', e);
                }
            }

            // Sort by day descending
            this.absences.sort((a, b) => new Date(b.day) - new Date(a.day));

            console.log(`Loaded ${this.absences.length} absences`);
            return this.absences;

        } catch (error) {
            console.error('Error loading absences:', error);
            return [];
        }
    },

    /**
     * Save an absence
     */
    async saveAbsence(event) {
        event.preventDefault();

        const dateStr = document.getElementById('absence-date').value;
        const typeIndex = parseInt(document.getElementById('absence-type').value);
        const description = document.getElementById('absence-description').value;
        const errorDiv = document.getElementById('absence-error');
        const submitBtn = document.getElementById('absence-submit-btn');

        errorDiv.classList.add('hidden');
        submitBtn.disabled = true;
        submitBtn.textContent = 'Speichern...';

        try {
            // Check if date already has an entry
            const existingAbsence = this.absences.find(a => {
                const aDate = new Date(a.day);
                const targetDate = new Date(dateStr);
                return aDate.toDateString() === targetDate.toDateString();
            });

            // Generate local ID
            const localId = existingAbsence?.localId || Date.now().toString();

            // Prepare data for encryption (match Flutter Vacation model)
            const dataToEncrypt = {
                key: parseInt(localId) || Date.now(),
                day: new Date(dateStr).toISOString(),
                description: description || null,
                typeIndex: typeIndex
            };

            // Encrypt
            const encrypted = await VTCrypto.encrypt(this.key, dataToEncrypt);

            // Save to server
            const response = await fetch('/web/api/vacation', {
                method: 'POST',
                credentials: 'same-origin',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    local_id: localId,
                    encrypted_blob: encrypted.blobBase64,
                    nonce: encrypted.nonceBase64,
                    data_type: 'vacation'
                })
            });

            if (!response.ok) {
                const err = await response.json();
                throw new Error(err.error || 'Failed to save absence');
            }

            // Reload and re-render
            await this.loadAbsences();
            this.renderCalendar();
            this.updateStats();
            this.renderAbsencesList();
            this.closeModal();

        } catch (error) {
            errorDiv.textContent = error.message || 'Fehler beim Speichern';
            errorDiv.classList.remove('hidden');
        } finally {
            submitBtn.disabled = false;
            submitBtn.textContent = 'Speichern';
        }

        return false;
    },

    /**
     * Delete an absence
     */
    async deleteAbsence(localId) {
        if (!confirm('Abwesenheit wirklich löschen?')) return;

        try {
            const response = await fetch(`/web/api/vacation/${localId}`, {
                method: 'DELETE',
                credentials: 'same-origin'
            });

            if (!response.ok) {
                const err = await response.json();
                throw new Error(err.error || 'Failed to delete absence');
            }

            // Reload and re-render
            await this.loadAbsences();
            this.renderCalendar();
            this.updateStats();
            this.renderAbsencesList();

        } catch (error) {
            alert('Fehler beim Löschen: ' + error.message);
        }
    },

    /**
     * Navigate to previous month
     */
    prevMonth() {
        this.currentMonth.setMonth(this.currentMonth.getMonth() - 1);
        this.renderCalendar();
    },

    /**
     * Navigate to next month
     */
    nextMonth() {
        this.currentMonth.setMonth(this.currentMonth.getMonth() + 1);
        this.renderCalendar();
    },

    /**
     * Render calendar grid
     */
    renderCalendar() {
        const grid = document.getElementById('calendar-grid');
        const monthLabel = document.getElementById('calendar-month');
        if (!grid || !monthLabel) return;

        const year = this.currentMonth.getFullYear();
        const month = this.currentMonth.getMonth();

        // Update month label
        monthLabel.textContent = new Date(year, month, 1).toLocaleDateString('de-DE', {
            month: 'long',
            year: 'numeric'
        });

        // Load holidays for this year if not already loaded
        if (!this.holidays[`${year}-01-01`]) {
            this.loadHolidays(year);
        }

        // Get first day of month and number of days
        const firstDay = new Date(year, month, 1);
        const lastDay = new Date(year, month + 1, 0);
        const daysInMonth = lastDay.getDate();

        // Get day of week for first day (0 = Sunday, convert to Monday start)
        let startDay = firstDay.getDay() - 1;
        if (startDay < 0) startDay = 6; // Sunday becomes 6

        // Build calendar HTML
        let html = '';

        // Empty cells for days before month starts
        for (let i = 0; i < startDay; i++) {
            html += '<div class="calendar-day p-2 rounded-lg"></div>';
        }

        // Days of the month
        const today = new Date();
        for (let day = 1; day <= daysInMonth; day++) {
            const date = new Date(year, month, day);
            const dateKey = this.formatDateKey(date);
            const isWeekend = date.getDay() === 0 || date.getDay() === 6;
            const isToday = date.toDateString() === today.toDateString();
            const holiday = this.holidays[dateKey];
            const absence = this.getAbsenceForDate(date);

            let bgClass = 'bg-gray-50 dark:bg-gray-800/50';
            let textClass = 'text-gray-900 dark:text-white';
            let indicator = '';

            if (isToday) {
                bgClass = 'bg-primary-100 dark:bg-primary-900/30 ring-2 ring-primary-500';
            }

            if (holiday) {
                bgClass = 'bg-red-50 dark:bg-red-900/20';
                textClass = 'text-red-700 dark:text-red-300';
                indicator = `<div class="text-xs text-red-600 dark:text-red-400 truncate">${holiday}</div>`;
            }

            if (absence) {
                const type = this.absenceTypes[absence.typeIndex] || this.absenceTypes[0];
                indicator = `
                    <div class="absolute bottom-1 left-1/2 transform -translate-x-1/2 w-2 h-2 rounded-full ${type.bgClass}"></div>
                    ${absence.description ? `<div class="text-xs truncate text-${type.color}-600 dark:text-${type.color}-400">${this.escapeHtml(absence.description)}</div>` : ''}
                `;
            }

            if (isWeekend && !holiday && !absence) {
                bgClass = 'bg-gray-100 dark:bg-gray-800';
                textClass = 'text-gray-500 dark:text-gray-500';
            }

            html += `
                <div class="calendar-day ${bgClass} p-2 rounded-lg cursor-pointer hover:ring-2 hover:ring-primary-400 transition-all relative min-h-[60px]"
                     onclick="VacationManager.openModal('${dateKey}')">
                    <div class="text-sm font-medium ${textClass}">${day}</div>
                    ${indicator}
                </div>
            `;
        }

        grid.innerHTML = html;
    },

    /**
     * Get absence for a specific date
     */
    getAbsenceForDate(date) {
        return this.absences.find(a => {
            const aDate = new Date(a.day);
            return aDate.toDateString() === date.toDateString();
        });
    },

    /**
     * Update statistics
     */
    updateStats() {
        const year = new Date().getFullYear();
        const today = new Date();

        let usedDays = 0;
        let plannedDays = 0;

        for (const absence of this.absences) {
            const absenceDate = new Date(absence.day);
            if (absenceDate.getFullYear() !== year) continue;

            // Only count vacation type (index 0) for quota
            if (absence.typeIndex !== 0) continue;

            if (absenceDate <= today) {
                usedDays++;
            } else {
                plannedDays++;
            }
        }

        const remaining = this.annualEntitlement - usedDays - plannedDays;

        // Update DOM
        const annualEl = document.querySelector('[data-stat="annual"]');
        const usedEl = document.querySelector('[data-stat="used"]');
        const plannedEl = document.querySelector('[data-stat="planned"]');
        const remainingEl = document.querySelector('[data-stat="remaining"]');

        if (annualEl) annualEl.textContent = this.annualEntitlement;
        if (usedEl) usedEl.textContent = usedDays;
        if (plannedEl) plannedEl.textContent = plannedDays;
        if (remainingEl) remainingEl.textContent = remaining;
    },

    /**
     * Render absences list
     */
    renderAbsencesList() {
        const container = document.getElementById('absences-list');
        if (!container) return;

        const currentYear = new Date().getFullYear();
        const filteredAbsences = this.absences.filter(a => {
            const date = new Date(a.day);
            return date.getFullYear() === currentYear;
        });

        if (filteredAbsences.length === 0) {
            container.innerHTML = `
                <div class="text-center py-8 text-gray-500 dark:text-gray-400">
                    <p>Keine Abwesenheiten in ${currentYear} eingetragen</p>
                </div>
            `;
            return;
        }

        let html = '';
        for (const absence of filteredAbsences) {
            const date = new Date(absence.day);
            const type = this.absenceTypes[absence.typeIndex] || this.absenceTypes[0];
            const localId = absence.localId || absence.key;

            html += `
                <div class="bg-white dark:bg-gray-900 rounded-lg p-4 border border-gray-200 dark:border-gray-800 flex items-center justify-between group">
                    <div class="flex items-center space-x-3">
                        <div class="w-3 h-10 ${type.bgClass} rounded-full"></div>
                        <div>
                            <div class="font-medium text-gray-900 dark:text-white">
                                ${date.toLocaleDateString('de-DE', { weekday: 'long', day: 'numeric', month: 'long' })}
                            </div>
                            <div class="text-sm text-gray-500 dark:text-gray-400">
                                ${type.label}${absence.description ? ' - ' + this.escapeHtml(absence.description) : ''}
                            </div>
                        </div>
                    </div>
                    <button onclick="VacationManager.deleteAbsence('${localId}')"
                        class="p-2 text-gray-400 hover:text-red-600 dark:hover:text-red-400 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg transition-colors opacity-0 group-hover:opacity-100">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                        </svg>
                    </button>
                </div>
            `;
        }

        container.innerHTML = html;
    },

    /**
     * Open modal for a specific date
     */
    openModal(dateKey) {
        const modal = document.getElementById('absence-modal');
        const dateInput = document.getElementById('absence-date');
        const dateDisplay = document.getElementById('selected-date-display');
        const descInput = document.getElementById('absence-description');

        if (!modal || !dateInput || !dateDisplay) return;

        // Parse date
        const date = new Date(dateKey + 'T12:00:00');
        dateInput.value = dateKey;
        dateDisplay.textContent = date.toLocaleDateString('de-DE', {
            weekday: 'long',
            day: 'numeric',
            month: 'long',
            year: 'numeric'
        });

        // Check for existing absence
        const existing = this.getAbsenceForDate(date);
        if (existing) {
            this.selectType(existing.typeIndex || 0);
            descInput.value = existing.description || '';
            document.getElementById('modal-title').textContent = 'Abwesenheit bearbeiten';
        } else {
            this.selectType(0);
            descInput.value = '';
            document.getElementById('modal-title').textContent = 'Abwesenheit eintragen';
        }

        // Show modal
        modal.classList.remove('hidden');
    },

    /**
     * Close modal
     */
    closeModal() {
        const modal = document.getElementById('absence-modal');
        if (modal) {
            modal.classList.add('hidden');
        }
        document.getElementById('absence-error').classList.add('hidden');
    },

    /**
     * Select absence type
     */
    selectType(typeIndex) {
        this.selectedType = typeIndex;
        document.getElementById('absence-type').value = typeIndex;

        // Update button styles
        const colors = ['orange', 'purple', 'pink', 'teal', 'gray'];
        document.querySelectorAll('.absence-type-btn').forEach(btn => {
            const btnType = parseInt(btn.dataset.type);
            const color = colors[btnType];

            if (btnType === typeIndex) {
                btn.classList.remove('border-gray-200', 'dark:border-gray-700');
                btn.classList.add(`border-${color}-500`, `bg-${color}-50`, `dark:bg-${color}-900/30`);
            } else {
                btn.classList.add('border-gray-200', 'dark:border-gray-700');
                btn.classList.remove(`border-${color}-500`, `bg-${color}-50`, `dark:bg-${color}-900/30`);
            }
        });
    },

    /**
     * Escape HTML
     */
    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
};

// Auto-initialize on DOMContentLoaded
document.addEventListener('DOMContentLoaded', () => {
    if (document.getElementById('calendar-grid')) {
        VacationManager.init();
    }
});
