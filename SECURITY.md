# VibedTracker Security Architecture

Dieses Dokument beschreibt die Sicherheitsarchitektur von VibedTracker im Detail.
Es richtet sich an sicherheitsbewusste Nutzer, Auditoren und Entwickler.

---

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [Zero-Knowledge Verschlüsselung](#zero-knowledge-verschlüsselung)
3. [Kryptographische Primitive](#kryptographische-primitive)
4. [Authentifizierung](#authentifizierung)
5. [Passkey-Support (WebAuthn)](#passkey-support-webauthn)
6. [Datenspeicherung](#datenspeicherung)
7. [Netzwerksicherheit](#netzwerksicherheit)
8. [Bedrohungsmodell](#bedrohungsmodell)
9. [Sicherheits-Checkliste](#sicherheits-checkliste)
10. [Responsible Disclosure](#responsible-disclosure)

---

## Übersicht

VibedTracker implementiert ein **Zero-Knowledge** Sicherheitsmodell:

```
┌─────────────────────────────────────────────────────────────────────┐
│                      SECURITY ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐                           ┌─────────────┐         │
│  │   CLIENT    │                           │   SERVER    │         │
│  │  (App/Web)  │                           │             │         │
│  ├─────────────┤                           ├─────────────┤         │
│  │             │                           │             │         │
│  │ Passphrase  │──PBKDF2──►┌──────────┐   │ Salt        │         │
│  │ (Nutzer)    │           │ AES-256  │   │ (öffentl.)  │         │
│  │             │           │ Key      │   │             │         │
│  │             │           └────┬─────┘   │             │         │
│  │             │                │         │             │         │
│  │ Klartext ───┼──AES-GCM──────►│         │             │         │
│  │ Daten       │                │         │             │         │
│  │             │                ▼         │             │         │
│  │             │         ┌──────────┐     │ Encrypted   │         │
│  │             │         │ Cipher-  │────►│ Blob        │         │
│  │             │         │ text+MAC │     │ (speichert) │         │
│  │             │         └──────────┘     │             │         │
│  │             │                          │             │         │
│  │ Server kann│NIEMALS Klartext sehen    │ ✗ Kein Key  │         │
│  │            │                           │ ✗ Kein      │         │
│  │            │                           │   Klartext  │         │
│  └────────────┘                           └─────────────┘         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Sicherheitsgarantien

| Garantie | Beschreibung |
|----------|--------------|
| **Vertraulichkeit** | Nur der Nutzer kann seine Daten lesen |
| **Integrität** | Manipulation wird durch MAC erkannt |
| **Zero-Knowledge** | Server lernt nichts über die Daten |
| **Forward Secrecy** | Vergangene Daten bleiben sicher bei Key-Kompromittierung* |

*Gilt pro Verschlüsselungskey - bei Passphrase-Änderung werden alle Daten neu verschlüsselt.

---

## Zero-Knowledge Verschlüsselung

### Warum Zero-Knowledge?

1. **Datenschutz**: Selbst bei Server-Hack sind Daten unlesbar
2. **Compliance**: DSGVO Art. 25 (Privacy by Design)
3. **Vertrauen**: Nutzer muss dem Betreiber nicht vertrauen
4. **Rechtlich**: Betreiber kann Daten nicht herausgeben (auch nicht an Behörden)

### Verschlüsselungs-Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ENCRYPTION FLOW                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  EINRICHTUNG (einmalig)                                             │
│  ───────────────────────                                            │
│                                                                     │
│  1. Nutzer wählt Passphrase                                         │
│          │                                                          │
│          ▼                                                          │
│  2. Client generiert Salt (16 Bytes, zufällig)                     │
│          │                                                          │
│          ▼                                                          │
│  3. PBKDF2(passphrase, salt, 100.000 iter) → 256-bit Key           │
│          │                                                          │
│          ▼                                                          │
│  4. HMAC-SHA256(key, "vibedtracker-verification") → Hash           │
│          │                                                          │
│          ▼                                                          │
│  5. Salt + Hash an Server (Key bleibt lokal!)                      │
│                                                                     │
│                                                                     │
│  VERSCHLÜSSELUNG (pro Eintrag)                                      │
│  ─────────────────────────────                                      │
│                                                                     │
│  1. Eintrag als JSON serialisieren                                  │
│          │                                                          │
│          ▼                                                          │
│  2. Nonce generieren (12 Bytes, zufällig)                          │
│          │                                                          │
│          ▼                                                          │
│  3. AES-256-GCM(key, nonce, plaintext) → ciphertext + tag          │
│          │                                                          │
│          ▼                                                          │
│  4. Blob = ciphertext || tag (MAC am Ende)                         │
│          │                                                          │
│          ▼                                                          │
│  5. Blob + Nonce an Server                                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Was der Server speichert

```json
{
  "user_id": "uuid",
  "data_type": "work_entry",
  "local_id": "client-generated-uuid",
  "encrypted_blob": "base64(ciphertext + mac)",
  "nonce": "base64(12 bytes)",
  "updated_at": "timestamp"
}
```

### Was der Server NICHT kennt

- ❌ Passphrase
- ❌ Abgeleiteter Key
- ❌ Klartext-Daten
- ❌ Struktur der Daten

---

## Kryptographische Primitive

### Übersicht der verwendeten Algorithmen

| Komponente | Algorithmus | Parameter | Standard |
|------------|-------------|-----------|----------|
| **Key Derivation** | PBKDF2-HMAC-SHA256 | 100.000 Iterationen | RFC 8018 |
| **Verschlüsselung** | AES-256-GCM | 256-bit Key, 12-byte Nonce | NIST SP 800-38D |
| **Authentifizierung** | HMAC-SHA256 | - | RFC 2104 |
| **Password Hashing** | bcrypt | Cost 12 | OpenBSD |
| **Session Tokens** | CSPRNG | 256-bit | - |

### PBKDF2 - Key Derivation

```
Eingabe:
  - Passphrase (UTF-8 encoded)
  - Salt (16 Bytes, zufällig)
  - Iterationen: 100.000
  - Hash: HMAC-SHA256

Ausgabe:
  - 256-bit Key für AES-GCM

Sicherheit:
  - 100k Iterationen ≈ 100ms auf modernem PC
  - Brute-Force: ~10.000 Versuche/Sekunde/GPU
  - Mit 12-Zeichen-Passphrase: >10^15 Jahre
```

### AES-256-GCM - Authenticated Encryption

```
Eigenschaften:
  - Vertraulichkeit (AES-256)
  - Integrität (GHASH MAC)
  - Authentizität (16-byte Tag)

Nonce-Handling:
  - 12 Bytes (96 Bit)
  - Zufällig generiert pro Verschlüsselung
  - Niemals wiederverwendet mit gleichem Key

Sicherheitsmarge:
  - AES-256: 256-bit Sicherheit
  - GCM: 128-bit Tag
  - Kollisionsgrenze: 2^32 Verschlüsselungen pro Key
```

### Passphrase-Anforderungen

| Anforderung | Minimum | Empfohlen |
|-------------|---------|-----------|
| **Länge** | 12 Zeichen | 16+ Zeichen |
| **Großbuchstaben** | 1 | 2+ |
| **Kleinbuchstaben** | 1 | 2+ |
| **Ziffern** | 1 | 2+ |
| **Sonderzeichen** | 1 | 2+ |

Entropie-Schätzung:
- 12 Zeichen (gemischt): ~72 Bit Entropie
- 16 Zeichen (gemischt): ~96 Bit Entropie

---

## Authentifizierung

### Login-Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AUTHENTICATION FLOW                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  CLIENT                              SERVER                         │
│  ──────                              ──────                         │
│                                                                     │
│  1. E-Mail + Passwort ──────────────► Validierung                  │
│                                       bcrypt.Compare()              │
│                                              │                      │
│                                              ▼                      │
│                           ┌─────────────────────────────┐          │
│                           │ 2FA aktiviert?              │          │
│                           └──────────┬──────────────────┘          │
│                                      │                              │
│                         ┌────────────┴────────────┐                │
│                         │                         │                │
│                         ▼                         ▼                │
│                     JA: TOTP                  NEIN: JWT            │
│                         │                         │                │
│  2. TOTP-Code ─────────►│                         │                │
│                         │                         │                │
│                         ▼                         │                │
│  ◄───────────────── JWT Token ◄───────────────────┘                │
│                                                                     │
│  3. JWT in Cookie (HttpOnly, Secure, SameSite=Strict)              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### JWT Token

```
Header:
  alg: HS256
  typ: JWT

Payload:
  sub: user_id (UUID)
  email: user@example.com
  role: user|admin
  device_id: device_uuid
  exp: expiration_timestamp
  iat: issued_at_timestamp

Signature:
  HMAC-SHA256(header.payload, server_secret)
```

### Zwei-Faktor-Authentifizierung (2FA)

- **Algorithmus**: TOTP (RFC 6238)
- **Hash**: SHA-1 (Standard für Authenticator-Apps)
- **Zeitschritt**: 30 Sekunden
- **Ziffern**: 6
- **Secret**: 160 Bit, Base32 encoded

### Session-Sicherheit

| Maßnahme | Implementierung |
|----------|-----------------|
| **Cookie Flags** | HttpOnly, Secure, SameSite=Strict |
| **Token-Rotation** | Bei jedem Login |
| **Expiration** | 24 Stunden (konfigurierbar) |
| **Device-Binding** | Token an Device-ID gebunden |

---

## Passkey-Support (WebAuthn)

### Übersicht

VibedTracker unterstützt **optional** WebAuthn/Passkeys für:
1. Passwordloses Login
2. Komfort-Entsperren (ohne Passphrase-Eingabe)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PASSKEY ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  STANDARD-MODUS              PASSKEY-MODUS                          │
│  (ohne Passkey)              (mit Passkey + PRF)                    │
│                                                                     │
│  ┌─────────────┐             ┌─────────────┐                       │
│  │ Passphrase  │             │ Biometrie/  │                       │
│  │ eingeben    │             │ PIN         │                       │
│  └──────┬──────┘             └──────┬──────┘                       │
│         │                           │                               │
│         ▼                           ▼                               │
│  ┌─────────────┐             ┌─────────────┐                       │
│  │ PBKDF2      │             │ WebAuthn    │                       │
│  │ Key Deriv.  │             │ + PRF Ext.  │                       │
│  └──────┬──────┘             └──────┬──────┘                       │
│         │                           │                               │
│         ▼                           ▼                               │
│  ┌─────────────┐             ┌─────────────┐                       │
│  │ AES-256 Key │             │ PRF Secret  │                       │
│  │ (direkt)    │             │             │                       │
│  └──────┬──────┘             └──────┬──────┘                       │
│         │                           │                               │
│         │                           ▼                               │
│         │                    ┌─────────────┐                       │
│         │                    │ Wrapped Key │                       │
│         │                    │ entschlüss. │                       │
│         │                    └──────┬──────┘                       │
│         │                           │                               │
│         ▼                           ▼                               │
│  ┌─────────────────────────────────────────┐                       │
│  │           AES-256 Encryption Key        │                       │
│  │           (in sessionStorage)           │                       │
│  └─────────────────────────────────────────┘                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### PRF Extension (Pseudo-Random Function)

Die PRF-Extension (Chrome 116+, Safari 17+) ermöglicht:

1. **Deterministisches Secret**: Passkey generiert immer gleiches Secret
2. **Hardware-gebunden**: Secret kann nicht exportiert werden
3. **Key Wrapping**: Encryption Key wird mit PRF-Secret verschlüsselt

```
PRF-Flow:
1. WebAuthn-Authentifizierung mit PRF-Request
2. Authenticator gibt PRF-Output (32 Bytes)
3. HKDF(prfOutput, "vibedtracker-key-wrap") → Wrapping Key
4. AES-GCM-Unwrap(wrappedKey, wrappingKey) → Encryption Key
```

### Sicherheitsüberlegungen

| Aspekt | Standard-Modus | Passkey-Modus |
|--------|----------------|---------------|
| **Key-Schutz** | RAM only (sessionStorage) | Hardware (TPM/Secure Enclave) |
| **Persistenz** | Nie | Wrapped Key auf Server |
| **Kompromittierung** | Passphrase nötig | Biometrie/PIN + Hardware |
| **Offline-Zugang** | Ja (mit Passphrase) | Nein (Authenticator nötig) |

### Wann Passkey-Modus nutzen?

| Szenario | Empfehlung |
|----------|------------|
| **Maximale Sicherheit** | Standard-Modus (Passphrase) |
| **Alltäglicher Komfort** | Passkey-Modus |
| **Geteiltes Gerät** | Standard-Modus |
| **Persönliches Gerät** | Passkey-Modus |

---

## Datenspeicherung

### Client (Flutter App)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LOCAL STORAGE (FLUTTER)                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Hive Database (verschlüsselt mit AES-256)                         │
│  ├── work_entries.hive    → Zeiteinträge                           │
│  ├── vacations.hive       → Urlaubstage                            │
│  ├── settings.hive        → Einstellungen                          │
│  └── projects.hive        → Projekte                               │
│                                                                     │
│  Flutter Secure Storage (Keychain/Keystore)                        │
│  ├── encryption_key       → AES-Key (nur bei aktivem Lock)         │
│  └── jwt_token           → Auth-Token                              │
│                                                                     │
│  Shared Preferences (unverschlüsselt)                              │
│  └── non_sensitive_settings → UI-Präferenzen                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Client (Web Browser)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    BROWSER STORAGE                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  sessionStorage (cleared on tab close)                             │
│  └── vt_encryption_key    → AES-Key (Base64)                       │
│                                                                     │
│  Cookies (HttpOnly, Secure)                                        │
│  └── session_token        → JWT für API-Zugriff                    │
│                                                                     │
│  localStorage (persistent) - NUR wenn Passkey aktiv                │
│  └── (keine sensitiven Daten)                                      │
│                                                                     │
│  NICHT VERWENDET:                                                  │
│  ✗ localStorage für Keys                                           │
│  ✗ IndexedDB für Keys                                              │
│  ✗ Cookies für Keys                                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Server (PostgreSQL)

```sql
-- Alle sensitiven Daten sind verschlüsselt
encrypted_data (
    id UUID,
    user_id UUID,
    data_type VARCHAR,        -- 'work_entry', 'vacation', etc.
    local_id VARCHAR,         -- Client-generierte ID
    encrypted_blob TEXT,      -- Base64(ciphertext + MAC)
    nonce TEXT,               -- Base64(12 bytes)
    updated_at TIMESTAMP
);

-- Server kennt NUR:
-- ✓ Wer (user_id)
-- ✓ Wann (updated_at)
-- ✓ Typ (data_type)
-- ✓ Wie viele Einträge

-- Server kennt NICHT:
-- ✗ Inhalt der Einträge
-- ✗ Konkrete Arbeitszeiten
-- ✗ Urlaubstage
-- ✗ Projekte
```

---

## Netzwerksicherheit

### TLS-Konfiguration

| Einstellung | Wert |
|-------------|------|
| **Minimum Version** | TLS 1.2 |
| **Empfohlen** | TLS 1.3 |
| **Cipher Suites** | ECDHE+AESGCM |
| **HSTS** | max-age=31536000; includeSubDomains |
| **Certificate** | Let's Encrypt (ECDSA P-256) |

### API-Sicherheit

```
Headers:
  Content-Security-Policy: default-src 'self'
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  X-XSS-Protection: 1; mode=block
  Referrer-Policy: strict-origin-when-cross-origin
```

### Rate Limiting

| Endpoint | Limit | Zeitfenster |
|----------|-------|-------------|
| `/api/login` | 5 | pro Minute |
| `/api/totp/verify` | 5 | pro Minute |
| `/api/passphrase/reset` | 3 | pro Stunde |
| `/api/*` (allgemein) | 100 | pro Minute |

---

## Bedrohungsmodell

### Annahmen

1. **TLS ist sicher**: Verschlüsselung der Übertragung funktioniert
2. **Client ist vertrauenswürdig**: Keine Malware auf dem Gerät
3. **Kryptographie ist sicher**: AES-256, SHA-256 sind nicht gebrochen

### Bedrohungen und Mitigationen

| Bedrohung | Risiko | Mitigation |
|-----------|--------|------------|
| **Server-Kompromittierung** | Hoch | Zero-Knowledge (Daten unlesbar) |
| **Man-in-the-Middle** | Mittel | TLS 1.2+, Certificate Pinning |
| **Brute-Force Passphrase** | Mittel | PBKDF2 100k iter, Passwort-Policy |
| **Session Hijacking** | Mittel | HttpOnly Cookies, Device-Binding |
| **XSS** | Niedrig | CSP, Input Sanitization |
| **CSRF** | Niedrig | SameSite Cookies, CSRF Tokens |
| **SQL Injection** | Niedrig | Parameterized Queries |

### Was VibedTracker NICHT schützt

| Bedrohung | Warum nicht? |
|-----------|--------------|
| **Kompromittiertes Endgerät** | Keylogger kann Passphrase abfangen |
| **Physischer Zugriff (entsperrt)** | Daten sind entschlüsselt |
| **Staatliche Akteure** | Targeted Attacks mit großen Ressourcen |
| **Social Engineering** | Nutzer gibt Passphrase preis |

---

## Sicherheits-Checkliste

### Für Nutzer

- [ ] Starke Passphrase (mind. 12 Zeichen, gemischt)
- [ ] 2FA aktiviert
- [ ] Passphrase nicht wiederverwenden
- [ ] Regelmäßig Geräte prüfen (Einstellungen → Geräte)
- [ ] Backup der Recovery Codes
- [ ] Bildschirmsperre auf Gerät aktiviert

### Für Self-Hoster

- [ ] HTTPS mit gültigem Zertifikat
- [ ] Aktuelle Server-Version
- [ ] Firewall konfiguriert (nur 443)
- [ ] Regelmäßige Backups
- [ ] Log-Monitoring eingerichtet
- [ ] Secrets nicht in Git
- [ ] Datenbank-Passwort stark

### Für Entwickler

- [ ] Dependencies aktuell (Dependabot)
- [ ] Keine Secrets in Code
- [ ] Input-Validierung überall
- [ ] Prepared Statements für SQL
- [ ] Security Headers gesetzt
- [ ] Rate Limiting aktiv

---

## Responsible Disclosure

### Sicherheitslücke gefunden?

1. **NICHT** öffentlich posten
2. E-Mail an: security@vibedtracker.com (oder Issue mit [SECURITY] Tag)
3. Details:
   - Beschreibung der Lücke
   - Schritte zur Reproduktion
   - Mögliche Auswirkungen
   - Vorgeschlagene Behebung (optional)

### Reaktionszeit

| Schweregrad | Reaktion | Fix |
|-------------|----------|-----|
| **Kritisch** | 24h | 72h |
| **Hoch** | 48h | 1 Woche |
| **Mittel** | 1 Woche | 2 Wochen |
| **Niedrig** | 2 Wochen | Nächstes Release |

### Hall of Fame

Wir danken allen, die verantwortungsvoll Sicherheitslücken melden.

---

## Audit-History

| Datum | Typ | Ergebnis |
|-------|-----|----------|
| - | Noch keine externen Audits | - |

---

## Versionierung

| Version | Änderung |
|---------|----------|
| 1.0 | Initiale Dokumentation |

---

*Letzte Aktualisierung: Januar 2025*
