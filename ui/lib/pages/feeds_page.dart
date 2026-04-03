import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../models.dart';

@RoutePage()
class FeedsPage extends StatefulWidget {
  const FeedsPage({super.key});

  @override
  State<FeedsPage> createState() => _FeedsPageState();
}

class _FeedsPageState extends State<FeedsPage> {
  late final ApiClient _apiClient;
  List<Feed>? _feeds;
  Object? _error;

  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiClient = GetIt.instance<ApiClient>();
    _loadData();
  }

  Future<void> _deleteFeed(Feed feed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteFeedDialog(feed: feed),
    );
    if (confirmed == true) {
      try {
        await _apiClient.deleteFeed(feed.id);
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete feed')),
          );
        }
      }
    }
  }

  Future<void> _loadData() async {
    try {
      final feeds = await _apiClient.getFeeds();
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
                            await _apiClient.addFeed(url);
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
              final lastSyncedAt = feed.lastSyncedAt != null
                  ? DateFormat.yMd().add_Hm().format(feed.lastSyncedAt!.toLocal())
                  : null;
              return ListTile(
                leading: const Icon(Icons.rss_feed),
                title: Text(feed.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(feed.url, overflow: TextOverflow.ellipsis),
                    if (lastSyncedAt != null)
                      Text(
                        'Last synced: $lastSyncedAt',
                      ),
                  ],
                ),
                isThreeLine: lastSyncedAt != null,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteFeed(feed),
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

class _DeleteFeedDialog extends StatelessWidget {
  const _DeleteFeedDialog({required this.feed});

  final Feed feed;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete Feed'),
      content: Text('Delete "${feed.title}" and all its posts?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
