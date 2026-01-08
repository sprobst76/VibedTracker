/**
 * VibedTracker Web Crypto API - Client-Side Encryption
 * Matches Flutter encryption_service.dart parameters exactly
 *
 * - PBKDF2: HMAC-SHA256, 100,000 iterations, 256-bit output
 * - AES-GCM: 256-bit key, 12-byte nonce
 * - Blob format: ciphertext + MAC (last 16 bytes)
 * - Verification: HMAC-SHA256 of 'vibedtracker-verification'
 */

const VTCrypto = {
    // Session storage key for the derived key
    KEY_STORAGE: 'vt_encryption_key',

    /**
     * Derive a key from passphrase using PBKDF2
     * @param {string} passphrase - User's passphrase
     * @param {string} saltBase64 - Base64 encoded salt from server
     * @returns {Promise<CryptoKey>} - Derived AES-GCM key
     */
    async deriveKey(passphrase, saltBase64) {
        const encoder = new TextEncoder();
        const salt = this.base64ToBytes(saltBase64);

        // Import passphrase as key material
        const keyMaterial = await crypto.subtle.importKey(
            'raw',
            encoder.encode(passphrase),
            'PBKDF2',
            false,
            ['deriveBits', 'deriveKey']
        );

        // Derive the AES-GCM key using PBKDF2
        const key = await crypto.subtle.deriveKey(
            {
                name: 'PBKDF2',
                salt: salt,
                iterations: 100000,
                hash: 'SHA-256'
            },
            keyMaterial,
            { name: 'AES-GCM', length: 256 },
            true, // extractable for HMAC verification
            ['encrypt', 'decrypt']
        );

        return key;
    },

    /**
     * Verify passphrase against stored verification hash
     * @param {CryptoKey} key - Derived AES-GCM key
     * @param {string} expectedHashBase64 - Expected verification hash from server
     * @returns {Promise<boolean>} - True if passphrase is correct
     */
    async verifyPassphrase(key, expectedHashBase64) {
        const encoder = new TextEncoder();
        const expectedHash = this.base64ToBytes(expectedHashBase64);

        // Export key bytes for HMAC
        const keyBytes = await crypto.subtle.exportKey('raw', key);

        // Import as HMAC key
        const hmacKey = await crypto.subtle.importKey(
            'raw',
            keyBytes,
            { name: 'HMAC', hash: 'SHA-256' },
            false,
            ['sign']
        );

        // Calculate HMAC of verification message
        const signature = await crypto.subtle.sign(
            'HMAC',
            hmacKey,
            encoder.encode('vibedtracker-verification')
        );

        // Constant-time comparison
        const computedHash = new Uint8Array(signature);
        return this.constantTimeCompare(computedHash, expectedHash);
    },

    /**
     * Create verification hash from a key
     * @param {CryptoKey} key - AES-GCM key
     * @returns {Promise<ArrayBuffer>} - Verification hash
     */
    async createVerificationHash(key) {
        const encoder = new TextEncoder();

        // Export key bytes for HMAC
        const keyBytes = await crypto.subtle.exportKey('raw', key);

        // Import as HMAC key
        const hmacKey = await crypto.subtle.importKey(
            'raw',
            keyBytes,
            { name: 'HMAC', hash: 'SHA-256' },
            false,
            ['sign']
        );

        // Calculate HMAC of verification message
        return await crypto.subtle.sign(
            'HMAC',
            hmacKey,
            encoder.encode('vibedtracker-verification')
        );
    },

    /**
     * Decrypt data using AES-GCM
     * @param {CryptoKey} key - AES-GCM key
     * @param {string} blobBase64 - Base64 encoded blob (ciphertext + mac)
     * @param {string} nonceBase64 - Base64 encoded nonce (12 bytes)
     * @returns {Promise<Object>} - Decrypted JSON object
     */
    async decrypt(key, blobBase64, nonceBase64) {
        const blob = this.base64ToBytes(blobBase64);
        const nonce = this.base64ToBytes(nonceBase64);

        // AES-GCM expects ciphertext with tag appended (which is our blob format)
        // The tag (MAC) is the last 16 bytes
        const decrypted = await crypto.subtle.decrypt(
            {
                name: 'AES-GCM',
                iv: nonce,
                tagLength: 128 // 16 bytes = 128 bits
            },
            key,
            blob // Web Crypto expects ciphertext+tag concatenated
        );

        const decoder = new TextDecoder();
        return JSON.parse(decoder.decode(decrypted));
    },

    /**
     * Encrypt data using AES-GCM
     * @param {CryptoKey} key - AES-GCM key
     * @param {Object} data - Data to encrypt
     * @returns {Promise<{blobBase64: string, nonceBase64: string}>}
     */
    async encrypt(key, data) {
        const encoder = new TextEncoder();
        const plaintext = encoder.encode(JSON.stringify(data));

        // Generate random 12-byte nonce
        const nonce = crypto.getRandomValues(new Uint8Array(12));

        // Encrypt (result includes ciphertext + tag)
        const ciphertext = await crypto.subtle.encrypt(
            {
                name: 'AES-GCM',
                iv: nonce,
                tagLength: 128
            },
            key,
            plaintext
        );

        return {
            blobBase64: this.bytesToBase64(new Uint8Array(ciphertext)),
            nonceBase64: this.bytesToBase64(nonce)
        };
    },

    /**
     * Store derived key in sessionStorage (cleared on tab close)
     * @param {CryptoKey} key - Key to store
     */
    async storeKey(key) {
        const exported = await crypto.subtle.exportKey('raw', key);
        const keyBase64 = this.bytesToBase64(new Uint8Array(exported));
        sessionStorage.setItem(this.KEY_STORAGE, keyBase64);
    },

    /**
     * Load key from sessionStorage
     * @returns {Promise<CryptoKey|null>} - Stored key or null
     */
    async loadKey() {
        const keyBase64 = sessionStorage.getItem(this.KEY_STORAGE);
        if (!keyBase64) return null;

        const keyBytes = this.base64ToBytes(keyBase64);
        return await crypto.subtle.importKey(
            'raw',
            keyBytes,
            { name: 'AES-GCM', length: 256 },
            true,
            ['encrypt', 'decrypt']
        );
    },

    /**
     * Check if key is stored
     * @returns {boolean}
     */
    hasKey() {
        return sessionStorage.getItem(this.KEY_STORAGE) !== null;
    },

    /**
     * Clear stored key
     */
    clearKey() {
        sessionStorage.removeItem(this.KEY_STORAGE);
    },

    // ==================== Utility Functions ====================

    /**
     * Convert Base64 string to Uint8Array
     */
    base64ToBytes(base64) {
        const binary = atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
        }
        return bytes;
    },

    /**
     * Convert Uint8Array to Base64 string
     */
    bytesToBase64(bytes) {
        let binary = '';
        for (let i = 0; i < bytes.length; i++) {
            binary += String.fromCharCode(bytes[i]);
        }
        return btoa(binary);
    },

    /**
     * Constant-time comparison to prevent timing attacks
     */
    constantTimeCompare(a, b) {
        if (a.length !== b.length) return false;
        let result = 0;
        for (let i = 0; i < a.length; i++) {
            result |= a[i] ^ b[i];
        }
        return result === 0;
    }
};

// Export for module usage (if needed)
if (typeof module !== 'undefined' && module.exports) {
    module.exports = VTCrypto;
}
