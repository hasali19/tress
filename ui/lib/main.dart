import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/find_locale.dart';

import 'router.dart';

final _dio = Dio();

const _pushChannel = MethodChannel('tress.hasali.dev/push');

final _appRouter = AppRouter();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await findSystemLocale();
  await initializeDateFormatting();

  final configRes = await _dio.get('https://tress.hasali.uk/api/config');
  final config = configRes.data;

  await _pushChannel.invokeMethod('register', {
    'vapid_key': config['vapid']['public_key'],
  });

  runApp(const MyApp());
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
          _registerPushEndpoint(
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
  await _dio.post(
    'https://tress.hasali.uk/api/push_subscriptions',
    data: {
      'subscription': {
        'endpoint': url,
        'keys': {'auth': auth, 'p256dh': pubKey},
      },
    },
  );
}

Future<void> _handlePushMessage(
  Uint8List messageContent,
  String instance,
) async {
  const notificationsChannel = MethodChannel('tress.hasali.dev/notifications');

  final messageData = jsonDecode(utf8.decode(messageContent));

  final post = await _dio
      .get('https://tress.hasali.uk/api/posts/${messageData['id']}')
      .then((res) => res.data);

  final feed = await _dio
      .get('https://tress.hasali.uk/api/feeds/${post['feed_id']}')
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tress',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      routerConfig: _appRouter.config(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      cardTheme: CardThemeData(clipBehavior: Clip.antiAlias),
    );
  }
}
