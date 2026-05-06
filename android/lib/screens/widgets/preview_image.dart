import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Network image with disk-backed thumbnail cache and HTTP 202 retry.
/// Thumbnails survive app restarts. Falls back to [fallback] on error.
class PreviewImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Widget fallback;
  final Map<String, String>? headers;
  final int maxRetries;
  final Duration retryDelay;
  const PreviewImage({
    super.key,
    required this.url,
    required this.fallback,
    this.headers,
    this.fit = BoxFit.cover,
    this.maxRetries = 8,
    this.retryDelay = const Duration(seconds: 3),
  });

  // Shared in-memory LRU cache across all instances
  static final Map<String, Uint8List> _memCache = {};
  static const int _maxMemEntries = 200;

  static void clearMemCache() => _memCache.clear();

  static void addToMemCache(String url, Uint8List data) {
    if (_memCache.length >= _maxMemEntries) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[url] = data;
  }

  @override
  State<PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends State<PreviewImage> {
  static Future<Directory>? _cacheDirFuture;
  static Directory? _cacheDir;

  Uint8List? _bytes;
  bool _loading = true;
  int _retries = 0;
  Timer? _timer;
  final _dio = Dio();

  static Future<Directory> _getCacheDir() {
    _cacheDirFuture ??= () async {
      final dir = await getTemporaryDirectory();
      _cacheDir = Directory('${dir.path}/preview_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      return _cacheDir!;
    }();
    return _cacheDirFuture!;
  }

  /// Simple deterministic filename from URL
  String _cacheKey(String url) {
    // Use hashCode as hex — fast and sufficient for cache keys
    return 'thumb_${url.hashCode.toRadixString(16)}.jpg';
  }

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    // 1. Check memory cache first
    final mem = PreviewImage._memCache[widget.url];
    if (mem != null) {
      if (mounted) setState(() { _bytes = mem; _loading = false; });
      return;
    }

    // 2. Check disk cache
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_cacheKey(widget.url)}');
      if (await file.exists()) {
        final data = await file.readAsBytes();
        PreviewImage.addToMemCache(widget.url, data);
        if (mounted) setState(() { _bytes = data; _loading = false; });
        return;
      }
    } catch (_) {}

    // 3. Fetch from network
    _fetch();
  }


  @override
  void dispose() {
    _timer?.cancel();
    _dio.close();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final resp = await _dio.get<List<int>>(widget.url,
          options: Options(responseType: ResponseType.bytes, headers: widget.headers));
      if (!mounted) return;
      if (resp.statusCode == 200 && resp.data != null) {
        final data = Uint8List.fromList(resp.data!);
        PreviewImage.addToMemCache(widget.url, data);
        _saveToDisk(widget.url, data);
        setState(() { _bytes = data; _loading = false; });
      } else {
        setState(() { _loading = false; });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 202 && _retries < widget.maxRetries) {
        _retries++;
        _timer = Timer(widget.retryDelay, _fetch);
      } else {
        setState(() { _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _saveToDisk(String url, Uint8List data) async {
    try {
      final dir = await _getCacheDir();
      final file = File('${dir.path}/${_cacheKey(url)}');
      await file.writeAsBytes(data, flush: true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: 56, height: 56,
        child: Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => widget.fallback,
      );
    }
    return widget.fallback;
  }
}
