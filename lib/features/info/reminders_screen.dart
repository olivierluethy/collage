import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/occasions.dart';
import '../../state/reminders.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import 'occasion_settings.dart';

/// Reminders: local notifications before occasions and birthdays. Off by
/// default; the OS permission is only requested when the user turns the
/// master switch on, and turning it off cancels everything scheduled.
/// Suggestions in the app work the same either way.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  bool _busy = false;

  Future<void> _setMaster(bool on) async {
    final notifier = ref.read(occasionPrefsProvider.notifier);
    final svc = ref.read(reminderServiceProvider);
    final l = context.l10n;
    if (!on) {
      notifier.setRemindersOn(false);
      await svc.cancelAll();
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final granted = await svc.requestPermission();
    if (!mounted) return;
    setState(() => _busy = false);
    if (granted) {
      notifier.setRemindersOn(true);
      showAppSnackOn(messenger, l.t('remTurnedOn'), kind: SnackKind.success);
    } else {
      showAppSnackOn(messenger, l.t('remPermissionDenied'));
    }
  }

  /// Export notifications stand on their own: they don't need the reminder
  /// switch, but they do need the OS permission, asked for only now.
  Future<void> _setExports(bool on) async {
    final notifier = ref.read(occasionPrefsProvider.notifier);
    if (!on) {
      notifier.setNotifyExports(false);
      return;
    }
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final granted = await ref.read(reminderServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() => _busy = false);
    if (granted) {
      notifier.setNotifyExports(true);
    } else {
      showAppSnackOn(messenger, l.t('remPermissionDenied'));
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final p = ref.read(occasionPrefsProvider);
    final minutes = start ? p.quietStart : p.quietEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null) return;
    final m = picked.hour * 60 + picked.minute;
    ref.read(occasionPrefsProvider.notifier).setQuietHours(start: start ? m : null, end: start ? null : m);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final p = ref.watch(occasionPrefsProvider);
    final on = p.remindersOn;
    final loc = MaterialLocalizations.of(context);
    final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
    String time(int m) =>
        loc.formatTimeOfDay(TimeOfDay(hour: m ~/ 60, minute: m % 60), alwaysUse24HourFormat: use24);

    Widget group(String title, List<Widget> rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.sm),
              child: Text(title, style: context.text.labelMd.copyWith(color: c.textMid)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Material(
                color: c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.card),
                  side: BorderSide(color: c.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) Divider(height: 1, indent: 56, color: c.line),
                      rows[i],
                    ],
                  ],
                ),
              ),
            ),
          ],
        );

    Widget choice(ReminderFrequency f, String label) => RadioListTile<ReminderFrequency>(
          value: f,
          enabled: on,
          title: Text(label, style: context.text.bodyLg.copyWith(color: on ? c.textHi : c.textDisabled)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.t('remTitle'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: Text(l.t('remIntro'), style: context.text.bodyMd.copyWith(color: c.textMid)),
          ),
          const SizedBox(height: Space.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Material(
              color: on ? c.amberTint : c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.card),
                side: BorderSide(color: on ? c.amber : c.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: SettingsSwitchRow(
                icon: Icons.notifications_none_rounded,
                title: l.t('remMaster'),
                subtitle: on ? l.t('remMasterOnHint') : l.t('remMasterOffHint'),
                value: on,
                enabled: !_busy,
                onChanged: _setMaster,
              ),
            ),
          ),
          group(l.t('remAbout'), [
            SettingsSwitchRow(
              icon: Icons.event_rounded,
              title: l.t('remOccasions'),
              subtitle: l.t('remOccasionsHint'),
              value: p.remindOccasions,
              enabled: on,
              onChanged: ref.read(occasionPrefsProvider.notifier).setRemindOccasions,
            ),
            SettingsSwitchRow(
              icon: Icons.cake_outlined,
              title: l.t('remBirthdays'),
              subtitle: l.t('remBirthdaysHint'),
              value: p.remindBirthdays,
              enabled: on,
              onChanged: ref.read(occasionPrefsProvider.notifier).setRemindBirthdays,
            ),
            SettingsSwitchRow(
              icon: Icons.photo_album_outlined,
              title: l.t('remMemories'),
              subtitle: l.t('remMemoriesHint'),
              value: p.remindMemories,
              enabled: on,
              onChanged: ref.read(occasionPrefsProvider.notifier).setRemindMemories,
            ),
          ]),
          group(l.t('remHowOften'), [
            RadioGroup<ReminderFrequency>(
              groupValue: p.frequency,
              onChanged: (f) {
                if (on && f != null) ref.read(occasionPrefsProvider.notifier).setFrequency(f);
              },
              child: Column(
                children: [
                  choice(ReminderFrequency.weekly1, l.t('remWeekly1')),
                  choice(ReminderFrequency.weekly2, l.t('remWeekly2')),
                  choice(ReminderFrequency.monthly1, l.t('remMonthly1')),
                ],
              ),
            ),
          ]),
          group(l.t('remQuietHours'), [
            ListTile(
              enabled: on,
              minTileHeight: 56,
              leading: Icon(Icons.bedtime_outlined, color: on ? c.textMid : c.textDisabled),
              title: Text(l.t('remQuietFrom'), style: context.text.bodyLg),
              trailing: SpecChip(time(p.quietStart), active: on),
              onTap: () => _pickTime(start: true),
            ),
            ListTile(
              enabled: on,
              minTileHeight: 56,
              leading: Icon(Icons.wb_sunny_outlined, color: on ? c.textMid : c.textDisabled),
              title: Text(l.t('remQuietUntil'), style: context.text.bodyLg),
              trailing: SpecChip(time(p.quietEnd), active: on),
              onTap: () => _pickTime(start: false),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, 0),
            child: Text(l.t('remTimezoneNote'), style: context.text.caption.copyWith(color: c.textLo)),
          ),
          group(l.t('remOther'), [
            SettingsSwitchRow(
              icon: Icons.download_done_rounded,
              title: l.t('remExports'),
              subtitle: l.t('remExportsHint'),
              value: p.notifyExports,
              enabled: !_busy,
              onChanged: _setExports,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, 0),
            child: Text(l.t('remPrivacyNote'), style: context.text.caption.copyWith(color: c.textLo)),
          ),
        ],
      ),
    );
  }
}
