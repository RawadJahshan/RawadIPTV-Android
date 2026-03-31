import 'package:flutter/material.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/profile.dart';
import '../../../data/services/playlist_sync_service.dart';

class PlaylistSyncScreen extends StatefulWidget {
  final Profile profile;
  final XtreamApi xtreamApi;
  final String title;
  final bool forceRefresh;

  const PlaylistSyncScreen({
    super.key,
    required this.profile,
    required this.xtreamApi,
    this.title = 'Adding Playlist Content',
    this.forceRefresh = false,
  });

  @override
  State<PlaylistSyncScreen> createState() => _PlaylistSyncScreenState();
}

class _PlaylistSyncScreenState extends State<PlaylistSyncScreen> {
  double _progress = 0;
  String _status = 'Preparing...';
  String? _error;
  bool _isDone = false;

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    try {
      await PlaylistSyncService.syncLightweightCatalog(
        profileId: widget.profile.id,
        xtreamApi: widget.xtreamApi,
        forceRefresh: widget.forceRefresh,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = progress.progress;
            _status = progress.status;
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _progress = 1;
        _status = 'Done';
        _isDone = true;
      });

      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              color: const Color(0xFF1E1E2E),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.profile.name,
                      style: const TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error ?? _status,
                      style: TextStyle(
                        color: _error == null ? Colors.white : Colors.redAccent,
                        fontSize: 16,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _startSync,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ),
                    ],
                    if (_isDone)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Metadata sync completed. Content loads on demand for faster startup.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
