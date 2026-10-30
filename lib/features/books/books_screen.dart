import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../services/book_service.dart';
import '../../services/export_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';

/// The user's photo books: each one an ordered set of saved collages that
/// exports as a multi-page PDF, one collage per page.
class BooksScreen extends ConsumerWidget {
  const BooksScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.t('newBook')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(hintText: context.l10n.t('bookTitle')),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text(context.l10n.t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(dialog, ctrl.text), child: Text(context.l10n.t('save'))),
        ],
      ),
    );
    ctrl.dispose();
    final t = title?.trim();
    if (t == null || t.isEmpty || !context.mounted) return;
    final book = PhotoBook(id: const Uuid().v4(), title: t, collageIds: [], updatedAt: 0);
    await ref.read(booksProvider.notifier).save(book);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookScreen(book: book)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('booksTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.l10n.t('newBook')),
      ),
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e', style: context.text.bodyMd)),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.menu_book_rounded,
                title: context.l10n.t('noBooksTitle'),
                message: context.l10n.t('noBooksMessage'),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final b = list[i];
                  return ListTile(
                    leading: const Icon(Icons.menu_book_rounded),
                    title: Text(b.title),
                    subtitle: Text(context.l10n.a('bookPages', {'count': '${b.collageIds.length}'})),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => BookScreen(book: b)),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// One photo book: reorder, add and remove pages, export as PDF.
class BookScreen extends ConsumerStatefulWidget {
  const BookScreen({super.key, required this.book});
  final PhotoBook book;

  @override
  ConsumerState<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends ConsumerState<BookScreen> {
  late final PhotoBook _book = widget.book;
  bool _busy = false;

  Future<void> _persist() => ref.read(booksProvider.notifier).save(_book);

  Future<void> _addPages(List<CollageProject> all) async {
    final chosen = <String>{};
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheet).size.height * 0.7,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      for (final p in all)
                        CheckboxListTile(
                          value: chosen.contains(p.id),
                          title: Text(p.title),
                          secondary: _Thumb(path: p.thumbnailPath),
                          onChanged: (on) => setSheet(() => on == true ? chosen.add(p.id) : chosen.remove(p.id)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheet, chosen),
                    child: Text(context.l10n.t('addPages')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    setState(() => _book.collageIds = [..._book.collageIds, ...all.map((p) => p.id).where(picked.contains)]);
    await _persist();
  }

  Future<void> _exportPdf() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final drafts = ref.read(draftServiceProvider);
      final pages = [
        for (final id in _book.collageIds)
          if (await drafts.renderOf(id) case final bytes?) bytes,
      ];
      if (pages.isEmpty) return;
      final pdf = await Isolate.run(() => buildPdf(pages, a4: true));
      final dir = await getTemporaryDirectory();
      final safe = _book.title.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
      final file = File('${dir.path}/${safe.isEmpty ? 'photo-book' : safe}.pdf');
      await file.writeAsBytes(pdf);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.t('backupFailed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.t('deleteBookTitle')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(context.l10n.t('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.l10n.t('delete'), style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(booksProvider.notifier).remove(_book.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(draftsProvider).valueOrNull ?? const <CollageProject>[];
    final byId = {for (final p in drafts) p.id: p};
    // Pages whose collage was deleted simply drop out.
    final pages = _book.collageIds.where(byId.containsKey).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_book.title),
        actions: [
          IconButton(
            tooltip: context.l10n.t('exportPdf'),
            onPressed: _busy || pages.isEmpty ? null : _exportPdf,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: context.l10n.t('delete'),
            onPressed: _delete,
            icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: drafts.isEmpty ? null : () => _addPages(drafts),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.l10n.t('addPages')),
      ),
      body: pages.isEmpty
          ? EmptyState(
              icon: Icons.auto_stories_outlined,
              title: context.l10n.t('bookEmptyTitle'),
              message: context.l10n.t('bookEmptyMessage'),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: pages.length,
              onReorderItem: (from, to) {
                setState(() {
                  final list = [...pages];
                  list.insert(to, list.removeAt(from));
                  _book.collageIds = list;
                });
                _persist();
              },
              itemBuilder: (_, i) {
                final p = byId[pages[i]]!;
                return ListTile(
                  key: ValueKey('$i-${p.id}'),
                  leading: _Thumb(path: p.thumbnailPath),
                  title: Text(p.title),
                  subtitle: Text(context.l10n.a('bookPageNumber', {'count': '${i + 1}'})),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: () {
                      setState(() => _book.collageIds = [...pages]..removeAt(i));
                      _persist();
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.control),
      child: SizedBox(
        width: 48,
        height: 48,
        child: p != null && File(p).existsSync()
            ? Image.file(File(p), fit: BoxFit.cover)
            : ColoredBox(color: context.colors.surfaceInput),
      ),
    );
  }
}
