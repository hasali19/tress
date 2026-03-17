import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../api_client.dart';
import '../router.dart';

final _dateFormat = DateFormat.yMMMd();

class Feed {
  final String id;
  final String title;
  final String url;

  Feed({required this.id, required this.title, required this.url});

  factory Feed.fromJson(Map<String, dynamic> json) =>
      Feed(id: json['id'], title: json['title'], url: json['url']);
}

class Post {
  final String id;
  final String feedId;
  final String title;
  final DateTime postTime;
  final String? thumbnail;
  final String? description;
  final String url;

  Post({
    required this.id,
    required this.feedId,
    required this.title,
    required this.postTime,
    required this.thumbnail,
    required this.description,
    required this.url,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['id'],
    feedId: json['feed_id'],
    title: json['title'],
    postTime: DateTime.parse(json['post_time']),
    thumbnail: json['thumbnail'],
    description: json['description'],
    url: json['url'],
  );
}

@RoutePage()
class PostsPage extends StatefulWidget {
  const PostsPage({super.key});

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  final _client = GetIt.instance<ApiClient>();
  late Future<(Map<String, Feed>, List<Post>)> dataFuture;

  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    dataFuture = _loadData();
    Permission.notification.request();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<(Map<String, Feed>, List<Post>)> _loadData() async {
    try {
      final [feedsData, postsData] = await Future.wait([
        _client.getFeeds(),
        _client.getPosts(),
      ]);

      Map<String, Feed> feeds = {};
      for (final Feed feed in feedsData.map((f) => Feed.fromJson(f))) {
        feeds[feed.id] = feed;
      }

      return (
        feeds,
        (postsData as List<dynamic>).map((p) => Post.fromJson(p)).toList(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _client.clearAuth();
        if (mounted) {
          context.router.replaceAll([const LoginRoute()]);
        }
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Posts'),
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text('Add Feed'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            hintText: 'https://example.com/index.xml',
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final url = _urlController.text;

                          try {
                            await _client.addFeed(url);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to add feed'),
                                ),
                              );
                            }
                          }

                          if (context.mounted) {
                            Navigator.pop(context);
                            _urlController.clear();
                          }
                        },
                        child: Text('Ok'),
                      ),
                    ],
                  );
                },
              );
            },
            icon: Icon(Icons.add),
          ),
        ],
      ),
      body: FutureBuilder(
        future: dataFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final (feeds, posts) = snapshot.requireData;
            return ListView.separated(
              padding: EdgeInsets.all(4),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return _PostTile(feed: feeds[post.feedId]!, post: post);
              },
              separatorBuilder: (context, index) => Gap(4),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                snapshot.error.toString(),
                textAlign: TextAlign.center,
              ),
            );
          }

          return Center(child: CircularProgressIndicator());
        },
      ),
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
        constraints: BoxConstraints(minHeight: 120),
        child: CachedNetworkImage(
          imageUrl: thumbnail,
          width: 120,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) {
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              elevation: 1.0,
              surfaceTintColor: Colors.transparent,
              child: Center(child: Icon(Icons.error_outline)),
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
                      Gap(4),
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
