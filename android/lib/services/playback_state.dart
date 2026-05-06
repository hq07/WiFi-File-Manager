import 'package:flutter/foundation.dart';

class PlaybackStateNotifier extends ChangeNotifier {
  String? _filePath;
  String? _fileName;
  int? _fileSize;
  List<Map<String, dynamic>> _directoryFiles = [];
  bool _isPlaying = false;
  bool _wasPlayingBeforePause = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  String? get filePath => _filePath;
  String? get fileName => _fileName;
  int? get fileSize => _fileSize;
  List<Map<String, dynamic>> get directoryFiles => _directoryFiles;
  bool get isPlaying => _isPlaying;
  bool get isActive => _filePath != null;
  bool get wasPlayingBeforePause => _wasPlayingBeforePause;
  Duration get position => _position;
  Duration get duration => _duration;

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

  void setPosition(Duration pos) {
    _position = pos;
    notifyListeners();
  }

  void setDuration(Duration dur) {
    _duration = dur;
    notifyListeners();
  }

  void clear() {
    _filePath = null;
    _fileName = null;
    _fileSize = null;
    _directoryFiles = [];
    _isPlaying = false;
    _wasPlayingBeforePause = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
  }
}

final playbackStateNotifier = PlaybackStateNotifier();
