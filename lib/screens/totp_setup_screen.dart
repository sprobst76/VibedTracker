import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

class TOTPSetupScreen extends ConsumerStatefulWidget {
  const TOTPSetupScreen({super.key});

  @override
  ConsumerState<TOTPSetupScreen> createState() => _TOTPSetupScreenState();
}

class _TOTPSetupScreenState extends ConsumerState<TOTPSetupScreen> {
  final _codeController = TextEditingController();

  TOTPSetupData? _setupData;
  List<String>? _recoveryCodes;

  bool _isLoading = false;
  String? _errorMessage;
  int _currentStep = 0; // 0: loading, 1: show QR, 2: verify, 3: recovery codes

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final setupData = await auth.setupTOTP();

      if (!mounted) return;

      setState(() {
        _setupData = setupData;
        _currentStep = 1;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Setup fehlgeschlagen: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.length != 6) {
      setState(() => _errorMessage = 'Bitte 6-stelligen Code eingeben');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final codes = await auth.verifyTOTPSetup(_codeController.text);

      if (!mounted) return;

      setState(() {
        _recoveryCodes = codes;
        _currentStep = 3;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Verifizierung fehlgeschlagen: $e';
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('In Zwischenablage kopiert'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copyAllCodes() {
    if (_recoveryCodes == null) return;
    final text = _recoveryCodes!.join('\n');
    _copyToClipboard(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('2FA einrichten'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _currentStep == 0) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _currentStep == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _startSetup,
                child: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    switch (_currentStep) {
      case 1:
        return _buildQRCodeStep();
      case 2:
        return _buildVerifyStep();
      case 3:
        return _buildRecoveryCodesStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildQRCodeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.qr_code_2, size: 64, color: Colors.blue),
          const SizedBox(height: 16),
          const Text(
            'Authenticator-App einrichten',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Scanne den QR-Code mit deiner Authenticator-App (z.B. Google Authenticator, Authy)',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: QrImageView(
                data: _setupData!.qrCodeUrl,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Manueller Code',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _setupData!.secret,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () => _copyToClipboard(_setupData!.secret),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => setState(() => _currentStep = 2),
            child: const Text('Weiter'),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.security, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          const Text(
            'Code verifizieren',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Gib den 6-stelligen Code aus deiner Authenticator-App ein',
            style: TextStyle(color: Colors.grey),
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
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Code',
              prefixIcon: Icon(Icons.pin),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            enabled: !_isLoading,
            autofocus: true,
            onSubmitted: (_) => _verifyCode(),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: _isLoading ? null : () => setState(() => _currentStep = 1),
                child: const Text('Zuruck'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: _isLoading ? null : _verifyCode,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verifizieren'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecoveryCodesStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          const Text(
            '2FA erfolgreich aktiviert!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Card(
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
                        'Wichtig: Recovery-Codes speichern!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Diese Codes sind deine einzige Moglichkeit, auf dein Konto zuzugreifen, '
                    'wenn du dein Smartphone verlierst. Speichere sie sicher!',
                    style: TextStyle(color: Colors.amber.shade900),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recovery-Codes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_all),
                        onPressed: _copyAllCodes,
                        tooltip: 'Alle kopieren',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _recoveryCodes!.map((code) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          code,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
  }
}
