import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../services/gallery_service.dart';
import '../../services/permission_service.dart';
import '../../services/photo_usage.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/meta_date.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/ui.dart';
import '../flow.dart';

/// Browse device albums and choose the photos for a collage.
///
/// The picker always shows the *whole* selection: when it opens from an
/// existing collage, the photos already in it start out selected (numbered in
/// order), so the user can see, add, remove and reorder them in one place. It
/// pops with the full, ordered final selection of asset ids (or null on back).
class PhotoPickerScreen extends ConsumerStatefulWidget {
  const PhotoPickerScreen({
    super.key,
    this.maxImages = 9,
    this.newCollage = false,
    this.initialSelection = const [],
    this.placed,
    this.collageId,
    this.onOpenCollage,
  });

  final int maxImages;

  /// Picking the photos for a brand-new collage: the button then says what
  /// happens next ("Create collage with 3 photos") and a one-time hint explains
  /// that tap order fills the slots.
  final bool newCollage;

  /// The photos already chosen, in order. A fresh collage passes nothing and
  /// starts at 0.
  final List<String> initialSelection;

  /// Photos currently placed in the collage's slots. Deselecting one of them
  /// shows a short note that it will be taken out. Defaults to
  /// [initialSelection].
  final Set<String>? placed;

  /// The collage being edited, left out of the usage badges and of the
  /// "you already made a collage with these photos" hint.
  final String? collageId;

  /// Called (after the picker closes itself) when the user asks to open one of
  /// their other collages. When null the collage is pushed on top instead.
  final void Function(CollageProject project)? onOpenCollage;

  @override
  ConsumerState<PhotoPickerScreen> createState() => _PhotoPickerScreenState();
}

class _PhotoPickerScreenState extends ConsumerState<PhotoPickerScreen> {
  GalleryService get _gallery => ref.read(galleryServiceProvider);

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  final List<String> _selected = [];

  /// Initial ids that no longer exist in the library (deleted or not shared).
  final Set<String> _missing = {};
  String? _focusedId; // the tray thumbnail currently highlighted
  int _page = 0;
  bool _loading = false;
  bool _end = false;
  bool _noPhotos = false; // the library is empty (or nothing was shared)
  bool _limited = false; // only some photos were shared with the app
  bool _showOrderHint = false;
  final _scroll = ScrollController();

  Set<String> get _placed => widget.placed ?? widget.initialSelection.toSet();
  bool get _editing => !widget.newCollage;

  @override
  void initState() {
    super.initState();
    for (final id in widget.initialSelection) {
      if (!_selected.contains(id)) _selected.add(id);
    }
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _checkMissing();
    _init();
  }

  /// Resolve the initial ids once, so a photo deleted from the library shows
  /// as a "missing photo" tile instead of a blank or a crash.
  Future<void> _checkMissing() async {
    final ids = List<String>.of(_selected);
    if (ids.isEmpty) return;
    final found = await Future.wait(ids.map((id) async {
      try {
        return await _gallery.byId(id) != null;
      } catch (_) {
        return false;
      }
    }));
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < ids.length; i++) {
        if (!found[i]) _missing.add(ids[i]);
      }
    });
  }

  Future<void> _init() async {
    final prefs = ref.read(prefsProvider);
    _showOrderHint = widget.newCollage && !prefs.coachSeen('picker_order');
    final access = await ref.read(permissionServiceProvider).current();
    final albums = await _gallery.albums();
    if (!mounted) return;
    setState(() => _limited = access == GalleryAccess.limited);
    if (albums.isEmpty) {
      setState(() => _noPhotos = true);
      return;
    }
    setState(() {
      _albums = albums;
      _album = albums.first;
    });
    _loadMore();
  }

  Future<void> _switchAlbum(AssetPathEntity album) async {
    setState(() {
      _album = album;
      _assets.clear();
      _page = 0;
      _end = false;
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _end || _album == null) return;
    setState(() => _loading = true);
    final page = await _gallery.page(_album!, _page, size: 60);
    if (!mounted) return;
    setState(() {
      _assets.addAll(page);
      _page++;
      _loading = false;
      if (page.length < 60) _end = true;
    });
  }

  void _removeSelected(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected.remove(id);
      if (_focusedId == id) _focusedId = null;
    });
  }

  /// Move a tray photo from [from] to [to] (both indexes in the final list).
  void _reorder(int from, int to) {
    if (from == to) return;
    setState(() => _selected.insert(to, _selected.removeAt(from)));
  }

  /// Tapping a tray thumbnail highlights it and scrolls the grid to it, so the
  /// user can find a chosen photo again without hunting.
  void _focusAsset(String id) {
    setState(() => _focusedId = id);
    final i = _assets.indexWhere((a) => a.id == id);
    if (i < 0 || !_scroll.hasClients) return;
    final w = MediaQuery.of(context).size.width;
    final tile = (w - 4) / 3; // 3 columns, 2px outer padding + gaps
    final target = (i ~/ 3) * (tile + 2);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: Motion.base,
      curve: Motion.standard,
    );
  }

  void _toggle(AssetEntity a) {
    if (_selected.contains(a.id)) {
      HapticFeedback.selectionClick();
      setState(() {
        _selected.remove(a.id);
        if (_focusedId == a.id) _focusedId = null;
      });
      return;
    }
    if (_selected.length >= widget.maxImages) {
      // Never a silent ignore: say why nothing happened, with a buzz.
      HapticFeedback.heavyImpact();
      showAppSnack(context, context.l10n.a('pickerLimitSnack', {'max': '${widget.maxImages}'}));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _selected.add(a.id);
      if (_showOrderHint) {
        _showOrderHint = false;
        ref.read(prefsProvider).setCoachSeen('picker_order');
      }
    });
  }

  /// Let the user widen a "selected photos only" grant, then reload.
  Future<void> _shareMore() async {
    await ref.read(permissionServiceProvider).presentLimited();
    if (!mounted) return;
    setState(() {
      _noPhotos = false;
      _assets.clear();
      _page = 0;
      _end = false;
    });
    await _init();
  }

  /// Leave the picker for one of the user's other collages.
  void _openCollage(CollageProject project) {
    final open = widget.onOpenCollage;
    if (open != null) {
      open(project);
      Navigator.of(context).pop();
    } else {
      openCollage(context, ref, project);
    }
  }

  /// The collages (other than the one being edited) that use [id].
  List<CollageProject> _usesOf(PhotoUsageIndex usage, String id) {
    if (!usage.isUsed(id)) return const [];
    return [
      for (final p in usage.collagesUsing(id))
        if (p.id != widget.collageId) p,
    ];
  }

  Future<void> _showUsage(String assetId) async {
    final uses = _usesOf(ref.read(photoUsageProvider), assetId);
    if (uses.isEmpty) return;
    HapticFeedback.mediumImpact();
    final project = await showModalBottomSheet<CollageProject>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => _UsageSheet(assetId: assetId, collages: uses),
    );
    if (project != null && mounted) _openCollage(project);
  }

  void _done() => Navigator.of(context).pop(List<String>.of(_selected));

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _primaryLabel(BuildContext context) {
    final l = context.l10n;
    final n = _selected.length;
    if (n == 0) {
      return _editing && widget.initialSelection.isNotEmpty
          ? l.t('pickerRemoveAll')
          : l.t('pickPhotosToContinue');
    }
    if (widget.newCollage) {
      return n == 1 ? l.t('createWithOnePhoto') : l.a('createWithNPhotos', {'count': '$n'});
    }
    return n == 1 ? l.t('useOnePhoto') : l.a('useNPhotos', {'count': '$n'});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final usage = ref.watch(photoUsageProvider);
    final max = widget.maxImages;
    final full = _selected.length >= max;
    final sameSet = _selected.isEmpty
        ? const <CollageProject>[]
        : usage.sameSet(_selected.toSet(), excludeId: widget.collageId);
    final removedPlaced = _placed.where((id) => !_selected.contains(id)).length;
    final missing = _selected.where(_missing.contains).length;
    final canFinish = _selected.isNotEmpty || (_editing && widget.initialSelection.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: _album == null
            ? Text(l.t('choosePhotos'))
            : _AlbumSelector(
                albums: _albums,
                selected: _album!,
                onPick: _switchAlbum,
              ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.lg),
            child: Center(
              child: Semantics(
                label: l.a('pickerSemCount', {'count': '${_selected.length}', 'max': '$max'}),
                excludeSemantics: true,
                child: SpecChip('${_selected.length}/$max', active: _selected.isNotEmpty),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _Header(
            full: full,
            text: full
                ? l.a('pickerLimitHeader', {'max': '$max'})
                : _editing
                    ? l.a('pickerHeaderEdit', {'count': '${_selected.length}', 'max': '$max'})
                    : l.a('pickerHeaderNew', {'count': '${_selected.length}', 'max': '$max'}),
          ),
          if (_limited)
            _Banner(
              icon: Icons.photo_library_outlined,
              text: l.t('pickerLimited'),
              actionLabel: l.t('pickerShareMore'),
              onAction: _shareMore,
            ),
          if (_showOrderHint && _selected.isEmpty)
            _Banner(
              icon: Icons.touch_app_outlined,
              text: l.t('pickerOrderHint'),
            ),
          if (sameSet.isNotEmpty)
            _Banner(
              icon: Icons.collections_outlined,
              text: l.t('pickerSameSet'),
              actionLabel: l.t('pickerOpenIt'),
              onAction: () => _openCollage(sameSet.first),
            ),
          if (removedPlaced > 0)
            _Banner(
              icon: Icons.remove_circle_outline_rounded,
              text: removedPlaced == 1
                  ? l.t('pickerRemovesPlacedOne')
                  : l.a('pickerRemovesPlacedMany', {'count': '$removedPlaced'}),
            ),
          if (missing > 0)
            _Banner(
              icon: Icons.image_not_supported_outlined,
              text: missing == 1
                  ? l.t('pickerMissingOne')
                  : l.a('pickerMissingMany', {'count': '$missing'}),
            ),
          Expanded(
            child: _noPhotos
                ? EmptyState(
                    icon: Icons.no_photography_outlined,
                    title: l.t('pickerEmptyTitle'),
                    message: l.t('pickerEmptyMessage'),
                    action: _limited
                        ? PrimaryButton(
                            label: l.t('pickerShareMore'),
                            icon: Icons.add_photo_alternate_outlined,
                            expand: false,
                            onPressed: _shareMore,
                          )
                        : null,
                  )
                : _assets.isEmpty && _loading
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(2),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                        itemCount: _assets.length,
                        itemBuilder: (_, i) {
                          final a = _assets[i];
                          // Only an id lookup per visible tile: the usage index
                          // is a map, so badges never load other assets.
                          final uses = _usesOf(usage, a.id).length;
                          return _Tile(
                            key: ValueKey(a.id),
                            asset: a,
                            gallery: _gallery,
                            order: _selected.indexOf(a.id),
                            max: max,
                            usedIn: uses,
                            onTap: () => _toggle(a),
                            onShowUsage: uses > 0 ? () => _showUsage(a.id) : null,
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SelectedTray(
            ids: _selected,
            missing: _missing,
            max: max,
            focusedId: _focusedId,
            onFocus: _focusAsset,
            onRemove: _removeSelected,
            onReorder: _reorder,
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: PrimaryButton(
                label: _primaryLabel(context),
                icon: Icons.arrow_forward_rounded,
                onPressed: canFinish ? _done : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The always-visible status line: how many photos are chosen out of the
/// limit and what tapping does. Turns into the limit notice when full.
class _Header extends StatelessWidget {
  const _Header({required this.text, required this.full});
  final String text;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.sm),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(
          children: [
            Icon(
              full ? Icons.info_outline_rounded : Icons.photo_library_outlined,
              size: 18,
              color: full ? c.info : c.textMid,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                text,
                style: context.text.bodyMd.copyWith(color: full ? c.textHi : c.textMid),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet one-line notice above the grid, with an optional amber action.
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.actionLabel, this.onAction});
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: Sizes.touchTarget),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.textMid),
          const SizedBox(width: Space.md),
          Expanded(child: Text(text, style: context.text.bodyMd.copyWith(color: c.textHi))),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// A static, always-visible strip of the photos currently selected. Pinned
/// above the primary action so the user never loses track of what they've
/// chosen, however far they scroll the grid. Hold and drag a thumbnail to
/// change the order; the × removes it. Collapses when empty.
class _SelectedTray extends StatelessWidget {
  const _SelectedTray({
    required this.ids,
    required this.missing,
    required this.max,
    required this.focusedId,
    required this.onFocus,
    required this.onRemove,
    required this.onReorder,
  });

  final List<String> ids;
  final Set<String> missing;
  final int max;
  final String? focusedId;
  final void Function(String id) onFocus;
  final void Function(String id) onRemove;
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
        boxShadow: Shadows.e2,
      ),
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Row(
              children: [
                SpecChip('${ids.length}/$max', active: true),
                const SizedBox(width: Space.sm),
                if (ids.length > 1)
                  Expanded(
                    child: Text(
                      context.l10n.t('pickerTrayHint'),
                      style: context.text.caption.copyWith(color: c.textLo),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: _TrayThumb.extent,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(left: Space.lg, right: Space.sm),
              itemCount: ids.length,
              onReorderItem: onReorder,
              proxyDecorator: (child, _, __) => Material(color: Colors.transparent, child: child),
              itemBuilder: (_, i) {
                final id = ids[i];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(id),
                  index: i,
                  child: _TrayThumb(
                    id: id,
                    index: i,
                    count: ids.length,
                    missing: missing.contains(id),
                    focused: focusedId == id,
                    onTap: () => onFocus(id),
                    onRemove: () => onRemove(id),
                    onMoveEarlier: i > 0 ? () => onReorder(i, i - 1) : null,
                    onMoveLater: i < ids.length - 1 ? () => onReorder(i, i + 1) : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrayThumb extends StatelessWidget {
  const _TrayThumb({
    required this.id,
    required this.index,
    required this.count,
    required this.missing,
    required this.focused,
    required this.onTap,
    required this.onRemove,
    this.onMoveEarlier,
    this.onMoveLater,
  });

  /// Each item is a 72dp box: the 56dp thumbnail sits bottom-left and the
  /// remove button's full 48dp hit area covers the top-right corner.
  static const double extent = 72;
  static const double _thumb = 56;

  final String id;
  final int index;
  final int count;
  final bool missing;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onMoveEarlier;
  final VoidCallback? onMoveLater;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final label = l.a(missing ? 'pickerSemTrayMissing' : 'pickerSemTrayPhoto',
        {'n': '${index + 1}', 'count': '$count'});
    return SizedBox(
      width: extent,
      height: extent,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: extent - _thumb,
            width: _thumb,
            height: _thumb,
            child: Semantics(
              label: label,
              hint: l.t('pickerTrayHint'),
              selected: focused,
              button: true,
              onTap: onTap,
              customSemanticsActions: {
                if (onMoveEarlier != null)
                  CustomSemanticsAction(label: l.t('pickerMoveEarlier')): onMoveEarlier!,
                if (onMoveLater != null)
                  CustomSemanticsAction(label: l.t('pickerMoveLater')): onMoveLater!,
              },
              excludeSemantics: true,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.surfaceInput,
                    borderRadius: BorderRadius.circular(Radii.control),
                    border: Border.all(
                      color: focused ? c.amber : c.line,
                      width: focused ? 2 : 1,
                    ),
                  ),
                  child: missing
                      ? Icon(Icons.image_not_supported_outlined, color: c.textLo, size: 22)
                      : PhotoImage(assetId: id, thumbPx: 150),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            width: Sizes.touchTarget,
            height: Sizes.touchTarget,
            child: Semantics(
              button: true,
              label: l.t('pickerRemovePhoto'),
              excludeSemantics: true,
              child: Tooltip(
                message: l.t('pickerRemovePhoto'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  // The visible × sits on the thumbnail's top-right corner.
                  child: Align(
                    alignment: const Alignment(1 / 3, -1 / 3),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surface, width: 1),
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.asset,
    required this.gallery,
    required this.order,
    required this.max,
    required this.usedIn,
    required this.onTap,
    this.onShowUsage,
  });
  final AssetEntity asset;
  final GalleryService gallery;
  final int order;
  final int max;

  /// How many other saved collages use this photo (0 = none).
  final int usedIn;
  final VoidCallback onTap;
  final VoidCallback? onShowUsage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final selected = order >= 0;
    final parts = [
      selected
          ? l.a('pickerSemSelected', {'n': '${order + 1}', 'max': '$max'})
          : l.t('pickerSemNotSelected'),
      if (usedIn == 1) l.t('pickerUsedInOne'),
      if (usedIn > 1) l.a('pickerUsedInMany', {'count': '$usedIn'}),
    ];
    return Semantics(
      label: parts.join('. '),
      button: true,
      selected: selected,
      onTap: onTap,
      customSemanticsActions: onShowUsage == null
          ? null
          : {CustomSemanticsAction(label: l.t('pickerShowUsage')): onShowUsage!},
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onShowUsage,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: gallery.thumb(asset, px: 300),
              builder: (_, snap) {
                if (snap.data == null) {
                  return ColoredBox(color: c.surfaceInput);
                }
                return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
              },
            ),
            if (selected)
              Container(
                decoration: BoxDecoration(
                  color: c.amber.withValues(alpha: 0.18),
                  border: Border.all(color: c.amber, width: 3),
                ),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: selected ? c.amber : Colors.black38,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? c.onAmber : Colors.white70, width: 1.5),
                ),
                child: selected
                    ? Center(
                        child: Text('${order + 1}',
                            style: context.text.labelMd.copyWith(color: c.onAmber)),
                      )
                    : null,
              ),
            ),
            // Quiet "already in a collage" mark: neutral scrim, never amber.
            if (usedIn > 0)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(Radii.chip),
                  ),
                  child: const Icon(Icons.collections_outlined, size: 13, color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Used in N collages": the saved collages that contain one photo, each a
/// tap away. Pops with the chosen collage.
class _UsageSheet extends StatelessWidget {
  const _UsageSheet({required this.assetId, required this.collages});
  final String assetId;
  final List<CollageProject> collages;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final n = collages.length;
    return SheetScaffold(
      title: n == 1 ? l.t('pickerUsedInOne') : l.a('pickerUsedInMany', {'count': '$n'}),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.control),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: PhotoImage(assetId: assetId, thumbPx: 150),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(l.t('pickerUsageNote'),
                      style: context.text.bodyMd.copyWith(color: c.textMid)),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Space.lg),
              itemCount: n,
              itemBuilder: (_, i) {
                final p = collages[i];
                final thumb = p.thumbnailPath;
                return ListTile(
                  minVerticalPadding: Space.sm,
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.chip),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: thumb != null && File(thumb).existsSync()
                          ? Image.file(File(thumb), fit: BoxFit.cover)
                          : ColoredBox(
                              color: c.surfaceInput,
                              child: Icon(Icons.image_outlined, color: c.textLo, size: 20),
                            ),
                    ),
                  ),
                  title: Text(p.title,
                      style: context.text.bodyLg.copyWith(color: c.textHi),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: MetaDate(epochMillis: p.updatedAt),
                  trailing: Icon(Icons.chevron_right_rounded, color: c.textMid),
                  onTap: () => Navigator.of(context).pop(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumSelector extends StatelessWidget {
  const _AlbumSelector({required this.albums, required this.selected, required this.onPick});
  final List<AssetPathEntity> albums;
  final AssetPathEntity selected;
  final ValueChanged<AssetPathEntity> onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AssetPathEntity>(
      onSelected: onPick,
      color: context.colors.surfaceHigh,
      itemBuilder: (_) => albums
          .map((a) => PopupMenuItem(value: a, child: Text(a.name, style: context.text.bodyMd)))
          .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(selected.name, style: context.text.titleLg, overflow: TextOverflow.ellipsis)),
          Icon(Icons.arrow_drop_down, color: context.colors.textMid),
        ],
      ),
    );
  }
}
