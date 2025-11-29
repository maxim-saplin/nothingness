import 'package:flutter/material.dart';

import 'screens/media_controller_page.dart';

void main() {
  runApp(const NothingApp());
}

class NothingApp extends StatelessWidget {
  const NothingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nothingness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF88),
          secondary: Color(0xFFFF6B35),
          surface: Color(0xFF12121A),
        ),
      ),
      home: const MediaControllerPage(),
    );
  }
}
