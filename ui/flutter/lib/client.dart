import 'package:dio/dio.dart';

import 'preferences_repo.dart';

const baseUrl = 'https://tress.hasali.uk';
const _authHeader = 'Authorization';

final dio = Dio();
final prefs = PreferencesRepo();

Future<void> applyAuth(String userId) async {
  await prefs.setUserId(userId);
  dio.options.headers[_authHeader] = userId;
}

Future<void> clearAuth() async {
  await prefs.clearUserId();
  dio.options.headers.remove(_authHeader);
}
