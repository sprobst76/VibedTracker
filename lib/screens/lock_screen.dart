import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/secure_storage_service.dart';
import '../theme/theme_colors.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final bool canUseBiometrics;

  const LockScreen({
    super.key,
    required this.onUnlocked,
    this.canUseBiometrics = true,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _secureStorage = SecureStorageService();
  final _pinController = TextEditingController();
  final _focusNode = FocusNode();

  String _enteredPin = '';
  bool _isLoading = false;
  bool _showError = false;
  int _failedAttempts = 0;
  bool _biometricsAvailable = false;
  bool _biometricsEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    if (!widget.canUseBiometrics) return;

    final available = await _secureStorage.isBiometricsAvailable();
    final enabled = await _secureStorage.isBiometricsEnabled();

    setState(() {
      _biometricsAvailable = available;
      _biometricsEnabled = enabled;
    });

    // Automatisch Biometrie starten wenn verfügbar
    if (available && enabled) {
      _authenticateWithBiometrics();
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    setState(() => _isLoading = true);

    final success = await _secureStorage.authenticateWithBiometrics(
      reason: 'Entsperren um auf VibedTracker zuzugreifen',
    );

    setState(() => _isLoading = false);

    if (success) {
      await _secureStorage.updateLastActivity();
      widget.onUnlocked();
    }
  }

  Future<void> _verifyPin() async {
    if (_enteredPin.length != 6) return;

    setState(() {
      _isLoading = true;
      _showError = false;
    });

    final success = await _secureStorage.verifyPin(_enteredPin);

    setState(() => _isLoading = false);

    if (success) {
      await _secureStorage.updateLastActivity();
      widget.onUnlocked();
    } else {
      setState(() {
        _showError = true;
        _failedAttempts++;
        _enteredPin = '';
      });

      // Haptic feedback
      HapticFeedback.heavyImpact();

      // Bei zu vielen Fehlversuchen: Verzögerung
      if (_failedAttempts >= 3) {
        final delay = _failedAttempts * 5; // 15s, 20s, 25s, ...
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zu viele Fehlversuche. Warte $delay Sekunden.'),
            duration: Duration(seconds: delay),
          ),
        );
        await Future.delayed(Duration(seconds: delay));
      }
    }
  }

  void _onDigitPressed(String digit) {
    if (_enteredPin.length >= 6) return;

    setState(() {
      _enteredPin += digit;
      _showError = false;
    });

    HapticFeedback.lightImpact();

    if (_enteredPin.length == 6) {
      _verifyPin();
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isEmpty) return;

    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _showError = false;
    });

    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Icon(
                Icons.lock_outline,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'VibedTracker entsperren',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),

              Text(
                'Gib deine 6-stellige PIN ein',
                style: TextStyle(color: context.subtleText),
              ),
              const SizedBox(height: 32),

              // PIN Dots
              _buildPinDots(),
              const SizedBox(height: 16),

              // Error message
              if (_showError)
                Text(
                  'Falsche PIN',
                  style: TextStyle(color: Colors.red.shade600),
                ),
              const SizedBox(height: 32),

              // Numpad
              _buildNumpad(),
              const SizedBox(height: 24),

              // Biometrics Button
              if (_biometricsAvailable && _biometricsEnabled)
                TextButton.icon(
                  onPressed: _isLoading ? null : _authenticateWithBiometrics,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Mit Fingerabdruck entsperren'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final isFilled = index < _enteredPin.length;
        final isError = _showError;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled
                ? (isError ? Colors.red : Theme.of(context).colorScheme.primary)
                : Colors.transparent,
            border: Border.all(
              color: isError
                  ? Colors.red
                  : Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['1', '2', '3'].map((d) => _buildDigitButton(d)).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['4', '5', '6'].map((d) => _buildDigitButton(d)).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['7', '8', '9'].map((d) => _buildDigitButton(d)).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Leerer Platz oder Biometrics
            _biometricsAvailable && _biometricsEnabled
                ? _buildIconButton(Icons.fingerprint, _authenticateWithBiometrics)
                : const SizedBox(width: 80, height: 80),
            _buildDigitButton('0'),
            _buildIconButton(Icons.backspace_outlined, _onBackspacePressed),
          ],
        ),
      ],
    );
  }

  Widget _buildDigitButton(String digit) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : () => _onDigitPressed(digit),
          borderRadius: BorderRadius.circular(40),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withAlpha(100),
              ),
            ),
            child: Center(
              child: Text(
                digit,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(40),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(
              child: Icon(icon, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget zum Setzen einer neuen PIN
class SetPinScreen extends StatefulWidget {
  final VoidCallback onPinSet;
  final bool isChangingPin;

  const SetPinScreen({
    super.key,
    required this.onPinSet,
    this.isChangingPin = false,
  });

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final _secureStorage = SecureStorageService();

  String _firstPin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _showError = false;
  bool _isLoading = false;

  void _onDigitPressed(String digit) {
    if (_isConfirming) {
      if (_confirmPin.length >= 6) return;
      setState(() {
        _confirmPin += digit;
        _showError = false;
      });
      if (_confirmPin.length == 6) {
        _verifyAndSave();
      }
    } else {
      if (_firstPin.length >= 6) return;
      setState(() {
        _firstPin += digit;
      });
      if (_firstPin.length == 6) {
        setState(() => _isConfirming = true);
      }
    }
    HapticFeedback.lightImpact();
  }

  void _onBackspacePressed() {
    if (_isConfirming) {
      if (_confirmPin.isEmpty) {
        setState(() {
          _isConfirming = false;
          _firstPin = '';
        });
      } else {
        setState(() {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        });
      }
    } else {
      if (_firstPin.isEmpty) return;
      setState(() {
        _firstPin = _firstPin.substring(0, _firstPin.length - 1);
      });
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _verifyAndSave() async {
    if (_firstPin != _confirmPin) {
      setState(() {
        _showError = true;
        _confirmPin = '';
      });
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _isLoading = true);

    await _secureStorage.setPin(_firstPin);
    await _secureStorage.setAppLockEnabled(true);

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN erfolgreich gesetzt')),
      );
      widget.onPinSet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = _isConfirming ? _confirmPin : _firstPin;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isChangingPin ? 'PIN ändern' : 'PIN festlegen'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isConfirming ? Icons.check_circle_outline : Icons.lock_outline,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),

              Text(
                _isConfirming ? 'PIN bestätigen' : 'Neue PIN eingeben',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),

              Text(
                _isConfirming
                    ? 'Gib die PIN erneut ein'
                    : 'Wähle eine 6-stellige PIN',
                style: TextStyle(color: context.subtleText),
              ),
              const SizedBox(height: 32),

              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final isFilled = index < currentPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? (_showError ? Colors.red : Theme.of(context).colorScheme.primary)
                          : Colors.transparent,
                      border: Border.all(
                        color: _showError
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),

              if (_showError)
                const Text(
                  'PINs stimmen nicht überein',
                  style: TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 32),

              // Numpad
              _buildNumpad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['1', '2', '3'].map((d) => _buildDigitButton(d)).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['4', '5', '6'].map((d) => _buildDigitButton(d)).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['7', '8', '9'].map((d) => _buildDigitButton(d)).toList(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 80, height: 80),
            _buildDigitButton('0'),
            _buildIconButton(Icons.backspace_outlined, _onBackspacePressed),
          ],
        ),
      ],
    );
  }

  Widget _buildDigitButton(String digit) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : () => _onDigitPressed(digit),
          borderRadius: BorderRadius.circular(40),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withAlpha(100),
              ),
            ),
            child: Center(
              child: Text(
                digit,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(40),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(child: Icon(icon, size: 28)),
          ),
        ),
      ),
    );
  }
}
