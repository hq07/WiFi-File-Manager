// android/lib/services/favorites_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class FavoriteItem {
  final String name;
  final String path;
  final String type; // 'file' or 'folder'
  final int size;

  FavoriteItem({
    required this.name,
    required this.path,
    required this.type,
    this.size = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'path': path, 'type': type, 'size': size,
  };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
    name: json['name'], path: json['path'], type: json['type'],
    size: json['size'] as int? ?? 0,
  );
}

class FavoritesService {
  static const _key = 'favorites';
  late SharedPreferences _prefs;
  ApiService? _api;
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
    if (_api == null || !_api!.isLoggedIn) {
      debugPrint('[FavSync] SKIP: api=${_api != null} loggedIn=${_api?.isLoggedIn}');
      return;
    }
    try {
      final data = getFavorites().map((f) => f.toJson()).toList();
      debugPrint('[FavSync] POST ${data.length} items');
      await _api!.postSyncFavorites(data);
      debugPrint('[FavSync] POST OK');
    } catch (e) {
      debugPrint('[FavSync] POST FAILED: $e');
    }
  }

  Future<void> syncFromServer() async {
    if (_api == null || !_api!.isLoggedIn) return;
    try {
      final serverItems = await _api!.getSyncFavorites();
      final serverFavorites = serverItems
          .map((e) => FavoriteItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final local = getFavorites();
      final Map<String, FavoriteItem> merged = {for (final f in local) f.path: f};
      for (final s in serverFavorites) {
        merged.putIfAbsent(s.path, () => s);
      }
      final result = merged.values.toList();
      await _prefs.setString(_key, jsonEncode(result.map((f) => f.toJson()).toList()));
      await _api!.postSyncFavorites(result.map((f) => f.toJson()).toList());
    } catch (e) {
      debugPrint('Favorites syncFromServer failed: $e');
    }
  }

  List<FavoriteItem> getFavorites() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(FavoriteItem.fromJson).toList();
  }

  bool isFavorite(String path) {
    return getFavorites().any((f) => f.path == path);
  }

  void toggle(FavoriteItem item) {
    final list = getFavorites();
    final idx = list.indexWhere((f) => f.path == item.path);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.insert(0, item);
    }
    _prefs.setString(_key, jsonEncode(list.map((f) => f.toJson()).toList()));
    _doSync();
    _scheduleSync();
  }

  void removeByPath(String path) {
    final list = getFavorites();
    list.removeWhere((f) => f.path == path);
    _prefs.setString(_key, jsonEncode(list.map((f) => f.toJson()).toList()));
    _doSync();
    _scheduleSync();
  }
}
