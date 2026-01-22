# Geofence Package Alternativen für VibedTracker

## Aktuelles Problem

Das aktuelle Package `geofence_foreground_service` (v1.1.5) hat einen kritischen Bug:
- Service crasht mit NullPointerException wenn Android ihn nach Memory-Pressure neu startet
- Geofencing fällt für 46+ Minuten aus nach jedem Crash

---

## Alternative Packages

### 1. native_geofence (Empfohlen)

**pub.dev:** https://pub.dev/packages/native_geofence

**Vorteile:**
- Basiert auf demselben Konzept, aber aktiver maintained
- Nutzt native iOS (CLLocationManager) und Android (GeofencingClient) APIs
- Erlaubt Customizing der Foreground Service Notification
- Wake Lock Duration konfigurierbar
- Battery-effizient

**Nachteile:**
- Erfordert iOS 14+ und Android API 29+
- Flutter + Kotlin 2+ Kompatibilitätsprobleme (Jan 2025)

**Migration Aufwand:** Mittel - ähnliche API wie geofence_foreground_service

```yaml
dependencies:
  native_geofence: ^1.0.0
```

---

### 2. flutter_background_geolocation (Transistorsoft)

**Website:** https://www.transistorsoft.com/shop/products/flutter-background-geolocation

**Vorteile:**
- Professionell maintained, sehr robust
- Sophisticated motion-detection intelligence
- Unlimited Geofences (bis 100 pro Device wegen Google-Limit)
- Polygon Geofences unterstützt
- Überlebt Device Reboot und App Terminate
- Beste Battery-Effizienz

**Nachteile:**
- **Kommerziell** - Lizenz erforderlich für Production
- Komplexere Integration

**Migration Aufwand:** Hoch - andere API, aber robuster

---

### 3. Radar.io SDK

**Docs:** https://docs.radar.com/sdk/flutter

**Vorteile:**
- Cloud-basiertes Geofencing
- Analytics und Insights
- Server-side Geofence Management

**Nachteile:**
- Benötigt Cloud-Account
- Datenschutz-Bedenken (Standort geht an Drittanbieter)
- Overkill für einfache Use Cases

**Migration Aufwand:** Hoch - komplett anderes Konzept

---

### 4. DIY: WorkManager + Location Polling

**Konzept:** Eigene Implementierung mit `workmanager` + `geolocator`

**Vorteile:**
- Volle Kontrolle
- Kein Dependency auf externe Packages
- Kann spezifisch für unsere Needs optimiert werden

**Nachteile:**
- Mehr Entwicklungsaufwand
- Battery-Effizienz muss selbst optimiert werden
- Kein echtes Geofencing, nur periodisches Polling (alle 15 min)

**Migration Aufwand:** Sehr hoch - komplett neu implementieren

---

## Empfehlung

### Kurzfristig (jetzt):
1. **Workaround nutzen:** Akkuoptimierung deaktivieren
2. **Bug Report** an geofence_foreground_service Maintainer senden
3. Warten auf Fix

### Mittelfristig (wenn kein Fix kommt):
1. **Migration zu `native_geofence`** - ähnlichste API, aktiver maintained
2. Oder: Package forken und selbst fixen

### Langfristig (wenn Budget vorhanden):
1. **flutter_background_geolocation** evaluieren - professionellste Lösung

---

## Migration Checkliste (zu native_geofence)

- [ ] pubspec.yaml updaten
- [ ] GeofenceService.dart anpassen
- [ ] GeofenceCallback.dart anpassen
- [ ] AndroidManifest.xml Permissions prüfen
- [ ] iOS Info.plist Permissions prüfen
- [ ] Notification Channel anpassen
- [ ] Testen auf Android und iOS

---

## Referenzen

- [Flutter Geolocation Packages](https://fluttergems.dev/geolocation-utilities/)
- [native_geofence Docs](https://pub.dev/documentation/native_geofence/latest/)
- [Geofencing in Flutter (Medium)](https://medium.com/@m5lk3n/geofencing-in-flutter-f610cb212964)
- [Flutter Background Processes](https://docs.flutter.dev/packages-and-plugins/background-processes)
