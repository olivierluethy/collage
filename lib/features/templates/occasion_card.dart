import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/template_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../services/occasion_service.dart';
import '../../state/occasions.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../flow.dart';
import 'template_tile.dart';

/// The occasion's name for display; a birthday reads "Mia's birthday".
String occasionTitle(AppLocalizations l, OccasionDate o) => o.birthday != null
    ? l.a('bdayOf', {'name': o.birthday!.name})
    : l.t(o.occasion.nameKey);

/// One plain sentence about when [o] is, relative to [today]:
/// "Halloween is on Friday", "Mia's birthday is tomorrow". Approximate dates
/// (Eid) never name a weekday.
String occasionHeadline(AppLocalizations l, OccasionDate o, DateTime today) {
  final days = o.daysFrom(today);
  final b = o.birthday;
  if (b != null) {
    final args = {'name': b.name};
    if (days <= 0) return l.a('bdayToday', args);
    if (days == 1) return l.a('bdayTomorrow', args);
    if (days < 7) return l.a('bdayOnDay', {...args, 'day': _weekday(l, o.date)});
    return l.a('bdayInDays', {...args, 'count': '$days'});
  }
  final args = {'occasion': l.t(o.occasion.nameKey)};
  if (o.occasion.approximate && days != 0) {
    return days < 0 ? l.a('occJustWas', args) : l.a('occComingUp', args);
  }
  if (days < 0) return l.a('occYesterday', args);
  if (days == 0) return l.a('occToday', args);
  if (days == 1) return l.a('occTomorrow', args);
  if (days < 7) return l.a('occOnDay', {...args, 'day': _weekday(l, o.date)});
  return l.a('occInDays', {...args, 'count': '$days'});
}

/// The second line: an open invitation, or — when the user already made one
/// this season — a neutral "another one". Never a reproach.
String occasionPrompt(AppLocalizations l, OccasionSuggestion s) {
  if (!s.madeAlready) return l.t('occWantToMake');
  final b = s.date.birthday;
  return b != null
      ? l.a('bdayMakeAnother', {'name': b.name})
      : l.a('occMakeAnother', {'occasion': l.t(s.occasion.nameKey)});
}

String _weekday(AppLocalizations l, DateTime d) {
  try {
    return DateFormat.EEEE(l.locale.toString()).format(d);
  } catch (_) {
    return DateFormat.EEEE().format(d);
  }
}

IconData _iconFor(OccasionDate o) => switch (o.id) {
      'birthday' => Icons.cake_rounded,
      'halloween' => Icons.nightlight_round,
      'christmas' => Icons.park_rounded,
      'valentines' || 'mothers_day' => Icons.favorite_rounded,
      'new_year' || 'lunar_new_year' || 'national_day' => Icons.celebration_rounded,
      'easter' => Icons.egg_rounded,
      'diwali' => Icons.light_mode_rounded,
      'eid_al_fitr' || 'eid_al_adha' => Icons.mode_night_rounded,
      _ => Icons.event_rounded,
    };

/// The single, compact, dismissable occasion card (Templates tab and the New
/// collage sheet). Renders nothing when there is no suggestion.
///
/// [onOpen] defaults to the occasion flow; the New collage sheet passes its
/// own so it can close itself first.
class OccasionCard extends ConsumerWidget {
  const OccasionCard({super.key, this.onOpen, this.padding = const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0)});

  final void Function(OccasionDate occasion)? onOpen;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(occasionSuggestionProvider);
    if (s == null) return const SizedBox.shrink();
    final l = context.l10n;
    final c = context.colors;
    final today = ref.watch(clockProvider)();
    final headline = occasionHeadline(l, s.date, today);
    final prompt = occasionPrompt(l, s);

    return Padding(
      padding: padding,
      child: Material(
        color: c.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                hint: l.t('occOpenHint'),
                child: InkWell(
                  onTap: () => (onOpen ?? (o) => openOccasion(context, o))(s.date),
                  child: MergeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, Space.sm),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c.amberTint,
                              borderRadius: BorderRadius.circular(Radii.control),
                            ),
                            child: Icon(_iconFor(s.date), color: c.amber, size: 22),
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(headline, style: context.text.labelLg.copyWith(color: c.textHi)),
                                const SizedBox(height: 2),
                                Text(prompt, style: context.text.bodyMd.copyWith(color: c.textMid)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: l.t('occDismiss'),
              icon: const Icon(Icons.close_rounded),
              color: c.textLo,
              onPressed: () => ref.read(dismissedOccasionsProvider.notifier).dismiss(s.date.key),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fast occasion flow, step 1: pick a matching template.
Future<void> openOccasion(BuildContext context, OccasionDate occasion) =>
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OccasionTemplatesScreen(occasion: occasion)),
    );

/// The templates made for one occasion (its own designs and invitations
/// first, then related styles). Tapping one opens the editor with the
/// occasion recorded on the collage; photos are added there.
class OccasionTemplatesScreen extends ConsumerStatefulWidget {
  const OccasionTemplatesScreen({super.key, required this.occasion});
  final OccasionDate occasion;

  @override
  ConsumerState<OccasionTemplatesScreen> createState() => _OccasionTemplatesScreenState();
}

class _OccasionTemplatesScreenState extends ConsumerState<OccasionTemplatesScreen> {
  bool _invitations = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final all = TemplateCatalog.withAnyTag(widget.occasion.occasion.templateTags);
    final invites = [
      for (final t in all)
        if (t.tags.contains(TemplateCatalog.invitationTag)) t,
    ];
    final shown = _invitations ? invites : all;

    return Scaffold(
      appBar: AppBar(title: Text(occasionTitle(l, widget.occasion))),
      body: LayoutBuilder(
        builder: (context, box) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.sm),
                child: Text(l.t('occPickIntro'), style: context.text.bodyMd.copyWith(color: c.textMid)),
              ),
            ),
            if (invites.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Wrap(
                    spacing: Space.sm,
                    children: [
                      ChoiceChip(
                        label: Text(l.t('templatesAll')),
                        selected: !_invitations,
                        onSelected: (_) => setState(() => _invitations = false),
                      ),
                      ChoiceChip(
                        label: Text(l.t('tplCatInvitations')),
                        selected: _invitations,
                        onSelected: (_) => setState(() => _invitations = true),
                      ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.all(Space.lg),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: templateGridColumns(box.maxWidth),
                  mainAxisSpacing: Space.sm,
                  crossAxisSpacing: Space.sm,
                  childAspectRatio: 0.7,
                ),
                itemCount: shown.length,
                itemBuilder: (_, i) => TemplateTile(
                  template: shown[i],
                  onTap: () => openTemplate(context, ref, shown[i], occasionId: widget.occasion.id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
