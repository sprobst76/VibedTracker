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

    // Jahre von 2 Jahren zurück bis 1 Jahr voraus
    final years = [
      currentYear - 2,
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
                  _buildDetailRow('- Genommen', '${stats.usedDays.toStringAsFixed(0)} Tage'),
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

    final controller = TextEditingController(
      text: stats.annualEntitlement.toStringAsFixed(0),
    );

    final result = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Urlaubsanspruch $year'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Standard aus Einstellungen: $defaultDays Tage',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Urlaubstage $year',
                border: const OutlineInputBorder(),
                suffixText: 'Tage',
                hintText: defaultDays.toString(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              hasCustom
                  ? 'Aktuell: Individueller Wert gesetzt'
                  : 'Aktuell: Nutzt Standard ($defaultDays Tage)',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            if (hasCustom) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, -1.0),
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Auf Standard zurücksetzen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              Navigator.pop(context, value);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (result != null) {
      if (result == -1.0) {
        await quotaNotifier.setAnnualEntitlement(year, null);
      } else {
        await quotaNotifier.setAnnualEntitlement(year, result);
      }
    }
  }
}
