# VibedTracker - Produkt-Roadmap & Feature-Analyse

Dieses Dokument beschreibt potenzielle Features, deren Aufwand, Risiken und Priorisierung.

---

## Inhaltsverzeichnis

1. [Philosophie](#philosophie)
2. [UI-Modi Konzept](#ui-modi-konzept)
3. [Feature-Übersicht](#feature-übersicht)
4. [Detaillierte Feature-Analyse](#detaillierte-feature-analyse)
5. [Priorisierte Roadmap](#priorisierte-roadmap)
6. [Risiko-Matrix](#risiko-matrix)

---

## Philosophie

### Kernprinzipien

| Prinzip | Beschreibung |
|---------|--------------|
| **Einfachheit** | Die App muss ohne Handbuch bedienbar sein |
| **Sicherheit** | Zero-Knowledge bleibt oberstes Gebot |
| **Flexibilität** | Verschiedene Nutzer, verschiedene Bedürfnisse |
| **Progressiv** | Komplexität nur wenn nötig |

### Das "Einfach vs. Mächtig" Problem

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   EINFACH                                        MÄCHTIG            │
│   ────────                                       ───────            │
│                                                                     │
│   ● Freelancer                              ● Unternehmen           │
│   ● "Nur Stunden tracken"                   ● Projekte, Kunden      │
│   ● Geofence ein/aus                        ● Genehmigungen         │
│   ● Urlaub eintragen                        ● Überstundenkonten     │
│                                             ● Integrationen         │
│                                                                     │
│                        ┌─────────────┐                              │
│                        │  LÖSUNG:    │                              │
│                        │  UI-MODI    │                              │
│                        └─────────────┘                              │
│                                                                     │
│   Nutzer wählt seinen Modus → UI passt sich an                     │
│   Features sind da, aber versteckt wenn nicht gebraucht            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## UI-Modi Konzept

### Drei Modi für verschiedene Nutzergruppen

```
┌─────────────────────────────────────────────────────────────────────┐
│                         UI-MODI                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │     SIMPLE      │  │   FREELANCER    │  │    BUSINESS     │     │
│  │     (Solo)      │  │   (Projekte)    │  │    (Teams)      │     │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────────┤     │
│  │                 │  │                 │  │                 │     │
│  │ ✓ Geofence      │  │ ✓ Alles Simple  │  │ ✓ Alles Freel.  │     │
│  │ ✓ Start/Stop   │  │ + Projekte      │  │ + Team-Ansicht  │     │
│  │ ✓ Urlaub       │  │ + Kunden        │  │ + Genehmigungen │     │
│  │ ✓ Berichte     │  │ + Stundensätze  │  │ + Rollen        │     │
│  │                 │  │ + Rechnungs-    │  │ + Überstunden-  │     │
│  │                 │  │   Export        │  │   konten        │     │
│  │                 │  │                 │  │ + API-Zugang    │     │
│  │                 │  │                 │  │                 │     │
│  │  KOSTENLOS      │  │  PRO €5/Mon     │  │ BUSINESS €9/Mon │     │
│  │                 │  │                 │  │                 │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
│                                                                     │
│  Wechsel jederzeit möglich in Einstellungen                        │
│  Daten bleiben erhalten                                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### UI-Unterschiede pro Modus

| Element | Simple | Freelancer | Business |
|---------|--------|------------|----------|
| **Home Screen** | Start/Stop Button | + Projekt-Auswahl | + Team-Status |
| **Navigation** | 4 Tabs | 5 Tabs (+Projekte) | 6 Tabs (+Team) |
| **Berichte** | Basis | + Projekt-Filter | + Team-Auswertung |
| **Einstellungen** | Minimal | Erweitert | Vollständig |
| **Komplexität** | ⭐ | ⭐⭐ | ⭐⭐⭐ |

### Implementierung

```dart
// Modus in Settings speichern
enum AppMode { simple, freelancer, business }

// UI-Elemente conditional rendern
if (settings.appMode >= AppMode.freelancer) {
  // Projekt-Auswahl anzeigen
}

if (settings.appMode == AppMode.business) {
  // Team-Features anzeigen
}
```

**Aufwand:** Mittel (Refactoring bestehender UI)
**Risiko:** Niedrig (keine Sicherheitsimplikationen)

---

## Feature-Übersicht

### Bewertungsskala

| Kategorie | Bedeutung |
|-----------|-----------|
| **Aufwand** | S (Stunden), T (Tage), W (Wochen), M (Monate) |
| **Sicherheitsrisiko** | 🟢 Keins, 🟡 Gering, 🟠 Mittel, 🔴 Hoch |
| **UX-Risiko** | 🟢 Verbessert, 🟡 Neutral, 🟠 Komplexer, 🔴 Verwirrend |
| **Priorität** | P1 (Kritisch), P2 (Wichtig), P3 (Nice-to-have) |

### Feature-Matrix

| Feature | Aufwand | Sicherheit | UX | Priorität | Modus |
|---------|---------|------------|-----|-----------|-------|
| **iOS App** | M | 🟢 | 🟢 | P1 | Alle |
| **Projekt-Zeiterfassung** | W | 🟢 | 🟡 | P1 | Freelancer+ |
| **Pausen-Management** | T | 🟢 | 🟢 | P1 | Alle |
| **Überstundenkonten** | W | 🟢 | 🟡 | P2 | Business |
| **Genehmigungs-Workflows** | W | 🟡 | 🟠 | P2 | Business |
| **REST API** | W | 🟠 | 🟢 | P2 | Business |
| **Erweiterte Berichte** | W | 🟢 | 🟢 | P2 | Freelancer+ |
| **Benachrichtigungen** | T | 🟢 | 🟢 | P2 | Alle |
| **Mehrsprachigkeit** | W | 🟢 | 🟢 | P2 | Alle |
| **Rechnungs-Export** | T | 🟢 | 🟢 | P3 | Freelancer |
| **Team-Management** | M | 🟡 | 🟠 | P3 | Business |
| **Integrationen** | M | 🟠 | 🟢 | P3 | Business |
| **Desktop-App** | M | 🟢 | 🟢 | P3 | Alle |

---

## Detaillierte Feature-Analyse

### 1. iOS App

**Status:** Geplant
**Priorität:** P1 (Kritisch)

```
Aufwand:    ████████░░  2-3 Monate
Sicherheit: 🟢 Kein zusätzliches Risiko (Flutter Cross-Platform)
UX-Risiko:  🟢 Erwartet von Nutzern
```

**Beschreibung:**
Flutter ermöglicht iOS-Build mit gleichem Codebase. Hauptaufwand liegt in:
- Apple Developer Account & Zertifikate
- iOS-spezifische Anpassungen (Permissions, Background-Modes)
- App Store Review Prozess
- TestFlight Beta-Testing

**Technische Überlegungen:**
- Geofencing funktioniert anders auf iOS (mehr Einschränkungen)
- Background-Location erfordert spezielle Genehmigung
- Keychain statt Keystore für Secrets

**Zero-Knowledge Impact:** Keiner - gleiche Verschlüsselung

---

### 2. Projekt- und Kundenbezogene Zeiterfassung

**Status:** Teilweise vorhanden (Projekte existieren)
**Priorität:** P1 (Wichtig für Freelancer)

```
Aufwand:    █████░░░░░  1-2 Wochen
Sicherheit: 🟢 Daten werden genauso verschlüsselt
UX-Risiko:  🟡 Zusätzliche Komplexität, aber optional
```

**Aktueller Stand:**
- Projekte können angelegt werden
- Projekte können Einträgen zugeordnet werden

**Erweiterungen:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                    PROJEKT-ERWEITERUNG                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Projekt                                                            │
│  ├── Name                        (vorhanden)                       │
│  ├── Farbe                       (vorhanden)                       │
│  ├── Kunde (NEU)                                                   │
│  ├── Stundensatz (NEU)           €85/h                            │
│  ├── Budget-Stunden (NEU)        40h                              │
│  └── Notizen (NEU)                                                 │
│                                                                     │
│  Kunde (NEU)                                                        │
│  ├── Name                                                          │
│  ├── Kontakt                                                       │
│  └── Projekte[]                                                    │
│                                                                     │
│  Auswertung (NEU)                                                  │
│  ├── Stunden pro Projekt                                           │
│  ├── Stunden pro Kunde                                             │
│  ├── Umsatz pro Projekt (Stunden × Stundensatz)                   │
│  └── Budget-Auslastung                                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**UI-Integration (Freelancer-Modus):**
```
┌─────────────────────────────────────┐
│          HOME SCREEN                │
│  ┌─────────────────────────────┐   │
│  │  08:32:15                   │   │
│  │  ══════════════════════     │   │
│  │                             │   │
│  │  [▼ Projekt auswählen    ]  │  ← NEU: Dropdown
│  │                             │   │
│  │       [ ■ STOP ]            │   │
│  │                             │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

**Zero-Knowledge Impact:**
- Projekt/Kunden-Daten werden verschlüsselt
- Server sieht nur verschlüsselte Blobs

---

### 3. Pausen-Management

**Status:** Grundlegend vorhanden
**Priorität:** P1 (Gesetzlich relevant)

```
Aufwand:    ███░░░░░░░  3-5 Tage
Sicherheit: 🟢 Kein Risiko
UX-Risiko:  🟢 Verbessert Compliance
```

**Aktuelle Funktionen:**
- Manuelle Pausen können erfasst werden

**Erweiterungen:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                    PAUSEN-ERWEITERUNG                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Einstellungen:                                                     │
│  ┌─────────────────────────────────────────────────────┐           │
│  │ Automatische Pause                                  │           │
│  │ ─────────────────────────────────────────────────── │           │
│  │ [✓] Nach 6h: 30 Min Pause automatisch abziehen     │           │
│  │ [✓] Nach 9h: 45 Min Pause automatisch abziehen     │           │
│  │ [ ] Pausen manuell erfassen                        │           │
│  └─────────────────────────────────────────────────────┘           │
│                                                                     │
│  Erinnerungen:                                                      │
│  ┌─────────────────────────────────────────────────────┐           │
│  │ [✓] Erinnerung nach 4h ohne Pause                  │           │
│  │ [✓] Erinnerung bei Verlassen ohne Ausstempeln      │           │
│  └─────────────────────────────────────────────────────┘           │
│                                                                     │
│  Berechnung:                                                        │
│  ┌─────────────────────────────────────────────────────┐           │
│  │ Arbeitszeit:        8:00 - 17:30 = 9h 30min        │           │
│  │ Pause (auto):       - 45 Min                       │           │
│  │ ─────────────────────────────────────────────────── │           │
│  │ Netto-Arbeitszeit:  8h 45min                       │           │
│  └─────────────────────────────────────────────────────┘           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Gesetzliche Anforderungen (Deutschland):**
- > 6h Arbeit: mind. 30 Min Pause
- > 9h Arbeit: mind. 45 Min Pause
- Pause muss am Stück oder in 15-Min-Blöcken genommen werden

---

### 4. Überstundenkonten

**Status:** Teilweise (Wochenübersicht zeigt +/-)
**Priorität:** P2 (Business-Feature)

```
Aufwand:    █████░░░░░  1-2 Wochen
Sicherheit: 🟢 Kein Risiko
UX-Risiko:  🟡 Zusätzliche Komplexität
```

**Erweiterungen:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                    ÜBERSTUNDENKONTO                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Konto-Übersicht:                                                   │
│  ┌─────────────────────────────────────────────────────┐           │
│  │ Überstundenkonto                          +24:30h   │           │
│  │ ═══════════════════════════════════════════════════ │           │
│  │                                                     │           │
│  │ Vormonat:                          +18:00h          │           │
│  │ Dieser Monat:                      +8:30h           │           │
│  │ Abgebaut (Gleitzeit):              -2:00h           │           │
│  │ ─────────────────────────────────────────────────── │           │
│  │ Aktuell:                           +24:30h          │           │
│  └─────────────────────────────────────────────────────┘           │
│                                                                     │
│  Optionen:                                                          │
│  ┌─────────────────────────────────────────────────────┐           │
│  │ [✓] Überstunden ins nächste Jahr übertragen        │           │
│  │ [ ] Verfall nach 3 Monaten                         │           │
│  │ [ ] Auszahlung anfordern                           │           │
│  │ [✓] Gleitzeit-Abbau möglich                        │           │
│  └─────────────────────────────────────────────────────┘           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### 5. Genehmigungs-Workflows

**Status:** Nicht vorhanden
**Priorität:** P2 (Business-Feature)

```
Aufwand:    ██████░░░░  2-3 Wochen
Sicherheit: 🟡 Rollenbasierte Zugriffskontrolle nötig
UX-Risiko:  🟠 Erhöht Komplexität signifikant
```

**Konzept:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                    GENEHMIGUNGS-WORKFLOW                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  URLAUBSANTRAG                                                      │
│  ─────────────                                                      │
│                                                                     │
│  Mitarbeiter              Admin/Vorgesetzter                        │
│       │                          │                                  │
│       │  1. Antrag stellen      │                                  │
│       │  ───────────────────►   │                                  │
│       │                          │                                  │
│       │                          │  2. Prüfen                      │
│       │                          │     (Kalender, Kapazität)       │
│       │                          │                                  │
│       │  3. Genehmigt/Abgelehnt │                                  │
│       │  ◄───────────────────   │                                  │
│       │                          │                                  │
│       ▼                          │                                  │
│  Urlaub im Kalender              │                                  │
│  (automatisch)                   │                                  │
│                                                                     │
│                                                                     │
│  ZEITKORREKTUR                                                      │
│  ─────────────                                                      │
│                                                                     │
│  Mitarbeiter: "Habe vergessen auszustempeln"                       │
│       │                                                             │
│       │  1. Korrektur-Antrag                                       │
│       │  ───────────────────►  Admin                               │
│       │                          │                                  │
│       │                          │  2. Prüfen                      │
│       │                          │                                  │
│       │  3. Bestätigt            │                                  │
│       │  ◄───────────────────    │                                  │
│       │                          │                                  │
│       ▼                          │                                  │
│  Eintrag angepasst               │                                  │
│  (mit Audit-Log)                 │                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Sicherheitsüberlegungen:**
- Wer darf was sehen? (Verschlüsselung vs. Team-Sichtbarkeit)
- Option 1: Team-Shared-Key (alle im Team teilen einen Key)
- Option 2: Hybrid (Metadaten unverschlüsselt, Details verschlüsselt)
- Option 3: Nur Zusammenfassungen für Admins sichtbar

**Zero-Knowledge Impact:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                ZERO-KNOWLEDGE VS. TEAM-FEATURES                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  PROBLEM:                                                           │
│  Admin muss Urlaubsanträge sehen können                            │
│  ABER: Daten sind verschlüsselt mit User-Key                       │
│                                                                     │
│  LÖSUNGEN:                                                          │
│                                                                     │
│  A) Anträge separat (unverschlüsselt)                              │
│     + Einfach                                                       │
│     - Weniger Privatsphäre für Anträge                             │
│                                                                     │
│  B) Team-Shared-Key                                                 │
│     + Alle Team-Daten verschlüsselt                                │
│     - Komplex (Key-Verteilung)                                     │
│     - Nutzer verliert individuelle Kontrolle                       │
│                                                                     │
│  C) Hybrid (EMPFOHLEN)                                             │
│     Anträge: Unverschlüsselt (nur Typ, Datum, Status)              │
│     Details: Verschlüsselt mit User-Key                            │
│     + Balance zwischen Features und Privatsphäre                   │
│     + Admin sieht "Urlaub 15.-20.1." aber nicht Notizen           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**UX-Risiko:** Hoch - Feature muss sehr gut designed sein, sonst wird App "enterprise-bloated"

---

### 6. REST API

**Status:** Intern vorhanden, nicht dokumentiert
**Priorität:** P2 (Business-Feature)

```
Aufwand:    █████░░░░░  1-2 Wochen (Dokumentation, Rate Limiting)
Sicherheit: 🟠 API-Keys, OAuth, Rate Limiting nötig
UX-Risiko:  🟢 Kein UI-Impact
```

**Konzept:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                        REST API                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Endpunkte (Beispiel):                                             │
│                                                                     │
│  GET  /api/v1/entries          Liste aller Einträge               │
│  POST /api/v1/entries          Neuer Eintrag                       │
│  GET  /api/v1/entries/:id      Einzelner Eintrag                   │
│  PUT  /api/v1/entries/:id      Eintrag aktualisieren               │
│  DEL  /api/v1/entries/:id      Eintrag löschen                     │
│                                                                     │
│  GET  /api/v1/reports/weekly   Wochenbericht                       │
│  GET  /api/v1/reports/monthly  Monatsbericht                       │
│                                                                     │
│  GET  /api/v1/vacations        Urlaube                             │
│  POST /api/v1/vacations        Urlaub eintragen                    │
│                                                                     │
│                                                                     │
│  Authentifizierung:                                                 │
│  ─────────────────                                                  │
│  Authorization: Bearer <api_key>                                   │
│                                                                     │
│  WICHTIG: API liefert VERSCHLÜSSELTE Daten!                        │
│  Client muss Passphrase kennen um zu entschlüsseln                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Sicherheitsüberlegungen:**
- API-Keys mit Scopes (read-only, read-write)
- Rate Limiting (100 req/min)
- Audit-Logging
- CORS konfigurieren

**Zero-Knowledge Impact:**
- API liefert nur verschlüsselte Blobs
- Client/Integration muss Passphrase haben
- Alternative: Export-API für Berichte (aggregierte, unverschlüsselte Zusammenfassungen)

---

### 7. Erweiterte Berichte & Dashboards

**Status:** Grundlegend vorhanden
**Priorität:** P2

```
Aufwand:    █████░░░░░  1-2 Wochen
Sicherheit: 🟢 Kein Risiko (Client-Side Auswertung)
UX-Risiko:  🟢 Verbessert Nutzwert
```

**Erweiterungen:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                    DASHBOARD (Freelancer)                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ Diese Woche      │  │ Dieser Monat     │  │ Dieses Jahr      │  │
│  │    32:15h        │  │   142:30h        │  │  1.234:00h       │  │
│  │   +2:15 Ü-Std    │  │  +12:30 Ü-Std    │  │  +98:00 Ü-Std    │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│                                                                     │
│  Stunden pro Projekt (Monat)                                       │
│  ═══════════════════════════                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Kunde A - Projekt X    ████████████████████░░░░  45h (32%)  │   │
│  │ Kunde B - Website      ██████████░░░░░░░░░░░░░░  28h (20%)  │   │
│  │ Intern - Admin         ████████░░░░░░░░░░░░░░░░  22h (15%)  │   │
│  │ ...                                                          │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  Trend (letzte 12 Wochen)                                          │
│  ════════════════════════                                          │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │     ▁▂▄▆█▆▄▂▁▂▄▆                                             │   │
│  │     ──────────────────────────────────────────────           │   │
│  │     KW1  KW4  KW8  KW12                                      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### 8. Benachrichtigungen & Reminders

**Status:** Grundlegend vorhanden
**Priorität:** P2

```
Aufwand:    ███░░░░░░░  3-5 Tage
Sicherheit: 🟢 Kein Risiko
UX-Risiko:  🟢 Verbessert Nutzung
```

**Erweiterungen:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                    BENACHRICHTIGUNGEN                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Erinnerungen (konfigurierbar):                                     │
│                                                                     │
│  [✓] Arbeitsort verlassen ohne Ausstempeln                         │
│      → "Du hast den Arbeitsort verlassen. Timer gestoppt."         │
│                                                                     │
│  [✓] Arbeitsort betreten                                           │
│      → "Willkommen! Timer gestartet."                              │
│                                                                     │
│  [✓] Lange Arbeitszeit ohne Pause (nach 4h)                        │
│      → "Zeit für eine Pause? Du arbeitest seit 4 Stunden."         │
│                                                                     │
│  [✓] Fehlende Einträge am Abend                                    │
│      → "Du hast heute keine Arbeitszeit erfasst. Vergessen?"       │
│                                                                     │
│  [ ] Wochenübersicht am Freitag                                    │
│      → "Deine Woche: 42:30h gearbeitet, +2:30h Überstunden"        │
│                                                                     │
│  [ ] Urlaubs-Erinnerung                                            │
│      → "Morgen beginnt dein Urlaub. Genieß die freie Zeit!"        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### 9. Mehrsprachigkeit (i18n)

**Status:** Nur Deutsch
**Priorität:** P2 (für Expansion)

```
Aufwand:    █████░░░░░  1-2 Wochen (Setup + Englisch)
Sicherheit: 🟢 Kein Risiko
UX-Risiko:  🟢 Erweitert Zielgruppe
```

**Implementierung:**
```dart
// Flutter i18n mit ARB-Dateien
// lib/l10n/app_de.arb
{
  "homeTitle": "Zeiterfassung",
  "startButton": "Starten",
  "stopButton": "Stoppen"
}

// lib/l10n/app_en.arb
{
  "homeTitle": "Time Tracking",
  "startButton": "Start",
  "stopButton": "Stop"
}
```

**Zusätzlich nötig:**
- Feiertags-Datenbank pro Land
- Datumsformate (DD.MM.YYYY vs. MM/DD/YYYY)
- Zeitzonen-Support
- Rechtliche Unterschiede (Pausenregelungen pro Land)

---

### 10. Rechnungs-Export

**Status:** Nicht vorhanden
**Priorität:** P3 (Freelancer-Feature)

```
Aufwand:    ███░░░░░░░  3-5 Tage
Sicherheit: 🟢 Kein Risiko
UX-Risiko:  🟢 Mehrwert für Freelancer
```

**Konzept:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                    RECHNUNGS-EXPORT                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Export-Optionen:                                                   │
│                                                                     │
│  [✓] PDF-Stundennachweis                                           │
│      → Professionelles PDF mit Firmenlogo                          │
│      → Auflistung aller Stunden pro Projekt                        │
│      → Summen und Stundensatz                                      │
│                                                                     │
│  [✓] CSV für Buchhaltung                                           │
│      → Import in DATEV, Lexware, etc.                              │
│                                                                     │
│  [ ] Direkt-Integration (später)                                   │
│      → sevDesk, lexoffice, Billomat                                │
│                                                                     │
│                                                                     │
│  Beispiel PDF:                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ STUNDENNACHWEIS                                              │   │
│  │                                                               │   │
│  │ Kunde: Acme Corp                    Zeitraum: Jan 2024       │   │
│  │ Projekt: Website Redesign                                     │   │
│  │                                                               │   │
│  │ Datum      Von     Bis     Dauer   Beschreibung              │   │
│  │ ──────────────────────────────────────────────────────────── │   │
│  │ 02.01.24   09:00   17:30   8:00h   Design-Review             │   │
│  │ 03.01.24   08:30   16:00   7:00h   Frontend-Entwicklung      │   │
│  │ ...                                                           │   │
│  │ ──────────────────────────────────────────────────────────── │   │
│  │ SUMME                      42:30h  × €85 = €3.612,50         │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### 11. Team-Management

**Status:** Grundlegend (Admin-Panel)
**Priorität:** P3 (Business-Feature)

```
Aufwand:    ████████░░  1-2 Monate
Sicherheit: 🟡 Rollenbasierte Zugriffskontrolle
UX-Risiko:  🟠 Erhöht Komplexität
```

**Konzept:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                    TEAM-MANAGEMENT                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Rollen:                                                            │
│  ───────                                                            │
│  • Admin         - Alles                                           │
│  • Teamleiter    - Eigenes Team sehen, Genehmigungen               │
│  • Mitarbeiter   - Nur eigene Daten                                │
│                                                                     │
│  Teams:                                                             │
│  ──────                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Entwicklung                                                  │   │
│  │ ├── Max Müller (Teamleiter)                                 │   │
│  │ ├── Anna Schmidt                                            │   │
│  │ └── Tom Weber                                               │   │
│  │                                                               │   │
│  │ Marketing                                                     │   │
│  │ ├── Lisa Fischer (Teamleiter)                               │   │
│  │ └── Jan Bauer                                               │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  Team-Dashboard:                                                    │
│  ───────────────                                                    │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Wer ist da?              Heute                               │   │
│  │                                                               │   │
│  │ 🟢 Max Müller           08:15 - ...     (4:30h)             │   │
│  │ 🟢 Anna Schmidt         09:00 - ...     (3:45h)             │   │
│  │ 🔴 Tom Weber            Urlaub                               │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Zero-Knowledge Herausforderung:**
- Team-Mitglieder müssen Status sehen können
- Lösung: Anwesenheitsstatus unverschlüsselt (Metadata), Details verschlüsselt

---

### 12. Integrationen

**Status:** Nicht vorhanden
**Priorität:** P3 (später)

```
Aufwand:    ████████░░  Variabel (pro Integration 1-2 Wochen)
Sicherheit: 🟠 OAuth, Token-Management
UX-Risiko:  🟢 Kein direkter UI-Impact
```

**Mögliche Integrationen:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                    INTEGRATIONEN                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Buchhaltung:                                                       │
│  • DATEV (Export)                                                  │
│  • Lexware (Export)                                                │
│  • sevDesk (API)                                                   │
│  • lexoffice (API)                                                 │
│                                                                     │
│  HR-Systeme:                                                        │
│  • Personio (Import/Export)                                        │
│  • HRworks (API)                                                   │
│                                                                     │
│  Projektmanagement:                                                 │
│  • Jira (Tickets → Zeiterfassung)                                  │
│  • Asana (Tasks)                                                   │
│  • Trello (Cards)                                                  │
│                                                                     │
│  Kalender:                                                          │
│  • Google Calendar (vorhanden, read-only)                          │
│  • Outlook/Exchange (geplant)                                      │
│  • iCal (Export vorhanden)                                         │
│                                                                     │
│  Automatisierung:                                                   │
│  • Zapier (Webhooks)                                               │
│  • Make/Integromat                                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Priorisierte Roadmap

### Phase 1: Foundation (Q1)
*Ziel: Stabile Basis für alle Nutzergruppen*

| Feature | Aufwand | Status |
|---------|---------|--------|
| Pausen-Management erweitern | T | 🔲 |
| Benachrichtigungen erweitern | T | 🔲 |
| UI-Modi Konzept implementieren | W | 🔲 |
| Play Store Release | T | 🔲 |

### Phase 2: Freelancer (Q2)
*Ziel: Attraktiv für Freelancer*

| Feature | Aufwand | Status |
|---------|---------|--------|
| iOS App | M | 🔲 |
| Projekt-Erweiterung (Kunden, Stundensätze) | W | 🔲 |
| Erweiterte Berichte | W | 🔲 |
| Rechnungs-Export (PDF) | T | 🔲 |

### Phase 3: Business (Q3-Q4)
*Ziel: Attraktiv für kleine Unternehmen*

| Feature | Aufwand | Status |
|---------|---------|--------|
| Überstundenkonten | W | 🔲 |
| Genehmigungs-Workflows (Basis) | W | 🔲 |
| REST API (dokumentiert) | W | 🔲 |
| Mehrsprachigkeit (EN) | W | 🔲 |

### Phase 4: Enterprise (2025+)
*Ziel: Größere Teams und Integrationen*

| Feature | Aufwand | Status |
|---------|---------|--------|
| Team-Management erweitert | M | 🔲 |
| Integrationen (DATEV, Personio) | M | 🔲 |
| Desktop-App (optional) | M | 🔲 |
| White-Label Option | M | 🔲 |

---

## Risiko-Matrix

```
                    SICHERHEITS-RISIKO
                    Niedrig          Hoch
                       │               │
              ─────────┼───────────────┼─────────
                       │               │
    Niedrig   │  iOS App        │  (leer)      │
              │  Pausen         │               │
    A         │  Berichte       │               │
    U         │  i18n           │               │
    F         │                 │               │
    W    ─────┼─────────────────┼───────────────
    A         │                 │               │
    N         │  Projekte       │  API          │
    D         │  Überstunden    │               │
              │  Notifications  │               │
    Hoch      │                 │               │
         ─────┼─────────────────┼───────────────
              │                 │               │
              │  Team-Mgmt      │  Workflows    │
              │  Desktop        │  Integrationen│
              │                 │               │
              └─────────────────┴───────────────
```

### Empfehlung

**Priorisiere Features links oben** (niedriger Aufwand, niedriges Risiko):
1. Pausen-Management
2. Benachrichtigungen
3. i18n (Englisch)

**Dann Features mit höherem Aufwand, aber niedrigem Risiko:**
4. iOS App
5. Projekt-Erweiterungen
6. Berichte

**Zuletzt Features mit Sicherheits-Implikationen:**
7. API (gut dokumentiert, Rate Limiting)
8. Workflows (Hybrid-Ansatz für Zero-Knowledge)
9. Integrationen (OAuth, saubere Scopes)

---

## Zusammenfassung

### Die wichtigsten Erkenntnisse

1. **UI-Modi sind der Schlüssel** - Einfach für Einzelnutzer, mächtig für Business
2. **Zero-Knowledge vs. Team-Features** - Hybrid-Ansatz (Metadaten offen, Details verschlüsselt)
3. **iOS ist kritisch** - Ohne iOS fehlt ~50% der Zielgruppe
4. **Freelancer-Features zuerst** - Projekte, Stundensätze, Rechnungen
5. **Schrittweise Komplexität** - Nicht alles auf einmal

### Feature-Empfehlung nach Nutzergruppe

| Nutzer | Must-Have | Nice-to-Have |
|--------|-----------|--------------|
| **Einzelnutzer** | Geofence, Pausen, Berichte | Benachrichtigungen |
| **Freelancer** | + Projekte, Kunden, Stundensätze | Rechnungs-Export |
| **Kleines Team** | + Überstundenkonten, Team-Ansicht | Genehmigungen |
| **Unternehmen** | + API, Integrationen, Workflows | White-Label |
