import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/find_locale.dart';

import 'api_client.dart';
import 'router.dart';

const _pushChannel = MethodChannel('tress.hasali.dev/push');

final _appRouter = AppRouter();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await findSystemLocale();
  await initializeDateFormatting();

  GetIt.instance.registerSingleton<ApiClient>(ApiClient());

  final config = await GetIt.instance<ApiClient>().getConfig();

  await _pushChannel.invokeMethod('register', {
    'vapid_key': config['vapid']['public_key'],
  });

  runApp(const MyApp());
}

@pragma('vm:entry-point')
void pushEntrypoint() {
  WidgetsFlutterBinding.ensureInitialized();

  final apiClient = ApiClient();

  String? url;

  _pushChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onNewEndpoint':
        final newUrl = call.arguments['url'];
        if (newUrl != url) {
          url = newUrl;
          await apiClient.registerPushSubscription(
            newUrl,
            call.arguments['keys']['auth'],
            call.arguments['keys']['pub'],
          );
        }
        break;
      case 'onMessage':
        _handlePushMessage(apiClient, call.arguments['content'], '');
        break;
    }
  });
}

Future<void> _handlePushMessage(
  ApiClient apiClient,
  Uint8List messageContent,
  String instance,
) async {
  const notificationsChannel = MethodChannel('tress.hasali.dev/notifications');

  final messageData = jsonDecode(utf8.decode(messageContent));

  final post = await apiClient.getPost(messageData['id']);
  final feed = await apiClient.getFeed(post.feedId);

  await notificationsChannel.invokeMethod('post', {
    'id': post.id.hashCode,
    'title': messageData['title'],
    'subtext': feed.title,
    'content': post.description,
    'url': post.url,
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
