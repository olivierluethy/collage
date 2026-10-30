// Collage AI proxy (Cloudflare Worker).
//
// Receives the app's Messages API request body, checks it, adds the Anthropic
// API key and headers server-side, and forwards it. The key never ships in the
// APK. See ../README.md and ../../docs/AI_PROXY.md.

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const ALLOWED_MODELS = ['claude-opus-5-5'];
const MAX_BODY_BYTES = 8_000_000; // 12 downscaled photos fit comfortably
const MAX_IMAGES = 12;
const MAX_TOKENS = 16_000;

function error(status, message) {
  return new Response(JSON.stringify({ type: 'error', error: { message } }), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return error(405, 'Method not allowed');

    // Per-client rate limit (binding configured in wrangler.toml).
    const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
    if (env.AI_LIMIT) {
      const { success } = await env.AI_LIMIT.limit({ key: ip });
      if (!success) return error(429, 'Too many requests');
    }

    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) return error(413, 'Request too large');

    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return error(400, 'Invalid JSON');
    }

    // Only allow the shape the app sends, so the key can't be used for
    // arbitrary requests.
    if (!ALLOWED_MODELS.includes(body.model)) return error(400, 'Model not allowed');
    if (typeof body.max_tokens !== 'number' || body.max_tokens > MAX_TOKENS) {
      return error(400, 'max_tokens too large');
    }
    if (!Array.isArray(body.messages) || body.messages.length !== 1) {
      return error(400, 'Unexpected messages');
    }
    const content = body.messages[0]?.content;
    const images = Array.isArray(content) ? content.filter((b) => b?.type === 'image').length : 0;
    if (images > MAX_IMAGES) return error(400, 'Too many images');
    delete body.tools; // the app never sends tools

    const upstream = await fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      body: JSON.stringify(body),
    });

    return new Response(upstream.body, {
      status: upstream.status,
      headers: { 'content-type': 'application/json' },
    });
  },
};
