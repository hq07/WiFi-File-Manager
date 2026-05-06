import 'dart:async';
import 'package:just_audio/just_audio.dart';

AudioPlayer? _globalPlayer;
bool _initialized = false;

AudioPlayer ensureAudioPlayer() {
  if (!_initialized) {
    _globalPlayer = AudioPlayer();
    _initialized = true;
  }
  return _globalPlayer!;
}
