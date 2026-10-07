import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/gallery_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';

/// Browse device albums and multi-select photos, with the maximum shown up
/// front and a live "3 / 9" counter so the user always knows the limit.
class PhotoPickerScreen extends ConsumerStatefulWidget {
  const PhotoPickerScreen({super.key, this.maxImages = 9});
  final int maxImages;

  @override
  ConsumerState<PhotoPickerScreen> createState() => _PhotoPickerScreenState();
}

class _PhotoPickerScreenState extends ConsumerState<PhotoPickerScreen> {
  GalleryService get _gallery => ref.read(galleryServiceProvider);

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  final List<String> _selected = [];
  String? _focusedId; // the tray thumbnail currently highlighted
  int _page = 0;
  bool _loading = false;
  bool _end = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _init();
  }

  Future<void> _init() async {
    final albums = await _gallery.albums();
    if (!mounted || albums.isEmpty) return;
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
    setState(() {
      _selected.remove(id);
      if (_focusedId == id) _focusedId = null;
    });
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
    setState(() {
      if (_selected.contains(a.id)) {
        _selected.remove(a.id);
        if (_focusedId == a.id) _focusedId = null;
      } else if (_selected.length >= widget.maxImages) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(context.l10n
                .a('pickUpTo', {'count': '${widget.maxImages}'})),
          ));
      } else {
        _selected.add(a.id);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: _album == null
            ? Text(context.l10n.t('choosePhotos'))
            : _AlbumSelector(
                albums: _albums,
                selected: _album!,
                onPick: _switchAlbum,
              ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.lg),
            child: Center(
              child: SpecChip('${_selected.length}/${widget.maxImages}',
                  active: _selected.isNotEmpty),
            ),
          ),
        ],
      ),
      body: _assets.isEmpty && _loading
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
                final order = _selected.indexOf(a.id);
                return _Tile(
                  asset: a,
                  gallery: _gallery,
                  order: order,
                  onTap: () => _toggle(a),
                );
              },
            ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SelectedTray(
            ids: _selected,
            assets: _assets,
            gallery: _gallery,
            max: widget.maxImages,
            focusedId: _focusedId,
            onFocus: _focusAsset,
            onRemove: _removeSelected,
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: PrimaryButton(
                label: _selected.isEmpty
                    ? context.l10n.t('pickPhotosToContinue')
                    : (_selected.length == 1
                        ? context.l10n.t('useOnePhoto')
                        : context.l10n.a('useNPhotos', {'count': '${_selected.length}'})),
                icon: Icons.arrow_forward_rounded,
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(List<String>.of(_selected)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A static, always-visible strip of the photos currently selected. Pinned
/// above the primary action so the user never loses track of what they've
/// chosen, however far they scroll the grid. Collapses when empty.
class _SelectedTray extends StatelessWidget {
  const _SelectedTray({
    required this.ids,
    required this.assets,
    required this.gallery,
    required this.max,
    required this.focusedId,
    required this.onFocus,
    required this.onRemove,
  });

  final List<String> ids;
  final List<AssetEntity> assets;
  final GalleryService gallery;
  final int max;
  final String? focusedId;
  final void Function(String id) onFocus;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.line)),
        boxShadow: Shadows.e2,
      ),
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          const SizedBox(width: Space.lg),
          SpecChip('${ids.length}/$max', active: true),
          const SizedBox(width: Space.sm),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: Space.lg),
                itemCount: ids.length,
                separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
                itemBuilder: (_, i) {
                  final id = ids[i];
                  final asset = assets.firstWhereOrNull((a) => a.id == id);
                  return _TrayThumb(
                    id: id,
                    asset: asset,
                    gallery: gallery,
                    focused: focusedId == id,
                    onTap: () => onFocus(id),
                    onRemove: () => onRemove(id),
                  );
                },
              ),
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
    required this.asset,
    required this.gallery,
    required this.focused,
    required this.onTap,
    required this.onRemove,
  });

  final String id;
  final AssetEntity? asset;
  final GalleryService gallery;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.colors.surfaceInput,
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(
                color: focused ? context.colors.amber : context.colors.line,
                width: focused ? 2 : 1,
              ),
            ),
            child: asset == null
                ? null
                : FutureBuilder<Uint8List?>(
                    future: gallery.thumb(asset!, px: 150),
                    builder: (_, snap) => snap.data == null
                        ? const SizedBox.shrink()
                        : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.surface, width: 1),
                ),
                child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
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
    required this.asset,
    required this.gallery,
    required this.order,
    required this.onTap,
  });
  final AssetEntity asset;
  final GalleryService gallery;
  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = order >= 0;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: gallery.thumb(asset, px: 300),
            builder: (_, snap) {
              if (snap.data == null) {
                return ColoredBox(color: context.colors.surfaceInput);
              }
              return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
            },
          ),
          if (selected)
            Container(
              decoration: BoxDecoration(
                color: context.colors.amber.withValues(alpha: 0.18),
                border: Border.all(color: context.colors.amber, width: 3),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? context.colors.amber : Colors.black38,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 1),
              ),
              child: selected
                  ? Center(
                      child: Text('${order + 1}',
                          style: context.text.labelMd.copyWith(color: context.colors.onAmber)),
                    )
                  : null,
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
