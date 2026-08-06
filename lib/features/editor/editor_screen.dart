import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/canvas_element.dart';
import '../../models/collage_project.dart';
import '../../data/layout_templates.dart';
import '../../state/providers.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/layout_miniature.dart';
import '../../widgets/ui.dart';
import '../picker/photo_picker_screen.dart';
import '../result/result_screen.dart';
import 'collage_canvas.dart';
import 'editor_controller.dart';
import 'editor_sheets.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.project, required this.pool});
  final CollageProject project;
  final List<String> pool;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final EditorController _c;
  final _boundaryKey = GlobalKey();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _c = EditorController(project: widget.project, pool: widget.pool);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCoach());
  }

  Future<void> _maybeCoach() async {
    final prefs = ref.read(prefsProvider);
    if (prefs.coachSeen('editor_slots')) return;
    await prefs.setCoachSeen('editor_slots');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: const Text('Tap a slot to choose its photo. Press and hold a photo, '
          'then drag it onto another to swap them.'),
      action: SnackBarAction(label: 'Got it', onPressed: () {}),
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 9)),
    );
    if (picked == null) return;
    final freeform = _c.project.layout.slots.isEmpty;
    for (final id in picked) {
      _c.addToPool(id);
      if (freeform) {
        final asset = await ref.read(galleryServiceProvider).byId(id);
        _c.addImageElement(id, asset == null ? 1.0 : ref.read(galleryServiceProvider).aspectOf(asset));
      }
    }
    if (!freeform) _c.autofill();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    _c.clearSelection();
    await Future.delayed(Motion.fast); // let selection chrome clear before capture
    final export = ref.read(exportServiceProvider);
    final png = await export.capture(_boundaryKey, targetWidth: 2048);
    final thumb = await export.capture(_boundaryKey, targetWidth: 500);
    if (png == null) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not render the collage. Try again.')),
        );
      }
      return;
    }
    await ref.read(draftServiceProvider).save(_c.project, thumbnail: thumb);
    await ref.read(draftsProvider.notifier).reload();
    setState(() => _saving = false);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResultScreen(project: _c.project, png: png)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Editor'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.sm),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAmber))
                  : const Icon(Icons.save_alt_rounded, size: 18),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: AspectRatio(
                  aspectRatio: _c.project.ratio.value,
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: CollageCanvas(
                      controller: _c,
                      onSlotTap: (slotId) {
                        _c.selectSlot(slotId);
                        showSlotActionsSheet(context, _c, slotId);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          _ContextBar(controller: _c),
          _ToolRail(
            onLayout: () => _showLayoutSheet(),
            onPhotos: _addPhotos,
            onBorders: () => showBordersSheet(context, _c),
            onBackground: () => showBackgroundSheet(context, _c),
            onStickers: () => showStickersSheet(context, _c),
            onShapes: () => showShapesSheet(context, _c),
            onText: () => showTextSheet(context, _c),
            onEmoji: () => showEmojiSheet(context, _c),
            onGif: () => showGiphySheet(context, _c, ref.read(giphyServiceProvider)),
          ),
        ],
      ),
    );
  }

  void _showLayoutSheet() {
    final count = _c.pool.length.clamp(1, 9);
    final options = [...LayoutTemplates.forCount(count), LayoutTemplates.freeform];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => SheetScaffold(
        title: 'Layout',
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const SectionHeader('Canvas shape'),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                itemCount: CanvasRatio.all.length,
                separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
                itemBuilder: (_, i) {
                  final r = CanvasRatio.all[i];
                  final sel = r.label == _c.project.ratioLabel;
                  return GestureDetector(
                    onTap: () {
                      _c.setRatioLabel(r.label);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: Space.md),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.amberTint : AppColors.surfaceInput,
                        borderRadius: BorderRadius.circular(Radii.chip),
                      ),
                      child: Text(r.label,
                          style: AppText.spec.copyWith(color: sel ? AppColors.amber : AppColors.textMid)),
                    ),
                  );
                },
              ),
            ),
            const SectionHeader('Arrangement'),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: Space.md,
                  crossAxisSpacing: Space.md,
                  childAspectRatio: 0.85,
                ),
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final t = options[i];
                  final sel = _c.project.layout.id == t.id;
                  return GestureDetector(
                    onTap: () {
                      _c.setLayout(t);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(Radii.control),
                        border: Border.all(
                          color: sel ? AppColors.amber : AppColors.line,
                          width: sel ? 2 : 1,
                        ),
                      ),
                      child: AspectRatio(
                        aspectRatio: _c.project.ratio.value,
                        child: LayoutMiniature(template: t),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contextual actions for the currently selected overlay element.
class _ContextBar extends StatelessWidget {
  const _ContextBar({required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final el = controller.selectedElement;
        if (el == null) return const SizedBox.shrink();
        return Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (el is TextElement)
                _CtxBtn(icon: Icons.edit_rounded, label: 'Edit', onTap: () => showTextSheet(context, controller, edit: el)),
              _CtxBtn(icon: Icons.flip_to_front_rounded, label: 'Forward', onTap: () => controller.bringForward(el.id)),
              _CtxBtn(icon: Icons.flip_to_back_rounded, label: 'Back', onTap: () => controller.sendBackward(el.id)),
              _CtxBtn(icon: Icons.restart_alt_rounded, label: 'Straighten', onTap: () => controller.updateTransform(el.id, rotation: 0)),
              _CtxBtn(icon: Icons.delete_outline_rounded, label: 'Delete', color: AppColors.danger, onTap: () => controller.deleteElement(el.id)),
            ],
          ),
        );
      },
    );
  }
}

class _CtxBtn extends StatelessWidget {
  const _CtxBtn({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMid;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(height: 2),
            Text(label, style: AppText.caption.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

/// The always-visible, labelled bottom tool rail.
class _ToolRail extends StatelessWidget {
  const _ToolRail({
    required this.onLayout,
    required this.onPhotos,
    required this.onBorders,
    required this.onBackground,
    required this.onStickers,
    required this.onShapes,
    required this.onText,
    required this.onEmoji,
    required this.onGif,
  });

  final VoidCallback onLayout;
  final VoidCallback onPhotos;
  final VoidCallback onBorders;
  final VoidCallback onBackground;
  final VoidCallback onStickers;
  final VoidCallback onShapes;
  final VoidCallback onText;
  final VoidCallback onEmoji;
  final VoidCallback onGif;

  @override
  Widget build(BuildContext context) {
    final tools = <(IconData, String, VoidCallback)>[
      (Icons.grid_view_rounded, 'Layout', onLayout),
      (Icons.add_photo_alternate_outlined, 'Photos', onPhotos),
      (Icons.border_outer_rounded, 'Borders', onBorders),
      (Icons.gradient_rounded, 'Background', onBackground),
      (Icons.emoji_emotions_outlined, 'Stickers', onStickers),
      (Icons.category_outlined, 'Shapes', onShapes),
      (Icons.title_rounded, 'Text', onText),
      (Icons.tag_faces_rounded, 'Emoji', onEmoji),
      (Icons.gif_box_outlined, 'GIF', onGif),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            itemCount: tools.length,
            itemBuilder: (_, i) {
              final (icon, label, onTap) = tools[i];
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(Radii.control),
                child: SizedBox(
                  width: 76,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: AppColors.textMid, size: 24),
                      const SizedBox(height: 6),
                      Text(label, style: AppText.labelMd),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
