import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

/// Where the user stands on photo-library access. Drives the guided
/// permission flow (rationale → request → recover).
enum GalleryAccess {
  granted, // full access
  limited, // iOS "selected photos" / Android partial
  denied, // can re-request
  permanentlyDenied, // must deep-link to system settings
  restricted, // parental controls etc.
}

extension GalleryAccessX on GalleryAccess {
  bool get usable => this == GalleryAccess.granted || this == GalleryAccess.limited;
}

/// Handles photo + save permissions correctly on Android (incl. Android 13+
/// READ_MEDIA_IMAGES) and iOS (NSPhotoLibrary*). photo_manager requests the
/// right platform permission; permission_handler detects permanent denial and
/// deep-links to settings.
class PermissionService {
  const PermissionService();

  Future<GalleryAccess> request() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    switch (state) {
      case PermissionState.authorized:
        return GalleryAccess.granted;
      case PermissionState.limited:
        return GalleryAccess.limited;
      case PermissionState.restricted:
        return GalleryAccess.restricted;
      case PermissionState.denied:
      case PermissionState.notDetermined:
        // Distinguish "denied once" from "don't ask again".
        final ph = await Permission.photos.status;
        if (ph.isPermanentlyDenied || ph.isRestricted) {
          return GalleryAccess.permanentlyDenied;
        }
        return GalleryAccess.denied;
    }
  }

  /// Check current access without prompting (best-effort).
  Future<GalleryAccess> current() async {
    final ph = await Permission.photos.status;
    if (ph.isGranted) return GalleryAccess.granted;
    if (ph.isLimited) return GalleryAccess.limited;
    if (ph.isPermanentlyDenied) return GalleryAccess.permanentlyDenied;
    if (ph.isRestricted) return GalleryAccess.restricted;
    return GalleryAccess.denied;
  }

  /// Open the OS settings page so the user can grant access after a permanent
  /// denial.
  Future<bool> openSettings() => openAppSettings();

  /// iOS: let the user extend the "selected photos" set.
  Future<void> presentLimited() => PhotoManager.presentLimited();
}
