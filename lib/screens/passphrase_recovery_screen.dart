import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';

class PassphraseRecoveryScreen extends ConsumerStatefulWidget {
  const PassphraseRecoveryScreen({super.key});

  @override
  ConsumerState<PassphraseRecoveryScreen> createState() =>
      _PassphraseRecoveryScreenState();
}

class _PassphraseRecoveryScreenState
    extends ConsumerState<PassphraseRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recoveryCodeController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassphrase = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  // Step 1: Enter recovery code, Step 2: Set new passphrase, Step 3: Show new codes
  int _currentStep = 1;
  List<String>? _newRecoveryCodes;

  // Passphrase strength
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;

  @override
  void initState() {
    super.initState();
    _passphraseController.addListener(_updateStrength);
  }

  @override
  void dispose() {
    _passphraseController.removeListener(_updateStrength);
    _recoveryCodeController.dispose();
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

  Future<void> _resetPassphrase() async {
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

      // Set up new encryption locally
      await encryption.setUp(_passphraseController.text);

      // Get the new salt and hash
      final salt = await encryption.getSaltBase64();
      final hash = await encryption.getVerificationHashBase64();

      if (salt == null || hash == null) {
        throw Exception('Fehler beim Erstellen der neuen Verschlüsselung');
      }

      // Reset on server with recovery code and get new recovery codes
      final newCodes = await syncService.resetPassphraseWithRecoveryCode(
        _recoveryCodeController.text.trim(),
        salt,
        hash,
      );

      if (!mounted) return;

      setState(() {
        _newRecoveryCodes = newCodes;
        _currentStep = 3;
      });
    } catch (e) {
      // Reset local encryption on failure
      final encryption = ref.read(encryptionServiceProvider);
      await encryption.reset();

      setState(() {
        _errorMessage = e.toString().contains('invalid recovery code')
            ? 'Ungültiger Recovery Code'
            : e.toString().contains('too many attempts')
                ? 'Zu viele Versuche. Bitte später erneut versuchen.'
                : 'Fehler: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _proceedToNewPassphrase() {
    final code = _recoveryCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Bitte Recovery Code eingeben');
      return;
    }
    setState(() {
      _errorMessage = null;
      _currentStep = 2;
    });
  }

  void _finish() {
    Navigator.of(context).pop(true); // Return success
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentStep == 3 ? 'Neue Recovery Codes' : 'Passphrase wiederherstellen'),
        automaticallyImplyLeading: _currentStep != 3,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progress indicator
            if (_currentStep < 3) ...[
              Builder(builder: (context) {
                final primaryColor = Theme.of(context).colorScheme.primary;
                return Row(
                  children: [
                    _buildStepIndicator(1, 'Recovery Code', primaryColor),
                    Expanded(child: Container(height: 2, color: _currentStep >= 2 ? primaryColor : Colors.grey.shade300)),
                    _buildStepIndicator(2, 'Neue Passphrase', primaryColor),
                  ],
                );
              }),
              const SizedBox(height: 32),
            ],

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

            if (_currentStep == 1) _buildStep1(),
            if (_currentStep == 2) _buildStep2(),
            if (_currentStep == 3) _buildStep3(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, Color primaryColor) {
    final isActive = _currentStep >= step;
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? primaryColor : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$step',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? primaryColor : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.key,
          size: 64,
          color: Colors.amber,
        ),
        const SizedBox(height: 24),
        const Text(
          'Recovery Code eingeben',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Gib einen deiner Recovery Codes ein, um deine Passphrase zurückzusetzen.',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _recoveryCodeController,
          decoration: const InputDecoration(
            labelText: 'Recovery Code',
            prefixIcon: Icon(Icons.vpn_key),
            border: OutlineInputBorder(),
            hintText: 'z.B. a1b2c3d4e5f6g7h8',
          ),
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          enabled: !_isLoading,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _proceedToNewPassphrase,
          child: const Text('Weiter'),
        ),
        const SizedBox(height: 16),
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Hinweis',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Jeder Recovery Code kann nur einmal verwendet werden. '
                  'Nach dem Zurücksetzen erhältst du neue Codes.',
                  style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.lock_reset,
            size: 64,
            color: Colors.blue,
          ),
          const SizedBox(height: 24),
          const Text(
            'Neue Passphrase festlegen',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Wähle eine neue sichere Passphrase für deine Daten.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
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
            validator: (value) {
              if (value != _passphraseController.text) {
                return 'Passphrasen stimmen nicht überein';
              }
              return null;
            },
            enabled: !_isLoading,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () {
                    setState(() => _currentStep = 1);
                  },
                  child: const Text('Zurück'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _isLoading || !_isPassphraseStrong ? null : _resetPassphrase,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Passphrase zurücksetzen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.check_circle,
          size: 64,
          color: Colors.green,
        ),
        const SizedBox(height: 24),
        const Text(
          'Passphrase zurückgesetzt!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Speichere deine neuen Recovery Codes sicher ab.',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
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
              for (int i = 0; i < (_newRecoveryCodes?.length ?? 0); i += 2)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}. ${_newRecoveryCodes![i]}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (i + 1 < _newRecoveryCodes!.length)
                        Expanded(
                          child: Text(
                            '${i + 2}. ${_newRecoveryCodes![i + 1]}',
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
        OutlinedButton.icon(
          onPressed: () {
            final codes = _newRecoveryCodes!.asMap().entries
                .map((e) => '${e.key + 1}. ${e.value}')
                .join('\n');
            Clipboard.setData(ClipboardData(text: codes));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Codes kopiert')),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('Codes kopieren'),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _finish,
          child: const Text('Fertig'),
        ),
      ],
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
}
