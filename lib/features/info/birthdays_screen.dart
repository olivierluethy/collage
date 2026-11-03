import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../services/contacts_birthdays.dart';
import '../../services/occasion_service.dart';
import '../../state/occasions.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import 'occasion_settings.dart';

final contactsBirthdaysProvider = Provider((_) => const ContactsBirthdays());

/// Birthdays the app may suggest a collage for, a week ahead. Typed in by
/// hand (the default, no permission) or, after an explicit opt-in, imported
/// from contacts. Everything stays on the device.
class BirthdaysScreen extends ConsumerWidget {
  const BirthdaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final list = ref.watch(birthdaysProvider);
    final connected = ref.watch(occasionPrefsProvider.select((p) => p.contactsConnected));
    final imported = list.where((b) => b.fromContacts).length;

    return Scaffold(
      appBar: AppBar(title: Text(l.t('bdayTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBirthdayEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.t('bdayAdd')),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.huge + Space.xl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
            child: Text(l.t('bdayIntro'), style: context.text.bodyMd.copyWith(color: c.textMid)),
          ),
          if (!connected)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: ActionCard(
                icon: Icons.contacts_outlined,
                title: l.t('bdayImport'),
                subtitle: l.t('bdayImportHint'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ContactsImportScreen()),
                ),
              ),
            )
          else ...[
            SettingsSwitchRow(
              icon: Icons.contacts_outlined,
              title: l.t('bdayContactsConnected'),
              subtitle: l.a('bdayContactsConnectedHint', {'count': '$imported'}),
              value: true,
              onChanged: (_) => _disconnect(context, ref),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.only(left: Space.xxxl + Space.md),
                child: TextButton.icon(
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(l.t('bdayRefresh')),
                  onPressed: () => importFromContacts(context, ref),
                ),
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                children: [
                  Icon(Icons.cake_outlined, size: 40, color: c.textLo),
                  const SizedBox(height: Space.md),
                  Text(l.t('bdayEmpty'),
                      style: context.text.bodyMd.copyWith(color: c.textMid), textAlign: TextAlign.center),
                ],
              ),
            )
          else
            for (final b in list)
              ListTile(
                minTileHeight: 56,
                leading: Icon(Icons.cake_outlined, color: c.textMid),
                title: Text(b.name, style: context.text.bodyLg),
                subtitle: Text(
                  [
                    birthdayDateLabel(context, b),
                    if (b.fromContacts) l.t('bdayFromContacts'),
                  ].join(' · '),
                  style: context.text.caption.copyWith(color: c.textMid),
                ),
                trailing: Icon(Icons.edit_outlined, color: c.textLo, size: 20),
                onTap: () => showBirthdayEditor(context, ref, existing: b),
              ),
        ],
      ),
    );
  }

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await confirmDestructive(
      context,
      title: l.t('bdayDisconnectTitle'),
      message: l.t('bdayDisconnectBody'),
      confirmLabel: l.t('bdayDisconnect'),
      cancelLabel: l.t('cancel'),
    );
    if (!ok) return;
    ref.read(birthdaysProvider.notifier).removeImported();
    ref.read(occasionPrefsProvider.notifier).setContactsConnected(false);
    if (context.mounted) showAppSnack(context, l.t('bdayDisconnected'), kind: SnackKind.success);
  }
}

/// "14 March" or "14 March 1990" in the user's language.
String birthdayDateLabel(BuildContext context, Birthday b) {
  final locale = Localizations.localeOf(context).toString();
  final d = DateTime(b.year ?? 2000, b.month, b.day);
  try {
    return b.year == null ? DateFormat.MMMMd(locale).format(d) : DateFormat.yMMMMd(locale).format(d);
  } catch (_) {
    return b.year == null ? DateFormat.MMMMd().format(d) : DateFormat.yMMMMd().format(d);
  }
}

/// Imports (or refreshes) contact birthdays, then reports how many arrived.
/// Only called after the explanation screen.
Future<bool> importFromContacts(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final svc = ref.read(contactsBirthdaysProvider);
  final access = await svc.requestAccess();
  switch (access) {
    case ContactsAccess.denied:
      showAppSnackOn(messenger, l.t('bdayAccessDenied'));
      return false;
    case ContactsAccess.blocked:
      showAppSnackOn(
        messenger,
        l.t('bdayAccessBlocked'),
        actionLabel: l.t('bdayOpenSettings'),
        onAction: svc.openSettings,
      );
      return false;
    case ContactsAccess.granted:
      break;
  }
  try {
    final found = await svc.read();
    final n = ref.read(birthdaysProvider.notifier).replaceImported(found);
    ref.read(occasionPrefsProvider.notifier).setContactsConnected(true);
    showAppSnackOn(messenger, l.a('bdayImported', {'count': '$n'}), kind: SnackKind.success);
    return true;
  } catch (_) {
    showAppSnackOn(messenger, l.t('bdayImportFailed'), kind: SnackKind.error);
    return false;
  }
}

/// Explains, before any permission prompt, what importing from contacts
/// does and doesn't do. Only "Continue" asks the OS for access.
class ContactsImportScreen extends ConsumerStatefulWidget {
  const ContactsImportScreen({super.key});

  @override
  ConsumerState<ContactsImportScreen> createState() => _ContactsImportScreenState();
}

class _ContactsImportScreenState extends ConsumerState<ContactsImportScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: c.amber, size: 22),
              const SizedBox(width: Space.md),
              Expanded(child: Text(text, style: context.text.bodyLg)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.xl),
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: c.surfaceHigh, shape: BoxShape.circle),
                child: Icon(Icons.contacts_outlined, size: 40, color: c.textMid),
              ),
            ),
            const SizedBox(height: Space.xl),
            Text(l.t('bdayImportTitle'), style: context.text.displayMd, textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            Text(l.t('bdayImportWhy'),
                style: context.text.bodyLg.copyWith(color: c.textMid), textAlign: TextAlign.center),
            const SizedBox(height: Space.xl),
            point(Icons.visibility_outlined, l.t('bdayImportPointRead')),
            point(Icons.phone_iphone_rounded, l.t('bdayImportPointDevice')),
            point(Icons.link_off_rounded, l.t('bdayImportPointDisconnect')),
            const SizedBox(height: Space.lg),
            PrimaryButton(
              label: l.t('bdayImportContinue'),
              busy: _busy,
              onPressed: () async {
                setState(() => _busy = true);
                final ok = await importFromContacts(context, ref);
                if (!mounted) return;
                setState(() => _busy = false);
                if (ok && context.mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: Space.sm),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.t('bdayImportNotNow')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add / edit sheet: name, day and month, optional year.
Future<void> showBirthdayEditor(BuildContext context, WidgetRef ref, {Birthday? existing}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _BirthdayEditor(existing: existing),
    );

class _BirthdayEditor extends ConsumerStatefulWidget {
  const _BirthdayEditor({this.existing});
  final Birthday? existing;

  @override
  ConsumerState<_BirthdayEditor> createState() => _BirthdayEditorState();
}

class _BirthdayEditorState extends ConsumerState<_BirthdayEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _year = TextEditingController(text: widget.existing?.year?.toString() ?? '');
  late int _month = widget.existing?.month ?? DateTime.now().month;
  late int _day = widget.existing?.day ?? DateTime.now().day;
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    _year.dispose();
    super.dispose();
  }

  /// Days in [_month], allowing 29 February.
  int get _maxDay => DateTime(2000, _month + 1, 0).day;

  int? get _parsedYear {
    final y = int.tryParse(_year.text.trim());
    if (y == null) return null;
    return (y >= 1900 && y <= DateTime.now().year) ? y : null;
  }

  bool get _yearInvalid => _year.text.trim().isNotEmpty && _parsedYear == null;

  void _save() {
    setState(() => _tried = true);
    final name = _name.text.trim();
    if (name.isEmpty || _yearInvalid) return;
    final n = ref.read(birthdaysProvider.notifier);
    final year = _parsedYear;
    final e = widget.existing;
    if (e == null) {
      n.add(name: name, month: _month, day: _day, year: year);
    } else {
      n.update(e.copyWith(name: name, month: _month, day: _day, year: year, clearYear: year == null));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final locale = Localizations.localeOf(context).toString();
    String monthName(int m) {
      try {
        return DateFormat.MMMM(locale).format(DateTime(2000, m));
      } catch (_) {
        return DateFormat.MMMM().format(DateTime(2000, m));
      }
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Space.xl,
          0,
          Space.xl,
          Space.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.existing == null ? l.t('bdayAdd') : l.t('bdayEdit'), style: context.text.titleMd),
              const SizedBox(height: Space.lg),
              TextField(
                controller: _name,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l.t('bdayName'),
                  errorText: _tried && _name.text.trim().isEmpty ? l.t('bdayNameMissing') : null,
                ),
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      initialValue: _day.clamp(1, _maxDay),
                      decoration: InputDecoration(labelText: l.t('bdayDay')),
                      items: [
                        for (var d = 1; d <= _maxDay; d++) DropdownMenuItem(value: d, child: Text('$d')),
                      ],
                      onChanged: (v) => setState(() => _day = v ?? _day),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      initialValue: _month,
                      decoration: InputDecoration(labelText: l.t('bdayMonth')),
                      items: [
                        for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(monthName(m))),
                      ],
                      onChanged: (v) => setState(() {
                        _month = v ?? _month;
                        _day = _day.clamp(1, _maxDay);
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: _year,
                keyboardType: TextInputType.number,
                maxLength: 4,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.t('bdayYear'),
                  helperText: l.t('bdayYearHint'),
                  counterText: '',
                  errorText: _yearInvalid ? l.t('bdayYearInvalid') : null,
                ),
              ),
              const SizedBox(height: Space.xl),
              Row(
                children: [
                  if (widget.existing != null)
                    TextButton(
                      onPressed: () {
                        final removed = widget.existing!;
                        final notifier = ref.read(birthdaysProvider.notifier)..remove(removed.id);
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);
                        showAppSnackOn(
                          messenger,
                          l.a('bdayRemoved', {'name': removed.name}),
                          actionLabel: l.t('undo'),
                          onAction: () => notifier.restore(removed),
                        );
                      },
                      child: Text(l.t('delete'), style: TextStyle(color: c.danger)),
                    ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(l.t('cancel'))),
                  const SizedBox(width: Space.sm),
                  PrimaryButton(expand: false, label: l.t('save'), onPressed: _save),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
