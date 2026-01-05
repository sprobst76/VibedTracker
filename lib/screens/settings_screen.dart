import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import 'weekly_hours_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Weekly Hours Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wöchentliche Arbeitszeit',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: settings.weeklyHours,
                          min: 10,
                          max: 60,
                          divisions: 50,
                          label: '${settings.weeklyHours.toStringAsFixed(1)} h',
                          onChanged: (value) => notifier.updateWeeklyHours(value),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          '${settings.weeklyHours.toStringAsFixed(1)} h',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WeeklyHoursScreen()),
                    ),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Arbeitszeit-Perioden verwalten'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Locale Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sprache / Region',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: settings.locale,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'de_DE', child: Text('Deutsch (Deutschland)')),
                      DropdownMenuItem(value: 'en_US', child: Text('English (US)')),
                      DropdownMenuItem(value: 'en_GB', child: Text('English (UK)')),
                    ],
                    onChanged: (value) {
                      if (value != null) notifier.updateLocale(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Dark Mode Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dark Mode',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          settings.isDarkMode ? 'Dunkles Design aktiv' : 'Helles Design aktiv',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: settings.isDarkMode,
                    onChanged: (value) => notifier.updateThemeMode(value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ICS Path Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Outlook ICS-Pfad',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pfad für ICS-Export (Outlook-Synchronisation)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: settings.outlookIcsPath ?? '',
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '/pfad/zu/kalender.ics',
                      suffixIcon: settings.outlookIcsPath != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => notifier.updateOutlookIcsPath(null),
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      notifier.updateOutlookIcsPath(value.isEmpty ? null : value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Info Section
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Änderungen werden automatisch gespeichert.',
                      style: TextStyle(color: Colors.blue.shade700),
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
}
