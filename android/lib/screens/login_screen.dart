import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import '../services/history_service.dart';
import '../services/favorites_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  final HistoryService historyService;
  final FavoritesService favoritesService;
  final SharedPreferences prefs;
  const LoginScreen({
    super.key,
    required this.api,
    required this.layoutPrefs,
    required this.historyService,
    required this.favoritesService,
    required this.prefs,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '7777');
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _scanning = true;
  bool _rememberPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final ip = await widget.api.getSavedIp();
    final port = await widget.api.getSavedPort();
    if (ip != null) _ipCtrl.text = ip;
    if (port != null) _portCtrl.text = port;
    // 加载记住的密码
    final savedUser = widget.prefs.getString('saved_username');
    final savedPass = widget.prefs.getString('saved_password');
    if (savedUser != null && savedPass != null) {
      _userCtrl.text = savedUser;
      _passCtrl.text = savedPass;
      _rememberPassword = true;
    }
    _scanForServer();
  }

  Future<void> _scanForServer() async {
    setState(() { _scanning = true; });
    final foundIp = await widget.api.discoverServer();
    if (foundIp != null && mounted) {
      _ipCtrl.text = foundIp;
    }
    if (mounted) setState(() { _scanning = false; });
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.setServer(_ipCtrl.text, _portCtrl.text);
      final ok = await widget.api.login(_userCtrl.text, _passCtrl.text)
          .timeout(const Duration(seconds: 3), onTimeout: () => throw TimeoutException('login'));
      if (ok) {
        // 保存或清除记住的密码
        if (_rememberPassword) {
          await widget.prefs.setString('saved_username', _userCtrl.text);
          await widget.prefs.setString('saved_password', _passCtrl.text);
        } else {
          await widget.prefs.remove('saved_username');
          await widget.prefs.remove('saved_password');
        }
        // Init services in background, don't block navigation
        widget.historyService.init(widget.prefs, api: widget.api);
        widget.favoritesService.init(widget.prefs, api: widget.api);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              api: widget.api,
              layoutPrefs: widget.layoutPrefs,
              historyService: widget.historyService,
              favoritesService: widget.favoritesService,
              prefs: widget.prefs,
            ),
          ),
        );
        // Sync after navigation (non-blocking)
        try {
          await widget.historyService.syncFromServer();
          await widget.favoritesService.syncFromServer();
        } catch (_) {}
      } else {
        setState(() { _error = '登录失败，请检查 IP、端口和密码'; });
      }
    } on TimeoutException {
      setState(() { _error = '登录超时，请检查服务器是否在线'; });
    } catch (e) {
      setState(() { _error = '登录失败: $e'; });
    }
    if (mounted) setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi File Manager')),
      body: Center(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _ipCtrl,
              decoration: InputDecoration(
                labelText: 'Server IP',
                border: const OutlineInputBorder(),
                suffixIcon: _scanning
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _scanForServer,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _portCtrl, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
            CheckboxListTile(
              value: _rememberPassword,
              onChanged: (v) => setState(() => _rememberPassword = v ?? false),
              title: const Text('记住密码'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading ? const CircularProgressIndicator() : const Text('Login'),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
