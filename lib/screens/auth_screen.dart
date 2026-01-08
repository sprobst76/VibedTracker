import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  // Login
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Register
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerConfirmPasswordController = TextEditingController();

  // TOTP
  final _totpCodeController = TextEditingController();
  String? _pendingTOTPToken;
  bool _showTOTPInput = false;
  bool _useRecoveryCode = false;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _errorMessage = null;
        _successMessage = null;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmPasswordController.dispose();
    _totpCodeController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(authStatusProvider.notifier).login(
            _loginEmailController.text.trim(),
            _loginPasswordController.text,
          );

      if (!mounted) return;

      // Check if TOTP is required
      if (result.requiresTOTP) {
        setState(() {
          _pendingTOTPToken = result.tempToken;
          _showTOTPInput = true;
          _isLoading = false;
        });
        return;
      }

      final status = ref.read(authStatusProvider);
      if (status == AuthStatus.authenticated) {
        // Nur pop wenn nicht Root-Screen (Web zeigt automatisch Home)
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      } else if (status == AuthStatus.pendingApproval) {
        setState(() {
          _errorMessage = 'Account wartet auf Freischaltung durch Admin';
        });
      } else if (status == AuthStatus.blocked) {
        setState(() {
          _errorMessage = 'Account wurde gesperrt';
        });
      }
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Login fehlgeschlagen: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _validateTOTP() async {
    if (_totpCodeController.text.isEmpty) {
      setState(() => _errorMessage = 'Bitte Code eingeben');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_useRecoveryCode) {
        await ref.read(authStatusProvider.notifier).validateRecoveryCode(
              _pendingTOTPToken!,
              _totpCodeController.text.trim(),
            );
      } else {
        await ref.read(authStatusProvider.notifier).validateTOTP(
              _pendingTOTPToken!,
              _totpCodeController.text.trim(),
            );
      }

      if (!mounted) return;

      final status = ref.read(authStatusProvider);
      if (status == AuthStatus.authenticated) {
        // Nur pop wenn nicht Root-Screen (Web zeigt automatisch Home)
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      } else if (status == AuthStatus.pendingApproval) {
        setState(() {
          _errorMessage = 'Account wartet auf Freischaltung durch Admin';
        });
      } else if (status == AuthStatus.blocked) {
        setState(() {
          _errorMessage = 'Account wurde gesperrt';
        });
      }
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Verifizierung fehlgeschlagen: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _cancelTOTP() {
    setState(() {
      _showTOTPInput = false;
      _pendingTOTPToken = null;
      _useRecoveryCode = false;
      _totpCodeController.clear();
      _errorMessage = null;
    });
  }

  Future<void> _register() async {
    if (!_registerFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.register(
        _registerEmailController.text.trim(),
        _registerPasswordController.text,
      );

      if (!mounted) return;

      setState(() {
        _successMessage =
            'Registrierung erfolgreich! Bitte warte auf die Freischaltung durch einen Admin.';
      });

      // Clear form
      _registerEmailController.clear();
      _registerPasswordController.clear();
      _registerConfirmPasswordController.clear();

      // Switch to login tab after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _tabController.animateTo(0);
        }
      });
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Registrierung fehlgeschlagen: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'E-Mail ist erforderlich';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Ungültige E-Mail-Adresse';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Passwort ist erforderlich';
    }
    if (value.length < 8) {
      return 'Passwort muss mindestens 8 Zeichen haben';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != _registerPasswordController.text) {
      return 'Passwörter stimmen nicht überein';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Show TOTP input if required
    if (_showTOTPInput) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Zwei-Faktor-Authentifizierung'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _cancelTOTP,
          ),
        ),
        body: _buildTOTPInput(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('VibedTracker'),
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Anmelden'),
            Tab(text: 'Registrieren'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLoginTab(),
          _buildRegisterTab(),
        ],
      ),
    );
  }

  Widget _buildTOTPInput() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Icon(
            _useRecoveryCode ? Icons.key : Icons.security,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            _useRecoveryCode
                ? 'Recovery-Code eingeben'
                : 'Authenticator-Code eingeben',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _useRecoveryCode
                ? 'Gib einen deiner Wiederherstellungscodes ein'
                : 'Gib den 6-stelligen Code aus deiner Authenticator-App ein',
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
          TextField(
            controller: _totpCodeController,
            decoration: InputDecoration(
              labelText: _useRecoveryCode ? 'Recovery-Code' : 'Code',
              prefixIcon: Icon(_useRecoveryCode ? Icons.key : Icons.pin),
              border: const OutlineInputBorder(),
            ),
            keyboardType: _useRecoveryCode
                ? TextInputType.text
                : TextInputType.number,
            textInputAction: TextInputAction.done,
            enabled: !_isLoading,
            autofocus: true,
            maxLength: _useRecoveryCode ? null : 6,
            onSubmitted: (_) => _validateTOTP(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isLoading ? null : _validateTOTP,
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
            onPressed: _isLoading
                ? null
                : () {
                    setState(() {
                      _useRecoveryCode = !_useRecoveryCode;
                      _totpCodeController.clear();
                      _errorMessage = null;
                    });
                  },
            child: Text(
              _useRecoveryCode
                  ? 'Authenticator-Code verwenden'
                  : 'Recovery-Code verwenden',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AutofillGroup(
        child: Form(
          key: _loginFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(
                Icons.cloud_sync,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              const Text(
                'Mit Cloud-Account anmelden',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Synchronisiere deine Arbeitszeiten sicher zwischen Geräten',
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
              TextFormField(
                controller: _loginEmailController,
                decoration: const InputDecoration(
                  labelText: 'E-Mail',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                validator: _validateEmail,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _loginPasswordController,
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: _validatePassword,
                enabled: !_isLoading,
                onFieldSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Anmelden'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AutofillGroup(
        child: Form(
          key: _registerFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(
                Icons.person_add,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              const Text(
                'Neuen Account erstellen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Nach der Registrierung muss ein Admin deinen Account freischalten',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_successMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: TextStyle(color: Colors.green.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
              TextFormField(
                controller: _registerEmailController,
                decoration: const InputDecoration(
                  labelText: 'E-Mail',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                validator: _validateEmail,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _registerPasswordController,
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                validator: _validatePassword,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _registerConfirmPasswordController,
                decoration: InputDecoration(
                  labelText: 'Passwort bestätigen',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(
                          () => _obscureConfirmPassword = !_obscureConfirmPassword);
                    },
                  ),
                ),
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                validator: _validateConfirmPassword,
                enabled: !_isLoading,
                onFieldSubmitted: (_) => _register(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _register,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Registrieren'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
