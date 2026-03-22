import 'package:auto_route/auto_route.dart';

import 'pages/feeds_page.dart';
import 'pages/home_page.dart';
import 'pages/posts_page.dart';

part 'router.gr.dart';

@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: HomeRoute.page,
      initial: true,
      children: [
        AutoRoute(page: PostsRoute.page, initial: true),
        AutoRoute(page: FeedsRoute.page),
      ],
    ),
  ];
}
