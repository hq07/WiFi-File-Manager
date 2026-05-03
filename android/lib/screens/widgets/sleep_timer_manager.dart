import 'dart:async';
import 'package:flutter/foundation.dart';

class SleepTimerManager extends ChangeNotifier {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _isActive = false;

  bool get isActive => _isActive;
  Duration get remaining => _remaining;

  String get remainingFormatted {
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void start(Duration duration, VoidCallback onExpired) {
    cancel();
    _remaining = duration;
    _isActive = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remaining -= const Duration(seconds: 1);
      if (_remaining <= Duration.zero) {
        _isActive = false;
        _timer?.cancel();
        _timer = null;
        _remaining = Duration.zero;
        notifyListeners();
        onExpired();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isActive = false;
    _remaining = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
