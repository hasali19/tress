import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/find_locale.dart';

import 'client.dart';
import 'router.dart';

const _pushChannel = MethodChannel('tress.hasali.dev/push');

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final [_, __, configRes] = await Future.wait([
    findSystemLocale(),
    initializeDateFormatting(),
    dio.get('$baseUrl/api/config'),
  ]);
  final config = configRes.data;

  await _pushChannel.invokeMethod('register', {
    'vapid_key': config['vapid']['public_key'],
  });

  final userId = await prefs.getUserId();
  if (userId != null) {
    dio.options.headers['Authorization'] = userId;
  }

  runApp(MyApp(initiallyLoggedIn: userId != null));
}

@pragma('vm:entry-point')
void pushEntrypoint() {
  WidgetsFlutterBinding.ensureInitialized();

  String? url;

  _pushChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onNewEndpoint':
        final newUrl = call.arguments['url'];
        if (newUrl != url) {
          url = newUrl;
          await _registerPushEndpoint(
            newUrl,
            call.arguments['keys']['auth'],
            call.arguments['keys']['pub'],
          );
        }
        break;
      case 'onMessage':
        _handlePushMessage(call.arguments['content'], '');
        break;
    }
  });
}

Future<void> _registerPushEndpoint(
  String url,
  String? auth,
  String? pubKey,
) async {
  final userId = await prefs.getUserId();
  if (userId == null) return;

  await dio.post(
    '$baseUrl/api/push_subscriptions',
    data: {
      'subscription': {
        'endpoint': url,
        'keys': {'auth': auth, 'p256dh': pubKey},
      },
    },
    options: Options(headers: {'Authorization': userId}),
  );
}

Future<void> _handlePushMessage(
  Uint8List messageContent,
  String instance,
) async {
  const notificationsChannel = MethodChannel('tress.hasali.dev/notifications');

  final messageData = jsonDecode(utf8.decode(messageContent));

  final post = await dio
      .get('$baseUrl/api/posts/${messageData['id']}')
      .then((res) => res.data);

  final feed = await dio
      .get('$baseUrl/api/feeds/${post['feed_id']}')
      .then((res) => res.data);

  final String id = post['id'];

  await notificationsChannel.invokeMethod('post', {
    'id': id.hashCode,
    'title': messageData['title'],
    'subtext': feed['title'],
    'content': post['description'],
    'url': post['url'],
  });
}

class MyApp extends StatefulWidget {
  final bool initiallyLoggedIn;

  const MyApp({super.key, required this.initiallyLoggedIn});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _router = AppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tress',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      routerConfig: _router.config(
        initialRoutes: [
          if (widget.initiallyLoggedIn) const PostsRoute() else const LoginRoute(),
        ],
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      cardTheme: CardThemeData(clipBehavior: Clip.antiAlias),
    );
  }
}
