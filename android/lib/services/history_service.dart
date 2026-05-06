// android/lib/services/history_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class HistoryItem {
  final String name;
  final String path;
  final String dirPath;
  final int size;
  final String playedAt;
  final int lastPositionMs;
  final int durationMs;
  final bool completed;

  HistoryItem({
    required this.name,
    required this.path,
    required this.dirPath,
    required this.size,
    required this.playedAt,
    this.lastPositionMs = 0,
    this.durationMs = 0,
    this.completed = false,
  });

  double get progress => durationMs > 0 ? lastPositionMs / durationMs : 0;

  Map<String, dynamic> toJson() => {
    'name': name, 'path': path, 'dirPath': dirPath,
    'size': size, 'playedAt': playedAt,
    'lastPositionMs': lastPositionMs, 'durationMs': durationMs,
    'completed': completed,
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    name: json['name'], path: json['path'], dirPath: json['dirPath'],
    size: json['size'], playedAt: json['playedAt'],
    lastPositionMs: json['lastPositionMs'] as int? ?? 0,
    durationMs: json['durationMs'] as int? ?? 0,
    completed: json['completed'] as bool? ?? false,
  );
}

class HistoryService {
  static const _key = 'play_history';
  static const _maxItems = 30;
  late final SharedPreferences _prefs;
  ApiService? _api;
  Future<void> _writeQueue = Future.value();
  Timer? _syncTimer;

  Future<void> init(SharedPreferences prefs, {ApiService? api}) async {
    _prefs = prefs;
    _api = api;
  }

  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 5), _doSync);
  }

  Future<void> _doSync() async {
    if (_api == null || !_api!.isLoggedIn) return;
    try {
      await _api!.postSyncHistory(getHistory().map((h) => h.toJson()).toList());
    } catch (e) {
      debugPrint('History sync failed: $e');
    }
  }

  Future<void> syncFromServer() async {
    if (_api == null || !_api!.isLoggedIn) return;
    try {
      final serverItems = await _api!.getSyncHistory();
      final serverHistory = serverItems
          .map((e) => HistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final local = getHistory();
      final Map<String, HistoryItem> merged = {for (final h in local) h.path: h};
      for (final s in serverHistory) {
        final existing = merged[s.path];
        if (existing == null || s.playedAt.compareTo(existing.playedAt) > 0) {
          merged[s.path] = s;
        }
      }
      final result = merged.values.toList()
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
      if (result.length > _maxItems) result.removeRange(_maxItems, result.length);
      await _save(result);
      await _api!.postSyncHistory(result.map((h) => h.toJson()).toList());
    } catch (e) {
      debugPrint('History syncFromServer failed: $e');
    }
  }

  /// Chain a write operation onto the queue to prevent concurrent overwrites.
  Future<T> _enqueue<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) => op().then(completer.complete, onError: completer.completeError));
    return completer.future;
  }

  List<HistoryItem> getHistory() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(HistoryItem.fromJson).toList();
  }

  Future<void> addEntry({
    required String name,
    required String path,
    required String dirPath,
    required int size,
    int lastPositionMs = 0,
    int durationMs = 0,
    bool completed = false,
  }) {
    return _enqueue(() async {
      final history = getHistory();
      history.removeWhere((h) => h.path == path);
      history.insert(0, HistoryItem(
        name: name, path: path, dirPath: dirPath,
        size: size, playedAt: DateTime.now().toIso8601String(),
        lastPositionMs: lastPositionMs, durationMs: durationMs,
        completed: completed,
      ));
      if (history.length > _maxItems) history.removeRange(_maxItems, history.length);
      await _save(history);
      _scheduleSync();
    });
  }

  Future<void> updatePosition(String path, int positionMs, int durationMs) {
    return _enqueue(() async {
      final history = getHistory();
      final idx = history.indexWhere((h) => h.path == path);
      if (idx < 0) return;
      final old = history[idx];
      history[idx] = HistoryItem(
        name: old.name, path: old.path, dirPath: old.dirPath,
        size: old.size, playedAt: old.playedAt,
        lastPositionMs: positionMs, durationMs: durationMs,
        completed: positionMs >= durationMs && durationMs > 0,
      );
      await _prefs.setString(_key, jsonEncode(history.map((h) => h.toJson()).toList()));
      _scheduleSync();
    });
  }

  Future<void> markCompleted(String path) {
    return _enqueue(() async {
      final history = getHistory();
      final idx = history.indexWhere((h) => h.path == path);
      if (idx < 0) return;
      final old = history[idx];
      history[idx] = HistoryItem(
        name: old.name, path: old.path, dirPath: old.dirPath,
        size: old.size, playedAt: old.playedAt,
        lastPositionMs: old.durationMs, durationMs: old.durationMs,
        completed: true,
      );
      await _prefs.setString(_key, jsonEncode(history.map((h) => h.toJson()).toList()));
      _scheduleSync();
    });
  }

  HistoryItem? getEntry(String path) {
    final history = getHistory();
    final idx = history.indexWhere((h) => h.path == path);
    return idx >= 0 ? history[idx] : null;
  }

  int getLastPosition(String path) {
    final history = getHistory();
    final item = history.firstWhere((h) => h.path == path, orElse: () => HistoryItem(
      name: '', path: '', dirPath: '', size: 0, playedAt: '',
    ));
    if (item.completed || item.path.isEmpty) return 0;
    return item.lastPositionMs;
  }

  Future<void> clearHistory() {
    return _enqueue(() async {
      await _prefs.remove(_key);
      _scheduleSync();
    });
  }

  /// Wait for all pending writes to complete.
  Future<void> flush() => _writeQueue;

  Future<void> _save(List<HistoryItem> history) async {
    await _prefs.setString(_key, jsonEncode(history.map((h) => h.toJson()).toList()));
  }
}
