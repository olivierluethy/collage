import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
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

  static const _pages = [
    _Page(
      icon: Icons.dashboard_customize_rounded,
      title: 'Make beautiful collages',
      body: 'Pick your photos, choose a layout, and arrange them just how you '
          'like. Everything is labelled — no guesswork.',
    ),
    _Page(
      icon: Icons.swap_horiz_rounded,
      title: 'You decide what goes where',
      body: 'Unlike other apps, you choose exactly which photo fills each spot. '
          'Tap a slot to set its photo, or drag one photo onto another to swap them.',
    ),
    _Page(
      icon: Icons.auto_awesome_rounded,
      title: 'Add your personal touch',
      body: 'Stickers, text, emoji, shapes, GIFs and backgrounds — move, resize '
          'and rotate anything with your fingers. Then save it to your gallery.',
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
                child: const Text('Skip'),
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
                    color: active ? AppColors.amber : AppColors.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: PrimaryButton(
                label: last ? 'Get started' : 'Next',
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
  final String title;
  final String body;

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
            decoration: const BoxDecoration(
              color: AppColors.amberTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: AppColors.amber),
          ),
          const SizedBox(height: Space.xxl),
          Text(title, style: AppText.displayMd, textAlign: TextAlign.center),
          const SizedBox(height: Space.md),
          Text(body, style: AppText.bodyLg.copyWith(color: AppColors.textMid),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
