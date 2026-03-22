import 'package:dio/dio.dart';

import 'auth_service.dart';
import 'models.dart';

class ApiClient {
  static const _baseUrl = 'https://tress.hasali.uk/api';

  final Dio _dio = Dio();

  ApiClient({AuthService? authService}) {
    if (authService != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final token = authService.idToken;
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            handler.next(options);
          },
        ),
      );
    }
  }

  Future<Map<String, dynamic>> getConfig() async {
    final res = await _dio.get('$_baseUrl/config');
    return res.data;
  }

  Future<List<Feed>> getFeeds() async {
    final res = await _dio.get('$_baseUrl/feeds');
    return (res.data as List<dynamic>).map((e) => Feed.fromJson(e)).toList();
  }

  Future<Feed> getFeed(String id) async {
    final res = await _dio.get('$_baseUrl/feeds/$id');
    return Feed.fromJson(res.data);
  }

  Future<List<Post>> getPosts() async {
    final res = await _dio.get('$_baseUrl/posts');
    return (res.data as List<dynamic>).map((e) => Post.fromJson(e)).toList();
  }

  Future<Post> getPost(String id) async {
    final res = await _dio.get('$_baseUrl/posts/$id');
    return Post.fromJson(res.data);
  }

  Future<void> addFeed(String url) async {
    await _dio.post('$_baseUrl/feeds', data: {'url': url});
  }

  Future<void> registerPushSubscription(
    String endpoint,
    String? auth,
    String? pubKey,
  ) async {
    await _dio.post(
      '$_baseUrl/push_subscriptions',
      data: {
        'subscription': {
          'endpoint': endpoint,
          'keys': {'auth': auth, 'p256dh': pubKey},
        },
      },
    );
  }
}
