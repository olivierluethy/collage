import '../models/collage_project.dart';

/// Which saved collages use which photos — built locally from the library, no
/// cloud involved. Asset ids are the photo library's stable local identifiers
/// (photo_manager `AssetEntity.id`), so a photo keeps its history across
/// renames; a deleted photo simply stops matching anything.
class PhotoUsageIndex {
  PhotoUsageIndex(List<CollageProject> collages) {
    for (final p in collages) {
      _byId[p.id] = p;
      for (final a in p.assetIds) {
        (_byAsset[a] ??= <String>[]).add(p.id);
      }
    }
  }

  static final empty = PhotoUsageIndex(const []);

  final _byAsset = <String, List<String>>{};
  final _byId = <String, CollageProject>{};

  /// True when [assetId] appears in at least one saved collage.
  bool isUsed(String assetId) => _byAsset.containsKey(assetId);

  /// Every asset id that appears in a saved collage.
  Set<String> get usedAssets => _byAsset.keys.toSet();

  /// The collages (newest first) that contain [assetId].
  List<CollageProject> collagesUsing(String assetId) {
    final ids = _byAsset[assetId];
    if (ids == null) return const [];
    return [for (final id in ids) _byId[id]!]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Collages made from exactly the photos in [assets] (order ignored),
  /// newest first, skipping [excludeId] (the collage being edited). Used for
  /// the non-blocking "you already made a collage with these photos" hint.
  List<CollageProject> sameSet(Set<String> assets, {String? excludeId}) {
    if (assets.isEmpty) return const [];
    final out = <CollageProject>[];
    for (final p in _byId.values) {
      if (p.id == excludeId) continue;
      final set = p.assetIds;
      if (set.length == assets.length && set.containsAll(assets)) out.add(p);
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }
}
