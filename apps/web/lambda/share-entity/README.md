# share-entity Lambda

Per-request SSR for the six public **entity** share surfaces, so an
entity created/edited after the last static build still unfurls with the
right per-entity `<head>` (crawlers + chat-app link-unfurlers do not run
the SPA's JS). One HTML-only Lambda behind a Function URL, fronted by
CloudFront.

## Paths owned (routed here in `infra/modules/web-stack/main.tf`)

| Path | Entity | JSON-LD |
|---|---|---|
| `/share/event/<id>` | public club event | `SportsEvent` / `Event` |
| `/share/profile/<id>` | public runner profile | `ProfilePage` + `Person` |
| `/share/club/<slug>` | public club | `SportsOrganization` |
| `/share/race/<id>` | race-calendar listing | `SportsEvent` |
| `/share/session/<id>` | public session plan | `WebPage` + breadcrumb |
| `/share/workout/<id>` | public gym workout | `WebPage` + breadcrumb |

The matching SvelteKit routes
(`src/routes/share/{event,profile,club,race,session,workout}/[…]`) carry
`prerender = false` and run the same lookup + meta builders under `vite dev`,
so every path works locally without standing up the Lambda.

Session plans + workouts read the **redacted** projections only — the
`public_gym_workouts` / `public_gym_sets` views (no `notes`, no per-set `rpe`)
for a workout, and for a plan the authored fields without the per-item `cue` /
`tempo` teaching notes. An og:description is handed to every unfurler that
touches the link, so the meta says how many sets / movements and how long,
never what the owner wrote in them.

## Why one Lambda (not six)

These surfaces share an identical shape — anon public lookup → pure
`build*Head` → `render*HeadTags` → `injectEntityHead` into the SPA shell —
and none needs a per-entity `og:image` PNG (the OG image is the branded
card, or the avatar URL for profiles/clubs). So a single dispatcher
Lambda serves all six with no native rasteriser, versus cloning the
share-badge stack (Function URL + OAC + cache/origin-request policy +
release/OIDC wiring) six times. See `../share-badge/README.md` for the
one-per-type pattern this deliberately diverges from.

## Build

Run from `apps/web/` **after** `npm run build` (the bundler embeds
`build/200.html` as the SPA shell):

```
node lambda/share-entity/build.mjs
```

Output: `lambda/share-entity/dist/share-entity.zip` (esbuild-bundled
`index.mjs` + `package.json`; supabase-js inlined). CI's
`release-web.yml` rebuilds + deploys it on every `web@*` tag.

## Fail-open posture

A private / missing / deleted entity returns a **404 HTML** with a
`noindex` robots tag (a clean crawler signal), never a 5xx. A path whose
segment carries a malformed percent-escape (`/share/club/%zz`) takes the
same 404 — it is an entity we cannot find, and a 503 there would tell a
crawler to retry a link that can never resolve. Only an unhandled error
returns 503. There is no image endpoint to fall back on.
