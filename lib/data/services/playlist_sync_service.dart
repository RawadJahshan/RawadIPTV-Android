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
  static const String _accountInfo = 'account_info';
  static const String _liveCategories = 'live_categories';
  static const String _vodCategories = 'vod_categories';
  static const String _seriesCategories = 'series_categories';

  static const Duration accountInfoTtl = Duration(minutes: 5);
  static const Duration categoriesTtl = Duration(minutes: 30);

  static Future<void> syncLightweightCatalog({
    required String profileId,
    required XtreamApi xtreamApi,
    required void Function(PlaylistSyncProgress progress) onProgress,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      XtreamApi.clearAllInMemoryCaches();
      await CatalogCacheService.clearProfileCatalog(profileId);
    }

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Fetching account info...',
        progress: 0.2,
      ),
    );
    final accountInfo = await xtreamApi.getAccountInfo();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Fetching Live TV categories...',
        progress: 0.45,
      ),
    );
    final liveCategories = await xtreamApi.getLiveCategories();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Fetching movie categories...',
        progress: 0.65,
      ),
    );
    final vodCategories = await xtreamApi.getVodCategories();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Fetching series categories...',
        progress: 0.8,
      ),
    );
    final seriesCategories = await xtreamApi.getSeriesCategories();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Saving metadata...',
        progress: 0.9,
      ),
    );

    final accountList = accountInfo.isEmpty ? <Map<String, dynamic>>[] : <Map<String, dynamic>>[accountInfo];

    await CatalogCacheService.saveCatalogSection(profileId, _accountInfo, accountList);
    await CatalogCacheService.saveCatalogSection(profileId, _liveCategories, liveCategories);
    await CatalogCacheService.saveCatalogSection(profileId, _vodCategories, vodCategories);
    await CatalogCacheService.saveCatalogSection(profileId, _seriesCategories, seriesCategories);
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
    return CatalogCacheService.getCatalogSectionIfFresh(
      profileId,
      _liveCategories,
      ttl: categoriesTtl,
    );
  }

  static Future<List<Map<String, dynamic>>> getVodCategories(String profileId) {
    return CatalogCacheService.getCatalogSectionIfFresh(
      profileId,
      _vodCategories,
      ttl: categoriesTtl,
    );
  }

  static Future<List<Map<String, dynamic>>> getSeriesCategories(String profileId) {
    return CatalogCacheService.getCatalogSectionIfFresh(
      profileId,
      _seriesCategories,
      ttl: categoriesTtl,
    );
  }

  static Future<Map<String, dynamic>?> getAccountInfo(String profileId) async {
    final rows = await CatalogCacheService.getCatalogSectionIfFresh(
      profileId,
      _accountInfo,
      ttl: accountInfoTtl,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }
}
