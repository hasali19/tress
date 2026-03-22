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
