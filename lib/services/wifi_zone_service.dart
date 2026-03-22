import 'dart:async';
import 'dart:developer';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/geofence_zone.dart';
import 'geofence_event_queue.dart';

/// Aktuell verbundene WiFi-Informationen (für UI und Matching).
class WifiInfo {
  final String? ssid;
  final String? bssid;

  const WifiInfo({this.ssid, this.bssid});

  bool get isConnected => ssid != null || bssid != null;

  /// Kurzform der BSSID für Anzeige: nur die letzten 3 Bytes.
  /// z.B. "AA:BB:CC:DD:EE:FF" → "DD:EE:FF"
  String get bssidShort {
    if (bssid == null) return '';
    final parts = bssid!.split(':');
    if (parts.length < 3) return bssid!;
    return parts.sublist(parts.length - 3).join(':').toUpperCase();
  }

  @override
  String toString() => 'WifiInfo(ssid: $ssid, bssid: $bssid)';
}

/// Erkennt Zonenein- und -austritte anhand von SSID und/oder BSSID.
///
/// Matching-Priorität (spezifischer gewinnt):
///   1. BSSID-Match → Raum-Ebene (~1 AP pro Raum/Zone)
///   2. SSID-Match  → Gebäude-Ebene (ganzes Netzwerk)
///
/// Energie: near-zero — event-driven via OS-Callback, kein aktives Scanning.
class WifiZoneService {
  final NetworkInfo _networkInfo = NetworkInfo();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  List<GeofenceZone> _zones = [];
  String? _currentZoneId;

  /// Callback wenn Enter/Exit eingereiht → HomeScreen triggert Sync.
  void Function()? onZoneEvent;

  /// Callback beim Verlassen einer bekannten Zone → Pause-Dialog.
  void Function(DateTime since)? onExitZone;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> init(List<GeofenceZone> zones) async {
    _zones = zones;
    await _checkCurrentWifi(isInit: true);
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((_) => _checkCurrentWifi());
  }

  void updateZones(List<GeofenceZone> zones) {
    _zones = zones;
    _checkCurrentWifi();
  }

  void dispose() => _connectivitySub?.cancel();

  // ── Kern-Logik ─────────────────────────────────────────────────────────────

  Future<void> _checkCurrentWifi({bool isInit = false}) async {
    final info = await currentWifiInfo();
    final matchingZone = _findMatchingZone(info);

    final newZoneId = matchingZone?.id;
    if (newZoneId == _currentZoneId) return;

    final previousZoneId = _currentZoneId;
    _currentZoneId = newZoneId;

    if (newZoneId != null) {
      final matchType = _matchType(matchingZone!, info);
      log('WifiZoneService: ENTER "${matchingZone.name}" via $matchType '
          '(ssid=${info.ssid}, bssid=${info.bssid})',
          name: 'WifiZoneService');
      await GeofenceEventQueue.enqueue(GeofenceEventData(
        zoneId: newZoneId,
        event: GeofenceEvent.enter,
        timestamp: DateTime.now(),
      ));
      onZoneEvent?.call();
    } else if (previousZoneId != null && !isInit) {
      log('WifiZoneService: EXIT $previousZoneId → ${info.ssid ?? "offline"}',
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

  /// Sucht die passende Zone — BSSID hat Vorrang vor SSID.
  GeofenceZone? _findMatchingZone(WifiInfo info) {
    final active = _zones.where((z) => z.isActive);

    // 1. BSSID-Match (Raum-Ebene)
    if (info.bssid != null) {
      final match = active.where((z) =>
          z.wifiBSSID != null &&
          z.wifiBSSID!.isNotEmpty &&
          z.wifiBSSID!.toUpperCase() == info.bssid!.toUpperCase()).firstOrNull;
      if (match != null) return match;
    }

    // 2. SSID-Match (Netzwerk-Ebene)
    if (info.ssid != null) {
      return active.where((z) =>
          z.wifiSSID != null &&
          z.wifiSSID!.isNotEmpty &&
          z.wifiSSID == info.ssid).firstOrNull;
    }

    return null;
  }

  String _matchType(GeofenceZone zone, WifiInfo info) {
    if (info.bssid != null &&
        zone.wifiBSSID?.toUpperCase() == info.bssid!.toUpperCase()) {
      return 'BSSID (Raum)';
    }
    return 'SSID (Netzwerk)';
  }

  // ── Öffentliche Hilfs-API (für UI) ─────────────────────────────────────────

  /// Gibt SSID und BSSID des aktuell verbundenen Netzes zurück.
  /// Kann direkt im Zone-Dialog für "Übernehmen"-Buttons verwendet werden.
  Future<WifiInfo> currentWifiInfo() async {
    try {
      final rawSsid  = await _networkInfo.getWifiName();
      final rawBssid = await _networkInfo.getWifiBSSID();

      final ssid = rawSsid != null && rawSsid.isNotEmpty
          ? rawSsid.replaceAll('"', '').trim()
          : null;
      final bssid = rawBssid != null && rawBssid.isNotEmpty
          ? rawBssid.toUpperCase().trim()
          : null;

      return WifiInfo(ssid: ssid, bssid: bssid);
    } catch (e) {
      log('WifiZoneService: Fehler beim SSID/BSSID-Lesen: $e',
          name: 'WifiZoneService');
      return const WifiInfo();
    }
  }

  bool get isInWifiZone => _currentZoneId != null;
  String? get currentWifiZoneId => _currentZoneId;
}
