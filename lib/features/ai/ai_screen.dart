import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';

import '../../config.dart';
import '../../data/layout_templates.dart';
import '../../models/collage_project.dart';
import '../../services/ai_collage_service.dart';
import '../../state/providers.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/ui.dart';
import '../editor/editor_screen.dart';
import '../flow.dart';
import '../picker/photo_picker_screen.dart';

/// AI auto-collage: pick a bunch of photos and get ready-made collages grouped
/// by scene/destination — no manual sorting. Groups by photo location/date on
/// device, and (if an AI key is supplied) refines titles and ordering with
/// Claude vision. Degrades gracefully without a key.
class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _SuggestedCollage {
  _SuggestedCollage(this.title, this.assetIds);
  final String title;
  final List<String> assetIds;
}

class _AiScreenState extends ConsumerState<AiScreen> {
  bool _busy = false;
  String _status = '';
  List<_SuggestedCollage> _results = [];

  Future<void> _run() async {
    if (!await ensureGalleryAccess(context, ref)) return;
    if (!mounted) return;
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 12)),
    );
    if (picked == null || picked.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Looking at your photos…';
      _results = [];
    });

    // Group offline by place + day first (works without any key).
    final offline = await _clusterByPlaceAndDay(picked);
    var groups = offline;

    // Refine with AI when a key is present.
    final ai = ref.read(aiServiceProvider);
    if (ai.available) {
      try {
        setState(() => _status = 'Grouping by destination with AI…');
        final inputs = await _buildInputs(picked);
        final aiGroups = await ai.suggest(inputs);
        if (aiGroups.isNotEmpty) {
          groups = aiGroups.map((g) => _SuggestedCollage(g.title, g.assetIds)).toList();
        }
      } on AiUnavailable {
        // fall through to offline groups
      } catch (_) {
        // AI failed (network/key) — keep the offline grouping.
      }
    }

    setState(() {
      _busy = false;
      _results = groups;
      _status = '';
    });
  }

  Future<List<AiImageInput>> _buildInputs(List<String> ids) async {
    final inputs = <AiImageInput>[];
    for (final id in ids) {
      final bytes = await PhotoImage.bytes(id, thumbPx: 256);
      if (bytes == null) continue;
      final asset = await AssetEntity.fromId(id);
      String? hint;
      if (asset != null) {
        final lat = asset.latitude;
        final lng = asset.longitude;
        final d = asset.createDateTime;
        final parts = <String>['taken ${d.year}-${d.month.toString().padLeft(2, '0')}'];
        if (lat != null && lng != null && (lat != 0 || lng != 0)) {
          parts.add('near ${lat.toStringAsFixed(2)},${lng.toStringAsFixed(2)}');
        }
        hint = parts.join(' ');
      }
      inputs.add(AiImageInput(assetId: id, jpegBase64: base64Encode(bytes), hint: hint));
    }
    return inputs;
  }

  Future<List<_SuggestedCollage>> _clusterByPlaceAndDay(List<String> ids) async {
    final buckets = <String, List<String>>{};
    for (final id in ids) {
      final asset = await AssetEntity.fromId(id);
      var key = 'trip';
      if (asset != null) {
        final lat = asset.latitude;
        final lng = asset.longitude;
        final d = asset.createDateTime;
        final place = (lat != null && lng != null && (lat != 0 || lng != 0))
            ? '${(lat * 5).round()}_${(lng * 5).round()}'
            : 'here';
        key = '${d.year}-${d.month}-$place';
      }
      buckets.putIfAbsent(key, () => []).add(id);
    }
    var i = 1;
    return buckets.entries.map((e) => _SuggestedCollage('Collage ${i++}', e.value)).toList();
  }

  void _openGroup(_SuggestedCollage g) {
    final pool = g.assetIds.take(9).toList();
    final layout = LayoutTemplates.forCount(pool.length.clamp(1, 9)).first;
    final now = DateTime.now().millisecondsSinceEpoch;
    final project = CollageProject(
      id: const Uuid().v4(),
      title: g.title,
      createdAt: now,
      updatedAt: now,
      ratioLabel: CanvasRatio.square.label,
      layout: layout,
      fills: {},
      elements: [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorScreen(project: project, pool: pool)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('AI auto-collage'),
      ),
      body: _busy
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: Space.lg),
                  Text(_status, style: AppText.bodyMd),
                ],
              ),
            )
          : _results.isEmpty
              ? EmptyState(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Let us do the sorting',
                  message: Config.hasAi
                      ? 'Pick a batch of photos and we\'ll group them into collages by '
                          'place and moment — then you can fine-tune any of them.'
                      : 'Pick a batch of photos and we\'ll group them by place and date. '
                          'Add an AI key (see the README) for smarter, named suggestions.',
                  action: PrimaryButton(
                    label: 'Choose photos',
                    icon: Icons.auto_awesome_rounded,
                    expand: false,
                    onPressed: _run,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(Space.lg),
                  children: [
                    Text('Tap a suggestion to open it in the editor.', style: AppText.bodyMd),
                    const SizedBox(height: Space.md),
                    for (final g in _results) _SuggestionCard(group: g, onTap: () => _openGroup(g)),
                    const SizedBox(height: Space.lg),
                    OutlinedButton.icon(
                      onPressed: _run,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try other photos'),
                    ),
                  ],
                ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.group, required this.onTap});
  final _SuggestedCollage group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 96,
                child: Row(
                  children: [
                    for (final id in group.assetIds.take(4))
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(1),
                          child: PhotoImage(assetId: id, fit: BoxFit.cover),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    Expanded(child: Text(group.title, style: AppText.titleMd)),
                    SpecChip('${group.assetIds.length} photos'),
                    const SizedBox(width: Space.sm),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textMid),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
