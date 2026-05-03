// android/lib/services/api_service.dart
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

  Options get _authOptions =>
      Options(headers: {'Authorization': 'Bearer $_token'});

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

  String getPreviewUrl(String path) {
    return '$_baseUrl/api/files/preview?path=${Uri.encodeComponent(path)}&token=$_token';
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
}
