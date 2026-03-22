import 'package:auto_route/auto_route.dart';

import 'pages/posts_page.dart';

part 'router.gr.dart';

@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: PostsRoute.page, initial: true),
  ];
}
