import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/permission_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/mini_collage.dart';
import '../../widgets/ui.dart';
import '../home/home_screen.dart';
import '../info/settings_pickers.dart';

/// First-run onboarding: shows (rather than tells) what the app makes and its
/// one big advantage — you choose which photo goes in which slot — then hands
/// over straight into the first collage. Two pages of "what", one of "go".
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _busy = false;

  static const _count = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Leave onboarding for Home; with [create] the new-collage flow opens on
  /// arrival so the user lands in the photo picker.
  Future<void> _finish({bool create = false}) async {
    await ref.read(prefsProvider).setOnboardingDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(startCreating: create)),
    );
  }

  /// Ask for gallery access right here, where the reason was just explained.
  /// Granted → straight into the picker; declined → Home, where the guided
  /// permission screen takes over the next time the user creates a collage.
  Future<void> _pickPhotos() async {
    setState(() => _busy = true);
    final access = await ref.read(permissionServiceProvider).request();
    if (!mounted) return;
    setState(() => _busy = false);
    await _finish(create: access.usable);
  }

  void _next() => _controller.nextPage(duration: Motion.slow, curve: Motion.standard);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final last = _page == _count - 1;
    final code = activeLanguageCode(context, ref);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, 0),
              child: Row(
                children: [
                  // Language first: someone who can't read the copy can still
                  // switch it before reading anything else.
                  ActionChip(
                    avatar: Icon(Icons.language_rounded, size: 18, color: context.colors.textMid),
                    label: Text(languageName(code) ?? code.toUpperCase()),
                    tooltip: l.t('language'),
                    onPressed: () => showLanguagePicker(context, ref),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: Motion.base,
                    opacity: last ? 0 : 1,
                    child: TextButton(
                      onPressed: last ? null : () => _finish(),
                      child: Text(l.t('skip')),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Page(
                    art: const MiniCollage(),
                    title: l.t('obTitle1'),
                    body: l.t('obBody1'),
                  ),
                  _Page(
                    art: const MiniCollage(swap: true),
                    title: l.t('obTitle2'),
                    body: l.t('obBody2'),
                  ),
                  _Page(
                    art: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: context.colors.amberTint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.photo_library_rounded, size: 52, color: context.colors.amber),
                    ),
                    title: l.t('obTitleStart'),
                    body: l.t('obBodyStart'),
                    note: l.t('obPrivacyNote'),
                  ),
                ],
              ),
            ),
            Semantics(
              label: l.a('obPageOf', {'page': '${_page + 1}', 'count': '$_count'}),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_count, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: Motion.base,
                    curve: Motion.standard,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? context.colors.amber : context.colors.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.md),
              child: last
                  ? Column(
                      children: [
                        PrimaryButton(
                          label: l.t('obPickPhotos'),
                          icon: Icons.photo_library_rounded,
                          busy: _busy,
                          onPressed: _pickPhotos,
                        ),
                        const SizedBox(height: Space.sm),
                        SizedBox(
                          height: Sizes.touchTarget,
                          child: TextButton(
                            onPressed: _busy ? null : () => _finish(),
                            child: Text(l.t('obLookAround')),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        PrimaryButton(
                          label: l.t('next'),
                          icon: Icons.arrow_forward_rounded,
                          onPressed: _next,
                        ),
                        // Same height as the last page's second button, so the
                        // primary button never jumps between pages.
                        const SizedBox(height: Space.sm + Sizes.touchTarget),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.art, required this.title, required this.body, this.note});
  final Widget art;
  final String title;
  final String body;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              art,
              const SizedBox(height: Space.xxl),
              Text(title, style: context.text.displayLg, textAlign: TextAlign.center),
              const SizedBox(height: Space.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(body,
                    style: context.text.bodyLg.copyWith(color: c.textMid),
                    textAlign: TextAlign.center),
              ),
              if (note != null) ...[
                const SizedBox(height: Space.lg),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 16, color: c.success),
                    const SizedBox(width: Space.xs),
                    Flexible(
                      child: Text(note!,
                          style: context.text.caption.copyWith(color: c.textMid),
                          textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
