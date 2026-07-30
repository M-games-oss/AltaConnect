import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const RemoteDesktopApp());
}

/// Root widget. Sets up a dark, glass-friendly theme (translucent
/// panels read best against a dark, slightly gradient background)
/// and launches straight into [HomeScreen].
class RemoteDesktopApp extends StatelessWidget {
  const RemoteDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remote Desktop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: '.SF Pro Text',
      ),
      home: const HomeScreen(),
    );
  }
}
