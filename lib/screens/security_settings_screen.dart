import 'package:flutter/material.dart';
import '../services/secure_storage_service.dart';
import '../theme/theme_colors.dart';
import 'lock_screen.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _secureStorage = SecureStorageService();

  bool _isLoading = true;
  bool _appLockEnabled = false;
  bool _hasPin = false;
  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;
  int _autoLockTimeout = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final appLockEnabled = await _secureStorage.isAppLockEnabled();
    final hasPin = await _secureStorage.hasPin();
    final biometricsEnabled = await _secureStorage.isBiometricsEnabled();
    final biometricsAvailable = await _secureStorage.isBiometricsAvailable();
    final autoLockTimeout = await _secureStorage.getAutoLockTimeout();

    setState(() {
      _appLockEnabled = appLockEnabled;
      _hasPin = hasPin;
      _biometricsEnabled = biometricsEnabled;
      _biometricsAvailable = biometricsAvailable;
      _autoLockTimeout = autoLockTimeout;
      _isLoading = false;
    });
  }

  Future<void> _toggleAppLock(bool enabled) async {
    if (enabled && !_hasPin) {
      // PIN muss erst gesetzt werden
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => SetPinScreen(
            onPinSet: () => Navigator.pop(context, true),
          ),
        ),
      );

      if (result == true) {
        await _loadSettings();
      }
    } else if (!enabled) {
      // Deaktivieren - PIN Bestätigung erforderlich
      final confirmed = await _showPinConfirmation();
      if (confirmed) {
        await _secureStorage.setAppLockEnabled(false);
        await _loadSettings();
      }
    } else {
      await _secureStorage.setAppLockEnabled(enabled);
      await _loadSettings();
    }
  }

  Future<void> _changePin() async {
    // Erst alte PIN bestätigen
    final confirmed = await _showPinConfirmation();
    if (!confirmed) return;

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SetPinScreen(
            isChangingPin: true,
            onPinSet: () => Navigator.pop(context),
          ),
        ),
      );
    }
  }

  Future<void> _removePin() async {
    final confirmed = await _showPinConfirmation();
    if (!confirmed) return;

    final confirmRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PIN entfernen?'),
        content: const Text(
          'Die App-Sperre wird deaktiviert und die PIN gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );

    if (confirmRemove == true) {
      await _secureStorage.resetAuthentication();
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN wurde entfernt')),
        );
      }
    }
  }

  Future<bool> _showPinConfirmation() async {
    final completer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PinConfirmationDialog(
        secureStorage: _secureStorage,
      ),
    );
    return completer == true;
  }

  Future<void> _toggleBiometrics(bool enabled) async {
    if (enabled) {
      // Biometrie testen
      final success = await _secureStorage.authenticateWithBiometrics(
        reason: 'Biometrie aktivieren',
      );
      if (success) {
        await _secureStorage.setBiometricsEnabled(true);
        await _loadSettings();
      }
    } else {
      await _secureStorage.setBiometricsEnabled(false);
      await _loadSettings();
    }
  }

  Future<void> _setAutoLockTimeout(int minutes) async {
    await _secureStorage.setAutoLockTimeout(minutes);
    setState(() => _autoLockTimeout = minutes);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sicherheit')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sicherheit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App-Sperre
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lock,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'App-Sperre',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Switch(
                        value: _appLockEnabled,
                        onChanged: _toggleAppLock,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _appLockEnabled
                        ? 'App ist durch PIN geschützt'
                        : 'App ist nicht geschützt',
                    style: TextStyle(color: context.subtleText, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // PIN verwalten (nur wenn App-Lock aktiv)
          if (_hasPin) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PIN verwalten',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _changePin,
                            icon: const Icon(Icons.edit),
                            label: const Text('PIN ändern'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _removePin,
                            icon: Icon(Icons.delete, color: Colors.red.shade700),
                            label: Text(
                              'Entfernen',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Biometrie (nur wenn verfügbar und PIN gesetzt)
          if (_biometricsAvailable && _hasPin) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.fingerprint,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Biometrische Entsperrung',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Fingerabdruck oder Face ID nutzen',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _biometricsEnabled,
                          onChanged: _toggleBiometrics,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Auto-Lock Timeout (nur wenn App-Lock aktiv)
          if (_appLockEnabled && _hasPin) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Automatisch sperren nach',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTimeoutChip(0, 'Sofort'),
                        _buildTimeoutChip(1, '1 Min'),
                        _buildTimeoutChip(5, '5 Min'),
                        _buildTimeoutChip(15, '15 Min'),
                        _buildTimeoutChip(30, '30 Min'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Info Card
          Card(
            color: context.infoBackground,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: context.infoForeground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Deine Daten werden lokal auf dem Gerät verschlüsselt gespeichert.',
                      style: TextStyle(color: context.infoForeground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeoutChip(int minutes, String label) {
    final isSelected = _autoLockTimeout == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _setAutoLockTimeout(minutes),
    );
  }
}

/// Dialog zur PIN-Bestätigung
class _PinConfirmationDialog extends StatefulWidget {
  final SecureStorageService secureStorage;

  const _PinConfirmationDialog({required this.secureStorage});

  @override
  State<_PinConfirmationDialog> createState() => _PinConfirmationDialogState();
}

class _PinConfirmationDialogState extends State<_PinConfirmationDialog> {
  String _pin = '';
  bool _showError = false;
  bool _isLoading = false;

  void _onDigitPressed(String digit) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _showError = false;
    });
    if (_pin.length == 6) {
      _verify();
    }
  }

  void _onBackspacePressed() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    final success = await widget.secureStorage.verifyPin(_pin);
    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _showError = true;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PIN bestätigen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // PIN Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              final isFilled = index < _pin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled
                      ? (_showError ? Colors.red : Theme.of(context).colorScheme.primary)
                      : Colors.transparent,
                  border: Border.all(
                    color: _showError ? Colors.red : Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
          if (_showError) ...[
            const SizedBox(height: 8),
            const Text('Falsche PIN', style: TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          // Compact numpad
          _buildCompactNumpad(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }

  Widget _buildCompactNumpad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['1', '2', '3'].map(_buildSmallDigit).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['4', '5', '6'].map(_buildSmallDigit).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['7', '8', '9'].map(_buildSmallDigit).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 56),
            _buildSmallDigit('0'),
            InkWell(
              onTap: _onBackspacePressed,
              child: const SizedBox(
                width: 56,
                height: 48,
                child: Center(child: Icon(Icons.backspace_outlined, size: 20)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSmallDigit(String digit) {
    return InkWell(
      onTap: _isLoading ? null : () => _onDigitPressed(digit),
      child: SizedBox(
        width: 56,
        height: 48,
        child: Center(
          child: Text(
            digit,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
