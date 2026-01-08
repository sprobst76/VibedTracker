import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/work_entry.dart';
import '../models/pause.dart';
import '../models/vacation.dart';
import '../models/project.dart';
import 'auth_service.dart';
import 'encryption_service.dart';
import 'api_client.dart';

/// Sync-Status
enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  offline,
  notApproved,
}

/// Sync-Ergebnis
class SyncResult {
  final SyncStatus status;
  final int pushedItems;
  final int pulledItems;
  final String? errorMessage;

  SyncResult({
    required this.status,
    this.pushedItems = 0,
    this.pulledItems = 0,
    this.errorMessage,
  });
}

/// Item für Sync-Queue
class SyncQueueItem {
  final String dataType;
  final String localId;
  final Map<String, dynamic> data;
  final bool deleted;
  final DateTime timestamp;

  SyncQueueItem({
    required this.dataType,
    required this.localId,
    required this.data,
    this.deleted = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'dataType': dataType,
    'localId': localId,
    'data': data,
    'deleted': deleted,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) => SyncQueueItem(
    dataType: json['dataType'] as String,
    localId: json['localId'] as String,
    data: json['data'] as Map<String, dynamic>,
    deleted: json['deleted'] as bool? ?? false,
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
  );
}

/// Service für Cloud-Synchronisation
class CloudSyncService {
  final AuthService _auth;
  final EncryptionService _encryption;

  // Prefs Keys
  static const _keyLastSync = 'sync_last_timestamp';
  static const _keySyncQueue = 'sync_queue';

  // Data Types für Server
  static const dataTypeWorkEntry = 'work_entry';
  static const dataTypeVacation = 'vacation';
  static const dataTypeProject = 'project';

  SyncStatus _status = SyncStatus.idle;
  final List<SyncQueueItem> _queue = [];

  CloudSyncService({
    required AuthService auth,
    required EncryptionService encryption,
  }) : _auth = auth, _encryption = encryption;

  /// Aktueller Sync-Status
  SyncStatus get status => _status;

  /// Prüft ob Sync möglich ist
  bool get canSync => _auth.canSync;

  /// Lädt Sync-Queue aus Prefs
  Future<void> loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getString(_keySyncQueue);
    if (queueJson != null) {
      final list = jsonDecode(queueJson) as List;
      _queue.clear();
      _queue.addAll(list.map((e) => SyncQueueItem.fromJson(e as Map<String, dynamic>)));
      debugPrint('Loaded ${_queue.length} items from sync queue');
    }
  }

  /// Speichert Sync-Queue
  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySyncQueue, jsonEncode(_queue.map((e) => e.toJson()).toList()));
  }

  /// Fügt Item zur Sync-Queue hinzu
  Future<void> queueItem(String dataType, String localId, Map<String, dynamic> data, {bool deleted = false}) async {
    // Entferne altes Item mit gleicher ID
    _queue.removeWhere((item) => item.dataType == dataType && item.localId == localId);

    _queue.add(SyncQueueItem(
      dataType: dataType,
      localId: localId,
      data: data,
      deleted: deleted,
    ));

    await _saveQueue();
    debugPrint('Queued $dataType:$localId for sync (deleted: $deleted)');
  }

  /// Führt vollständigen Sync durch
  Future<SyncResult> sync() async {
    if (!_auth.canSync) {
      if (_auth.status == AuthStatus.pendingApproval) {
        return SyncResult(status: SyncStatus.notApproved, errorMessage: 'Account nicht freigeschalten');
      }
      return SyncResult(status: SyncStatus.error, errorMessage: 'Nicht eingeloggt');
    }

    _status = SyncStatus.syncing;

    try {
      // Server erreichbar?
      final serverAvailable = await _auth.isServerAvailable();
      if (!serverAvailable) {
        _status = SyncStatus.offline;
        return SyncResult(status: SyncStatus.offline, errorMessage: 'Server nicht erreichbar');
      }

      // 1. Push lokale Änderungen
      final pushedCount = await _pushChanges();

      // 2. Pull remote Änderungen
      final pulledCount = await _pullChanges();

      _status = SyncStatus.success;
      return SyncResult(
        status: SyncStatus.success,
        pushedItems: pushedCount,
        pulledItems: pulledCount,
      );
    } on ApiException catch (e) {
      _status = SyncStatus.error;
      if (e.isNotApproved) {
        return SyncResult(status: SyncStatus.notApproved, errorMessage: 'Account nicht freigeschalten');
      }
      return SyncResult(status: SyncStatus.error, errorMessage: e.message);
    } catch (e) {
      _status = SyncStatus.error;
      debugPrint('Sync error: $e');
      return SyncResult(status: SyncStatus.error, errorMessage: e.toString());
    }
  }

  /// Push lokale Änderungen zum Server
  Future<int> _pushChanges() async {
    if (_queue.isEmpty) return 0;

    final deviceId = _auth.deviceId;
    if (deviceId == null) throw Exception('No device ID');

    // Items verschlüsseln
    final encryptedItems = <Map<String, dynamic>>[];
    for (final item in _queue) {
      final encrypted = await _encryption.encrypt(item.data);
      encryptedItems.add({
        'data_type': item.dataType,
        'local_id': item.localId,
        'encrypted_blob': encrypted.blobBase64,
        'nonce': encrypted.nonceBase64,
        'schema_version': 1,
        'deleted': item.deleted,
      });
    }

    // Push zum Server
    await _auth.api.post('/api/v1/sync/push', body: {
      'device_id': deviceId,
      'items': encryptedItems,
    });

    final count = _queue.length;

    // Queue leeren
    _queue.clear();
    await _saveQueue();

    debugPrint('Pushed $count items to server');
    return count;
  }

  /// Pull Änderungen vom Server
  Future<int> _pullChanges() async {
    final deviceId = _auth.deviceId;
    if (deviceId == null) throw Exception('No device ID');

    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt(_keyLastSync) ?? 0;

    final response = await _auth.api.get('/api/v1/sync/pull', queryParams: {
      'device_id': deviceId,
      'since': lastSync.toString(),
    });

    final items = (response['items'] as List?) ?? [];
    final serverTimestamp = response['timestamp'] as int;

    var count = 0;
    for (final item in items) {
      try {
        await _processIncomingItem(item as Map<String, dynamic>);
        count++;
      } catch (e) {
        debugPrint('Failed to process item: $e');
      }
    }

    // Timestamp speichern
    await prefs.setInt(_keyLastSync, serverTimestamp);

    debugPrint('Pulled $count items from server');
    return count;
  }

  /// Verarbeitet ein eingehendes Item
  Future<void> _processIncomingItem(Map<String, dynamic> item) async {
    final dataType = item['data_type'] as String;
    final localId = item['local_id'] as String;
    final blobBase64 = item['encrypted_blob'] as String;
    final nonceBase64 = item['nonce'] as String;
    final deleted = item['deleted'] as bool? ?? false;

    // Entschlüsseln
    final encrypted = EncryptedData.fromBase64(
      blobBase64: blobBase64,
      nonceBase64: nonceBase64,
    );
    final data = await _encryption.decrypt(encrypted);

    if (deleted) {
      await _deleteLocalItem(dataType, localId);
    } else {
      await _upsertLocalItem(dataType, localId, data);
    }
  }

  /// Löscht lokales Item
  Future<void> _deleteLocalItem(String dataType, String localId) async {
    final key = int.tryParse(localId);
    if (key == null) return;

    switch (dataType) {
      case dataTypeWorkEntry:
        final box = Hive.box<WorkEntry>('work');
        if (box.containsKey(key)) await box.delete(key);
        break;
      case dataTypeVacation:
        final box = Hive.box<Vacation>('vacations');
        if (box.containsKey(key)) await box.delete(key);
        break;
      case dataTypeProject:
        final box = Hive.box<Project>('projects');
        if (box.containsKey(key)) await box.delete(key);
        break;
    }
  }

  /// Fügt lokales Item ein oder aktualisiert es
  Future<void> _upsertLocalItem(String dataType, String localId, Map<String, dynamic> data) async {
    final key = int.tryParse(localId);

    switch (dataType) {
      case dataTypeWorkEntry:
        final box = Hive.box<WorkEntry>('work');
        final entry = _workEntryFromJson(data);
        if (key != null && box.containsKey(key)) {
          await box.put(key, entry);
        } else {
          await box.add(entry);
        }
        break;
      case dataTypeVacation:
        final box = Hive.box<Vacation>('vacations');
        final vacation = _vacationFromJson(data);
        if (key != null && box.containsKey(key)) {
          await box.put(key, vacation);
        } else {
          await box.add(vacation);
        }
        break;
      case dataTypeProject:
        final box = Hive.box<Project>('projects');
        final project = _projectFromJson(data);
        if (key != null && box.containsKey(key)) {
          await box.put(key, project);
        } else {
          await box.add(project);
        }
        break;
    }
  }

  // ==================== Serialization Helpers ====================

  WorkEntry _workEntryFromJson(Map<String, dynamic> json) {
    return WorkEntry(
      start: DateTime.parse(json['start'] as String),
      stop: json['stop'] != null ? DateTime.parse(json['stop'] as String) : null,
      pauses: (json['pauses'] as List?)
          ?.map((p) => Pause(
                start: DateTime.parse(p['start'] as String),
                end: p['end'] != null ? DateTime.parse(p['end'] as String) : null,
              ))
          .toList() ?? [],
      notes: json['notes'] as String?,
      workModeIndex: json['workModeIndex'] as int? ?? 0,
      projectId: json['projectId'] as String?,
    );
  }

  Map<String, dynamic> workEntryToJson(WorkEntry entry, int key) {
    return {
      'key': key,
      'start': entry.start.toIso8601String(),
      'stop': entry.stop?.toIso8601String(),
      'pauses': entry.pauses.map((p) => {
        'start': p.start.toIso8601String(),
        'end': p.end?.toIso8601String(),
      }).toList(),
      'notes': entry.notes,
      'workModeIndex': entry.workModeIndex,
      'projectId': entry.projectId,
    };
  }

  Vacation _vacationFromJson(Map<String, dynamic> json) {
    return Vacation(
      day: DateTime.parse(json['day'] as String),
      type: AbsenceType.values[(json['typeIndex'] as int? ?? 0).clamp(0, 4)],
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> vacationToJson(Vacation vacation, int key) {
    return {
      'key': key,
      'day': vacation.day.toIso8601String(),
      'typeIndex': vacation.typeIndex,
      'description': vacation.description,
    };
  }

  Project _projectFromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String? ?? '',
      name: json['name'] as String,
      colorHex: json['colorHex'] as String? ?? '#2196F3',
      isActive: json['isActive'] as bool? ?? true,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> projectToJson(Project project, int key) {
    return {
      'key': key,
      'id': project.id,
      'name': project.name,
      'colorHex': project.colorHex,
      'isActive': project.isActive,
      'sortOrder': project.sortOrder,
    };
  }

  // Queue-Hilfsmethoden für einfache Nutzung

  /// Queue WorkEntry für Sync (key ist der Hive-Key)
  Future<void> queueWorkEntry(WorkEntry entry, int key, {bool deleted = false}) async {
    await queueItem(dataTypeWorkEntry, key.toString(), workEntryToJson(entry, key), deleted: deleted);
  }

  /// Queue Vacation für Sync (key ist der Hive-Key)
  Future<void> queueVacation(Vacation vacation, int key, {bool deleted = false}) async {
    await queueItem(dataTypeVacation, key.toString(), vacationToJson(vacation, key), deleted: deleted);
  }

  /// Queue Project für Sync (key ist der Hive-Key)
  Future<void> queueProject(Project project, int key, {bool deleted = false}) async {
    await queueItem(dataTypeProject, key.toString(), projectToJson(project, key), deleted: deleted);
  }

  /// Gibt Anzahl der ausstehenden Items zurück
  int get pendingCount => _queue.length;

  /// Letzter Sync-Zeitpunkt
  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyLastSync);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000) : null;
  }

  /// Uploads encryption key info to server and returns recovery codes
  /// Returns empty list if encryption is already set up (no new codes)
  Future<List<String>> setKeyWithRecoveryCodes() async {
    final salt = await _encryption.getSaltBase64();
    final hash = await _encryption.getVerificationHashBase64();

    if (salt == null || hash == null) {
      throw Exception('Encryption not set up locally');
    }

    final response = await _auth.api.post('/api/v1/key', body: {
      'key_salt': salt,
      'key_verification_hash': hash,
    });

    // Extract recovery codes from response (only returned on first setup)
    final codes = response['recovery_codes'] as List?;
    if (codes != null) {
      return codes.map((c) => c.toString()).toList();
    }
    return [];
  }

  /// Gets the passphrase recovery status
  Future<Map<String, dynamic>> getRecoveryStatus() async {
    return await _auth.api.get('/api/v1/passphrase/recovery/status');
  }

  /// Regenerates passphrase recovery codes
  Future<List<String>> regenerateRecoveryCodes() async {
    final response = await _auth.api.post('/api/v1/passphrase/recovery/regenerate');
    final codes = response['codes'] as List?;
    if (codes != null) {
      return codes.map((c) => c.toString()).toList();
    }
    return [];
  }

  /// Resets passphrase using a recovery code
  Future<List<String>> resetPassphraseWithRecoveryCode(
    String recoveryCode,
    String newKeySalt,
    String newKeyVerificationHash,
  ) async {
    final response = await _auth.api.post('/api/v1/passphrase/recovery/reset', body: {
      'recovery_code': recoveryCode,
      'new_key_salt': newKeySalt,
      'new_key_verification_hash': newKeyVerificationHash,
    });

    // New recovery codes are returned after reset
    final codes = response['recovery_codes'] as List?;
    if (codes != null) {
      return codes.map((c) => c.toString()).toList();
    }
    return [];
  }
}
