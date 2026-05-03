import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/layout_prefs.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final layoutPrefs = LayoutPrefs();
  await layoutPrefs.init();
  runApp(MyApp(layoutPrefs: layoutPrefs));
}

class MyApp extends StatelessWidget {
  final LayoutPrefs layoutPrefs;
  const MyApp({super.key, required this.layoutPrefs});

  @override
  Widget build(BuildContext context) {
    final api = ApiService();
    return MaterialApp(
      title: 'WiFi File Manager',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: LoginScreen(api: api, layoutPrefs: layoutPrefs),
    );
  }
}
