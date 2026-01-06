import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/geofence_zone.dart';
import '../providers.dart';
import '../widgets/map_picker_widget.dart';
import 'geofence_map_view_screen.dart';

class GeofenceSetupScreen extends ConsumerStatefulWidget {
  const GeofenceSetupScreen({super.key});

  @override
  ConsumerState<GeofenceSetupScreen> createState() => _GeofenceSetupScreenState();
}

class _GeofenceSetupScreenState extends ConsumerState<GeofenceSetupScreen> {
  Position? _currentPosition;
  bool _loadingPosition = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
  }

  Future<void> _loadCurrentPosition() async {
    setState(() => _loadingPosition = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (e) {
      debugPrint('Error getting position: $e');
    }
    if (mounted) {
      setState(() => _loadingPosition = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(geofenceZonesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arbeitsorte'),
        actions: [
          if (_loadingPosition)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.map),
            tooltip: 'Kartenansicht',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GeofenceMapViewScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info Card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Definiere Arbeitsorte, an denen die automatische Zeiterfassung aktiv sein soll.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Zones List
          if (zones.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.location_off, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Keine Arbeitsorte definiert',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tippe auf das + um einen Arbeitsort hinzuzufügen.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          else
            ...zones.map((zone) => _buildZoneCard(zone)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(null),
        icon: const Icon(Icons.add_location),
        label: const Text('Neuer Ort'),
      ),
    );
  }

  Widget _buildZoneCard(GeofenceZone zone) {
    return Card(
      color: zone.isActive ? Colors.green.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: zone.isActive ? Colors.green : Colors.grey,
          child: const Icon(Icons.location_on, color: Colors.white),
        ),
        title: Text(
          zone.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Radius: ${zone.radius.round()}m\n'
          '${zone.latitude.toStringAsFixed(5)}, ${zone.longitude.toStringAsFixed(5)}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (zone.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Aktiv',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            PopupMenuButton<String>(
              onSelected: (action) async {
                switch (action) {
                  case 'edit':
                    _showAddEditDialog(zone);
                    break;
                  case 'toggle':
                    await ref.read(geofenceZonesProvider.notifier).updateZone(
                      zone,
                      newIsActive: !zone.isActive,
                    );
                    break;
                  case 'delete':
                    _confirmDelete(zone);
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
                PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                    leading: Icon(zone.isActive ? Icons.pause : Icons.play_arrow),
                    title: Text(zone.isActive ? 'Deaktivieren' : 'Aktivieren'),
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
          ],
        ),
      ),
    );
  }

  Future<void> _showAddEditDialog(GeofenceZone? zone) async {
    final isEdit = zone != null;
    String name = zone?.name ?? '';
    double latitude = zone?.latitude ?? _currentPosition?.latitude ?? 0;
    double longitude = zone?.longitude ?? _currentPosition?.longitude ?? 0;
    double radius = zone?.radius ?? 150;
    bool isActive = zone?.isActive ?? true;

    final nameController = TextEditingController(text: name);
    final latController = TextEditingController(text: latitude.toString());
    final lngController = TextEditingController(text: longitude.toString());

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Ort bearbeiten' : 'Neuer Arbeitsort'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                const Text('Name', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'z.B. Büro, Homeoffice',
                  ),
                  onChanged: (value) => name = value,
                ),
                const SizedBox(height: 16),

                // Map Picker Button
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<Map<String, double>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapPickerScreen(
                          initialLatitude: latitude != 0 ? latitude : null,
                          initialLongitude: longitude != 0 ? longitude : null,
                          initialRadius: radius,
                        ),
                      ),
                    );
                    if (result != null) {
                      setDialogState(() {
                        latitude = result['lat']!;
                        longitude = result['lng']!;
                        radius = result['radius']!;
                        latController.text = latitude.toString();
                        lngController.text = longitude.toString();
                      });
                    }
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('Auf Karte auswählen'),
                ),
                const SizedBox(height: 8),

                // Current Position Button
                OutlinedButton.icon(
                  onPressed: _currentPosition != null
                      ? () {
                          setDialogState(() {
                            latitude = _currentPosition!.latitude;
                            longitude = _currentPosition!.longitude;
                            latController.text = latitude.toString();
                            lngController.text = longitude.toString();
                          });
                        }
                      : null,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Aktuelle Position verwenden'),
                ),
                const SizedBox(height: 16),

                // Coordinates (collapsible)
                ExpansionTile(
                  title: const Text('Koordinaten manuell eingeben'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Breitengrad',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            onChanged: (value) => latitude = double.tryParse(value) ?? latitude,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: lngController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Längengrad',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            onChanged: (value) => longitude = double.tryParse(value) ?? longitude,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Radius
                const Text('Radius', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: radius,
                        min: 50,
                        max: 500,
                        divisions: 45,
                        label: '${radius.round()}m',
                        onChanged: (value) {
                          setDialogState(() => radius = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${radius.round()}m',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Active Toggle
                Row(
                  children: [
                    const Expanded(
                      child: Text('Aktiv', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Switch(
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() => isActive = value);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: name.isEmpty
                  ? null
                  : () async {
                      final notifier = ref.read(geofenceZonesProvider.notifier);
                      if (isEdit) {
                        await notifier.updateZone(
                          zone,
                          newName: name,
                          newLatitude: latitude,
                          newLongitude: longitude,
                          newRadius: radius,
                          newIsActive: isActive,
                        );
                      } else {
                        await notifier.addZone(GeofenceZone(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          name: name,
                          latitude: latitude,
                          longitude: longitude,
                          radius: radius,
                          isActive: isActive,
                        ));
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
              child: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(GeofenceZone zone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ort löschen?'),
        content: Text('Der Arbeitsort "${zone.name}" wird unwiderruflich gelöscht.'),
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
      await ref.read(geofenceZonesProvider.notifier).deleteZone(zone);
    }
  }
}
