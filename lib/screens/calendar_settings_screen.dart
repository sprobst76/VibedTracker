import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/google_calendar_service.dart';

class CalendarSettingsScreen extends ConsumerStatefulWidget {
  const CalendarSettingsScreen({super.key});

  @override
  ConsumerState<CalendarSettingsScreen> createState() => _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState extends ConsumerState<CalendarSettingsScreen> {
  final _calendarService = GoogleCalendarService();
  List<CalendarInfo> _calendars = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSignIn();
  }

  Future<void> _checkSignIn() async {
    setState(() => _isLoading = true);
    try {
      final isSignedIn = await _calendarService.checkSignIn();
      if (isSignedIn) {
        await _loadCalendars();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
    setState(() => _isLoading = false);
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final success = await _calendarService.signIn();
      if (success) {
        await _loadCalendars();
        ref.read(settingsProvider.notifier).updateGoogleCalendarEnabled(true);
      } else {
        setState(() => _error = 'Anmeldung fehlgeschlagen');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }

    setState(() => _isLoading = false);
  }

  Future<void> _signOut() async {
    setState(() => _isLoading = true);
    await _calendarService.signOut();
    ref.read(settingsProvider.notifier).updateGoogleCalendarEnabled(false);
    ref.read(settingsProvider.notifier).updateGoogleCalendarId(null);
    setState(() {
      _calendars = [];
      _isLoading = false;
    });
  }

  Future<void> _loadCalendars() async {
    try {
      final calendars = await _calendarService.getCalendars();
      setState(() => _calendars = calendars);
    } catch (e) {
      setState(() => _error = 'Kalender konnten nicht geladen werden');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isSignedIn = _calendarService.isSignedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Kalender'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status Card
          Card(
            color: isSignedIn ? Colors.green.shade50 : Colors.grey.shade100,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isSignedIn ? Colors.green : Colors.grey,
                    child: Icon(
                      isSignedIn ? Icons.check : Icons.cloud_off,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSignedIn ? 'Verbunden' : 'Nicht verbunden',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (isSignedIn && _calendarService.userEmail != null)
                          Text(
                            _calendarService.userEmail!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    ElevatedButton(
                      onPressed: isSignedIn ? _signOut : _signIn,
                      child: Text(isSignedIn ? 'Trennen' : 'Verbinden'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Error
          if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Calendar Selection
          if (isSignedIn && _calendars.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kalender auswählen',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Wähle den Kalender, dessen Termine in der Wochenübersicht angezeigt werden sollen.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: settings.googleCalendarId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Kein Kalender'),
                        ),
                        ..._calendars.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Row(
                                children: [
                                  if (c.primary)
                                    const Icon(Icons.star, size: 16, color: Colors.amber),
                                  if (c.primary) const SizedBox(width: 8),
                                  Expanded(child: Text(c.summary)),
                                ],
                              ),
                            )),
                      ],
                      onChanged: (value) {
                        ref.read(settingsProvider.notifier).updateGoogleCalendarId(value);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Info
          const SizedBox(height: 32),
          Card(
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
                        'Hinweis',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Die Google Kalender Integration ist schreibgeschützt. '
                    'Termine werden nur angezeigt, nicht verändert.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
