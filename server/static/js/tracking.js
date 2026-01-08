/**
 * VibedTracker Live Tracking Manager
 * Handles start/stop/pause functionality for time tracking
 */

const TrackingManager = {
    currentEntry: null,
    isPaused: false,
    timerInterval: null,
    key: null,

    // Work modes matching Flutter
    workModes: [
        { label: 'Arbeit', color: 'blue', bgClass: 'bg-blue-500' },
        { label: 'Deep Work', color: 'purple', bgClass: 'bg-purple-500' },
        { label: 'Meeting', color: 'orange', bgClass: 'bg-orange-500' },
        { label: 'Support', color: 'green', bgClass: 'bg-green-500' },
        { label: 'Administration', color: 'gray', bgClass: 'bg-gray-500' }
    ],

    /**
     * Initialize tracking manager
     */
    async init() {
        this.key = await VTCrypto.loadKey();
        if (!this.key) {
            console.log('No encryption key for tracking');
            return false;
        }

        // Check for active entry
        await this.checkActiveEntry();
        this.updateUI();

        return true;
    },

    /**
     * Check if there's an active (running) entry
     */
    async checkActiveEntry() {
        if (!this.key) return;

        try {
            const response = await fetch('/web/api/data?type=work_entry', {
                credentials: 'same-origin'
            });

            if (!response.ok) return;

            const data = await response.json();

            // Find entry without stop time (active entry)
            for (const item of data.items || []) {
                try {
                    const decrypted = await VTCrypto.decrypt(
                        this.key,
                        item.encrypted_blob,
                        item.nonce
                    );

                    // Check if this entry is active (no stop time)
                    if (decrypted.start && !decrypted.stop) {
                        this.currentEntry = {
                            id: item.id,
                            localId: item.local_id,
                            ...decrypted
                        };

                        // Check if currently in a pause
                        if (this.currentEntry.pauses && this.currentEntry.pauses.length > 0) {
                            const lastPause = this.currentEntry.pauses[this.currentEntry.pauses.length - 1];
                            if (lastPause.start && !lastPause.end) {
                                this.isPaused = true;
                            }
                        }

                        console.log('Found active entry:', this.currentEntry);
                        break;
                    }
                } catch (e) {
                    // Continue checking other entries
                }
            }
        } catch (error) {
            console.error('Error checking active entry:', error);
        }
    },

    /**
     * Start tracking
     */
    async start(workModeIndex = 0) {
        if (!this.key) {
            alert('Bitte zuerst entsperren');
            window.location.href = '/web/unlock';
            return;
        }

        if (this.currentEntry) {
            console.log('Already tracking');
            return;
        }

        const now = new Date();
        const localId = Date.now().toString();

        this.currentEntry = {
            key: parseInt(localId),
            localId: localId,
            start: now.toISOString(),
            stop: null,
            pauses: [],
            notes: null,
            tags: [],
            projectId: null,
            workModeIndex: workModeIndex
        };

        this.isPaused = false;
        await this.saveCurrentEntry();
        this.updateUI();
        this.startTimer();
    },

    /**
     * Stop tracking
     */
    async stop() {
        if (!this.currentEntry) return;

        // If paused, end the pause first
        if (this.isPaused && this.currentEntry.pauses.length > 0) {
            const lastPause = this.currentEntry.pauses[this.currentEntry.pauses.length - 1];
            if (!lastPause.end) {
                lastPause.end = new Date().toISOString();
            }
        }

        this.currentEntry.stop = new Date().toISOString();
        await this.saveCurrentEntry();

        this.currentEntry = null;
        this.isPaused = false;
        this.stopTimer();
        this.updateUI();

        // Reload entries list if present
        if (typeof TimeTrackingManager !== 'undefined') {
            await TimeTrackingManager.loadEntries();
            TimeTrackingManager.updateDashboardStats();
            TimeTrackingManager.renderEntriesList('entries-list');
        }
    },

    /**
     * Toggle pause
     */
    async togglePause() {
        if (!this.currentEntry) return;

        const now = new Date().toISOString();

        if (this.isPaused) {
            // End current pause
            if (this.currentEntry.pauses.length > 0) {
                const lastPause = this.currentEntry.pauses[this.currentEntry.pauses.length - 1];
                if (!lastPause.end) {
                    lastPause.end = now;
                }
            }
            this.isPaused = false;
        } else {
            // Start new pause
            if (!this.currentEntry.pauses) {
                this.currentEntry.pauses = [];
            }
            this.currentEntry.pauses.push({
                start: now,
                end: null
            });
            this.isPaused = true;
        }

        await this.saveCurrentEntry();
        this.updateUI();
    },

    /**
     * Change work mode of current entry
     */
    async changeWorkMode(workModeIndex) {
        if (!this.currentEntry) return;

        this.currentEntry.workModeIndex = workModeIndex;
        await this.saveCurrentEntry();
        this.updateUI();
    },

    /**
     * Save current entry to server
     */
    async saveCurrentEntry() {
        if (!this.currentEntry || !this.key) return;

        const dataToEncrypt = {
            key: this.currentEntry.key || parseInt(this.currentEntry.localId),
            start: this.currentEntry.start,
            stop: this.currentEntry.stop || null,
            pauses: this.currentEntry.pauses || [],
            notes: this.currentEntry.notes || null,
            tags: this.currentEntry.tags || [],
            projectId: this.currentEntry.projectId || null,
            workModeIndex: this.currentEntry.workModeIndex || 0
        };

        const encrypted = await VTCrypto.encrypt(this.key, dataToEncrypt);

        const response = await fetch('/web/api/entry', {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                local_id: this.currentEntry.localId,
                encrypted_blob: encrypted.blobBase64,
                nonce: encrypted.nonceBase64,
                data_type: 'work_entry'
            })
        });

        if (!response.ok) {
            console.error('Failed to save entry');
        }
    },

    /**
     * Calculate current duration in minutes
     */
    getCurrentDuration() {
        if (!this.currentEntry || !this.currentEntry.start) return 0;

        const start = new Date(this.currentEntry.start);
        const now = new Date();
        let totalMinutes = (now - start) / 60000;

        // Subtract completed pauses
        if (this.currentEntry.pauses) {
            for (const pause of this.currentEntry.pauses) {
                if (pause.start) {
                    const pauseStart = new Date(pause.start);
                    const pauseEnd = pause.end ? new Date(pause.end) : now;
                    totalMinutes -= (pauseEnd - pauseStart) / 60000;
                }
            }
        }

        return Math.max(0, totalMinutes);
    },

    /**
     * Format duration as HH:MM:SS
     */
    formatDuration(minutes) {
        const hours = Math.floor(minutes / 60);
        const mins = Math.floor(minutes % 60);
        const secs = Math.floor((minutes * 60) % 60);
        return `${hours}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    },

    /**
     * Start the timer interval
     */
    startTimer() {
        if (this.timerInterval) return;

        this.timerInterval = setInterval(() => {
            this.updateTimerDisplay();
        }, 1000);
    },

    /**
     * Stop the timer interval
     */
    stopTimer() {
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
            this.timerInterval = null;
        }
    },

    /**
     * Update timer display
     */
    updateTimerDisplay() {
        const timerEl = document.getElementById('tracking-timer');
        if (timerEl && this.currentEntry) {
            const duration = this.getCurrentDuration();
            timerEl.textContent = this.formatDuration(duration);
        }
    },

    /**
     * Update the UI based on current state
     */
    updateUI() {
        const widget = document.getElementById('tracking-widget');
        if (!widget) return;

        const isTracking = !!this.currentEntry;

        // Update button visibility
        const startBtn = document.getElementById('tracking-start-btn');
        const stopBtn = document.getElementById('tracking-stop-btn');
        const pauseBtn = document.getElementById('tracking-pause-btn');
        const timerDisplay = document.getElementById('tracking-timer-container');
        const modeSelector = document.getElementById('tracking-mode-selector');
        const statusText = document.getElementById('tracking-status');

        if (startBtn) startBtn.classList.toggle('hidden', isTracking);
        if (stopBtn) stopBtn.classList.toggle('hidden', !isTracking);
        if (pauseBtn) pauseBtn.classList.toggle('hidden', !isTracking);
        if (timerDisplay) timerDisplay.classList.toggle('hidden', !isTracking);
        if (modeSelector) modeSelector.classList.toggle('hidden', isTracking);

        // Update pause button state
        if (pauseBtn) {
            if (this.isPaused) {
                pauseBtn.innerHTML = `
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                    </svg>
                    <span>Fortsetzen</span>
                `;
                pauseBtn.className = pauseBtn.className.replace('bg-amber-500 hover:bg-amber-600', 'bg-green-500 hover:bg-green-600');
            } else {
                pauseBtn.innerHTML = `
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                    </svg>
                    <span>Pause</span>
                `;
                pauseBtn.className = pauseBtn.className.replace('bg-green-500 hover:bg-green-600', 'bg-amber-500 hover:bg-amber-600');
            }
        }

        // Update status text
        if (statusText) {
            if (isTracking) {
                const mode = this.workModes[this.currentEntry.workModeIndex || 0];
                statusText.innerHTML = `
                    <span class="inline-flex items-center">
                        <span class="w-2 h-2 ${mode.bgClass} rounded-full mr-2 ${this.isPaused ? '' : 'animate-pulse'}"></span>
                        ${this.isPaused ? 'Pausiert' : mode.label}
                    </span>
                `;
            } else {
                statusText.textContent = 'Nicht aktiv';
            }
        }

        // Update timer display
        if (isTracking) {
            this.updateTimerDisplay();
            this.startTimer();
        } else {
            this.stopTimer();
            const timerEl = document.getElementById('tracking-timer');
            if (timerEl) timerEl.textContent = '0:00:00';
        }

        // Update work mode buttons
        this.updateWorkModeButtons();
    },

    /**
     * Update work mode button states
     */
    updateWorkModeButtons() {
        const currentMode = this.currentEntry?.workModeIndex || 0;
        document.querySelectorAll('.tracking-mode-btn').forEach(btn => {
            const modeIndex = parseInt(btn.dataset.mode);
            const mode = this.workModes[modeIndex];

            if (modeIndex === currentMode) {
                btn.classList.add(`ring-2`, `ring-${mode.color}-500`);
            } else {
                btn.classList.remove(`ring-2`, `ring-${mode.color}-500`);
            }
        });
    }
};

// Global functions for button onclick handlers
function startTracking(workModeIndex = 0) {
    TrackingManager.start(workModeIndex);
}

function stopTracking() {
    TrackingManager.stop();
}

function togglePause() {
    TrackingManager.togglePause();
}

function selectTrackingMode(modeIndex) {
    if (TrackingManager.currentEntry) {
        TrackingManager.changeWorkMode(modeIndex);
    }
    // Update selected state
    document.querySelectorAll('.tracking-mode-btn').forEach(btn => {
        const btnMode = parseInt(btn.dataset.mode);
        btn.classList.toggle('ring-2', btnMode === modeIndex);
    });
}

// Auto-initialize
document.addEventListener('DOMContentLoaded', () => {
    if (document.getElementById('tracking-widget')) {
        if (typeof VTCrypto !== 'undefined' && VTCrypto.hasKey()) {
            TrackingManager.init();
        }
    }
});
