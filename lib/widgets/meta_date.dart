import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/palette.dart';
import '../theme/typography.dart';

/// Formats a raw epoch-millis timestamp for display. The timestamp is always
/// stored raw; formatting happens only here, following the device locale with a
/// German-friendly `dd.MM.yyyy · HH:mm` default so dates read naturally for the
/// app's primary audience.
String formatCollageDate(int epochMillis, {String? localeName}) {
  if (epochMillis <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  return DateFormat('dd.MM.yyyy · HH:mm', localeName).format(dt);
}

/// A quiet "meta line" — a small calendar icon + the formatted creation date in
/// `caption`/`textLo`. Used under a collage title in the library and on the
/// result screen. Metadata stays quiet: never amber.
class MetaDate extends StatelessWidget {
  const MetaDate({
    super.key,
    required this.epochMillis,
    this.icon = Icons.event_rounded,
    this.color,
  });

  final int epochMillis;
  final IconData icon;

  /// Overrides the default `textLo`. Resolved against the live palette in
  /// [build] when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = formatCollageDate(
      epochMillis,
      localeName: Localizations.maybeLocaleOf(context)?.toString(),
    );
    if (text.isEmpty) return const SizedBox.shrink();
    final c = color ?? context.colors.textLo;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: context.text.caption.copyWith(color: c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
