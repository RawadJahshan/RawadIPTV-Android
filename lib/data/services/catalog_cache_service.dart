import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CatalogCacheService {
  static String _key(String profileId, String section) =>
      'catalog_${profileId}_$section';

  static String _sectionUpdatedAtKey(String profileId, String section) =>
      'catalog_${profileId}_${section}_updated_at';

  static String _updatedAtKey(String profileId) =>
      'catalog_${profileId}_updated_at';

  static Future<void> saveCatalogSection(
    String profileId,
    String section,
    List<Map<String, dynamic>> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(profileId, section), jsonEncode(data));
    await prefs.setString(
      _sectionUpdatedAtKey(profileId, section),
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  static Future<List<Map<String, dynamic>>> getCatalogSection(
    String profileId,
    String section,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key(profileId, section));
    if (jsonString == null || jsonString.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final parsed = jsonDecode(jsonString);
      if (parsed is! List) {
        return <Map<String, dynamic>>[];
      }

      return parsed
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> getCatalogSectionIfFresh(
    String profileId,
    String section, {
    required Duration ttl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sectionUpdatedAtKey(profileId, section));
    final updatedAt = raw == null ? null : DateTime.tryParse(raw);
    if (updatedAt == null) {
      return <Map<String, dynamic>>[];
    }

    final expiresAt = updatedAt.toUtc().add(ttl);
    if (DateTime.now().toUtc().isAfter(expiresAt)) {
      return <Map<String, dynamic>>[];
    }

    return getCatalogSection(profileId, section);
  }

  static Future<void> clearProfileCatalog(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'catalog_${profileId}_';
    final keysToRemove = prefs.getKeys().where((key) => key.startsWith(prefix));
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  static Future<void> setLastRefresh(String profileId, DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_updatedAtKey(profileId), timestamp.toIso8601String());
  }

  static Future<DateTime?> getLastRefresh(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_updatedAtKey(profileId));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
