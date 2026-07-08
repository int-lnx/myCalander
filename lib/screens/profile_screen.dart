import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.firebaseUser;
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilim'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (user != null) ...[
              CircleAvatar(
                radius: 40,
                backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                child: user.photoURL == null ? const Icon(Icons.person, size: 40) : null,
              ),
              const SizedBox(height: 16),
              Text(user.displayName ?? 'Kullanıcı', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(user.email ?? '', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Çıkış Yap'),
                onPressed: () async {
                  await authService.signOut();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ] else ...[
              const Center(
                child: Text('Giriş yapılmış bir kullanıcı bulunamadı.'),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
