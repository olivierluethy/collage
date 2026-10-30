# Collage AI proxy

A Cloudflare Worker that holds the Anthropic API key for the AI auto-collage
feature, so release APKs don't carry it. The request contract is described in
[../docs/AI_PROXY.md](../docs/AI_PROXY.md).

The worker only forwards requests shaped like the app's: an allowed model,
`max_tokens` ≤ 16,000, a single user message with at most 12 images, and no
tools. It also rate-limits each client IP to 10 requests per minute.

## Deploy

You need a Cloudflare account and Node.js.

```
cd proxy
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY   # paste your key
npx wrangler deploy
```

`deploy` prints the worker URL, e.g.
`https://collage-ai-proxy.<your-subdomain>.workers.dev`. Then:

1. Add it as the `AI_PROXY_URL` secret in the GitHub repository
   (Settings → Secrets and variables → Actions).
2. Tag a release; the release workflow builds the APK with it.

For a local build:

```
flutter build apk --release --dart-define=AI_PROXY_URL=https://collage-ai-proxy.<your-subdomain>.workers.dev
```

## Changing the model

The app sends `claude-opus-5-5` by default (`AI_MODEL` dart-define). If you
change it, add the new id to `ALLOWED_MODELS` in `src/index.js` and redeploy.
