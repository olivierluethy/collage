import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

/// Builds a "Rome · 12 June 2026" caption from the photos' own date and
/// location metadata.
class StampService {
  const StampService();

  /// Place (city, else region/country) and date (or date range) of
  /// [assetIds], formatted for [localeName]. Null when the photos carry
  /// neither.
  Future<String?> dateAndPlace(List<String> assetIds, {String? localeName}) async {
    DateTime? first, last;
    double? lat, lng;
    for (final id in assetIds) {
      final a = await AssetEntity.fromId(id);
      if (a == null) continue;
      final d = a.createDateTime;
      if (first == null || d.isBefore(first)) first = d;
      if (last == null || d.isAfter(last)) last = d;
      if (lat == null) {
        final ll = await a.latlngAsync();
        if (ll != null && (ll.latitude != 0 || ll.longitude != 0)) {
          lat = ll.latitude;
          lng = ll.longitude;
        }
      }
    }

    String? place;
    if (lat != null && lng != null) {
      try {
        final marks = await placemarkFromCoordinates(lat, lng);
        if (marks.isNotEmpty) {
          final m = marks.first;
          place = [m.locality, m.subAdministrativeArea, m.administrativeArea, m.country]
              .firstWhere((s) => s != null && s.isNotEmpty, orElse: () => null);
        }
      } catch (_) {
        // Offline or no geocoder: date only.
      }
    }

    String? date;
    if (first != null && last != null) {
      final fmt = DateFormat.yMMMMd(localeName);
      final sameDay = first.year == last.year && first.month == last.month && first.day == last.day;
      date = sameDay ? fmt.format(first) : '${fmt.format(first)} – ${fmt.format(last)}';
    }

    final parts = [?place, ?date];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
