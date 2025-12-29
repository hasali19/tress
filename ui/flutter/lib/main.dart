import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/find_locale.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';

final _dio = Dio();
final _dateFormat = DateFormat.yMMMd();

const _pushChannel = MethodChannel('tress.hasali.dev/push');

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await findSystemLocale();
  await initializeDateFormatting();

  final configRes = await _dio.get('https://tress.hasali.uk/api/config');
  final config = configRes.data;

  await _pushChannel
      .invokeMethod('register', {'vapid_key': config['vapid']['public_key']});

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
    String url, String? auth, String? pubKey) async {
  await _dio.post(
    'https://tress.hasali.uk/api/push_subscriptions',
    data: {
      'subscription': {
        'endpoint': url,
        'keys': {
          'auth': auth,
          'p256dh': pubKey,
        },
      },
    },
  );
}

Future<void> _handlePushMessage(
    Uint8List messageContent, String instance) async {
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
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tress',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const PostsPage(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      cardTheme: CardThemeData(clipBehavior: Clip.antiAlias),
    );
  }
}

class PostsPage extends StatefulWidget {
  const PostsPage({super.key});

  @override
  State<PostsPage> createState() => _PostsPageState();
}

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

class _PostsPageState extends State<PostsPage> {
  late Future<(Map<String, Feed>, List<Post>)> dataFuture;

  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();

    dataFuture = (() async {
      final [feedsResponse, postsResponse] = await Future.wait([
        _dio.get('https://tress.hasali.uk/api/feeds'),
        _dio.get('https://tress.hasali.uk/api/posts'),
      ]);

      Map<String, Feed> feeds = {};
      for (final Feed feed in feedsResponse.data.map(
        (feed) => Feed.fromJson(feed),
      )) {
        feeds[feed.id] = feed;
      }

      return (
        feeds,
        (postsResponse.data as List<dynamic>)
            .map((post) => Post.fromJson(post))
            .toList(),
      );
    })();

    Permission.notification.request();
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
                                hintText: 'https://example.com/index.xml'),
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
                              await _dio.post(
                                'https://tress.hasali.uk/api/feeds',
                                data: {
                                  'url': url,
                                },
                              );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Failed to add feed')));
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
              icon: Icon(Icons.add))
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
              child: Center(
                child: Icon(Icons.error_outline),
              ),
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
                              child: Text(feed.title, style: overlineStyle)),
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
