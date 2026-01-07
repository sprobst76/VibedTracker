import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../screens/calendar_overview_screen.dart';
import '../screens/vacation_screen.dart';
import '../screens/report_screen.dart';
import '../screens/settings_screen.dart';

/// Responsive Shell für Web und Mobile
/// Web: Sidebar Navigation
/// Mobile: Standard AppBar
class ResponsiveShell extends ConsumerStatefulWidget {
  final Widget child;
  final String title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const ResponsiveShell({
    super.key,
    required this.child,
    this.title = 'VibedTracker',
    this.actions,
    this.floatingActionButton,
  });

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  int _selectedIndex = 0;

  static const _breakpoint = 800.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWideScreen = width >= _breakpoint;

    // Web mit breitem Screen: Sidebar Layout
    if (kIsWeb && isWideScreen) {
      return _buildWebLayout(context);
    }

    // Mobile oder schmaler Web-Screen: Standard Layout
    return _buildMobileLayout(context);
  }

  Widget _buildWebLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authStatus = ref.watch(authStatusProvider);

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 240,
            color: colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 32,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'VibedTracker',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _buildNavItem(
                        context,
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home,
                        label: 'Dashboard',
                        index: 0,
                      ),
                      _buildNavItem(
                        context,
                        icon: Icons.calendar_month_outlined,
                        selectedIcon: Icons.calendar_month,
                        label: 'Kalender',
                        index: 1,
                      ),
                      _buildNavItem(
                        context,
                        icon: Icons.event_available_outlined,
                        selectedIcon: Icons.event_available,
                        label: 'Abwesenheiten',
                        index: 2,
                      ),
                      _buildNavItem(
                        context,
                        icon: Icons.bar_chart_outlined,
                        selectedIcon: Icons.bar_chart,
                        label: 'Auswertungen',
                        index: 3,
                      ),
                      const Divider(height: 32),
                      _buildNavItem(
                        context,
                        icon: Icons.settings_outlined,
                        selectedIcon: Icons.settings,
                        label: 'Einstellungen',
                        index: 4,
                      ),
                    ],
                  ),
                ),

                // User Info / Logout
                if (authStatus == AuthStatus.authenticated) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            Icons.person,
                            size: 20,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            ref.watch(authServiceProvider).currentUser?.email ?? '',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, size: 20),
                          tooltip: 'Abmelden',
                          onPressed: () => _logout(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: _buildContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selectedIndex = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_selectedIndex) {
      case 0:
        return widget.child; // Dashboard (HomeScreen content)
      case 1:
        return const CalendarOverviewScreen();
      case 2:
        return const VacationScreen();
      case 3:
        return const ReportScreen();
      case 4:
        return const SettingsScreen();
      default:
        return widget.child;
    }
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: widget.actions,
      ),
      body: widget.child,
      floatingActionButton: widget.floatingActionButton,
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abmelden'),
        content: const Text('Möchtest du dich wirklich abmelden?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authStatusProvider.notifier).logout();
    }
  }
}

/// Helper Widget für Web-optimierte Content-Container
class WebContentContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  const WebContentContainer({
    super.key,
    required this.child,
    this.maxWidth = 1200,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
