import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/find_locale.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

final dio = Dio();
final _dateFormat = DateFormat.yMMMd();

void main() async {
  await findSystemLocale();
  await initializeDateFormatting();

  runApp(const MyApp());
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
      cardTheme: CardTheme(clipBehavior: Clip.antiAlias),
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

  factory Feed.fromJson(Map<String, dynamic> json) => Feed(
        id: json['id'],
        title: json['title'],
        url: json['url'],
      );
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

  @override
  void initState() {
    super.initState();
    dataFuture = (() async {
      final [feedsResponse, postsResponse] = await Future.wait([
        dio.get('https://tress.hasali.uk/api/feeds'),
        dio.get('https://tress.hasali.uk/api/posts')
      ]);

      Map<String, Feed> feeds = {};
      for (final Feed feed
          in feedsResponse.data.map((feed) => Feed.fromJson(feed))) {
        feeds[feed.id] = feed;
      }

      return (
        feeds,
        (postsResponse.data as List<dynamic>)
            .map((post) => Post.fromJson(post))
            .toList()
      );
    })();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Posts'),
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
              child:
                  Text(snapshot.error.toString(), textAlign: TextAlign.center),
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

  const _PostTile({
    required this.feed,
    required this.post,
  });

  @override
  Widget build(BuildContext context) {
    Widget? image;
    if (post.thumbnail case String thumbnail) {
      image = Image.network(
        thumbnail,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
      );
    }

    final theme = Theme.of(context);
    final titleStyle =
        theme.textTheme.bodyLarge!.copyWith(color: theme.colorScheme.onSurface);
    final overlineStyle = theme.textTheme.bodySmall!
        .copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      child: InkWell(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                        Text(_dateFormat.format(post.postTime),
                            style: overlineStyle),
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
        onTap: () async {
          await launchUrlString(post.url);
        },
      ),
    );
  }
}
