import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../services/gallery_service.dart';
import '../../state/providers.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
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

  void _toggle(AssetEntity a) {
    setState(() {
      if (_selected.contains(a.id)) {
        _selected.remove(a.id);
      } else if (_selected.length >= widget.maxImages) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('You can pick up to ${widget.maxImages} photos.'),
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
            ? const Text('Choose photos')
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: PrimaryButton(
            label: _selected.isEmpty
                ? 'Pick photos to continue'
                : 'Use ${_selected.length} ${_selected.length == 1 ? "photo" : "photos"}',
            icon: Icons.arrow_forward_rounded,
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(List<String>.of(_selected)),
          ),
        ),
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
                return const ColoredBox(color: AppColors.surfaceInput);
              }
              return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
            },
          ),
          if (selected)
            Container(
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.18),
                border: Border.all(color: AppColors.amber, width: 3),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? AppColors.amber : Colors.black38,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 1),
              ),
              child: selected
                  ? Center(
                      child: Text('${order + 1}',
                          style: AppText.labelMd.copyWith(color: AppColors.onAmber)),
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
      color: AppColors.surfaceHigh,
      itemBuilder: (_) => albums
          .map((a) => PopupMenuItem(value: a, child: Text(a.name, style: AppText.bodyMd)))
          .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(selected.name, style: AppText.titleLg, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down, color: AppColors.textMid),
        ],
      ),
    );
  }
}
