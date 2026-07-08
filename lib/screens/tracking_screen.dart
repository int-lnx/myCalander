import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final projects = appState.projects;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zaman Takibi'),
      ),
      body: projects.isEmpty
          ? const Center(child: Text('Takip edilecek bir proje bulunmamaktadır.'))
          : ListView.builder(
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(project.colorValue),
                  ),
                  title: Text(project.title),
                  subtitle: Text(project.description),
                );
              },
            ),
    );
  }
}
