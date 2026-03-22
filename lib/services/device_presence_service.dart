import 'dart:async';
import 'dart:developer';
import 'dart:io';

/// Ergebnis einer PC-Präsenz-Probe.
class PresenceResult {
  final bool isOnline;
  final String host;
  final int port;
  final Duration? latency; // null wenn offline
  final String? error;

  const PresenceResult({
    required this.isOnline,
    required this.host,
    required this.port,
    this.latency,
    this.error,
  });

  @override
  String toString() => isOnline
      ? 'PresenceResult: $host:$port online (${latency?.inMilliseconds}ms)'
      : 'PresenceResult: $host:$port offline ($error)';
}

/// Erkennt ob ein Arbeits-PC im lokalen Netz aktiv ist — via TCP-Probe.
///
/// Energie: near-zero. Ein TCP-Handshake dauert ~1ms und sendet <200 Bytes.
/// Selbst im 1-Minuten-Takt ist die Energiebilanz vernachlässigbar.
///
/// Typische Ports:
///   Windows: 445 (SMB) — läuft immer wenn PC an ist
///   macOS:   22 (SSH) oder 5000 (AirPlay)
///   Linux:   22 (SSH)
///   Custom:  jeder offene Port funktioniert
class DevicePresenceService {
  Timer? _timer;
  bool? _lastKnownState;
  bool _running = false;

  /// Callback wenn PC-Status sich ändert.
  void Function(PresenceResult result)? onStateChange;

  // ── Statische Probe-API ────────────────────────────────────────────────────

  /// Einmaliger TCP-Verbindungsversuch. Gibt sofort zurück.
  static Future<PresenceResult> probe(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (host.isEmpty) {
      return PresenceResult(
        isOnline: false,
        host: host,
        port: port,
        error: 'Kein Hostname konfiguriert',
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: timeout,
      );
      stopwatch.stop();
      socket.destroy();
      log('DevicePresenceService: $host:$port online (${stopwatch.elapsedMilliseconds}ms)',
          name: 'DevicePresenceService');
      return PresenceResult(
        isOnline: true,
        host: host,
        port: port,
        latency: stopwatch.elapsed,
      );
    } on SocketException catch (e) {
      stopwatch.stop();
      // Connection refused = Port zu, aber PC ist an (häufig bei Windows ohne SMB)
      final pcIsUp = e.osError?.errorCode == 111 || // ECONNREFUSED Linux
          e.osError?.errorCode == 61;               // ECONNREFUSED macOS
      log('DevicePresenceService: $host:$port ${pcIsUp ? "up (port closed)" : "offline"} – ${e.message}',
          name: 'DevicePresenceService');
      return PresenceResult(
        isOnline: pcIsUp, // PC an, aber Port geschlossen → trotzdem "aktiv"
        host: host,
        port: port,
        error: e.message,
      );
    } catch (e) {
      log('DevicePresenceService: $host:$port error – $e',
          name: 'DevicePresenceService');
      return PresenceResult(
        isOnline: false,
        host: host,
        port: port,
        error: e.toString(),
      );
    }
  }

  // ── Watcher (periodisch) ──────────────────────────────────────────────────

  /// Startet periodische Prüfung. Führt sofort einen ersten Check aus.
  Future<void> startWatching({
    required String host,
    required int port,
    required Duration interval,
  }) async {
    stopWatching();
    _running = true;

    // Sofortiger erster Check
    await _doCheck(host, port);

    _timer = Timer.periodic(interval, (_) async {
      if (_running) await _doCheck(host, port);
    });
    log('DevicePresenceService: watching $host:$port every ${interval.inMinutes}min',
        name: 'DevicePresenceService');
  }

  void stopWatching() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _lastKnownState = null;
  }

  void dispose() => stopWatching();

  Future<void> _doCheck(String host, int port) async {
    final result = await probe(host, port);
    if (result.isOnline != _lastKnownState) {
      _lastKnownState = result.isOnline;
      onStateChange?.call(result);
    }
  }

  bool get isWatching => _running;
  bool? get lastKnownState => _lastKnownState;

  // ── Port-Presets ──────────────────────────────────────────────────────────

  static const List<_PortPreset> portPresets = [
    _PortPreset(label: 'Windows (SMB)', port: 445),
    _PortPreset(label: 'macOS (SSH)', port: 22),
    _PortPreset(label: 'Linux (SSH)', port: 22),
    _PortPreset(label: 'RDP', port: 3389),
    _PortPreset(label: 'VNC', port: 5900),
  ];
}

class _PortPreset {
  final String label;
  final int port;
  const _PortPreset({required this.label, required this.port});
}
