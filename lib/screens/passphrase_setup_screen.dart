import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import 'passphrase_recovery_screen.dart';

class PassphraseSetupScreen extends ConsumerStatefulWidget {
  const PassphraseSetupScreen({super.key});

  @override
  ConsumerState<PassphraseSetupScreen> createState() =>
      _PassphraseSetupScreenState();
}

class _PassphraseSetupScreenState
    extends ConsumerState<PassphraseSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassphrase = true;
  bool _obscureConfirm = true;
  bool _isSetUp = false;
  String? _errorMessage;
  List<String>? _recoveryCodes;
  bool _codesConfirmed = false;

  // Passphrase strength
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;

  @override
  void initState() {
    super.initState();
    _checkSetup();
    _passphraseController.addListener(_updateStrength);
  }

  @override
  void dispose() {
    _passphraseController.removeListener(_updateStrength);
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _updateStrength() {
    final value = _passphraseController.text;
    setState(() {
      _hasMinLength = value.length >= 12;
      _hasUppercase = value.contains(RegExp(r'[A-Z]'));
      _hasLowercase = value.contains(RegExp(r'[a-z]'));
      _hasDigit = value.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = value.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{};:"|,.<>/?~\\]'));
    });
  }

  bool get _isPassphraseStrong =>
      _hasMinLength && _hasUppercase && _hasLowercase && _hasDigit && _hasSpecialChar;

  Future<void> _checkSetup() async {
    final encryption = ref.read(encryptionServiceProvider);
    final isSetUp = await encryption.isSetUp();
    if (mounted) {
      setState(() => _isSetUp = isSetUp);
    }
  }

  Future<void> _setupPassphrase() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isPassphraseStrong) {
      setState(() => _errorMessage = 'Passphrase erfüllt nicht alle Anforderungen');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final encryption = ref.read(encryptionServiceProvider);
      final syncService = ref.read(syncServiceProvider);

      // Set up encryption locally
      await encryption.setUp(_passphraseController.text);

      // Upload key info to server and get recovery codes
      final recoveryCodes = await syncService.setKeyWithRecoveryCodes();

      if (!mounted) return;

      setState(() {
        _recoveryCodes = recoveryCodes;
        _isSetUp = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler beim Einrichten: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmCodesAndFinish() async {
    setState(() => _codesConfirmed = true);
    _recoveryCodes = null;
    _passphraseController.clear();
    _confirmController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Passphrase erfolgreich eingerichtet'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _verifyPassphrase() async {
    if (_passphraseController.text.isEmpty) {
      setState(() => _errorMessage = 'Bitte Passphrase eingeben');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final encryption = ref.read(encryptionServiceProvider);
      final isValid =
          await encryption.verifyPassphrase(_passphraseController.text);

      if (!mounted) return;

      if (isValid) {
        await encryption.loadKeys();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Passphrase korrekt'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _errorMessage = 'Passphrase falsch');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler bei Verifizierung: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetPassphrase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Passphrase zurücksetzen'),
        content: const Text(
          'ACHTUNG: Wenn du die Passphrase zurücksetzt, können alle '
          'verschlüsselten Daten auf dem Server nicht mehr entschlüsselt werden!\n\n'
          'Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final encryption = ref.read(encryptionServiceProvider);
      await encryption.reset();
      setState(() {
        _isSetUp = false;
        _recoveryCodes = null;
        _codesConfirmed = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passphrase wurde zurückgesetzt'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  String? _validatePassphrase(String? value) {
    if (value == null || value.isEmpty) {
      return 'Passphrase ist erforderlich';
    }
    if (!_isPassphraseStrong) {
      return 'Passphrase erfüllt nicht alle Anforderungen';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _passphraseController.text) {
      return 'Passphrasen stimmen nicht überein';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Show recovery codes if just generated
    if (_recoveryCodes != null && !_codesConfirmed) {
      return _buildRecoveryCodesScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verschlüsselung'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              _isSetUp ? Icons.lock : Icons.lock_open,
              size: 80,
              color: _isSetUp ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(
              _isSetUp
                  ? 'Verschlüsselung aktiv'
                  : 'Verschlüsselung einrichten',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _isSetUp
                  ? 'Deine Daten werden vor dem Sync verschlüsselt'
                  : 'Richte eine sichere Passphrase ein, um deine Daten zu verschlüsseln',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (!_isSetUp) _buildSetupForm() else _buildVerifyForm(),
            const SizedBox(height: 32),
            _buildInfoCard(),
            if (_isSetUp) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _resetPassphrase,
                icon: const Icon(Icons.refresh, color: Colors.red),
                label: const Text(
                  'Passphrase zurücksetzen',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecoveryCodesScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recovery Codes'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.key,
              size: 64,
              color: Colors.amber,
            ),
            const SizedBox(height: 24),
            const Text(
              'Recovery Codes sichern',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Diese Codes ermöglichen den Zugang zu deinen Daten, '
              'falls du deine Passphrase vergisst. Speichere sie sicher!',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Jeder Code kann nur einmal verwendet werden!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < (_recoveryCodes?.length ?? 0); i += 2)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${i + 1}. ${_recoveryCodes![i]}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (i + 1 < _recoveryCodes!.length)
                            Expanded(
                              child: Text(
                                '${i + 2}. ${_recoveryCodes![i + 1]}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final codes = _recoveryCodes!.asMap().entries
                          .map((e) => '${e.key + 1}. ${e.value}')
                          .join('\n');
                      Clipboard.setData(ClipboardData(text: codes));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Codes kopiert')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Kopieren'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _confirmCodesAndFinish,
              child: const Text('Ich habe die Codes gesichert'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _passphraseController,
            decoration: InputDecoration(
              labelText: 'Neue Passphrase',
              prefixIcon: const Icon(Icons.key),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassphrase
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () {
                  setState(() => _obscurePassphrase = !_obscurePassphrase);
                },
              ),
            ),
            obscureText: _obscurePassphrase,
            validator: _validatePassphrase,
            enabled: !_isLoading,
          ),
          const SizedBox(height: 16),
          _buildStrengthIndicator(),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmController,
            decoration: InputDecoration(
              labelText: 'Passphrase bestätigen',
              prefixIcon: const Icon(Icons.key),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () {
                  setState(() => _obscureConfirm = !_obscureConfirm);
                },
              ),
            ),
            obscureText: _obscureConfirm,
            validator: _validateConfirm,
            enabled: !_isLoading,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isLoading || !_isPassphraseStrong ? null : _setupPassphrase,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Passphrase einrichten'),
          ),
        ],
      ),
    );
  }

  Widget _buildStrengthIndicator() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Passphrase-Anforderungen:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _buildRequirement('Mindestens 12 Zeichen', _hasMinLength),
          _buildRequirement('Mindestens ein Großbuchstabe', _hasUppercase),
          _buildRequirement('Mindestens ein Kleinbuchstabe', _hasLowercase),
          _buildRequirement('Mindestens eine Zahl', _hasDigit),
          _buildRequirement('Mindestens ein Sonderzeichen', _hasSpecialChar),
        ],
      ),
    );
  }

  Widget _buildRequirement(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: isMet ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: isMet ? Colors.green.shade700 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyForm() {
    return Column(
      children: [
        TextFormField(
          controller: _passphraseController,
          decoration: InputDecoration(
            labelText: 'Passphrase verifizieren',
            prefixIcon: const Icon(Icons.key),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassphrase
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () {
                setState(() => _obscurePassphrase = !_obscurePassphrase);
              },
            ),
          ),
          obscureText: _obscurePassphrase,
          enabled: !_isLoading,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _verifyPassphrase,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verifizieren'),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _isLoading ? null : () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) => const PassphraseRecoveryScreen(),
              ),
            );
            if (result == true) {
              // Passphrase was reset, refresh state
              await _checkSetup();
            }
          },
          child: const Text('Passphrase vergessen?'),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Text(
                  'Wichtig',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Merke dir deine Passphrase gut! Sie wird benötigt, um deine '
              'Daten auf anderen Geräten zu entschlüsseln. Falls du sie vergisst, '
              'kannst du deine Recovery Codes verwenden.',
              style: TextStyle(color: Colors.amber.shade900),
            ),
          ],
        ),
      ),
    );
  }
}
