/**
 * VibedTracker Web Utilities
 */

const VTUtils = {
    /**
     * Format duration in minutes to HH:MM string
     * @param {number} minutes - Duration in minutes
     * @returns {string} - Formatted string like "8:30"
     */
    formatDuration(minutes) {
        if (!minutes || minutes < 0) return '0:00';
        const hours = Math.floor(minutes / 60);
        const mins = Math.round(minutes % 60);
        return `${hours}:${mins.toString().padStart(2, '0')}`;
    },

    /**
     * Format date for display (German locale)
     * @param {string|Date} date - Date to format
     * @returns {string} - Formatted date like "08.01.2026"
     */
    formatDate(date) {
        const d = new Date(date);
        return d.toLocaleDateString('de-DE', {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric'
        });
    },

    /**
     * Format time for display
     * @param {string|Date} date - Date/time to format
     * @returns {string} - Formatted time like "08:30"
     */
    formatTime(date) {
        const d = new Date(date);
        return d.toLocaleTimeString('de-DE', {
            hour: '2-digit',
            minute: '2-digit'
        });
    },

    /**
     * Format datetime for display
     * @param {string|Date} date - Date/time to format
     * @returns {string} - Formatted datetime like "08.01.2026 08:30"
     */
    formatDateTime(date) {
        return `${this.formatDate(date)} ${this.formatTime(date)}`;
    },

    /**
     * Get start of today (midnight)
     * @returns {Date}
     */
    startOfToday() {
        const d = new Date();
        d.setHours(0, 0, 0, 0);
        return d;
    },

    /**
     * Get start of this week (Monday)
     * @returns {Date}
     */
    startOfWeek() {
        const d = new Date();
        const day = d.getDay();
        const diff = d.getDate() - day + (day === 0 ? -6 : 1); // Monday
        d.setDate(diff);
        d.setHours(0, 0, 0, 0);
        return d;
    },

    /**
     * Get start of this month
     * @returns {Date}
     */
    startOfMonth() {
        const d = new Date();
        d.setDate(1);
        d.setHours(0, 0, 0, 0);
        return d;
    },

    /**
     * Calculate duration between two dates in minutes
     * @param {string|Date} start - Start time
     * @param {string|Date} end - End time
     * @returns {number} - Duration in minutes
     */
    calculateDuration(start, end) {
        const startDate = new Date(start);
        const endDate = new Date(end);
        return Math.round((endDate - startDate) / 60000);
    },

    /**
     * Show a toast notification
     * @param {string} message - Message to display
     * @param {string} type - 'success', 'error', or 'info'
     */
    showToast(message, type = 'info') {
        // Create toast container if not exists
        let container = document.getElementById('toast-container');
        if (!container) {
            container = document.createElement('div');
            container.id = 'toast-container';
            container.className = 'fixed bottom-4 right-4 z-50 space-y-2';
            document.body.appendChild(container);
        }

        // Create toast element
        const toast = document.createElement('div');
        const bgColor = type === 'success' ? 'bg-green-600' :
                       type === 'error' ? 'bg-red-600' : 'bg-primary-600';
        toast.className = `${bgColor} text-white px-4 py-3 rounded-lg shadow-lg transform transition-all duration-300 translate-x-full`;
        toast.textContent = message;

        container.appendChild(toast);

        // Animate in
        requestAnimationFrame(() => {
            toast.classList.remove('translate-x-full');
        });

        // Remove after delay
        setTimeout(() => {
            toast.classList.add('translate-x-full');
            setTimeout(() => toast.remove(), 300);
        }, 3000);
    },

    /**
     * Debounce function calls
     * @param {Function} func - Function to debounce
     * @param {number} wait - Wait time in ms
     * @returns {Function}
     */
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    },

    /**
     * Parse ISO date string preserving local timezone
     * @param {string} isoString - ISO date string
     * @returns {Date}
     */
    parseLocalDate(isoString) {
        // Handle ISO strings like "2026-01-08T08:30:00"
        // by parsing as local time, not UTC
        if (isoString.includes('T') && !isoString.includes('Z') && !isoString.includes('+')) {
            const [datePart, timePart] = isoString.split('T');
            const [year, month, day] = datePart.split('-').map(Number);
            const [hour, minute, second] = timePart.split(':').map(n => parseInt(n) || 0);
            return new Date(year, month - 1, day, hour, minute, second);
        }
        return new Date(isoString);
    }
};

// Export for module usage
if (typeof module !== 'undefined' && module.exports) {
    module.exports = VTUtils;
}
