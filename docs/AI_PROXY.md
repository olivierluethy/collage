# AI proxy

The AI auto-collage feature calls Anthropic's Messages API. A key compiled into
the app (`--dart-define=AI_API_KEY=...`) can be extracted from any APK, so it is
only meant for local builds. For release builds, run a small proxy that holds
the key and build the app with:

```
flutter build apk --release --dart-define=AI_PROXY_URL=https://your-proxy.example.com/collage-ai
```

## Contract

The app sends `POST <AI_PROXY_URL>` with `content-type: application/json` and a
complete Messages API request body (model, `max_tokens`, `fallbacks`,
`output_config`, `messages`). It sends no credentials.

The proxy must:

1. Forward the body unchanged to `https://api.anthropic.com/v1/messages`.
2. Add these headers:
   - `x-api-key: <your Anthropic API key>`
   - `anthropic-version: 2023-06-01`
   - `anthropic-beta: server-side-fallback-2026-07-01` (the body uses
     `fallbacks: "default"`, which needs this beta)
3. Return Anthropic's status code and JSON response body unchanged.

It should also protect the key from abuse: rate-limit per client, cap the
request size (the app sends at most 12 downscaled photos), and allow only the
model the app uses.

## Minimal example (Cloudflare Worker)

```js
export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
    const body = await request.text();
    if (body.length > 8_000_000) return new Response('Too large', { status: 413 });
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      body,
    });
    return new Response(res.body, {
      status: res.status,
      headers: { 'content-type': 'application/json' },
    });
  },
};
```

Store the key as a Worker secret (`wrangler secret put ANTHROPIC_API_KEY`) and
add a rate-limiting rule in front of the route.
