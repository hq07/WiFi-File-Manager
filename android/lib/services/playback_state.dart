import 'package:flutter/foundation.dart';

class PlaybackStateNotifier extends ChangeNotifier {
  String? _filePath;
  String? _fileName;
  int? _fileSize;
  List<Map<String, dynamic>> _directoryFiles = [];
  bool _isPlaying = false;
  bool _wasPlayingBeforePause = false;

  String? get filePath => _filePath;
  String? get fileName => _fileName;
  int? get fileSize => _fileSize;
  List<Map<String, dynamic>> get directoryFiles => _directoryFiles;
  bool get isPlaying => _isPlaying;
  bool get isActive => _filePath != null;
  bool get wasPlayingBeforePause => _wasPlayingBeforePause;

  void updatePlaying({
    required String filePath,
    required String fileName,
    int? fileSize,
    required List<Map<String, dynamic>> directoryFiles,
    required bool isPlaying,
  }) {
    _filePath = filePath;
    _fileName = fileName;
    _fileSize = fileSize;
    _directoryFiles = directoryFiles;
    _isPlaying = isPlaying;
    _wasPlayingBeforePause = isPlaying;
    notifyListeners();
  }

  void setPlaying(bool playing) {
    if (playing) _wasPlayingBeforePause = true;
    _isPlaying = playing;
    notifyListeners();
  }

  void clear() {
    _filePath = null;
    _fileName = null;
    _fileSize = null;
    _directoryFiles = [];
    _isPlaying = false;
    _wasPlayingBeforePause = false;
    notifyListeners();
  }
}

final playbackStateNotifier = PlaybackStateNotifier();
