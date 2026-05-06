import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_service.dart';
import 'services/layout_prefs.dart';
import 'services/history_service.dart';
import 'services/favorites_service.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final layoutPrefs = LayoutPrefs();
  await layoutPrefs.init();
  final prefs = await SharedPreferences.getInstance();
  final historyService = HistoryService();
  await historyService.init(prefs);
  final favoritesService = FavoritesService();
  await favoritesService.init(prefs);
  runApp(MyApp(
    layoutPrefs: layoutPrefs,
    historyService: historyService,
    favoritesService: favoritesService,
    prefs: prefs,
  ));
}

class MyApp extends StatefulWidget {
  final LayoutPrefs layoutPrefs;
  final HistoryService historyService;
  final FavoritesService favoritesService;
  final SharedPreferences prefs;
  const MyApp({
    super.key,
    required this.layoutPrefs,
    required this.historyService,
    required this.favoritesService,
    required this.prefs,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ApiService _api = ApiService();

  @override
  Widget build(BuildContext context) {
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
      home: LoginScreen(
        api: _api,
        layoutPrefs: widget.layoutPrefs,
        historyService: widget.historyService,
        favoritesService: widget.favoritesService,
        prefs: widget.prefs,
      ),
    );
  }
}
