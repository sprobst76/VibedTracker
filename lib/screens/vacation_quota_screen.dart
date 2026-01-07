import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../models/vacation_quota.dart';
import '../theme/theme_colors.dart';

/// Screen zur Verwaltung des Urlaubsanspruchs pro Jahr
class VacationQuotaScreen extends ConsumerStatefulWidget {
  const VacationQuotaScreen({super.key});

  @override
  ConsumerState<VacationQuotaScreen> createState() => _VacationQuotaScreenState();
}

class _VacationQuotaScreenState extends ConsumerState<VacationQuotaScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final currentYear = DateTime.now().year;

    // Jahre: Vorjahr, aktuelles Jahr, nächstes Jahr
    final years = [
      currentYear - 1,
      currentYear,
      currentYear + 1,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Urlaubsanspruch pro Jahr'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info Card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Theme.of(context).colorScheme.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Standard: ${settings.annualVacationDays} Tage/Jahr',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hier kannst du für jedes Jahr einen individuellen Urlaubsanspruch festlegen. '
                    'Wenn kein Wert gesetzt ist, gilt der Standard aus den Einstellungen.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Jahres-Liste
          ...years.map((year) => _buildYearCard(year, currentYear)),
        ],
      ),
    );
  }

  Widget _buildYearCard(int year, int currentYear) {
    final stats = ref.watch(vacationStatsProvider(year));
    final settings = ref.watch(settingsProvider);
    final quotaNotifier = ref.read(vacationQuotaProvider.notifier);
    final quota = quotaNotifier.getForYear(year);
    final hasCustomEntitlement = quota?.annualEntitlementDays != null;
    final isCurrentYear = year == currentYear;
    final isPastYear = year < currentYear;

    return Card(
      color: isCurrentYear ? Colors.green.shade50 : null,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header mit Jahr
            Row(
              children: [
                Text(
                  '$year',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                if (isCurrentYear)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Aktuell',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                if (isPastYear)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Vergangen',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                const Spacer(),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: stats.remainingDays >= 0 ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${stats.remainingDays.toStringAsFixed(0)} Rest',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Anspruch-Zeile
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Jahresanspruch', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${stats.annualEntitlement.toStringAsFixed(0)} Tage',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          if (hasCustomEntitlement) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Individuell',
                                style: TextStyle(fontSize: 10, color: Colors.orange.shade700),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(width: 8),
                            Text(
                              '(Standard)',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showEditDialog(year, stats, settings.annualVacationDays),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Details
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.infoBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Basis-Anspruch', '${stats.annualEntitlement.toStringAsFixed(0)} Tage'),
                  if (stats.carryover > 0)
                    _buildDetailRow('+ Übertrag', '${stats.carryover.toStringAsFixed(0)} Tage'),
                  if (stats.adjustments != 0)
                    _buildDetailRow(stats.adjustments > 0 ? '+ Anpassung' : '- Anpassung',
                                   '${stats.adjustments.abs().toStringAsFixed(0)} Tage'),
                  const Divider(height: 8),
                  _buildDetailRow('= Gesamt', '${stats.totalEntitlement.toStringAsFixed(0)} Tage', bold: true),
                  if (stats.trackedDays > 0)
                    _buildDetailRow('- Eingetragen', '${stats.trackedDays.toStringAsFixed(0)} Tage'),
                  if (stats.manualDays > 0)
                    _buildDetailRow('- Manuell', '${stats.manualDays.toStringAsFixed(0)} Tage'),
                  if (stats.trackedDays > 0 || stats.manualDays > 0)
                    _buildDetailRow('- Genommen gesamt', '${stats.usedDays.toStringAsFixed(0)} Tage'),
                  if (stats.trackedDays == 0 && stats.manualDays == 0)
                    _buildDetailRow('- Genommen', '0 Tage'),
                  const Divider(height: 8),
                  _buildDetailRow('= Verbleibend', '${stats.remainingDays.toStringAsFixed(0)} Tage',
                                 bold: true,
                                 color: stats.remainingDays >= 0 ? Colors.green : Colors.red),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color ?? (bold ? Colors.black : Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(int year, VacationStats stats, int defaultDays) async {
    final quotaNotifier = ref.read(vacationQuotaProvider.notifier);
    final quota = quotaNotifier.getForYear(year);
    final hasCustom = quota?.annualEntitlementDays != null;

    final entitlementController = TextEditingController(
      text: stats.annualEntitlement.toStringAsFixed(0),
    );
    final manualDaysController = TextEditingController(
      text: stats.manualDays > 0 ? stats.manualDays.toStringAsFixed(0) : '',
    );

    final result = await showDialog<Map<String, double?>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Urlaub $year bearbeiten'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Jahresanspruch
              Text(
                'Jahresanspruch',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 4),
              Text(
                'Standard: $defaultDays Tage',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: entitlementController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Urlaubstage',
                  border: const OutlineInputBorder(),
                  suffixText: 'Tage',
                  hintText: defaultDays.toString(),
                ),
              ),
              if (hasCustom) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    entitlementController.text = defaultDays.toString();
                  },
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('Standard verwenden'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Manuell genommene Tage
              Text(
                'Bereits genommene Tage (manuell)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 4),
              Text(
                'Für Tage die nicht einzeln eingetragen sind.\n'
                'Z.B. aus früherem System übernommen.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: manualDaysController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Manuell genommen',
                  border: OutlineInputBorder(),
                  suffixText: 'Tage',
                  hintText: '0',
                ),
              ),
              const SizedBox(height: 8),
              if (stats.trackedDays > 0)
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
                          'Zusätzlich: ${stats.trackedDays.toStringAsFixed(0)} eingetragene Tage',
                          style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final entitlement = double.tryParse(entitlementController.text);
              final manualDays = double.tryParse(manualDaysController.text) ?? 0.0;
              Navigator.pop(context, {
                'entitlement': entitlement,
                'manualDays': manualDays,
                'resetEntitlement': entitlement?.toInt() == defaultDays,
              });
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result != null) {
      final double? entitlement = result['entitlement'];
      final double manualDays = result['manualDays'] ?? 0.0;
      final resetEntitlement = result['resetEntitlement'] as bool? ?? false;

      if (resetEntitlement) {
        await quotaNotifier.setAnnualEntitlement(year, null);
      } else if (entitlement != null) {
        await quotaNotifier.setAnnualEntitlement(year, entitlement);
      }
      await quotaNotifier.setManualUsedDays(year, manualDays);
    }
  }
}
