import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Sharpens its child with the `shaders/sharpen.frag` fragment shader. The
/// shader is loaded once and shared; until it is ready, or on renderers that
/// can't run shader filters, the child is shown unsharpened.
class Sharpened extends StatefulWidget {
  const Sharpened({super.key, required this.amount, required this.child});

  /// 0 (off) .. 1 (strong).
  final double amount;
  final Widget child;

  static Future<ui.FragmentProgram>? _program;

  /// Start loading the shader early so the first sharpened photo (and any
  /// export) doesn't render without it.
  static Future<ui.FragmentProgram> preload() =>
      _program ??= ui.FragmentProgram.fromAsset('shaders/sharpen.frag');

  /// Fire-and-forget [preload] where shader filters are supported.
  static void warmUp() {
    if (ui.ImageFilter.isShaderFilterSupported) preload().ignore();
  }

  @override
  State<Sharpened> createState() => _SharpenedState();
}

class _SharpenedState extends State<Sharpened> {
  ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    Sharpened.preload().then((p) {
      if (mounted) setState(() => _program = p);
    }).catchError((Object _) {
      // No shader support at runtime: stay unsharpened.
    });
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    if (program == null || widget.amount <= 0) return widget.child;
    // Uniform 0-1 is u_size (set by the engine); 2 is the strength.
    final shader = program.fragmentShader()..setFloat(2, widget.amount * 1.5);
    return ImageFiltered(
      imageFilter: ui.ImageFilter.shader(shader),
      child: widget.child,
    );
  }
}
