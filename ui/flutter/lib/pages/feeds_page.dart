import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models.dart';

final _dio = Dio();

@RoutePage()
class FeedsPage extends StatefulWidget {
  const FeedsPage({super.key});

  @override
  State<FeedsPage> createState() => _FeedsPageState();
}

class _FeedsPageState extends State<FeedsPage> {
  List<Feed>? _feeds;
  Object? _error;

  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await _dio.get('https://tress.hasali.uk/api/feeds');
      final feeds = (response.data as List<dynamic>)
          .map((feed) => Feed.fromJson(feed))
          .toList();
      setState(() {
        _feeds = feeds;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _feeds = null;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeds'),
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Add Feed'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            hintText: 'https://example.com/index.xml',
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final url = _urlController.text;
                          try {
                            await _dio.post(
                              'https://tress.hasali.uk/api/feeds',
                              data: {'url': url},
                            );
                            await _loadData();
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
                        child: const Text('Ok'),
                      ),
                    ],
                  );
                },
              );
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: switch ((_feeds, _error)) {
        (final feeds?, _) when feeds.isEmpty => const Center(
          child: Text('No feeds yet. Add one to get started.'),
        ),
        (final feeds?, _) => RefreshIndicator(
          onRefresh: _loadData,
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: feeds.length,
            itemBuilder: (context, index) {
              final feed = feeds[index];
              return ListTile(
                leading: const Icon(Icons.rss_feed),
                title: Text(feed.title),
                subtitle: Text(
                  feed.url,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
            separatorBuilder: (context, index) => const Divider(height: 1),
          ),
        ),
        (_, final error?) => Center(
          child: Text(error.toString(), textAlign: TextAlign.center),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
