/**
 * VibedTracker WebAuthn/Passkey Support
 *
 * Provides passwordless authentication and optional encryption key storage
 * using the WebAuthn API and PRF extension.
 *
 * Security Model:
 * - Passkeys are stored in platform authenticator (TPM, Secure Enclave, etc.)
 * - PRF extension derives a secret that can wrap the encryption key
 * - Wrapped key stored on server, unwrapped locally with PRF secret
 * - User only needs biometric/PIN to unlock - no passphrase needed
 */

const VTPasskey = {
    // Check if WebAuthn is supported
    isSupported() {
        return window.PublicKeyCredential !== undefined &&
               typeof window.PublicKeyCredential === 'function';
    },

    // Check if platform authenticator is available (Face ID, Touch ID, Windows Hello)
    async isPlatformAuthenticatorAvailable() {
        if (!this.isSupported()) return false;
        try {
            return await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
        } catch (e) {
            console.error('Platform authenticator check failed:', e);
            return false;
        }
    },

    // Check if PRF extension is likely supported (Chrome 116+, Safari 17+)
    isPRFLikelySupported() {
        // PRF support detection is tricky - we try during registration
        const ua = navigator.userAgent;
        const isChrome = /Chrome\/(\d+)/.exec(ua);
        const isSafari = /Version\/(\d+).*Safari/.exec(ua);

        if (isChrome && parseInt(isChrome[1]) >= 116) return true;
        if (isSafari && parseInt(isSafari[1]) >= 17) return true;

        return false;
    },

    /**
     * Register a new passkey
     * @param {Object} options - Options from server's BeginRegistration
     * @param {string} name - User-provided name for this passkey
     * @param {CryptoKey} encryptionKey - Optional encryption key to wrap
     * @returns {Promise<Object>} - Registration result
     */
    async register(options, name, encryptionKey = null) {
        if (!this.isSupported()) {
            throw new Error('WebAuthn is not supported in this browser');
        }

        // Convert base64url to ArrayBuffer
        const publicKey = this._prepareCreationOptions(options.publicKey);

        // Create credential
        let credential;
        try {
            credential = await navigator.credentials.create({ publicKey });
        } catch (e) {
            if (e.name === 'NotAllowedError') {
                throw new Error('Passkey registration was cancelled');
            }
            throw new Error('Failed to create passkey: ' + e.message);
        }

        // Prepare response for server
        const response = {
            id: credential.id,
            rawId: this._arrayBufferToBase64url(credential.rawId),
            type: credential.type,
            response: {
                clientDataJSON: this._arrayBufferToBase64url(credential.response.clientDataJSON),
                attestationObject: this._arrayBufferToBase64url(credential.response.attestationObject),
            },
            name: name || 'Passkey',
        };

        // If encryption key provided and PRF is available, wrap it
        if (encryptionKey && credential.getClientExtensionResults) {
            const extensions = credential.getClientExtensionResults();
            if (extensions.prf && extensions.prf.enabled) {
                console.log('PRF extension available - wrapping encryption key');
                // PRF is enabled but we need to authenticate to get the actual PRF output
                // For registration, we just note that PRF is available
                response.prfEnabled = true;
            }
        }

        return response;
    },

    /**
     * Authenticate with a passkey
     * @param {Object} options - Options from server's BeginAuthentication
     * @returns {Promise<Object>} - Authentication result with optional PRF output
     */
    async authenticate(options) {
        if (!this.isSupported()) {
            throw new Error('WebAuthn is not supported in this browser');
        }

        // Convert base64url to ArrayBuffer
        const publicKey = this._prepareRequestOptions(options.publicKey);

        // Get credential
        let credential;
        try {
            credential = await navigator.credentials.get({ publicKey });
        } catch (e) {
            if (e.name === 'NotAllowedError') {
                throw new Error('Passkey authentication was cancelled');
            }
            throw new Error('Failed to authenticate with passkey: ' + e.message);
        }

        // Prepare response for server
        const response = {
            id: credential.id,
            rawId: this._arrayBufferToBase64url(credential.rawId),
            type: credential.type,
            response: {
                clientDataJSON: this._arrayBufferToBase64url(credential.response.clientDataJSON),
                authenticatorData: this._arrayBufferToBase64url(credential.response.authenticatorData),
                signature: this._arrayBufferToBase64url(credential.response.signature),
                userHandle: credential.response.userHandle
                    ? this._arrayBufferToBase64url(credential.response.userHandle)
                    : null,
            },
        };

        // Check for PRF output
        if (credential.getClientExtensionResults) {
            const extensions = credential.getClientExtensionResults();
            if (extensions.prf && extensions.prf.results && extensions.prf.results.first) {
                response.prfOutput = new Uint8Array(extensions.prf.results.first);
                console.log('PRF output received');
            }
        }

        return response;
    },

    /**
     * Wrap an encryption key using PRF-derived secret
     * @param {Uint8Array} prfOutput - PRF output from authentication
     * @param {CryptoKey} encryptionKey - Key to wrap
     * @returns {Promise<{wrappedKey: string, nonce: string}>}
     */
    async wrapKey(prfOutput, encryptionKey) {
        // Derive wrapping key from PRF output using HKDF
        const prfKeyMaterial = await crypto.subtle.importKey(
            'raw',
            prfOutput,
            'HKDF',
            false,
            ['deriveKey']
        );

        const wrappingKey = await crypto.subtle.deriveKey(
            {
                name: 'HKDF',
                salt: new TextEncoder().encode('vibedtracker-key-wrap'),
                info: new TextEncoder().encode('aes-gcm-wrapping'),
                hash: 'SHA-256',
            },
            prfKeyMaterial,
            { name: 'AES-GCM', length: 256 },
            false,
            ['wrapKey', 'unwrapKey']
        );

        // Generate nonce
        const nonce = crypto.getRandomValues(new Uint8Array(12));

        // Wrap the encryption key
        const wrappedKeyBuffer = await crypto.subtle.wrapKey(
            'raw',
            encryptionKey,
            wrappingKey,
            { name: 'AES-GCM', iv: nonce }
        );

        return {
            wrappedKey: this._arrayBufferToBase64(wrappedKeyBuffer),
            nonce: this._arrayBufferToBase64(nonce),
        };
    },

    /**
     * Unwrap an encryption key using PRF-derived secret
     * @param {Uint8Array} prfOutput - PRF output from authentication
     * @param {string} wrappedKeyB64 - Base64 encoded wrapped key
     * @param {string} nonceB64 - Base64 encoded nonce
     * @returns {Promise<CryptoKey>} - Unwrapped encryption key
     */
    async unwrapKey(prfOutput, wrappedKeyB64, nonceB64) {
        // Derive wrapping key from PRF output
        const prfKeyMaterial = await crypto.subtle.importKey(
            'raw',
            prfOutput,
            'HKDF',
            false,
            ['deriveKey']
        );

        const wrappingKey = await crypto.subtle.deriveKey(
            {
                name: 'HKDF',
                salt: new TextEncoder().encode('vibedtracker-key-wrap'),
                info: new TextEncoder().encode('aes-gcm-wrapping'),
                hash: 'SHA-256',
            },
            prfKeyMaterial,
            { name: 'AES-GCM', length: 256 },
            false,
            ['wrapKey', 'unwrapKey']
        );

        // Decode inputs
        const wrappedKey = this._base64ToArrayBuffer(wrappedKeyB64);
        const nonce = this._base64ToArrayBuffer(nonceB64);

        // Unwrap the key
        const encryptionKey = await crypto.subtle.unwrapKey(
            'raw',
            wrappedKey,
            wrappingKey,
            { name: 'AES-GCM', iv: nonce },
            { name: 'AES-GCM', length: 256 },
            true,
            ['encrypt', 'decrypt']
        );

        return encryptionKey;
    },

    // ==================== Helper Functions ====================

    _prepareCreationOptions(options) {
        const prepared = { ...options };

        // Convert challenge
        prepared.challenge = this._base64urlToArrayBuffer(options.challenge);

        // Convert user.id
        if (options.user && options.user.id) {
            prepared.user = { ...options.user };
            prepared.user.id = this._base64urlToArrayBuffer(options.user.id);
        }

        // Convert excludeCredentials
        if (options.excludeCredentials) {
            prepared.excludeCredentials = options.excludeCredentials.map(cred => ({
                ...cred,
                id: this._base64urlToArrayBuffer(cred.id),
            }));
        }

        return prepared;
    },

    _prepareRequestOptions(options) {
        const prepared = { ...options };

        // Convert challenge
        prepared.challenge = this._base64urlToArrayBuffer(options.challenge);

        // Convert allowCredentials
        if (options.allowCredentials) {
            prepared.allowCredentials = options.allowCredentials.map(cred => ({
                ...cred,
                id: this._base64urlToArrayBuffer(cred.id),
            }));
        }

        // Prepare PRF extension input if present
        if (options.extensions && options.extensions.prf && options.extensions.prf.eval) {
            prepared.extensions = { ...options.extensions };
            prepared.extensions.prf = {
                eval: {
                    first: this._base64urlToArrayBuffer(options.extensions.prf.eval.first),
                },
            };
        }

        return prepared;
    },

    _arrayBufferToBase64url(buffer) {
        const bytes = new Uint8Array(buffer);
        let binary = '';
        for (let i = 0; i < bytes.length; i++) {
            binary += String.fromCharCode(bytes[i]);
        }
        return btoa(binary)
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=/g, '');
    },

    _base64urlToArrayBuffer(base64url) {
        const base64 = base64url
            .replace(/-/g, '+')
            .replace(/_/g, '/');
        const padLen = (4 - (base64.length % 4)) % 4;
        const padded = base64 + '='.repeat(padLen);
        const binary = atob(padded);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
        }
        return bytes.buffer;
    },

    _arrayBufferToBase64(buffer) {
        const bytes = new Uint8Array(buffer);
        let binary = '';
        for (let i = 0; i < bytes.length; i++) {
            binary += String.fromCharCode(bytes[i]);
        }
        return btoa(binary);
    },

    _base64ToArrayBuffer(base64) {
        const binary = atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
            bytes[i] = binary.charCodeAt(i);
        }
        return bytes.buffer;
    },
};

// UI Helper for Passkey management
const PasskeyUI = {
    /**
     * Check and show passkey availability status
     * @param {HTMLElement} container - Container element for status message
     */
    async showAvailabilityStatus(container) {
        if (!VTPasskey.isSupported()) {
            container.innerHTML = `
                <div class="alert alert-warning">
                    <strong>Passkeys nicht unterstützt</strong><br>
                    Dein Browser unterstützt keine Passkeys.
                    Bitte verwende Chrome, Safari oder Edge in einer aktuellen Version.
                </div>
            `;
            return false;
        }

        const platformAvailable = await VTPasskey.isPlatformAuthenticatorAvailable();
        if (!platformAvailable) {
            container.innerHTML = `
                <div class="alert alert-info">
                    <strong>Kein Plattform-Authenticator</strong><br>
                    Dein Gerät hat keinen integrierten Authenticator (Touch ID, Face ID, Windows Hello).
                    Du kannst einen externen Security Key verwenden.
                </div>
            `;
            return true; // Still supported, just not platform
        }

        const prfSupported = VTPasskey.isPRFLikelySupported();
        container.innerHTML = `
            <div class="alert alert-success">
                <strong>Passkeys verfügbar</strong><br>
                Du kannst Passkeys für die Anmeldung und zum Entsperren verwenden.
                ${prfSupported ? '✓ Schnell-Entsperren unterstützt' : ''}
            </div>
        `;
        return true;
    },

    /**
     * Register a new passkey with UI feedback
     * @param {CryptoKey} encryptionKey - Optional encryption key to wrap
     * @returns {Promise<boolean>} - Success status
     */
    async registerWithUI(encryptionKey = null) {
        try {
            // Get registration options from server
            const optionsResponse = await fetch('/web/passkey/register/begin', {
                method: 'POST',
                credentials: 'include',
            });

            if (!optionsResponse.ok) {
                throw new Error('Failed to get registration options');
            }

            const options = await optionsResponse.json();

            // Prompt for passkey name
            const name = prompt('Name für diesen Passkey:', 'Mein ' + (navigator.platform || 'Gerät'));
            if (name === null) {
                return false; // User cancelled
            }

            // Create passkey
            const credential = await VTPasskey.register(options, name, encryptionKey);

            // Send to server
            const finishResponse = await fetch('/web/passkey/register/finish', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify(credential),
            });

            if (!finishResponse.ok) {
                const error = await finishResponse.json();
                throw new Error(error.error || 'Registration failed');
            }

            alert('Passkey erfolgreich registriert!');
            return true;

        } catch (e) {
            console.error('Passkey registration error:', e);
            alert('Fehler: ' + e.message);
            return false;
        }
    },

    /**
     * Authenticate with passkey and optionally unwrap encryption key
     * @returns {Promise<{success: boolean, encryptionKey?: CryptoKey}>}
     */
    async authenticateWithUI() {
        try {
            // Get authentication options from server
            const optionsResponse = await fetch('/web/passkey/authenticate/begin', {
                method: 'POST',
                credentials: 'include',
            });

            if (!optionsResponse.ok) {
                const error = await optionsResponse.json();
                throw new Error(error.error || 'Failed to get authentication options');
            }

            const options = await optionsResponse.json();

            // Authenticate with passkey
            const credential = await VTPasskey.authenticate(options);

            // Send to server
            const finishResponse = await fetch('/web/passkey/authenticate/finish', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify(credential),
            });

            if (!finishResponse.ok) {
                const error = await finishResponse.json();
                throw new Error(error.error || 'Authentication failed');
            }

            const result = await finishResponse.json();

            // If we have PRF output and wrapped key, unwrap it
            if (credential.prfOutput && result.wrapped_key && result.key_nonce) {
                const encryptionKey = await VTPasskey.unwrapKey(
                    credential.prfOutput,
                    result.wrapped_key,
                    result.key_nonce
                );

                // Store in session
                await VTCrypto.storeKey(encryptionKey);

                return { success: true, encryptionKey };
            }

            return { success: true };

        } catch (e) {
            console.error('Passkey authentication error:', e);
            alert('Fehler: ' + e.message);
            return { success: false };
        }
    },
};

// Export for module usage
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { VTPasskey, PasskeyUI };
}
