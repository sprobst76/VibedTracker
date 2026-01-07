import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/api_client.dart';
import 'auth_screen.dart';
import 'passphrase_setup_screen.dart';
import 'totp_setup_screen.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  DateTime? _lastSyncTime;
  bool _isLoadingLastSync = true;

  // 2FA state
  TOTPStatus? _totpStatus;
  bool _isLoadingTOTP = true;

  @override
  void initState() {
    super.initState();
    _loadLastSyncTime();
    _loadTOTPStatus();
  }

  Future<void> _loadLastSyncTime() async {
    final syncService = ref.read(cloudSyncServiceProvider);
    final lastSync = await syncService.getLastSyncTime();
    if (mounted) {
      setState(() {
        _lastSyncTime = lastSync;
        _isLoadingLastSync = false;
      });
    }
  }

  Future<void> _loadTOTPStatus() async {
    final authStatus = ref.read(authStatusProvider);
    if (authStatus != AuthStatus.authenticated) {
      setState(() => _isLoadingTOTP = false);
      return;
    }

    try {
      final auth = ref.read(authServiceProvider);
      final status = await auth.getTOTPStatus();
      if (mounted) {
        setState(() {
          _totpStatus = status;
          _isLoadingTOTP = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTOTP = false);
      }
    }
  }

  Future<void> _performSync() async {
    final result = await ref.read(syncStatusProvider.notifier).sync();
    await _loadLastSyncTime();

    if (!mounted) return;

    if (result.status == SyncStatus.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync erfolgreich: ${result.pushedItems} gesendet, ${result.pulledItems} empfangen',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else if (result.status == SyncStatus.notApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account wartet auf Freischaltung'),
          backgroundColor: Colors.orange,
        ),
      );
    } else if (result.status == SyncStatus.offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server nicht erreichbar'),
          backgroundColor: Colors.grey,
        ),
      );
    } else if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync-Fehler: ${result.errorMessage}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abmelden'),
        content: const Text(
          'Möchtest du dich wirklich abmelden? Deine lokalen Daten bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authStatusProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authStatus = ref.watch(authStatusProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final authNotifier = ref.watch(authStatusProvider.notifier);
    final syncNotifier = ref.watch(syncStatusProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Sync'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account Status Card
          _buildAccountCard(authStatus, authNotifier.currentUser),
          const SizedBox(height: 16),

          // Sync Status Card (only if authenticated)
          if (authStatus == AuthStatus.authenticated ||
              authStatus == AuthStatus.pendingApproval)
            _buildSyncCard(syncStatus, syncNotifier.pendingCount),

          const SizedBox(height: 16),

          // Encryption Setup (only if authenticated)
          if (authStatus == AuthStatus.authenticated)
            _buildEncryptionCard(),

          const SizedBox(height: 16),

          // 2FA Setup (only if authenticated)
          if (authStatus == AuthStatus.authenticated)
            _build2FACard(),

          const SizedBox(height: 16),

          // Info Card
          _buildInfoCard(),
        ],
      ),
    );
  }

  Widget _buildAccountCard(AuthStatus status, User? user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(status),
                  color: _getStatusColor(status),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getStatusText(status),
                        style: TextStyle(
                          color: _getStatusColor(status),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (user != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.email_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(user.email)),
                ],
              ),
              if (user.isAdmin) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.admin_panel_settings,
                        size: 20, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Administrator',
                      style: TextStyle(color: Colors.orange.shade700),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 16),
            if (status == AuthStatus.unauthenticated ||
                status == AuthStatus.unknown)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => const AuthScreen(),
                      ),
                    );
                    if (result == true) {
                      // Refresh status
                      await ref.read(authStatusProvider.notifier).refresh();
                    }
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Anmelden'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Abmelden'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncCard(SyncStatus status, int pendingCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildSyncStatusIcon(status),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Synchronisation',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getSyncStatusText(status),
                        style: TextStyle(
                          color: _getSyncStatusColor(status),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            if (pendingCount > 0)
              Row(
                children: [
                  const Icon(Icons.pending_actions, size: 20),
                  const SizedBox(width: 8),
                  Text('$pendingCount ausstehende Änderungen'),
                ],
              ),
            if (_isLoadingLastSync)
              const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Lade...'),
                ],
              )
            else if (_lastSyncTime != null)
              Row(
                children: [
                  const Icon(Icons.schedule, size: 20),
                  const SizedBox(width: 8),
                  Text('Letzter Sync: ${_formatDateTime(_lastSyncTime!)}'),
                ],
              )
            else
              const Row(
                children: [
                  Icon(Icons.schedule, size: 20),
                  SizedBox(width: 8),
                  Text('Noch nicht synchronisiert'),
                ],
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    status == SyncStatus.syncing ? null : _performSync,
                icon: status == SyncStatus.syncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  status == SyncStatus.syncing
                      ? 'Synchronisiere...'
                      : 'Jetzt synchronisieren',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEncryptionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verschlüsselung',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'E2E-Verschlüsselung für Sync',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const PassphraseSetupScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.key),
                label: const Text('Passphrase einrichten'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build2FACard() {
    final isEnabled = _totpStatus?.enabled ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEnabled ? Icons.security : Icons.security_outlined,
                  size: 28,
                  color: isEnabled ? Colors.green : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zwei-Faktor-Authentifizierung',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isEnabled ? 'Aktiviert' : 'Nicht eingerichtet',
                        style: TextStyle(
                          color: isEnabled ? Colors.green : Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isLoadingTOTP)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              if (isEnabled && _totpStatus!.remainingRecoveryCodes > 0) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.key, size: 20),
                    const SizedBox(width: 8),
                    Text('${_totpStatus!.remainingRecoveryCodes} Recovery-Codes verfügbar'),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (!isEnabled)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (context) => const TOTPSetupScreen(),
                        ),
                      );
                      if (result == true) {
                        _loadTOTPStatus();
                      }
                    },
                    icon: const Icon(Icons.shield),
                    label: const Text('2FA einrichten'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showDisable2FADialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('2FA deaktivieren'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showDisable2FADialog() async {
    final codeController = TextEditingController();
    final passwordController = TextEditingController();
    String? errorMessage;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('2FA deaktivieren'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gib deinen aktuellen TOTP-Code und dein Passwort ein, um die Zwei-Faktor-Authentifizierung zu deaktivieren.',
              ),
              const SizedBox(height: 16),
              if (errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    errorMessage!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'TOTP-Code',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                if (codeController.text.length != 6) {
                  setDialogState(() => errorMessage = 'Bitte 6-stelligen Code eingeben');
                  return;
                }
                if (passwordController.text.isEmpty) {
                  setDialogState(() => errorMessage = 'Bitte Passwort eingeben');
                  return;
                }

                try {
                  final auth = ref.read(authServiceProvider);
                  await auth.disableTOTP(codeController.text, passwordController.text);
                  if (context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                } on ApiException catch (e) {
                  setDialogState(() => errorMessage = e.message);
                } catch (e) {
                  setDialogState(() => errorMessage = 'Fehler: $e');
                }
              },
              child: const Text('Deaktivieren'),
            ),
          ],
        ),
      ),
    );

    codeController.dispose();
    passwordController.dispose();

    if (confirmed == true) {
      _loadTOTPStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('2FA wurde deaktiviert'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Zero-Knowledge Sync',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Deine Daten werden lokal auf deinem Gerät verschlüsselt, bevor sie mit der Cloud synchronisiert werden. '
              'Nur du kannst sie mit deiner Passphrase entschlüsseln - selbst der Server kann deine Daten nicht lesen.',
              style: TextStyle(color: Colors.blue.shade900),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(AuthStatus status) {
    switch (status) {
      case AuthStatus.authenticated:
        return Icons.check_circle;
      case AuthStatus.pendingApproval:
        return Icons.hourglass_empty;
      case AuthStatus.blocked:
        return Icons.block;
      case AuthStatus.unauthenticated:
      case AuthStatus.unknown:
        return Icons.person_off;
    }
  }

  Color _getStatusColor(AuthStatus status) {
    switch (status) {
      case AuthStatus.authenticated:
        return Colors.green;
      case AuthStatus.pendingApproval:
        return Colors.orange;
      case AuthStatus.blocked:
        return Colors.red;
      case AuthStatus.unauthenticated:
      case AuthStatus.unknown:
        return Colors.grey;
    }
  }

  String _getStatusText(AuthStatus status) {
    switch (status) {
      case AuthStatus.authenticated:
        return 'Angemeldet';
      case AuthStatus.pendingApproval:
        return 'Wartet auf Freischaltung';
      case AuthStatus.blocked:
        return 'Gesperrt';
      case AuthStatus.unauthenticated:
        return 'Nicht angemeldet';
      case AuthStatus.unknown:
        return 'Prüfe Status...';
    }
  }

  Widget _buildSyncStatusIcon(SyncStatus status) {
    if (status == SyncStatus.syncing) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    }
    return Icon(
      _getSyncIcon(status),
      color: _getSyncStatusColor(status),
      size: 28,
    );
  }

  IconData _getSyncIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return Icons.sync;
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.success:
        return Icons.cloud_done;
      case SyncStatus.error:
        return Icons.cloud_off;
      case SyncStatus.offline:
        return Icons.wifi_off;
      case SyncStatus.notApproved:
        return Icons.hourglass_empty;
    }
  }

  Color _getSyncStatusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return Colors.grey;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.success:
        return Colors.green;
      case SyncStatus.error:
        return Colors.red;
      case SyncStatus.offline:
        return Colors.grey;
      case SyncStatus.notApproved:
        return Colors.orange;
    }
  }

  String _getSyncStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return 'Bereit';
      case SyncStatus.syncing:
        return 'Synchronisiere...';
      case SyncStatus.success:
        return 'Synchronisiert';
      case SyncStatus.error:
        return 'Fehler';
      case SyncStatus.offline:
        return 'Offline';
      case SyncStatus.notApproved:
        return 'Account nicht freigeschaltet';
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'Gerade eben';
    } else if (diff.inHours < 1) {
      return 'Vor ${diff.inMinutes} Min.';
    } else if (diff.inDays < 1) {
      return 'Vor ${diff.inHours} Std.';
    } else {
      return '${dt.day}.${dt.month}.${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }
}
