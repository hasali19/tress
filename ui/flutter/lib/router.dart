import 'package:auto_route/auto_route.dart';

import 'routes/login_page.dart';
import 'routes/posts_page.dart';

part 'router.gr.dart';

@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: LoginRoute.page),
    AutoRoute(page: PostsRoute.page),
  ];
}
