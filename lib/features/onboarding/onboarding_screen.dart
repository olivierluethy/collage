import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import '../home/home_screen.dart';

/// First-run onboarding that "sells the need": explains, in plain language,
/// what the app does and its one big advantage — you choose which photo goes
/// in which slot.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // Each page stores its l10n key; text is resolved against the live locale in
  // [_Page] so the copy follows the selected app language.
  static const _pages = [
    _Page(
      icon: Icons.dashboard_customize_rounded,
      title: 'obTitle1',
      body: 'obBody1',
    ),
    _Page(
      icon: Icons.swap_horiz_rounded,
      title: 'obTitle2',
      body: 'obBody2',
    ),
    _Page(
      icon: Icons.auto_awesome_rounded,
      title: 'obTitle3',
      // No GIF mention: GIF search only exists in builds with a Giphy key.
      body: 'obBody3',
    ),
  ];

  Future<void> _finish() async {
    await ref.read(prefsProvider).setOnboardingDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(context.l10n.t('skip')),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: _pages,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: Motion.fast,
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
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: PrimaryButton(
                label: last ? context.l10n.t('getStarted') : context.l10n.t('next'),
                icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                onPressed: () {
                  if (last) {
                    _finish();
                  } else {
                    _controller.nextPage(duration: Motion.base, curve: Motion.standard);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title; // l10n key
  final String body; // l10n key

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: context.colors.amberTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: context.colors.amber),
          ),
          const SizedBox(height: Space.xxl),
          Text(context.l10n.t(title), style: context.text.displayMd, textAlign: TextAlign.center),
          const SizedBox(height: Space.md),
          Text(context.l10n.t(body),
              style: context.text.bodyLg.copyWith(color: context.colors.textMid),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
