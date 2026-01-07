import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';

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

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _checkSetup() async {
    final encryption = ref.read(encryptionServiceProvider);
    final isSetUp = await encryption.isSetUp();
    if (mounted) {
      setState(() => _isSetUp = isSetUp);
    }
  }

  Future<void> _setupPassphrase() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final encryption = ref.read(encryptionServiceProvider);
      await encryption.setUp(_passphraseController.text);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passphrase erfolgreich eingerichtet'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() => _isSetUp = true);
      _passphraseController.clear();
      _confirmController.clear();
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
        // Load keys after verification
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
      setState(() => _isSetUp = false);

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
    if (value.length < 8) {
      return 'Mindestens 8 Zeichen';
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
                  : 'Richte eine Passphrase ein, um deine Daten zu verschlüsseln',
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
            onPressed: _isLoading ? null : _setupPassphrase,
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
              'Daten auf anderen Geräten zu entschlüsseln. Die Passphrase '
              'kann nicht wiederhergestellt werden.',
              style: TextStyle(color: Colors.amber.shade900),
            ),
          ],
        ),
      ),
    );
  }
}
