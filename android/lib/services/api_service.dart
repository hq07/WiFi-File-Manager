// android/lib/services/api_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _baseUrl;
  String? _token;

  Future<void> setServer(String ip, String port) async {
    _baseUrl = 'http://$ip:$port';
    await _storage.write(key: 'server_ip', value: ip);
    await _storage.write(key: 'server_port', value: port);
  }

  Future<String?> getSavedIp() => _storage.read(key: 'server_ip');
  Future<String?> getSavedPort() => _storage.read(key: 'server_port');

  Future<bool> login(String username, String password) async {
    try {
      print('LOGIN: POST $_baseUrl/api/login');
      final resp = await _dio.post('$_baseUrl/api/login',
          data: {'username': username, 'password': password});
      print('LOGIN: status=${resp.statusCode} data=${resp.data}');
      _token = resp.data['token'];
      await _storage.write(key: 'token', value: _token);
      return true;
    } on DioException catch (e) {
      print('LOGIN ERROR: ${e.type} ${e.message} ${e.response?.statusCode}');
      return false;
    } catch (e) {
      print('LOGIN UNKNOWN ERROR: $e');
      return false;
    }
  }

  Future<void> loadToken() async {
    _token = await _storage.read(key: 'token');
  }

  void clearToken() {
    _token = null;
    _storage.delete(key: 'token');
  }

  bool get isLoggedIn => _token != null;

  Future<String?> discoverServer() async {
    final port = await getSavedPort() ?? '7777';
    final portNum = int.parse(port);

    // Try UDP broadcast discovery
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // Send to each interface's /24 broadcast address (covers most LANs)
      var sent = false;
      try {
        for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
          for (final addr in iface.addresses) {
            if (addr.address == '127.0.0.1') continue;
            final ip = addr.rawAddress;
            final bcast = InternetAddress.fromRawAddress(Uint8List.fromList([ip[0], ip[1], ip[2], 255]));
            socket.send('WFM_DISCOVER'.codeUnits, bcast, portNum);
            sent = true;
          }
        }
      } catch (_) {}

      // Fallback to global broadcast
      if (!sent) {
        socket.send('WFM_DISCOVER'.codeUnits, InternetAddress('255.255.255.255'), portNum);
      }

      final completer = Completer<Datagram?>();
      final sub = socket.listen((event) {
        if (event == RawSocketEvent.read && !completer.isCompleted) {
          completer.complete(socket.receive());
        }
      });

      final dg = await Future.any([
        completer.future,
        Future<Datagram?>.delayed(const Duration(seconds: 3)),
      ]);
      await sub.cancel();
      socket.close();

      if (dg != null) {
        final msg = String.fromCharCodes(dg.data);
        if (msg.startsWith('WFM_HERE|')) {
          final parts = msg.split('|');
          if (parts.length >= 2) return parts[1];
        }
      }
    } catch (_) {}

    // Fall back: try the saved IP via HTTP
    final savedIp = await getSavedIp();
    if (savedIp == null) return null;
    try {
      final resp = await Dio().get('http://$savedIp:$port/api/discover',
          options: Options(receiveTimeout: const Duration(seconds: 3)));
      return resp.data['ip'] ?? savedIp;
    } catch (_) {}
    return null;
  }

  Options get _authOptions =>
      Options(headers: {'Authorization': 'Bearer $_token'});

  Map<String, String> get previewHeaders =>
      {'Authorization': 'Bearer $_token'};

  Future<List<dynamic>> getShares() async {
    final resp =
        await _dio.get('$_baseUrl/api/shares', options: _authOptions);
    return resp.data;
  }

  Future<Map<String, dynamic>> addShare(String path) async {
    final resp = await _dio.post('$_baseUrl/api/shares',
        data: {'path': path}, options: _authOptions);
    return resp.data;
  }

  Future<void> removeShare(String id) async {
    await _dio.delete('$_baseUrl/api/shares/$id', options: _authOptions);
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    final resp = await _dio.get('$_baseUrl/api/files',
        queryParameters: {'path': path}, options: _authOptions);
    return resp.data;
  }

  Future<void> downloadFile(String path, String savePath,
      void Function(int, int)? onProgress) async {
    await _dio.download('$_baseUrl/api/files/download', savePath,
        queryParameters: {'path': path},
        options: _authOptions,
        onReceiveProgress: onProgress);
  }

  Future<Map<String, dynamic>> uploadFile(
      String targetPath, String filePath, String relativePath,
      void Function(int, int)? onProgress) async {
    final parts = relativePath.split('/');
    final filename = parts.last;
    final subdir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    final resp = await _dio.post('$_baseUrl/api/files/upload',
        data: formData,
        queryParameters: {'path': targetPath, 'subdir': subdir},
        options: _authOptions,
        onSendProgress: onProgress);
    return resp.data;
  }

  String getPreviewUrl(String path, {bool thumbnail = false}) {
    final thumbParam = thumbnail ? '&thumbnail=true' : '';
    return '$_baseUrl/api/files/preview?path=${Uri.encodeComponent(path)}&token=$_token$thumbParam';
  }

  Future<List<dynamic>> getDisks() async {
    final resp =
        await _dio.get('$_baseUrl/api/disks', options: _authOptions);
    return resp.data;
  }

  Future<Map<String, dynamic>> getUploadsDir() async {
    final resp =
        await _dio.get('$_baseUrl/api/uploads-dir', options: _authOptions);
    return resp.data;
  }

  Future<void> deleteFile(String path) async {
    await _dio.delete('$_baseUrl/api/files/delete',
        queryParameters: {'path': path}, options: _authOptions);
  }

  Future<void> renameFile(String path, String newName) async {
    await _dio.post('$_baseUrl/api/files/rename',
        queryParameters: {'path': path, 'new_name': newName},
        options: _authOptions);
  }

  Future<void> createSubdir(String parentPath, String dirName) async {
    await _dio.post('$_baseUrl/api/files/mkdir',
        queryParameters: {'path': parentPath, 'name': dirName},
        options: _authOptions);
  }

  Future<void> toggleShareVisible(String id, bool visible) async {
    await _dio.patch('$_baseUrl/api/shares/$id',
        data: {'visible': visible}, options: _authOptions);
  }

  Future<List<dynamic>> getCommonPaths() async {
    final resp =
        await _dio.get('$_baseUrl/api/common-paths', options: _authOptions);
    return resp.data;
  }

  Future<Map<String, dynamic>> browsePath(String path) async {
    final resp = await _dio.get('$_baseUrl/api/browse',
        queryParameters: {'path': path}, options: _authOptions);
    return resp.data;
  }

  Future<Map<String, dynamic>?> getFileMetadata(String filePath) async {
    final dir = filePath.substring(0, filePath.lastIndexOf('/'));
    final name = filePath.substring(filePath.lastIndexOf('/') + 1);
    try {
      final resp = await _dio.get('$_baseUrl/api/files/metadata',
          queryParameters: {'path': dir, 'filename': name},
          options: _authOptions);
      return resp.data as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> searchFiles(String query) async {
    final resp = await _dio.get('$_baseUrl/api/files/search',
        queryParameters: {'q': query}, options: _authOptions);
    return resp.data;
  }

  Future<List<dynamic>> getSyncHistory() async {
    final resp =
        await _dio.get('$_baseUrl/api/sync/history', options: _authOptions);
    return resp.data as List<dynamic>;
  }

  Future<void> postSyncHistory(List<dynamic> items) async {
    await _dio.post('$_baseUrl/api/sync/history',
        data: items, options: _authOptions);
  }

  Future<List<dynamic>> getSyncFavorites() async {
    final resp =
        await _dio.get('$_baseUrl/api/sync/favorites', options: _authOptions);
    return resp.data as List<dynamic>;
  }

  Future<void> postSyncFavorites(List<dynamic> items) async {
    await _dio.post('$_baseUrl/api/sync/favorites',
        data: items, options: _authOptions);
  }

  Future<List<dynamic>> getTrash({String path = ''}) async {
    final resp = await _dio.get('$_baseUrl/api/trash',
        queryParameters: {'path': path}, options: _authOptions);
    return resp.data as List<dynamic>;
  }

  Future<void> restoreTrash(String subPath) async {
    await _dio.post('$_baseUrl/api/trash/restore',
        queryParameters: {'path': subPath}, options: _authOptions);
  }

  Future<void> emptyTrash() async {
    await _dio.post('$_baseUrl/api/trash/empty', options: _authOptions);
  }

  Future<Map<String, dynamic>> getCacheInfo() async {
    final resp =
        await _dio.get('$_baseUrl/api/cache/info', options: _authOptions);
    return resp.data;
  }

  Future<void> clearServerCache() async {
    await _dio.post('$_baseUrl/api/cache/clear', options: _authOptions);
  }
}
