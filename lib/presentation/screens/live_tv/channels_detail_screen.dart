import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tha_player/tha_player.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/live_tv_category.dart';
import '../../../utils/favorites_manager.dart';

class ChannelsDetailScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  final LiveTvCategory category;

  const ChannelsDetailScreen({
    super.key,
    required this.xtreamApi,
    required this.category,
  });

  @override
  State<ChannelsDetailScreen> createState() => _ChannelsDetailScreenState();
}

class _ChannelsDetailScreenState extends State<ChannelsDetailScreen> {
  late Future<List<Channel>> _channelsFuture;

  int _selectedChannelIndex = 0;
  ThaNativePlayerController? _playerController;

  bool _isFavorite = false;
  bool _isBuffering = false;
  bool _hasError = false;
  bool _usingM3u8 = false;
  bool _isPlaying = true;
  bool _isFullscreen = false;

  String _errorMessage = '';
  int _retryCount = 0;

  static const int _maxRetries = 3;
  static const Map<String, String> _streamHttpHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Connection': 'keep-alive',
  };

  Timer? _fallbackTimer;
  Timer? _retryTimer;
  Timer? _bufferingGuardTimer;

  void _forceLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void initState() {
    super.initState();
    _forceLandscape();
    _channelsFuture = _loadChannels();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _forceLandscape();
  }

  Future<List<Channel>> _loadChannels() async {
    final rawChannels = await widget.xtreamApi.getLiveStreams(
      categoryId: widget.category.id,
    );

    final channels = rawChannels
        .map((json) => Channel.fromJson(
              json,
              widget.xtreamApi.serverUrl,
              widget.xtreamApi.username,
              widget.xtreamApi.password,
            ))
        .toList();

    if (channels.isNotEmpty) {
      await _playStream(channels[0]);
      await _loadFavoriteStatus(channels[0].id.toString());
    }

    return channels;
  }

  Future<void> _playStream(Channel channel) async {
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _bufferingGuardTimer?.cancel();

    _usingM3u8 = false;
    _retryCount = 0;

    if (mounted) {
      setState(() {
        _hasError = false;
        _isBuffering = true;
        _isPlaying = true;
        _errorMessage = '';
      });
    }

    await _replacePlayer(channel.streamUrl);

    _fallbackTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isBuffering && !_hasError) {
        _tryM3u8Fallback(channel);
      }
    });
  }

  Future<void> _replacePlayer(String url) async {
    final previousController = _playerController;

    final nextController = ThaNativePlayerController.single(
      ThaMediaSource(url, headers: _streamHttpHeaders),
      autoPlay: true,
    );

    setState(() {
      _playerController = nextController;
      _isPlaying = true;
      _isBuffering = true;
    });

    // Tha player does not expose buffering callbacks in this screen,
    // so we clear the loading spinner after a short guard window.
    _bufferingGuardTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _playerController != nextController) return;
      setState(() => _isBuffering = false);
    });

    previousController?.dispose();
  }

  Future<void> _tryM3u8Fallback(Channel channel) async {
    if (!mounted) return;

    _fallbackTimer?.cancel();
    _usingM3u8 = true;

    setState(() {
      _isBuffering = true;
      _hasError = false;
    });

    await _replacePlayer(channel.streamUrlM3u8);

    _fallbackTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isBuffering) {
        _handleError();
      }
    });
  }

  Future<void> _loadFavoriteStatus(String channelId) async {
    final fav = await FavoritesManager.isFavorite(channelId);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite(Channel channel) async {
    if (_isFavorite) {
      await FavoritesManager.removeFavorite(channel.id.toString());
    } else {
      await FavoritesManager.addFavorite(channel.id.toString());
    }

    if (mounted) {
      setState(() => _isFavorite = !_isFavorite);
    }
  }

  void _onChannelSelected(Channel channel, int index) async {
    if (_selectedChannelIndex == index) return;

    setState(() {
      _selectedChannelIndex = index;
      _isBuffering = true;
      _hasError = false;
      _errorMessage = '';
    });

    await _playStream(channel);
    await _loadFavoriteStatus(channel.id.toString());
  }

  void _onPlayerError(String? _) {
    _handleError();
  }

  void _handleError() {
    if (!mounted) return;

    _fallbackTimer?.cancel();
    _retryTimer?.cancel();

    if (!_usingM3u8) {
      _channelsFuture.then((channels) {
        if (!mounted || channels.isEmpty) return;
        _tryM3u8Fallback(channels[_selectedChannelIndex]);
      });
      return;
    }

    if (_retryCount < _maxRetries) {
      _retryCount++;
      _retryTimer = Timer(const Duration(seconds: 2), () {
        _channelsFuture.then((channels) {
          if (!mounted || channels.isEmpty) return;
          _playStream(channels[_selectedChannelIndex]);
        });
      });
      return;
    }

    setState(() {
      _hasError = true;
      _errorMessage = 'Stream unavailable';
      _isBuffering = false;
    });
  }

  void _retryStream(List<Channel> channels) {
    _retryCount = 0;
    _usingM3u8 = false;
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _playStream(channels[_selectedChannelIndex]);
  }

  Future<void> _togglePlayPause() async {
    final controller = _playerController;
    if (controller == null) return;

    if (_isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() {
        _isPlaying = !_isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _forceLandscape();
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _bufferingGuardTimer?.cancel();
    _playerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return WillPopScope(
      onWillPop: () async {
        if (_isFullscreen) {
          setState(() => _isFullscreen = false);
          return false;
        }

        _forceLandscape();
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: _isFullscreen
            ? null
            : AppBar(
                title: Text(widget.category.name),
                backgroundColor: const Color(0xFF0F0F1A),
                elevation: 0,
              ),
        body: FutureBuilder<List<Channel>>(
          future: _channelsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading channels...'),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No channels found'));
            }

            final channels = snapshot.data!;
            final selectedChannel = channels[_selectedChannelIndex];

            if (_isFullscreen) {
              return _buildPlayerArea(
                selectedChannel: selectedChannel,
                channels: channels,
                fullscreenOnly: true,
              );
            }

            return Row(
              children: [
                Container(
                  width: size.width * 0.3,
                  color: const Color(0xFF0F0F1A),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        color: const Color(0xFF07070F),
                        width: double.infinity,
                        child: Text(
                          '${channels.length} Channels',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: channels.length,
                          itemBuilder: (context, index) {
                            final channel = channels[index];
                            final isSelected = index == _selectedChannelIndex;

                            return Material(
                              color: isSelected
                                  ? const Color(0xFF1A3A5C)
                                  : Colors.transparent,
                              child: InkWell(
                                onTap: () => _onChannelSelected(channel, index),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: SizedBox(
                                    height: 56,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E2E),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: channel.logoUrl.isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  child: Image.network(
                                                    channel.logoUrl,
                                                    cacheWidth: 400,
                                                    cacheHeight: 450,
                                                    filterQuality:
                                                        FilterQuality.low,
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (_, __, ___) =>
                                                        const Icon(
                                                      Icons.tv,
                                                      color: Colors.white54,
                                                      size: 20,
                                                    ),
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.tv,
                                                  color: Colors.white54,
                                                  size: 20,
                                                ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            channel.name,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.white70,
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.play_arrow,
                                            color: Colors.blue,
                                            size: 16,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: (size.height - kToolbarHeight) * 0.62,
                        child: _buildPlayerArea(
                          selectedChannel: selectedChannel,
                          channels: channels,
                          fullscreenOnly: false,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          color: const Color(0xFF1E1E1E),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (selectedChannel.logoUrl.isNotEmpty)
                                    Container(
                                      width: 50,
                                      height: 50,
                                      margin:
                                          const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F0F1A),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          selectedChannel.logoUrl,
                                          cacheWidth: 400,
                                          cacheHeight: 450,
                                          filterQuality: FilterQuality.low,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.tv,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      selectedChannel.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _infoChip(
                                    Icons.stream,
                                    _usingM3u8 ? 'HLS Stream' : 'Main Stream',
                                  ),
                                  const SizedBox(width: 8),
                                  _infoChip(
                                    _isPlaying
                                        ? Icons.play_circle
                                        : Icons.pause_circle,
                                    _isPlaying ? 'Playing' : 'Paused',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F0F1A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.tv_outlined,
                                      color: Colors.white54,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'EPG: No guide available',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => _toggleFavorite(selectedChannel),
                                icon: Icon(
                                  _isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color:
                                      _isFavorite ? Colors.red : Colors.white,
                                ),
                                label: Text(
                                  _isFavorite
                                      ? 'Remove from Favorites'
                                      : 'Add to Favorites',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A1A2E),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayerArea({
    required Channel selectedChannel,
    required List<Channel> channels,
    required bool fullscreenOnly,
  }) {
    final controller = _playerController;

    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: ThaModernPlayer(
              key: ValueKey(selectedChannel.id),
              controller: controller,
              autoHideAfter: const Duration(seconds: 3),
              initialBoxFit: BoxFit.contain,
              autoFullscreen: false,
              isFullscreen: fullscreenOnly,
              doubleTapSeek: const Duration(seconds: 0),
              overlay: const SizedBox.shrink(),
              onError: _onPlayerError,
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _togglePlayPause,
                    icon: Icon(
                      _isPlaying ? Icons.stop : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    tooltip: _isPlaying ? 'Stop' : 'Play',
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _isFullscreen = !_isFullscreen);
                    },
                    icon: Icon(
                      _isFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: Colors.white,
                    ),
                    tooltip: _isFullscreen
                        ? 'Exit fullscreen'
                        : 'Fullscreen',
                  ),
                ],
              ),
            ),
          ),
          if (_isBuffering && !_hasError)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Loading ${selectedChannel.name}...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_hasError)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _retryStream(channels),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
