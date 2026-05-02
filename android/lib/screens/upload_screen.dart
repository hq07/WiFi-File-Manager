// android/lib/screens/upload_screen.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class UploadScreen extends StatefulWidget {
  final ApiService api;
  const UploadScreen({super.key, required this.api});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  List<dynamic> _shares = [];
  String? _selectedSharePath;
  String? _selectedFilePath;
  String? _selectedFileName;
  double _progress = 0;
  bool _uploading = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  Future<void> _loadShares() async {
    final shares = await widget.api.getShares();
    setState(() { _shares = shares; });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _selectedFileName = result.files.single.name;
      });
    }
  }

  Future<void> _upload() async {
    if (_selectedFilePath == null || _selectedSharePath == null) return;
    setState(() { _uploading = true; _progress = 0; _result = null; });
    try {
      await widget.api.uploadFile(
        _selectedSharePath!,
        _selectedFilePath!,
        (sent, total) {
          if (total > 0) setState(() { _progress = sent / total; });
        },
      );
      setState(() { _result = 'Upload successful!'; });
    } catch (e) {
      setState(() { _result = 'Upload failed: $e'; });
    }
    setState(() { _uploading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload File')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              icon: const Icon(Icons.file_open),
              label: Text(_selectedFileName ?? 'Pick a file'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Target directory', border: OutlineInputBorder()),
              initialValue: _selectedSharePath,
              items: _shares.map<DropdownMenuItem<String>>((s) {
                return DropdownMenuItem(value: s['path'] as String, child: Text(s['name'] ?? s['path']));
              }).toList(),
              onChanged: _uploading ? null : (v) { setState(() { _selectedSharePath = v; }); },
            ),
            const SizedBox(height: 24),
            if (_uploading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)}%'),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              Text(_result!, style: TextStyle(color: _result!.contains('successful') ? Colors.green : Colors.red)),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: (_selectedFilePath != null && _selectedSharePath != null && !_uploading) ? _upload : null,
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }
}
