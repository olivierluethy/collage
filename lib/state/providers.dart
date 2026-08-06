import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collage_project.dart';
import '../services/ai_collage_service.dart';
import '../services/draft_service.dart';
import '../services/export_service.dart';
import '../services/gallery_service.dart';
import '../services/giphy_service.dart';
import '../services/permission_service.dart';
import '../services/prefs_service.dart';

/// Overridden in main() once SharedPreferences has loaded.
final prefsProvider = Provider<PrefsService>((ref) {
  throw UnimplementedError('prefsProvider must be overridden in main()');
});

final permissionServiceProvider = Provider((_) => const PermissionService());
final galleryServiceProvider = Provider((_) => const GalleryService());
final draftServiceProvider = Provider((_) => const DraftService());
final exportServiceProvider = Provider((_) => const ExportService());
final giphyServiceProvider = Provider((_) => const GiphyService());
final aiServiceProvider = Provider((_) => const AiCollageService());

/// The "My Collages" library. Reloads on demand via [reload].
final draftsProvider =
    AsyncNotifierProvider<DraftsNotifier, List<CollageProject>>(DraftsNotifier.new);

class DraftsNotifier extends AsyncNotifier<List<CollageProject>> {
  @override
  Future<List<CollageProject>> build() =>
      ref.read(draftServiceProvider).list();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(draftServiceProvider).list());
  }

  Future<void> remove(String id) async {
    await ref.read(draftServiceProvider).delete(id);
    await reload();
  }
}
