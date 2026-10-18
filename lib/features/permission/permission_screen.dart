import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/permission_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
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
                decoration: BoxDecoration(
                  color: context.colors.amberTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.photo_library_rounded,
                    size: 44, color: context.colors.amber),
              ),
              const SizedBox(height: Space.xl),
              Text(context.l10n.t('permissionTitle'), style: context.text.displayMd),
              const SizedBox(height: Space.md),
              Text(
                context.l10n.t('permissionBody'),
                style: context.text.bodyLg.copyWith(color: context.colors.textMid),
              ),
              if (blocked) ...[
                const SizedBox(height: Space.lg),
                _Notice(
                  color: context.colors.warning,
                  text: context.l10n.t('permissionBlockedSnack'),
                ),
              ],
              if (permanent) ...[
                const SizedBox(height: Space.lg),
                _Notice(
                  color: context.colors.danger,
                  text: context.l10n.t('permissionOffSnack'),
                ),
              ],
              const Spacer(),
              if (permanent)
                PrimaryButton(
                  label: context.l10n.t('openSettings'),
                  icon: Icons.settings_rounded,
                  onPressed: () => _perm.openSettings(),
                )
              else
                PrimaryButton(
                  label: blocked
                      ? context.l10n.t('allowAccess')
                      : context.l10n.t('allowPhotoAccess'),
                  icon: Icons.check_rounded,
                  busy: _busy,
                  onPressed: _request,
                ),
              const SizedBox(height: Space.sm),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(context.l10n.t('notNow')),
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
          Expanded(child: Text(text, style: context.text.bodyMd.copyWith(color: context.colors.textHi))),
        ],
      ),
    );
  }
}
