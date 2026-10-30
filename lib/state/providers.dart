import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/collage_project.dart';
import '../models/remote_catalog.dart';
import '../services/ai_collage_service.dart';
import '../services/backup_service.dart';
import '../services/book_service.dart';
import '../services/catalog_service.dart';
import '../services/draft_service.dart';
import '../services/export_service.dart';
import '../services/gallery_service.dart';
import '../services/giphy_service.dart';
import '../services/moments_service.dart';
import '../services/permission_service.dart';
import '../services/prefs_service.dart';
import '../services/user_template_service.dart';
import '../services/vision_service.dart';

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
final momentsServiceProvider =
    Provider((ref) => MomentsService(ref.read(galleryServiceProvider)));

/// Loads and registers the optional remote font / sticker catalogs.
final catalogServiceProvider =
    Provider((ref) => CatalogService(ref.read(prefsProvider)));

/// The remote catalogs, fetched once. Watching this kicks off the load and
/// rebuilds the app when extra fonts / stickers arrive; an empty result simply
/// leaves the bundled sets in place.
final remoteCatalogsProvider = FutureProvider<RemoteCatalogs>(
  (ref) => ref.read(catalogServiceProvider).load(),
);

/// Location + date "moments" suggested on the Discover tab. autoDispose so it
/// re-scans when the user returns to Discover.
final momentsProvider = FutureProvider.autoDispose<List<Moment>>(
  (ref) => ref.read(momentsServiceProvider).discover(),
);

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

  /// Move a collage to the trash.
  Future<void> remove(String id) async {
    await ref.read(draftServiceProvider).delete(id);
    await reload();
    ref.invalidate(trashProvider);
  }

  Future<void> rename(String id, String title) async {
    await ref.read(draftServiceProvider).rename(id, title);
    await reload();
  }

  Future<void> duplicate(String id, {required String title}) async {
    await ref.read(draftServiceProvider).duplicate(id, newId: const Uuid().v4(), title: title);
    await reload();
  }
}

final userTemplateServiceProvider = Provider((_) => const UserTemplateService());

final backupServiceProvider = Provider((ref) => BackupService(ref.read(draftServiceProvider)));

/// The user's own templates (designs saved without photos).
final userTemplatesProvider =
    AsyncNotifierProvider<UserTemplatesNotifier, List<CollageProject>>(UserTemplatesNotifier.new);

class UserTemplatesNotifier extends AsyncNotifier<List<CollageProject>> {
  @override
  Future<List<CollageProject>> build() => ref.read(userTemplateServiceProvider).list();

  Future<void> reload() async {
    state = await AsyncValue.guard(() => ref.read(userTemplateServiceProvider).list());
  }

  Future<void> remove(String id) async {
    await ref.read(userTemplateServiceProvider).delete(id);
    await reload();
  }
}

/// Trashed collages with their deletion time, newest first.
final trashProvider =
    AsyncNotifierProvider<TrashNotifier, List<(CollageProject, int)>>(TrashNotifier.new);

class TrashNotifier extends AsyncNotifier<List<(CollageProject, int)>> {
  @override
  Future<List<(CollageProject, int)>> build() => ref.read(draftServiceProvider).listTrash();

  Future<void> reload() async {
    state = await AsyncValue.guard(() => ref.read(draftServiceProvider).listTrash());
  }

  Future<void> restore(String id) async {
    await ref.read(draftServiceProvider).restore(id);
    await reload();
    await ref.read(draftsProvider.notifier).reload();
  }

  Future<void> deleteForever(String id) async {
    await ref.read(draftServiceProvider).deleteForever(id);
    await reload();
  }

  Future<void> empty() async {
    await ref.read(draftServiceProvider).emptyTrash();
    await reload();
  }
}

final visionServiceProvider = Provider((_) => const VisionService());

final bookServiceProvider = Provider((_) => const BookService());

/// Photo books, most recently changed first.
final booksProvider = AsyncNotifierProvider<BooksNotifier, List<PhotoBook>>(BooksNotifier.new);

class BooksNotifier extends AsyncNotifier<List<PhotoBook>> {
  @override
  Future<List<PhotoBook>> build() => ref.read(bookServiceProvider).list();

  Future<void> save(PhotoBook book) async {
    await ref.read(bookServiceProvider).save(book);
    state = await AsyncValue.guard(() => ref.read(bookServiceProvider).list());
  }

  Future<void> remove(String id) async {
    await ref.read(bookServiceProvider).delete(id);
    state = await AsyncValue.guard(() => ref.read(bookServiceProvider).list());
  }
}
