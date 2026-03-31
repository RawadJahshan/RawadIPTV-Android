import '../datasources/remote/xtream_api.dart';
import 'catalog_cache_service.dart';

class PlaylistSyncProgress {
  final String title;
  final String status;
  final double progress;

  const PlaylistSyncProgress({
    required this.title,
    required this.status,
    required this.progress,
  });
}

class PlaylistSyncService {
  static const String _liveCategories = 'live_categories';
  static const String _liveStreams = 'live_streams';
  static const String _vodCategories = 'vod_categories';
  static const String _vodStreams = 'vod_streams';
  static const String _seriesCategories = 'series_categories';
  static const String _seriesList = 'series_list';

  static Future<void> syncLightweightCatalog({
    required String profileId,
    required XtreamApi xtreamApi,
    required void Function(PlaylistSyncProgress progress) onProgress,
  }) async {
    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Fetching categories...',
        progress: 0.1,
      ),
    );

    final liveCategories = await xtreamApi.getLiveCategories();
    final vodCategories = await xtreamApi.getVodCategories();
    final seriesCategories = await xtreamApi.getSeriesCategories();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Loading Live TV...',
        progress: 0.35,
      ),
    );
    final liveStreams = await xtreamApi.getLiveStreams();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Loading Movies...',
        progress: 0.55,
      ),
    );
    final vodStreams = await xtreamApi.getVodStreamsStrict();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Loading Series...',
        progress: 0.75,
      ),
    );
    final seriesList = await xtreamApi.getSeries();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Saving content...',
        progress: 0.9,
      ),
    );

    await CatalogCacheService.saveCatalogSection(
      profileId,
      _liveCategories,
      liveCategories,
    );
    await CatalogCacheService.saveCatalogSection(
      profileId,
      _liveStreams,
      liveStreams,
    );
    await CatalogCacheService.saveCatalogSection(
      profileId,
      _vodCategories,
      vodCategories,
    );
    await CatalogCacheService.saveCatalogSection(
      profileId,
      _vodStreams,
      vodStreams,
    );
    await CatalogCacheService.saveCatalogSection(
      profileId,
      _seriesCategories,
      seriesCategories,
    );
    await CatalogCacheService.saveCatalogSection(
      profileId,
      _seriesList,
      seriesList,
    );
    await CatalogCacheService.setLastRefresh(profileId, DateTime.now().toUtc());

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Completed',
        progress: 1,
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> getLiveCategories(String profileId) {
    return CatalogCacheService.getCatalogSection(profileId, _liveCategories);
  }

  static Future<List<Map<String, dynamic>>> getLiveStreams(String profileId) {
    return CatalogCacheService.getCatalogSection(profileId, _liveStreams);
  }

  static Future<List<Map<String, dynamic>>> getVodCategories(String profileId) {
    return CatalogCacheService.getCatalogSection(profileId, _vodCategories);
  }

  static Future<List<Map<String, dynamic>>> getVodStreams(String profileId) {
    return CatalogCacheService.getCatalogSection(profileId, _vodStreams);
  }

  static Future<List<Map<String, dynamic>>> getSeriesCategories(String profileId) {
    return CatalogCacheService.getCatalogSection(profileId, _seriesCategories);
  }

  static Future<List<Map<String, dynamic>>> getSeriesList(String profileId) {
    return CatalogCacheService.getCatalogSection(profileId, _seriesList);
  }
}
