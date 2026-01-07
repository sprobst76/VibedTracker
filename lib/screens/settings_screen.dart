import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../models/settings.dart';
import '../services/test_data_service.dart';
import '../services/reminder_service.dart';
import '../services/backup_service.dart';
import 'weekly_hours_screen.dart';
import 'geofence_setup_screen.dart';
import 'calendar_settings_screen.dart';
import 'projects_screen.dart';
import 'security_settings_screen.dart';
import 'vacation_quota_screen.dart';
import '../theme/theme_colors.dart';

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
          _buildWeeklyHoursSection(context, ref),
          const SizedBox(height: 16),

          // Arbeitswoche Section
          _buildWorkWeekSection(context, ref, settings, notifier),
          const SizedBox(height: 16),

          // Urlaubstage Section
          _buildVacationSection(context, ref, settings, notifier),
          const SizedBox(height: 16),

          // Heiligabend & Silvester Section
          _buildSpecialDaysSection(context, ref, settings, notifier),
          const SizedBox(height: 16),

          // Projekte Section
          _buildProjectsSection(context, ref),
          const SizedBox(height: 16),

          // Locale Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sprache',
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

          // Bundesland Section (für Feiertage)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bundesland (für Feiertage)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Bestimmt welche regionalen Feiertage angezeigt werden.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: settings.bundesland,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'DE', child: Text('Alle Bundesländer')),
                      DropdownMenuItem(value: 'BW', child: Text('Baden-Württemberg')),
                      DropdownMenuItem(value: 'BY', child: Text('Bayern')),
                      DropdownMenuItem(value: 'BE', child: Text('Berlin')),
                      DropdownMenuItem(value: 'BB', child: Text('Brandenburg')),
                      DropdownMenuItem(value: 'HB', child: Text('Bremen')),
                      DropdownMenuItem(value: 'HH', child: Text('Hamburg')),
                      DropdownMenuItem(value: 'HE', child: Text('Hessen')),
                      DropdownMenuItem(value: 'MV', child: Text('Mecklenburg-Vorpommern')),
                      DropdownMenuItem(value: 'NI', child: Text('Niedersachsen')),
                      DropdownMenuItem(value: 'NW', child: Text('Nordrhein-Westfalen')),
                      DropdownMenuItem(value: 'RP', child: Text('Rheinland-Pfalz')),
                      DropdownMenuItem(value: 'SL', child: Text('Saarland')),
                      DropdownMenuItem(value: 'SN', child: Text('Sachsen')),
                      DropdownMenuItem(value: 'ST', child: Text('Sachsen-Anhalt')),
                      DropdownMenuItem(value: 'SH', child: Text('Schleswig-Holstein')),
                      DropdownMenuItem(value: 'TH', child: Text('Thüringen')),
                    ],
                    onChanged: (value) {
                      if (value != null) notifier.updateBundesland(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Theme Mode Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Design',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<AppThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: AppThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Hell'),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Dunkel'),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (Set<AppThemeMode> selection) {
                      notifier.updateThemeMode(selection.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Security Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.security,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sicherheit',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'App-Sperre, PIN, Biometrie',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
                    ),
                    icon: const Icon(Icons.lock),
                    label: const Text('Sicherheit konfigurieren'),
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
          const SizedBox(height: 16),

          // Geofence Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Arbeitsorte (Geofencing)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Definiere Orte, an denen die automatische Zeiterfassung aktiv sein soll.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GeofenceSetupScreen()),
                    ),
                    icon: const Icon(Icons.location_on),
                    label: const Text('Arbeitsorte verwalten'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Location Tracking Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'GPS-Tracking',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              settings.enableLocationTracking
                                  ? 'Standort wird während der Arbeit aufgezeichnet'
                                  : 'Standort-Aufzeichnung deaktiviert',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: settings.enableLocationTracking,
                        onChanged: (value) => notifier.updateLocationTracking(value),
                      ),
                    ],
                  ),
                  if (settings.enableLocationTracking) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Der Standort wird alle 5 Minuten oder bei 100m Bewegung gespeichert.',
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Google Calendar Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Google Kalender',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Termine aus Google Kalender anzeigen (nur lesen)',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      if (settings.googleCalendarEnabled)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Verbunden',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CalendarSettingsScreen()),
                    ),
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Kalender konfigurieren'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Reminder Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Erinnerungen',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              settings.enableReminders
                                  ? 'Tägliche Erinnerung um ${settings.reminderHour}:00 Uhr'
                                  : 'Erinnerungen deaktiviert',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: settings.enableReminders,
                        onChanged: (value) async {
                          notifier.updateEnableReminders(value);
                          final reminderService = ReminderService();
                          if (value) {
                            await reminderService.scheduleDailyReminder(settings.reminderHour);
                          } else {
                            await reminderService.cancelAllReminders();
                          }
                        },
                      ),
                    ],
                  ),
                  if (settings.enableReminders) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 20),
                        const SizedBox(width: 8),
                        const Text('Uhrzeit:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 16),
                        DropdownButton<int>(
                          value: settings.reminderHour,
                          items: List.generate(24, (hour) => DropdownMenuItem(
                            value: hour,
                            child: Text('$hour:00 Uhr'),
                          )),
                          onChanged: (hour) async {
                            if (hour != null) {
                              notifier.updateReminderHour(hour);
                              final reminderService = ReminderService();
                              await reminderService.scheduleDailyReminder(hour);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active, size: 16, color: Colors.amber.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Du wirst benachrichtigt, wenn Tage ohne Zeiterfassung oder Abwesenheit fehlen.',
                              style: TextStyle(fontSize: 11, color: Colors.amber.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final reminderService = ReminderService();
                        await reminderService.showTestNotification();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Test-Notification gesendet'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.notification_add),
                      label: const Text('Test-Notification'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Backup Section
          _buildBackupSection(context, ref),
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

          // Developer Options (nur im Debug-Modus)
          if (kDebugMode) ...[
            const SizedBox(height: 32),
            _buildDeveloperOptions(context, ref),
          ],
        ],
      ),
    );
  }

  Widget _buildWeeklyHoursSection(BuildContext context, WidgetRef ref) {
    final periodsNotifier = ref.watch(weeklyHoursPeriodsProvider.notifier);
    final periods = ref.watch(weeklyHoursPeriodsProvider);
    final currentHours = periodsNotifier.getWeeklyHoursForDate(DateTime.now());

    // Find active period if any
    final activePeriods = periods.where((p) => p.containsDate(DateTime.now()));
    final activePeriod = activePeriods.isNotEmpty ? activePeriods.first : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Wöchentliche Arbeitszeit',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${currentHours.toStringAsFixed(currentHours == currentHours.roundToDouble() ? 0 : 1)}h',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              activePeriod != null
                  ? 'Aktive Periode: ${activePeriod.description ?? "${currentHours}h/Woche"}'
                  : 'Standard-Arbeitszeit (keine aktive Periode)',
              style: TextStyle(fontSize: 12, color: context.subtleText),
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
    );
  }

  Widget _buildWorkWeekSection(BuildContext context, WidgetRef ref, Settings settings, SettingsNotifier notifier) {
    const weekdayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Arbeitswoche',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Markiere Tage, an denen du normalerweise NICHT arbeitest.',
              style: TextStyle(fontSize: 12, color: context.subtleText),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (index) {
                final weekday = index + 1; // 1-7
                final isNonWorking = settings.nonWorkingWeekdays.contains(weekday);
                return FilterChip(
                  label: Text(weekdayNames[index]),
                  selected: isNonWorking,
                  selectedColor: Colors.red.shade100,
                  checkmarkColor: Colors.red.shade700,
                  onSelected: (_) => notifier.toggleNonWorkingWeekday(weekday),
                );
              }),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.infoBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: context.infoForeground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${settings.workingDaysPerWeek} Arbeitstage pro Woche'
                      '${settings.nonWorkingWeekdays.isEmpty ? '' : ' (${_formatNonWorkingDays(settings.nonWorkingWeekdays)} frei)'}',
                      style: TextStyle(fontSize: 11, color: context.infoForeground),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNonWorkingDays(List<int> weekdays) {
    const dayNames = {1: 'Mo', 2: 'Di', 3: 'Mi', 4: 'Do', 5: 'Fr', 6: 'Sa', 7: 'So'};
    return weekdays.map((d) => dayNames[d]).join(', ');
  }

  Widget _buildVacationSection(BuildContext context, WidgetRef ref, Settings settings, SettingsNotifier notifier) {
    final stats = ref.watch(currentYearVacationStatsProvider);
    final year = DateTime.now().year;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Urlaub',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: stats.remainingDays > 0 ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${stats.remainingDays.toStringAsFixed(0)} Tage',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Resturlaub-Anzeige
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.infoBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Anspruch $year:', style: TextStyle(color: context.infoForeground)),
                      Text('${stats.totalEntitlement.toStringAsFixed(0)} Tage',
                           style: TextStyle(fontWeight: FontWeight.bold, color: context.infoForeground)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Genommen:', style: TextStyle(color: context.infoForeground)),
                      Text('${stats.usedDays.toStringAsFixed(0)} Tage',
                           style: TextStyle(color: context.infoForeground)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Verbleibend:', style: TextStyle(color: context.infoForeground)),
                      Text('${stats.remainingDays.toStringAsFixed(0)} Tage',
                           style: TextStyle(fontWeight: FontWeight.bold, color: context.infoForeground)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VacationQuotaScreen()),
              ),
              icon: const Icon(Icons.edit_calendar),
              label: const Text('Urlaubsanspruch pro Jahr verwalten'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resturlaub übertragen'),
              subtitle: Text(
                'Nicht genommener Urlaub wird ins nächste Jahr übertragen.',
                style: TextStyle(fontSize: 12, color: context.subtleText),
              ),
              value: settings.enableVacationCarryover,
              onChanged: notifier.updateVacationCarryover,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialDaysSection(BuildContext context, WidgetRef ref, Settings settings, SettingsNotifier notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Heiligabend & Silvester',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Wie werden 24.12. und 31.12. im Arbeitszeitkonto behandelt?',
              style: TextStyle(fontSize: 12, color: context.subtleText),
            ),
            const SizedBox(height: 16),
            // Heiligabend
            Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text('24. Dezember'),
                ),
                Expanded(
                  flex: 3,
                  child: SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 0.0, label: Text('Frei')),
                      ButtonSegment(value: 0.5, label: Text('½ Tag')),
                      ButtonSegment(value: 1.0, label: Text('Voll')),
                    ],
                    selected: {settings.christmasEveWorkFactor},
                    onSelectionChanged: (values) {
                      notifier.updateChristmasEveWorkFactor(values.first);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Silvester
            Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text('31. Dezember'),
                ),
                Expanded(
                  flex: 3,
                  child: SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 0.0, label: Text('Frei')),
                      ButtonSegment(value: 0.5, label: Text('½ Tag')),
                      ButtonSegment(value: 1.0, label: Text('Voll')),
                    ],
                    selected: {settings.newYearsEveWorkFactor},
                    onSelectionChanged: (values) {
                      notifier.updateNewYearsEveWorkFactor(values.first);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.infoBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: context.infoForeground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Diese Einstellung beeinflusst die Soll-Arbeitszeit an diesen Tagen.',
                      style: TextStyle(fontSize: 11, color: context.infoForeground),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectsSection(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final activeProjects = projects.where((p) => p.isActive).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Projekte',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (activeProjects.isNotEmpty)
                  Text(
                    '${activeProjects.length} aktiv',
                    style: TextStyle(fontSize: 12, color: context.subtleText),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ordne Arbeitszeiten Projekten zu.',
              style: TextStyle(fontSize: 12, color: context.subtleText),
            ),
            const SizedBox(height: 12),
            if (activeProjects.isNotEmpty) ...[
              ...activeProjects.take(3).map((project) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: project.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(project.name),
                  ],
                ),
              )),
              if (activeProjects.length > 3)
                Text(
                  '+ ${activeProjects.length - 3} weitere...',
                  style: TextStyle(fontSize: 12, color: context.subtleText),
                ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProjectsScreen()),
              ),
              icon: const Icon(Icons.folder_open),
              label: Text(activeProjects.isEmpty ? 'Projekte anlegen' : 'Projekte verwalten'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupSection(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.backup,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daten & Backup',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Daten exportieren und importieren',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _createBackup(context),
                    icon: const Icon(Icons.upload),
                    label: const Text('Backup erstellen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showImportInfo(context, ref),
                    icon: const Icon(Icons.download),
                    label: const Text('Importieren'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.infoBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: context.infoForeground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Backup enthält alle Einträge, Urlaub, Projekte und Einstellungen.',
                      style: TextStyle(fontSize: 11, color: context.infoForeground),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBackup(BuildContext context) async {
    try {
      // Loading anzeigen
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final backupService = BackupService();
      await backupService.shareBackup();

      if (context.mounted) {
        Navigator.pop(context); // Loading schließen
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Loading schließen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showImportInfo(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup importieren'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Um ein Backup zu importieren:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('1. Öffne die Backup-ZIP-Datei auf deinem Gerät'),
            SizedBox(height: 4),
            Text('2. Wähle "Öffnen mit" → VibedTracker'),
            SizedBox(height: 12),
            Text(
              'Alternativ: Backup-Datei in den Download-Ordner kopieren und App neu starten.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SizedBox(height: 16),
            Text(
              'Hinweis: Bestehende Daten werden nicht überschrieben, nur ergänzt.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperOptions(BuildContext context, WidgetRef ref) {
    final testDataService = TestDataService();

    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.developer_mode, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Entwickler-Optionen',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Testdaten generieren?'),
                    content: const Text(
                      'Es werden Arbeitseinträge und Urlaubstage für die letzten 3 Monate generiert. '
                      'Bestehende Daten bleiben erhalten.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Abbrechen'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Generieren'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  final result = await testDataService.generateTestData(months: 3);
                  ref.invalidate(workListProvider);
                  ref.invalidate(workEntryProvider);
                  ref.invalidate(vacationProvider);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${result.entriesCreated} Einträge und ${result.vacationsCreated} Urlaubstage erstellt',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.add_chart),
              label: const Text('Testdaten generieren (3 Monate)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Alle Daten löschen?'),
                    content: const Text(
                      'ACHTUNG: Alle Arbeitseinträge und Urlaubstage werden unwiderruflich gelöscht!',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Abbrechen'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Löschen'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  await testDataService.clearAllData();
                  ref.invalidate(workListProvider);
                  ref.invalidate(workEntryProvider);
                  ref.invalidate(vacationProvider);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Alle Daten wurden gelöscht'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              icon: Icon(Icons.delete_forever, color: Colors.red.shade700),
              label: Text(
                'Alle Daten löschen',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

