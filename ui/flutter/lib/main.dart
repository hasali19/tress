import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/find_locale.dart';

import 'api_client.dart';
import 'router.dart';

const _pushChannel = MethodChannel('tress.hasali.dev/push');

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final client = ApiClient();
  GetIt.instance.registerSingleton(client);

  final [_, __, config] = await Future.wait([
    findSystemLocale(),
    initializeDateFormatting(),
    client.getConfig(),
  ]);

  await _pushChannel.invokeMethod('register', {
    'vapid_key': config['vapid']['public_key'],
  });

  final userId = await client.restoreAuth();

  runApp(MyApp(initiallyLoggedIn: userId != null));
}

@pragma('vm:entry-point')
void pushEntrypoint() {
  WidgetsFlutterBinding.ensureInitialized();

  final client = ApiClient();
  String? url;

  _pushChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onNewEndpoint':
        final newUrl = call.arguments['url'];
        if (newUrl != url) {
          url = newUrl;
          await client.registerPushSubscription(
            url: newUrl,
            auth: call.arguments['keys']['auth'],
            pubKey: call.arguments['keys']['pub'],
          );
        }
        break;
      case 'onMessage':
        await _handlePushMessage(client, call.arguments['content']);
        break;
    }
  });
}

Future<void> _handlePushMessage(
  ApiClient client,
  Uint8List messageContent,
) async {
  const notificationsChannel = MethodChannel('tress.hasali.dev/notifications');

  final messageData = jsonDecode(utf8.decode(messageContent));
  final post = await client.getPost(messageData['id']);
  final feed = await client.getFeed(post['feed_id']);
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
