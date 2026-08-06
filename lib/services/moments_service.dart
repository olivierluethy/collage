import 'package:geocoding/geocoding.dart';
import 'package:photo_manager/photo_manager.dart';

import 'gallery_service.dart';

/// A suggested collage built from photos taken around the same place and day —
/// "you were at {place} on {date}: make this day's collage".
class Moment {
  Moment({
    required this.title,
    required this.subtitle,
    required this.assetIds,
    required this.coverId,
    required this.when,
  });

  final String title; // place name, or a date-based label when no location
  final String subtitle; // formatted date
  final List<String> assetIds;
  final String coverId;
  final DateTime when;
}

class _Bucket {
  final List<AssetEntity> assets = [];
  double latSum = 0;
  double lngSum = 0;
  int located = 0;
  DateTime? day;

  double? get lat => located == 0 ? null : latSum / located;
  double? get lng => located == 0 ? null : lngSum / located;
}

/// Scans recent photos and clusters them into "moments" by place + day, then
/// reverse-geocodes each cluster to a human place name. Degrades to date-only
/// moments when location metadata is unavailable.
class MomentsService {
  const MomentsService(this._gallery);
  final GalleryService _gallery;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _fmt(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  Future<List<Moment>> discover({int scan = 120, int maxMoments = 12}) async {
    final albums = await _gallery.albums();
    if (albums.isEmpty) return const [];
    final recent = albums.first;

    final assets = <AssetEntity>[];
    var page = 0;
    while (assets.length < scan) {
      final chunk = await _gallery.page(recent, page, size: 60);
      if (chunk.isEmpty) break;
      assets.addAll(chunk);
      page++;
      if (chunk.length < 60) break;
    }

    // Bucket by day + coarse location cell (~5 km).
    final buckets = <String, _Bucket>{};
    for (final a in assets.take(scan)) {
      final d = a.createDateTime;
      final day = DateTime(d.year, d.month, d.day);
      double? lat = a.latitude;
      double? lng = a.longitude;
      if (lat == null || lng == null || (lat == 0 && lng == 0)) {
        try {
          final ll = await a.latlngAsync();
          lat = ll?.latitude;
          lng = ll?.longitude;
        } catch (_) {}
      }
      final hasLoc = lat != null && lng != null && !(lat == 0 && lng == 0);
      final cell = hasLoc ? '${(lat * 20).round()}_${(lng * 20).round()}' : 'none';
      final key = '${day.toIso8601String()}|$cell';
      final b = buckets.putIfAbsent(key, () => _Bucket()..day = day);
      b.assets.add(a);
      if (hasLoc) {
        b.latSum += lat;
        b.lngSum += lng;
        b.located++;
      }
    }

    // Keep buckets worth a collage, newest first.
    final good = buckets.values.where((b) => b.assets.length >= 3).toList()
      ..sort((a, z) => (z.day ?? DateTime(0)).compareTo(a.day ?? DateTime(0)));

    final moments = <Moment>[];
    for (final b in good.take(maxMoments)) {
      final day = b.day ?? b.assets.first.createDateTime;
      String title = 'A day of photos';
      if (b.lat != null && b.lng != null) {
        try {
          final marks = await placemarkFromCoordinates(b.lat!, b.lng!);
          if (marks.isNotEmpty) {
            final m = marks.first;
            final name = (m.locality?.isNotEmpty ?? false)
                ? m.locality!
                : (m.subAdministrativeArea?.isNotEmpty ?? false)
                    ? m.subAdministrativeArea!
                    : (m.administrativeArea?.isNotEmpty ?? false)
                        ? m.administrativeArea!
                        : m.country ?? '';
            if (name.isNotEmpty) title = name;
          }
        } catch (_) {
          // Geocoding unavailable/denied — keep the date-based title.
        }
      }
      moments.add(Moment(
        title: title,
        subtitle: _fmt(day),
        assetIds: b.assets.map((a) => a.id).toList(),
        coverId: b.assets.first.id,
        when: day,
      ));
    }
    return moments;
  }
}
