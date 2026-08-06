import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/permission_service.dart';
import '../../state/providers.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// Plain-language rationale for photo access, then the native request. On
/// denial the user stays in a guided "we can't continue without this" state
/// with a re-request, and on permanent denial a deep link to system settings.
class PermissionScreen extends ConsumerStatefulWidget {
  const PermissionScreen({super.key});

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen> {
  GalleryAccess? _state;
  bool _busy = false;

  PermissionService get _perm => ref.read(permissionServiceProvider);

  Future<void> _request() async {
    setState(() => _busy = true);
    final result = await _perm.request();
    if (!mounted) return;
    setState(() {
      _state = result;
      _busy = false;
    });
    if (result.usable && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _state == GalleryAccess.denied;
    final permanent = _state == GalleryAccess.permanentlyDenied ||
        _state == GalleryAccess.restricted;

    return Scaffold(
      appBar: AppBar(leading: const CloseButton()),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.amberTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library_rounded,
                    size: 44, color: AppColors.amber),
              ),
              const SizedBox(height: Space.xl),
              Text('Let Collage see your photos', style: AppText.displayMd),
              const SizedBox(height: Space.md),
              Text(
                'To build a collage, Collage needs to open your photo library so '
                'you can pick the pictures you want. It also needs permission to '
                'save your finished collage back to your gallery.\n\n'
                'Allowing photo access also lets Collage read when and where your '
                'photos were taken, so it can suggest ready-made collages like '
                '"you were in Rome on 12 Jun". \n\n'
                'Your photos stay on your device. Nothing is uploaded.',
                style: AppText.bodyLg.copyWith(color: AppColors.textMid),
              ),
              if (blocked) ...[
                const SizedBox(height: Space.lg),
                _Notice(
                  color: AppColors.warning,
                  text: 'Collage can\'t continue without photo access. Please '
                      'tap "Allow access" and choose Allow.',
                ),
              ],
              if (permanent) ...[
                const SizedBox(height: Space.lg),
                _Notice(
                  color: AppColors.danger,
                  text: 'Photo access is turned off. Open Settings, then turn on '
                      'Photos for Collage, and come back.',
                ),
              ],
              const Spacer(),
              if (permanent)
                PrimaryButton(
                  label: 'Open Settings',
                  icon: Icons.settings_rounded,
                  onPressed: () => _perm.openSettings(),
                )
              else
                PrimaryButton(
                  label: blocked ? 'Allow access' : 'Allow photo access',
                  icon: Icons.check_rounded,
                  busy: _busy,
                  onPressed: _request,
                ),
              const SizedBox(height: Space.sm),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 20),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(text, style: AppText.bodyMd.copyWith(color: AppColors.textHi))),
        ],
      ),
    );
  }
}
