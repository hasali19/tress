import 'package:dio/dio.dart';

import 'preferences_repo.dart';

class ApiClient {
  static const _baseUrl = 'https://tress.hasali.uk';
  static const _authHeader = 'Authorization';

  final _dio = Dio();
  final _prefs = PreferencesRepo();

  /// Reads the saved user ID from prefs, applies it to the auth header, and
  /// returns it. Returns null if no user is saved.
  Future<String?> restoreAuth() async {
    final userId = await _prefs.getUserId();
    if (userId != null) {
      _dio.options.headers[_authHeader] = userId;
    }
    return userId;
  }

  Future<void> applyAuth(String userId) async {
    await _prefs.setUserId(userId);
    _dio.options.headers[_authHeader] = userId;
  }

  Future<void> clearAuth() async {
    await _prefs.clearUserId();
    _dio.options.headers.remove(_authHeader);
  }

  Future<Map<String, dynamic>> getConfig() async {
    final res = await _dio.get('$_baseUrl/api/config');
    return res.data;
  }

  Future<String> login(String username) async {
    final res = await _dio.post(
      '$_baseUrl/api/login',
      data: {'username': username},
    );
    return res.data['id'] as String;
  }

  Future<List<dynamic>> getFeeds() async {
    final res = await _dio.get('$_baseUrl/api/feeds');
    return res.data;
  }

  Future<List<dynamic>> getPosts() async {
    final res = await _dio.get('$_baseUrl/api/posts');
    return res.data;
  }

  Future<void> addFeed(String url) async {
    await _dio.post('$_baseUrl/api/feeds', data: {'url': url});
  }

  Future<Map<String, dynamic>> getPost(String id) async {
    final res = await _dio.get('$_baseUrl/api/posts/$id');
    return res.data;
  }

  Future<Map<String, dynamic>> getFeed(String id) async {
    final res = await _dio.get('$_baseUrl/api/feeds/$id');
    return res.data;
  }

  Future<void> registerPushSubscription({
    required String url,
    required String? auth,
    required String? pubKey,
  }) async {
    final userId = await _prefs.getUserId();
    if (userId == null) return;

    await _dio.post(
      '$_baseUrl/api/push_subscriptions',
      data: {
        'subscription': {
          'endpoint': url,
          'keys': {'auth': auth, 'p256dh': pubKey},
        },
      },
      options: Options(headers: {_authHeader: userId}),
    );
  }
}
