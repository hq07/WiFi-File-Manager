import 'package:flutter/foundation.dart';

enum PlaylistRepeatMode { off, all, one }

class PlaylistManager extends ChangeNotifier {
  List<Map<String, dynamic>> _items = [];
  int _currentIndex = 0;
  bool _shuffle = false;
  PlaylistRepeatMode _repeatMode = PlaylistRepeatMode.off;
  List<int> _shuffleOrder = [];

  List<Map<String, dynamic>> get items => _items;
  int get currentIndex => _currentIndex;
  bool get shuffle => _shuffle;
  PlaylistRepeatMode get repeatMode => _repeatMode;

  Map<String, dynamic> get currentItem =>
      _items.isNotEmpty ? _items[_currentIndex] : {};

  bool get hasNext {
    if (_repeatMode == PlaylistRepeatMode.all || _repeatMode == PlaylistRepeatMode.one) return true;
    return _currentIndex < _items.length - 1;
  }

  bool get hasPrevious {
    if (_repeatMode == PlaylistRepeatMode.all) return true;
    return _currentIndex > 0;
  }

  void setItems(List<Map<String, dynamic>> items, {int startIndex = 0}) {
    _items = List.from(items);
    _currentIndex = startIndex.clamp(0, items.length - 1);
    _generateShuffleOrder();
    notifyListeners();
  }

  void _generateShuffleOrder() {
    _shuffleOrder = List.generate(_items.length, (i) => i);
    _shuffleOrder.shuffle();
  }

  void next() {
    if (_items.isEmpty) return;
    if (_repeatMode == PlaylistRepeatMode.one) {
      notifyListeners();
      return;
    }
    if (_shuffle) {
      final idx = _shuffleOrder.indexOf(_currentIndex);
      final nextIdx = (idx + 1) % _shuffleOrder.length;
      _currentIndex = _shuffleOrder[nextIdx];
    } else {
      _currentIndex++;
      if (_currentIndex >= _items.length) {
        if (_repeatMode == PlaylistRepeatMode.all) {
          _currentIndex = 0;
        } else {
          _currentIndex = _items.length - 1;
          notifyListeners();
          return;
        }
      }
    }
    notifyListeners();
  }

  void previous() {
    if (_items.isEmpty) return;
    if (_repeatMode == PlaylistRepeatMode.one) {
      notifyListeners();
      return;
    }
    if (_shuffle) {
      final idx = _shuffleOrder.indexOf(_currentIndex);
      final prevIdx = (idx - 1 + _shuffleOrder.length) % _shuffleOrder.length;
      _currentIndex = _shuffleOrder[prevIdx];
    } else {
      _currentIndex--;
      if (_currentIndex < 0) {
        if (_repeatMode == PlaylistRepeatMode.all) {
          _currentIndex = _items.length - 1;
        } else {
          _currentIndex = 0;
          notifyListeners();
          return;
        }
      }
    }
    notifyListeners();
  }

  void jumpTo(int index) {
    if (index < 0 || index >= _items.length) return;
    _currentIndex = index;
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) _generateShuffleOrder();
    notifyListeners();
  }

  void toggleRepeat() {
    const modes = PlaylistRepeatMode.values;
    _repeatMode = modes[(modes.indexOf(_repeatMode) + 1) % modes.length];
    notifyListeners();
  }
}
