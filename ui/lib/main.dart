import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/find_locale.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'router.dart';

const _pushChannel = MethodChannel('tress.hasali.dev/push');

final _appRouter = AppRouter();

Future<AuthService?> _initAuthService(Map<String, dynamic> config) async {
  final oidcConfig = config['oidc'];
  if (oidcConfig == null) {
    return null;
  }

  return AuthService.init(
    issuerUri: Uri.parse(oidcConfig['issuer_url']),
    clientId: oidcConfig['client_id'],
  );
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await findSystemLocale();
  await initializeDateFormatting();

  // TODO: avoid creating a second ApiClient below when OIDC is configured
  final config = await ApiClient().getConfig();

  final authService = await _initAuthService(config);
  if (authService != null) {
    GetIt.instance.registerSingleton<AuthService>(authService);

    if (!authService.isAuthenticated) {
      await authService.login();
    }
  }

  GetIt.instance.registerSingleton<ApiClient>(
    ApiClient(authService: authService),
  );

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

          final config = await ApiClient().getConfig();
          final authService = await _initAuthService(config);
          // No user is present to complete an interactive login from this
          // headless background isolate, so just silently refresh whatever
          // session is already cached, if any.
          await authService?.tryRefresh();

          await ApiClient(authService: authService).registerPushSubscription(
            newUrl,
            call.arguments['keys']['auth'],
            call.arguments['keys']['pub'],
          );
        }
        break;
      case 'onMessage':
        _handlePushMessage(call.arguments['content']);
        break;
    }
  });
}

Future<void> _handlePushMessage(Uint8List messageContent) async {
  const notificationsChannel = MethodChannel('tress.hasali.dev/notifications');

  final messageData =
      jsonDecode(utf8.decode(messageContent)) as Map<String, dynamic>;

  await notificationsChannel.invokeMethod('post', {
    'id': (messageData['id'] as String).hashCode,
    'title': messageData['title'],
    'subtext': messageData['feed_title'],
    'content': messageData['description'],
    'url': messageData['url'],
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
