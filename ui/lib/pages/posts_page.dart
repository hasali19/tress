import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../api_client.dart';
import '../models.dart';

final _dateFormat = DateFormat.yMMMd();

@RoutePage()
class PostsPage extends StatefulWidget {
  const PostsPage({super.key});

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  Map<String, Feed>? _feeds;
  List<Post>? _posts;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
    Permission.notification.request();
  }

  Future<void> _loadData() async {
    final apiClient = GetIt.instance<ApiClient>();
    try {
      final [feeds, posts] = await Future.wait([
        apiClient.getFeeds(),
        apiClient.getPosts(),
      ]);

      setState(() {
        _feeds = {for (final feed in feeds as List<Feed>) feed.id: feed};
        _posts = posts as List<Post>;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _feeds = null;
        _posts = null;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Posts')),
      body: switch ((_feeds, _posts, _error)) {
        (final feeds?, final posts?, _) => RefreshIndicator(
          onRefresh: _loadData,
          child: ListView.separated(
            padding: const EdgeInsets.all(4),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return _PostTile(feed: feeds[post.feedId]!, post: post);
            },
            separatorBuilder: (context, index) => const Gap(4),
          ),
        ),
        (_, _, final error?) => Center(
          child: Text(error.toString(), textAlign: TextAlign.center),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

final class _PostTile extends StatelessWidget {
  final Feed feed;
  final Post post;

  const _PostTile({required this.feed, required this.post});

  @override
  Widget build(BuildContext context) {
    Widget? image;
    if (post.thumbnail case String thumbnail) {
      image = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120),
        child: CachedNetworkImage(
          imageUrl: thumbnail,
          width: 120,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) {
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              elevation: 1.0,
              surfaceTintColor: Colors.transparent,
              child: const Center(child: Icon(Icons.error_outline)),
            );
          },
        ),
      );
    }

    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.bodyLarge!.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final overlineStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      child: InkWell(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (image != null) image,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(feed.title, style: overlineStyle),
                          ),
                          Text(
                            _dateFormat.format(post.postTime),
                            style: overlineStyle,
                          ),
                        ],
                      ),
                      const Gap(4),
                      Text(post.title, style: titleStyle),
                      if (post.description case String description)
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        onTap: () async {
          await launchUrlString(post.url);
        },
      ),
    );
  }
}
