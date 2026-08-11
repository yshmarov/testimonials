# PRD: testimonials

**One-liner:** Collect, curate, and expose customer testimonials — text and video — plus NPS, from inside your Rails app. Self-hosted alternative to Testimonial.to / Senja. Zero UI dependencies. Headless display: the gem stores and serves data; you render it wherever you want.

- Gem name: `testimonials` (renamed from `review_engine` pre-release; name confirmed free on rubygems)
- Repo: [yshmarov/testimonials](https://github.com/yshmarov/testimonials)
- Status: **shipped as v1.0.0; audited against the implementation on 2026-08-11.** Deferred ideas live in §12.

## 1. Problem & positioning

SaaS testimonial tools cost $25–95/mo per product, hold your social proof in their database, and can't connect a testimonial to the actual user record in your app. For a Rails app, collection and curation belong in the app itself — with better attribution than any external tool, because the reviewer is already authenticated.

Family positioning: `ideasbugs` captures private feedback; `testimonials`
captures public praise and sentiment (NPS); `i18n_proofreading` fixes the words.
Same architecture across the suite: mountable engine, plain-JS self-styled
widget, install generator, pluggable gating, broad locale coverage.

## 2. Personas

1. **Customer (authenticated)** — prompted in-app, identity known, minimum friction.
2. **Customer (guest)** — arrives via a shareable collection link from an email/DM.
3. **Admin** — triages and curates in the mounted dashboard.
4. **Developer** — installs in 3 commands, configures via one initializer, renders testimonials with their own markup (or copies the shipped examples).

Note: the site **visitor** persona is served by the host app / marketing site, not by this gem. The gem provides data; display is the developer's job (see §6).

## 3. Core flows

### 3.1 In-app prompt (the iOS "leave a review" pattern)

Two-stage widget, deliberately modeled on `SKStoreReviewController`:

- **Stage 1 — rating card.** Compact centered card: "Enjoying {AppName}?",
  five tappable stars, "Not now". No text input visible. Tapping a star is the
  commitment device.
- **Stage 2 — expansion.** The card grows in place: selected stars remain editable, textarea (with optional guiding questions rendered above it, see `config.questions`), **Record a video** button, consent checkbox, Submit. For authenticated users there are no name/email/photo fields — attribution comes from the session.

**Invocation — three ways:**

1. **Declarative:** any element with `data-testimonial-prompt` opens it (a nav link, a menu item).
2. **JS API:** `window.Testimonials.open()` / `window.Testimonials.openNps()`.
3. **Server-side:** `testimonial_prompt!` in a controller (e.g. after a "success moment": 10th invoice sent, subscription renewed) sets a flash-like signal; the widget auto-opens on the next page render. App logic knows the right moment natively — no "automation" product needed.

**Throttling (hard requirement):** never auto-prompt a user who submitted, dismissed within N days (default 90), or was prompted M times total (default 3). Stored per-user for authenticated users, per-cookie for guests. Explicit invocations (user clicked a link) bypass throttling.

### 3.2 Video recording (as shipped)

- `getUserMedia` + `MediaRecorder`, plain JS, no dependencies.
- Camera-check screen (live preview, default devices) → 3-2-1 countdown → recording with a remaining-time overlay and configurable max duration (default 120s) → review screen with playback → **Record again** / **Use this video**. The guiding questions stay pinned above the preview the whole time.
- Upload is **plain multipart form data** through the create endpoint — a ≤120s clip fits comfortably in a normal request; no direct-upload machinery, no progress bar (see §12 for when that trade-off should be revisited).
- Fallback: "Upload a video file instead" for browsers/devices where recording fails.
- Stored as recorded (webm from Chrome/Firefox, mp4 from Safari). No
  transcoding. Recorded videos get a best-effort client-captured poster;
  ordinary uploaded files may have none.
- Desktop Safari verified by hand (record, replay, submit, re-edit). iOS remains untested.

### 3.3 Public collection page

`GET /testimonials/new` on the mounted engine — a standalone, self-styled page
(header, guiding questions, Record video / Send text buttons) for sharing with
customers outside the app. Guest flow adds name (required), email (required),
title/company, and headshot upload.

- **Togglable via `config.public_collection` — ON by default.** Off = the page 404s; only in-app collection remains. The dashboard header links to the page so admins can grab the URL.

### 3.4 Thank-you state

Localized thanks message; the widget auto-closes, the public page keeps it on screen. No redirect, no image customization (§12).

### 3.4b One review per signed-in user (added post-PRD)

The App Store / G2 model: a signed-in user's re-submission edits their review in place. The widget opens pre-filled (rating, text, consent state, playable attached video with a remove control), skipping the star card; the edit resets status to `pending` for re-moderation and clears the admin's best line. Guests have no reliable identity, so guest submissions stay separate records.

### 3.5 NPS (ships in this gem — decided)

- Same widget chassis, different form: "How likely are you to recommend {AppName} to a friend or colleague?" 0–10 buttons, then optional "What's the main reason for your score?" comment.
- Attribution identical to testimonials (session or email field).
- Own throttle (default: once per 90 days per user).
- **Auto-routing:**
  - score ≥ 9 → immediately offer the testimonial form: "Glad to hear it! Mind saying that publicly?"
  - score ≤ 6 → configurable lambda; documented recipe routes it into `ideasbugs` if installed.
- Admin sees NPS score (%promoters − %detractors), promoter/passive/detractor counts, and the response list. (No over-time trend chart — §12.)

## 4. Admin dashboard

Mounted at the engine path, gated by `config.authorize_admin`. Visually the
sibling of ideasbugs' triage UI (tabs, search, light/dark).

- **Inbox:** pending → approved → archived tabs with counts, kind filter, search. Rows show rating, quote, author name (plain text — a clickable link into the host's own user admin is a §12 idea), consent, received-at, and inline Approve/Archive (the moderation-queue pattern; feature / best line / delete live on the show page).
- **Show page:** full text, inline video player, consent snapshot, metadata, status transitions, feature toggle, best-line picker. **Deliberately no editing of the customer's words.**
- **CSP note:** the dashboard ships no inline JS — delete confirms and the auto-submitting filter run from a tiny same-origin `dashboard.js`, same delivery pattern as the widget.
- **NPS tab:** score, category guide, promoter/passive/detractor counts, and
  responses.
- All records are plain ActiveRecord models for anything custom.

## 5. What the gem does NOT ship: display UI

**Decided:** no `testimonial_wall` / `testimonial_card` / `testimonial_badge` helpers or partials in the gem. No embeddable `<script>` widget. Display belongs to the host app or the (often separate, static) marketing site.

Instead the gem ships:

1. **A read API** (see §6) that host code and — optionally — external sites consume.
2. **Copy-paste examples** in the repo's `examples/`: a wall of love, a single
   quote card, a rating badge, a schema.org `AggregateRating`/`Review` JSON-LD
   snippet, and a static-site (Astro) recipe. Devs see the final-result value,
   then own the markup.

## 6. Read API

- **Internal:** `Testimonials::Testimonial.approved` etc. — plain ActiveRecord, always available.
- **HTTP JSON API**, mounted under the engine:
  - `GET /api/testimonials` — approved + consented records only; filters: `featured`, `min_rating`, `limit`; never serializes emails or any guest PII beyond name/title/company/avatar URL.
  - `GET /api/stats` — count, average rating (powers badge examples).
  - Video/poster/avatar exposed as gated engine URLs. The engine streams the
    authorized bytes with Range support and never redirects to a reusable
    signed blob URL.
- **Togglable public access:** `config.public_api` — **OFF by default** (API
  requires an authenticated admin); ON = readable without auth with CORS `*`,
  for consumption by a static marketing site at build time or client-side.

## 7. Data model

```
testimonials_testimonials
  kind (text|video), body, rating (1..5, null allowed), best_line,
  status (pending|approved|archived), featured (bool),
  consent_given (bool), consent_text (string snapshot),
  author_id (loose string, no FK), name, email, title_company,
  source (widget|page|nps), page_url, user_agent, locale
  + Active Storage: video_file, avatar

testimonials_nps_responses
  score (0..10), comment, author_id, name, email,
  page_url, user_agent, locale

testimonials_prompt_events   # throttling ledger
  author_id or visitor_token (permanent cookie), kind (testimonial|nps),
  action (shown|dismissed|submitted), created_at
```

Attribution follows house style: loose `author_id` string plus denormalized
name/email, no FK to the host's user table — portable across apps. Signed-in
users are attributed server-side via `config.user_display`; the endpoint never
trusts client contact fields for them. No "spaces": the host app is the
space. Single-product by design. Note the engine table prefix makes the main
table `testimonials_testimonials` — standard engine convention, and safer
than squatting a bare `testimonials` table the host might own.

## 8. Configuration sketch

```ruby
Testimonials.configure do |config|
  config.app_name = "SupeRails"
  config.current_user = ->(request) { request.env["warden"]&.user }
  config.authorize_admin = ->(request) { request.env["warden"]&.user&.admin? }
  config.user_display = ->(user) { { name: user.name, email: user.email } }

  # Guiding prompts shown above the textarea / recorder (not form fields).
  # Default nil = the gem's built-in best-practice questions, localized via
  # the gem's own locale files (`testimonials.questions`, %{app} interpolated).
  # Override with an array of literal strings, or a lambda for host i18n:
  #   config.questions = -> { I18n.t("myapp.review_questions") }
  # Empty array = don't render the section at all.
  config.questions = nil

  config.video = true                  # false = text-only product
  config.max_video_seconds = 120
  config.reprompt_after = 90.days
  config.max_prompts = 3
  # config.consent_text = nil          # localized default: explicit marketing permission

  config.public_collection = true      # standalone /testimonials/new page (ON by default)
  config.public_api = false            # unauthenticated read API (OFF by default)
  config.mount_path = "/testimonials"  # keep in sync with the mount line

  config.nps = true
  config.on_detractor = ->(response) { Ideasbugs::Feedback.create!(...) } # optional
end
```

The full option list lives in the generated initializer; see the README for
`testimonials_tag`, `testimonials_button`, `testimonials_cta_label`, and
`testimonial_prompt!`.

## 9. Out of scope — absolute (decided)

Brand monitoring, case studies, multi-product/spaces, email invitation campaigns, gift-card rewards, social imports (X/LinkedIn), video watermarks/effects/transcoding, team roles (the `authorize_admin` lambda is the whole story), custom domains. Also excluded: shipped display UI and embeddable widgets (§5), AI features, image export for social.

## 9b. Pragmatic build decisions (v1)

- **Questions ship localized.** The gem carries best-practice default questions in its own locale files; `config.questions` overrides with literal strings or a lambda (for host-side i18n).
- **No direct uploads.** Recorded video posts as ordinary multipart form data — a ≤120s clip is well within a normal request. Boring beats clever.
- **No server-side poster extraction.** The recorder captures a best-effort
  still in the browser; ordinary uploaded files rely on normal video playback.
- **No tokenized collection links** in v1 — `config.public_collection` toggle only (ON by default). Revisit if someone actually asks.
- **Attribution follows house style:** loose `author_id` string + denormalized
  name/email fields, no FK to the host's user table (portable across apps, same
  as ideasbugs).

## 10. Status (2026-08-11)

Everything in §3–§6 is built and covered by Minitest across Rails 7.1–8.1 and
Ruby 3.2–4.0. A headless-Chrome acceptance test drives the NPS promoter handoff,
text submission, pending moderation, approval, and public read. The widget and
dashboard JavaScript ship as same-origin scripts; media streams through gated
engine routes; flat routes keep the mount path as the resource; 26 locales
include the guiding questions and CTA labels.

Desktop Safari recording was verified manually before v1. iOS recording
remains a documented platform-validation gap rather than a different API.

## 11. Success criteria

- Install-to-first-testimonial in under 5 minutes on a fresh Rails app. ✓
- Widget works under Turbo Drive and strict CSP with zero host asset-pipeline involvement. ✓ (verified against a `script-src 'self'` + nonce policy)
- A video recorded in Safari plays back in the admin and in the edit form. ✓ desktop; iOS pending
- A static marketing site can render a wall of love from the public API with no Rails involved. ✓ (recipe in examples/static_site.md)

## 12. Deferred — revisit only on real demand

- **Direct uploads + progress bar** — worth it only if real users hit request
  timeouts on slow connections (e.g. Heroku's 30s router limit with large
  clips). Costs ~100 lines of widget JS and host CORS setup; zero gem deps.
- **Poster frames** — solved cheaply: every playback src carries a `#t=0.1`
  media fragment, which makes browsers paint that frame as the thumbnail.
  Client-side canvas capture (~30 lines + an attachment) only if that ever
  proves insufficient.
- **Camera/mic device pickers** — hold until someone asks. Helps multi-device
  users; browser default is right for most. ~60 lines plus permissions edge
  cases.
- **Thank-you redirect** after submit.
- **NPS trend over time** in the dashboard.
- **Admin → host-user link**: a `config.user_path` lambda so the author name
  in the dashboard links into the host's own user admin.
- **Tokenized collection links** (revocable/scoped campaigns).
- **Video transcripts & subtitles** — a `captions` (WebVTT) attachment +
  `<track>` in the players + `captions_url` in the API; transcription itself
  stays a host-side `on_submit` recipe (see
  [issue #2](https://github.com/yshmarov/testimonials/issues/2)).
- **prompt_events pruning** helper/recipe (the ledger grows unbounded).
