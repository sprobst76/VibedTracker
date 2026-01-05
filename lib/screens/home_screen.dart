import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../providers.dart';
import '../services/geofence_service.dart';
import 'settings_screen.dart';
import 'vacation_screen.dart';
import 'report_screen.dart';
import '../models/work_entry.dart';
import 'package:hive/hive.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeState();
}

class _HomeState extends ConsumerState<HomeScreen> {
  final geo = MyGeofenceService();

  Future<void> _initializeGeofence() async {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    await geo.init(lat: pos.latitude, lng: pos.longitude);
  }

  @override
  void initState() {
    super.initState();
    _initializeGeofence();  
  } 


  @override
  Widget build(BuildContext ctx) {
    final entries = ref.watch(workListProvider);
    final last = entries.isEmpty ? null : entries.last;
    final running = last != null && last.stop == null;

    return Scaffold(
      appBar: AppBar(title: const Text('TimeTracker'), actions: [
        IconButton(icon: const Icon(Icons.calendar_today),
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const VacationScreen()))),
        IconButton(icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ReportScreen()))),
        IconButton(icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      ]),
      body: Center(
        child: ElevatedButton(
          child: Text(running ? 'Stop' : 'Start'),
          onPressed: () {
            final now = DateTime.now();
            final box = Hive.box<WorkEntry>('work');
            if (running) {
              last.stop = now;
              last.save();
            } else {
              box.add(WorkEntry(start: now));
            }
            setState(() {});
          },
        ),
      ),
    );
  }
}
