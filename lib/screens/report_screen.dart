import 'package:flutter/material.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Berichte')),
      body: const Center(child: Text('Soll-Ist-Auswertung pro Woche hier')),
    );
  }
}
