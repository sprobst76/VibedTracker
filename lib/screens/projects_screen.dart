import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../models/project.dart';
import '../theme/theme_colors.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final activeProjects = projects.where((p) => p.isActive).toList();
    final archivedProjects = projects.where((p) => !p.isActive).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projekte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddProjectDialog(context, ref),
            tooltip: 'Neues Projekt',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (activeProjects.isEmpty && archivedProjects.isEmpty) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.folder_open, size: 64, color: context.subtleText),
                    const SizedBox(height: 16),
                    Text(
                      'Noch keine Projekte',
                      style: TextStyle(fontSize: 18, color: context.subtleText),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Erstelle Projekte, um deine Arbeitszeit\nbesser zu kategorisieren.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.subtleText),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _showAddProjectDialog(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Erstes Projekt erstellen'),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Aktive Projekte
            if (activeProjects.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Aktive Projekte',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.subtleText,
                  ),
                ),
              ),
              ...activeProjects.map((project) => _buildProjectTile(context, ref, project)),
              const SizedBox(height: 16),
            ],

            // Archivierte Projekte
            if (archivedProjects.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Archivierte Projekte',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.subtleText,
                  ),
                ),
              ),
              ...archivedProjects.map((project) => _buildProjectTile(context, ref, project, isArchived: true)),
            ],
          ],
        ],
      ),
      floatingActionButton: (activeProjects.isNotEmpty || archivedProjects.isNotEmpty)
          ? FloatingActionButton(
              onPressed: () => _showAddProjectDialog(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildProjectTile(BuildContext context, WidgetRef ref, Project project, {bool isArchived = false}) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: project.color.withAlpha(isArchived ? 100 : 255),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.folder,
            color: Colors.white.withAlpha(isArchived ? 150 : 255),
          ),
        ),
        title: Text(
          project.name,
          style: TextStyle(
            color: isArchived ? context.subtleText : null,
            decoration: isArchived ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: isArchived ? const Text('Archiviert') : null,
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                _showEditProjectDialog(context, ref, project);
                break;
              case 'archive':
                await ref.read(projectsProvider.notifier).updateProject(project, newIsActive: false);
                break;
              case 'restore':
                await ref.read(projectsProvider.notifier).updateProject(project, newIsActive: true);
                break;
              case 'delete':
                _showDeleteConfirmation(context, ref, project);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit),
                title: Text('Bearbeiten'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (!isArchived)
              const PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  leading: Icon(Icons.archive),
                  title: Text('Archivieren'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            if (isArchived)
              const PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  leading: Icon(Icons.unarchive),
                  title: Text('Wiederherstellen'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Löschen', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        onTap: () => _showEditProjectDialog(context, ref, project),
      ),
    );
  }

  Future<void> _showAddProjectDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    String selectedColor = '#2196F3'; // Default blue

    final colors = [
      '#2196F3', // Blue
      '#4CAF50', // Green
      '#FF9800', // Orange
      '#9C27B0', // Purple
      '#F44336', // Red
      '#00BCD4', // Cyan
      '#E91E63', // Pink
      '#795548', // Brown
    ];

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Neues Projekt'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Projektname',
                    hintText: 'z.B. Projekt Alpha',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                const Text('Farbe', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colors.map((colorHex) {
                    final isSelected = selectedColor == colorHex;
                    final color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = colorHex),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      await ref.read(projectsProvider.notifier).createProject(
        name: nameController.text.trim(),
        colorHex: selectedColor,
      );
    }
  }

  Future<void> _showEditProjectDialog(BuildContext context, WidgetRef ref, Project project) async {
    final nameController = TextEditingController(text: project.name);
    String selectedColor = project.colorHex ?? '#2196F3';

    final colors = [
      '#2196F3', // Blue
      '#4CAF50', // Green
      '#FF9800', // Orange
      '#9C27B0', // Purple
      '#F44336', // Red
      '#00BCD4', // Cyan
      '#E91E63', // Pink
      '#795548', // Brown
    ];

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Projekt bearbeiten'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Projektname',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                const Text('Farbe', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colors.map((colorHex) {
                    final isSelected = selectedColor == colorHex;
                    final color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = colorHex),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      await ref.read(projectsProvider.notifier).updateProject(
        project,
        newName: nameController.text.trim(),
        newColorHex: selectedColor,
      );
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context, WidgetRef ref, Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Projekt löschen?'),
        content: Text(
          'Das Projekt "${project.name}" wird unwiderruflich gelöscht. '
          'Bereits zugeordnete Arbeitszeiten behalten ihre Referenz, '
          'aber das Projekt erscheint nicht mehr in der Auswahl.',
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
      await ref.read(projectsProvider.notifier).deleteProject(project);
    }
  }
}
