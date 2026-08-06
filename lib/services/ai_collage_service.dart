import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// One image handed to the model: a base64 JPEG plus optional EXIF-derived
/// context (place/date) so it can group photos by trip/scene.
class AiImageInput {
  const AiImageInput({
    required this.assetId,
    required this.jpegBase64,
    this.hint,
  });
  final String assetId;
  final String jpegBase64;
  final String? hint; // e.g. "taken 2026-07 near 46.9,7.4"
}

/// A collage the model proposes: a title and the ordered asset ids to place.
class AiGroup {
  const AiGroup({required this.title, required this.assetIds});
  final String title;
  final List<String> assetIds;
}

class AiUnavailable implements Exception {
  const AiUnavailable();
}

/// Sends downscaled photos (as base64) to Claude and asks it to group them into
/// suggested collages by scene/destination and decide an ordering — so the user
/// gets ready-made collages without doing the sorting themselves. Degrades
/// gracefully when no AI key is supplied.
class AiCollageService {
  const AiCollageService();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  bool get available => Config.hasAi;

  Future<List<AiGroup>> suggest(List<AiImageInput> images) async {
    if (!available) throw const AiUnavailable();
    if (images.isEmpty) return const [];

    // Bound cost/latency: at most 12 photos per request.
    final batch = images.take(12).toList();

    final content = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text':
            'You are helping build photo collages. Below are ${batch.length} photos, '
                'numbered 0..${batch.length - 1}, each optionally annotated with when/where '
                'it was taken. Group them into 1-3 collages by scene or travel destination, '
                'give each a short friendly title, and order the photos within each collage '
                'for a pleasing layout (hero shot first). Every photo should appear in exactly '
                'one collage.',
      },
    ];
    for (var i = 0; i < batch.length; i++) {
      content.add({
        'type': 'text',
        'text': 'Photo $i${batch[i].hint != null ? ' — ${batch[i].hint}' : ''}:',
      });
      content.add({
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/jpeg',
          'data': batch[i].jpegBase64,
        },
      });
    }

    final body = {
      'model': Config.aiModel,
      'max_tokens': 1500,
      'thinking': {'type': 'disabled'},
      'output_config': {
        'effort': 'low',
        'format': {
          'type': 'json_schema',
          'schema': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'groups': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'additionalProperties': false,
                  'properties': {
                    'title': {'type': 'string'},
                    'photos': {
                      'type': 'array',
                      'items': {'type': 'integer'},
                    },
                  },
                  'required': ['title', 'photos'],
                },
              },
            },
            'required': ['groups'],
          },
        },
      },
      'messages': [
        {'role': 'user', 'content': content},
      ],
    };

    final res = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'content-type': 'application/json',
        'x-api-key': Config.aiApiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      throw Exception('AI request failed (${res.statusCode}).');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final blocks = (data['content'] as List).cast<Map<String, dynamic>>();
    final text = blocks
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    final parsed = jsonDecode(text) as Map<String, dynamic>;
    final groups = (parsed['groups'] as List).cast<Map<String, dynamic>>();

    return groups.map((g) {
      final idx = (g['photos'] as List).map((e) => e as int).toList();
      final ids = idx
          .where((i) => i >= 0 && i < batch.length)
          .map((i) => batch[i].assetId)
          .toList();
      return AiGroup(title: g['title'] as String? ?? 'Trip', assetIds: ids);
    }).where((g) => g.assetIds.isNotEmpty).toList();
  }
}
