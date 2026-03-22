import 'dart:async';
import 'dart:developer';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/geofence_zone.dart';
import 'geofence_event_queue.dart';

/// Erkennt Zonenein- und -austritte anhand des verbundenen WiFi-Netzes.
///
/// Funktioniert komplementär zum GPS-Geofencing:
/// - Energie: near-zero (event-driven, kein aktives Scanning)
/// - Zuverlässigkeit: sehr hoch für Innen-Bereiche (Büro, Homeoffice)
/// - Latenz: sofort bei WiFi-Verbindungswechsel
///
/// Jede GeofenceZone kann optional eine WiFi-SSID hinterlegt haben.
/// Wird die SSID verbunden/getrennt, wird ein Enter/Exit-Event
/// in die GeofenceEventQueue eingereiht (identisch zum GPS-Pfad).
class WifiZoneService {
  final NetworkInfo _networkInfo = NetworkInfo();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  List<GeofenceZone> _zones = [];
  String? _currentZoneId; // ID der Zone, die aktuell via WiFi aktiv ist

  /// Wird aufgerufen wenn ein Enter- oder Exit-Event eingereiht wurde.
  /// HomeScreen nutzt das zum Anstoßen von _syncPendingEvents().
  void Function()? onZoneEvent;

  /// Wird aufgerufen beim Exit aus einer bekannten Zone (inkl. Disconnect-Zeitpunkt).
  /// HomeScreen kann daraus einen Pause-Dialog ableiten.
  void Function(DateTime since)? onExitZone;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> init(List<GeofenceZone> zones) async {
    _zones = zones;

    // Initialer Check ohne Enter-Event (App-Start, nicht "neu verbunden")
    await _checkCurrentSsid(isInit: true);

    // Auf Connectivity-Änderungen lauschen
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((_) => _checkCurrentSsid());
  }

  /// Zonen aktualisieren (aufrufen wenn sich die Zone-Liste ändert).
  void updateZones(List<GeofenceZone> zones) {
    _zones = zones;
    _checkCurrentSsid();
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  // ── Kern-Logik ─────────────────────────────────────────────────────────────

  Future<void> _checkCurrentSsid({bool isInit = false}) async {
    final ssid = await _getCurrentSsid();

    // Zone suchen, deren SSID mit der aktuellen übereinstimmt
    final GeofenceZone? matchingZone = _zones
        .where((z) =>
            z.isActive && (z.wifiSSID?.isNotEmpty ?? false) && z.wifiSSID == ssid)
        .firstOrNull;

    final newZoneId = matchingZone?.id;
    if (newZoneId == _currentZoneId) return; // keine Änderung

    final previousZoneId = _currentZoneId;
    _currentZoneId = newZoneId;

    if (newZoneId != null) {
      // ── ENTER ──────────────────────────────────────────────────────────
      log('WifiZoneService: ENTER zone "${matchingZone!.name}" (SSID: $ssid)',
          name: 'WifiZoneService');
      await GeofenceEventQueue.enqueue(GeofenceEventData(
        zoneId: newZoneId,
        event: GeofenceEvent.enter,
        timestamp: DateTime.now(),
      ));
      onZoneEvent?.call();
    } else if (previousZoneId != null && !isInit) {
      // ── EXIT ───────────────────────────────────────────────────────────
      log('WifiZoneService: EXIT zone $previousZoneId (now on: ${ssid ?? "offline"})',
          name: 'WifiZoneService');
      await GeofenceEventQueue.enqueue(GeofenceEventData(
        zoneId: previousZoneId,
        event: GeofenceEvent.exit,
        timestamp: DateTime.now(),
      ));
      onZoneEvent?.call();
      onExitZone?.call(DateTime.now());
    }
  }

  Future<String?> _getCurrentSsid() async {
    try {
      final raw = await _networkInfo.getWifiName();
      if (raw == null || raw.isEmpty) return null;
      // iOS liefert SSID mit Anführungszeichen: "MeinNetz"
      return raw.replaceAll('"', '').trim();
    } catch (e) {
      log('WifiZoneService: SSID-Abfrage fehlgeschlagen: $e',
          name: 'WifiZoneService');
      return null;
    }
  }

  // ── Debug-Hilfe ────────────────────────────────────────────────────────────

  /// Gibt die aktuell verbundene SSID zurück (für UI-Anzeige).
  Future<String?> currentSsid() => _getCurrentSsid();

  /// Gibt an ob aktuell eine Zone via WiFi aktiv ist.
  bool get isInWifiZone => _currentZoneId != null;

  /// ID der aktuell aktiven WiFi-Zone (null = keine).
  String? get currentWifiZoneId => _currentZoneId;
}
