import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  const LoginScreen({super.key, required this.api, required this.layoutPrefs});

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
    await widget.api.setServer(_ipCtrl.text, _portCtrl.text);
    final ok = await widget.api.login(_userCtrl.text, _passCtrl.text);
    if (ok) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(api: widget.api, layoutPrefs: widget.layoutPrefs)),
      );
    } else {
      setState(() { _error = 'Login failed. Check IP, port, and password.'; });
    }
    setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi File Manager')),
      body: Padding(
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
            const SizedBox(height: 20),
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
    );
  }
}
