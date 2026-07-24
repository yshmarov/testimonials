# PRD: review_engine

**One-liner:** Collect, curate, and expose customer testimonials — text and video — plus NPS, from inside your Rails app. Self-hosted alternative to Testimonial.to / Senja. Zero UI dependencies. Headless display: the gem stores and serves data; you render it wherever you want.

- Gem name: `review_engine` (decided)
- Repo: [yshmarov/testimonials-engine](https://github.com/yshmarov/testimonials-engine)
- Status: approved, in build (2026-07-24)

## 1. Problem & positioning

SaaS testimonial tools cost $25–95/mo per product, hold your social proof in their database, and can't connect a testimonial to the actual user record in your app. For a Rails app, collection and curation belong in the app itself — with better attribution than any external tool, because the reviewer is already authenticated.

Family positioning: `feedback_engine` captures private feedback; `review_engine` captures public praise and sentiment (NPS); `i18n_feedback` fixes the words. Same architecture across the suite: mountable engine, plain-JS self-styled widget, install generator, pluggable gating, broad locale coverage.

## 2. Personas

1. **Customer (authenticated)** — prompted in-app, identity known, minimum friction.
2. **Customer (guest)** — arrives via a shareable collection link from an email/DM.
3. **Admin** — triages and curates in the mounted dashboard.
4. **Developer** — installs in 3 commands, configures via one initializer, renders testimonials with their own markup (or copies the shipped examples).

Note: the site **visitor** persona is served by the host app / marketing site, not by this gem. The gem provides data; display is the developer's job (see §6).

## 3. Core flows

### 3.1 In-app prompt (the iOS "leave a review" pattern)

Two-stage widget, deliberately modeled on `SKStoreReviewController`:

- **Stage 1 — rating card.** Compact centered card: app logo (config), "Enjoying {AppName}?", five tappable stars, "Not now". No text input visible. Tapping a star is the commitment device.
- **Stage 2 — expansion.** The card grows in place: selected stars remain editable, textarea (with optional guiding questions rendered above it, see `config.questions`), **Record a video** button, consent checkbox, Submit. For authenticated users there are no name/email/photo fields — attribution comes from the session.

**Invocation — three ways:**

1. **Declarative:** any element with `data-review-prompt` opens it (a nav link, a menu item).
2. **JS API:** `window.ReviewEngine.open()` / `window.ReviewEngine.openNps()`.
3. **Server-side:** `review_prompt!` in a controller (e.g. after a "success moment": 10th invoice sent, subscription renewed) sets a flash-like signal; the widget auto-opens on the next page render. App logic knows the right moment natively — no "automation" product needed.

**Throttling (hard requirement):** never auto-prompt a user who submitted, dismissed within N days (default 90), or was prompted M times total (default 3). Stored per-user for authenticated users, per-cookie for guests. Explicit invocations (user clicked a link) bypass throttling.

### 3.2 Video recording

- `getUserMedia` + `MediaRecorder`, plain JS, no dependencies.
- Device-check screen (camera/mic pickers, live preview) → 3-2-1 countdown → recording with elapsed timer and configurable max duration (default 120s) → review screen with playback → **Record again** / **Confirm**.
- Upload via Active Storage direct upload (signed endpoint, `fetch`-based — no `@rails/activestorage` npm dependency) with a progress bar.
- Fallback: "Choose a file to submit" for browsers/devices where recording fails.
- Stored as recorded (webm from Chrome/Firefox, mp4 from Safari). **No transcoding in v1**; document an optional `after_video_upload` hook where the host can enqueue ffmpeg. Poster frame captured client-side and uploaded alongside.
- **Risk item:** Safari/iOS codec matrix. Spike this before committing to the video milestone (Testimonial.to has a "disable video recording for iPhone users" toggle for a reason).

### 3.3 Public collection page

`GET /reviews/new` on the mounted engine — a standalone, self-styled page (logo, header, guiding questions, Record video / Send text buttons) for sharing with customers outside the app. Guest flow adds name (required), email (required), title/company, headshot upload.

- **Togglable via `config.public_collection` — ON by default.** Off = the page 404s; only in-app collection remains.
- Optionally tokenized links (`?token=`) so admins can revoke/scope a campaign.

### 3.4 Thank-you state

Configurable title/message (i18n-able), optional redirect URL. No image customization in v1.

### 3.5 NPS (ships in this gem — decided)

- Same widget chassis, different form: "How likely are you to recommend {AppName} to a friend or colleague?" 0–10 buttons, then optional "What's the main reason for your score?" comment.
- Attribution identical to testimonials (session or email field).
- Own throttle (default: once per 90 days per user).
- **Auto-routing:**
  - score ≥ 9 → immediately offer the testimonial form: "Glad to hear it! Mind saying that publicly?"
  - score ≤ 6 → configurable lambda; documented recipe routes it into `feedback_engine` if installed.
- Admin sees NPS score (%promoters − %detractors), response list, simple trend.

## 4. Admin dashboard

Mounted at the engine path, gated by `config.authorize_admin`. Visually the sibling of feedback_engine's triage UI (tabs, search, light/dark).

- **Inbox:** pending → approved → archived. Cards show rating, text, inline video player, author (linked to host user record when attributed — clickable via a configurable `user_path` lambda), consent status, source (widget / link / NPS-routed), submitted-at.
- **Actions:** approve, archive, feature/unfeature, select excerpt (highlight the best sentence). **Deliberately no editing of the customer's words.**
- **NPS tab:** score, responses, trend.
- All records are plain ActiveRecord models for anything custom.

## 5. What the gem does NOT ship: display UI

**Decided:** no `testimonial_wall` / `testimonial_card` / `testimonial_badge` helpers or partials in the gem. No embeddable `<script>` widget. Display belongs to the host app or the (often separate, static) marketing site.

Instead the gem ships:

1. **A read API** (see §6) that host code and — optionally — external sites consume.
2. **Copy-paste examples** in the repo (`examples/` + rendered in the dummy app): a wall of love, a single quote card, a rating badge (default and stacked-avatars variants), and a schema.org `AggregateRating`/`Review` JSON-LD snippet. Devs see the final-result value visually, then own the markup. Screenshots of these examples go in the README.

## 6. Read API

- **Internal:** `ReviewEngine::Testimonial.approved` etc. — plain ActiveRecord, always available.
- **HTTP JSON API**, mounted under the engine:
  - `GET /api/testimonials` — approved + consented records only; filters: `featured`, `min_rating`, `limit`; never serializes emails or any guest PII beyond name/title/company/avatar URL.
  - `GET /api/stats` — count, average rating (powers badge examples).
  - Video/poster/avatar exposed as URLs (signed or public per host's Active Storage config).
- **Togglable public access:** `config.public_api` — **OFF by default** (API requires an authenticated admin or same-app request); ON = readable without auth, for consumption by a static marketing site at build time or client-side. CORS configurable when public.

## 7. Data model

```
review_engine_testimonials
  kind (text|video), body, rating (1..5, null allowed), excerpt,
  status (pending|approved|archived), featured (bool),
  consent_given (bool), consent_text (string snapshot),
  author (polymorphic, optional), guest_name, guest_email, guest_title_company,
  source (widget|link|nps), page_url, locale, token (nullable)
  + Active Storage: video, poster, avatar

review_engine_nps_responses
  score (0..10), comment, author (polymorphic, optional), guest_email, source

review_engine_prompt_events   # throttling ledger
  author (polymorphic) or cookie_id, kind (testimonial|nps),
  action (shown|dismissed|submitted), occurred_at
```

No "spaces": the host app is the space. Single-product by design.

## 8. Configuration sketch

```ruby
ReviewEngine.configure do |config|
  config.app_name = "SupeRails"
  config.logo = "logo.png"
  config.current_user = ->(request) { request.env["warden"]&.user }
  config.authorize_admin = ->(user) { user&.admin? }
  config.user_display = ->(user) { { name: user.name, email: user.email, avatar_url: user.avatar_url } }

  # Guiding prompts shown above the textarea / recorder (not form fields).
  # Default nil = the gem's built-in best-practice questions, localized via
  # the gem's own locale files (`review_engine.questions`, %{app} interpolated).
  # Override with an array of literal strings, or a lambda for host i18n:
  #   config.questions = -> { I18n.t("myapp.review_questions") }
  # Empty array = don't render the section at all.
  config.questions = nil

  config.video = true                  # false = text-only product
  config.max_video_seconds = 120
  config.reprompt_after = 90.days
  config.max_prompts = 3
  config.consent_text = "You may publish this with my name and photo."

  config.public_collection = true      # standalone /reviews/new page (ON by default)
  config.public_api = false            # unauthenticated read API (OFF by default)

  config.nps = true
  config.on_detractor = ->(response) { FeedbackEngine::Feedback.create!(...) } # optional
end
```

## 9. Out of scope — absolute (decided)

Brand monitoring, case studies, multi-product/spaces, email invitation campaigns, gift-card rewards, social imports (X/LinkedIn), video watermarks/effects/transcoding, team roles (the `authorize_admin` lambda is the whole story), custom domains. Also excluded: shipped display UI and embeddable widgets (§5), AI features, image export for social.

## 9b. Pragmatic build decisions (v1)

- **Questions ship localized.** The gem carries best-practice default questions in its own locale files; `config.questions` overrides with literal strings or a lambda (for host-side i18n).
- **No direct uploads.** Recorded video posts as ordinary multipart form data — a ≤120s clip is well within a normal request. Boring beats clever.
- **No poster frames.** Admin and consumers use `<video preload="metadata">`; browsers show the first frame.
- **No tokenized collection links** in v1 — `config.public_collection` toggle only (ON by default). Revisit if someone actually asks.
- **Attribution follows house style:** loose `author_id` string + denormalized name/email fields, no FK to the host's user table (portable across apps, same as feedback_engine).

## 10. Milestones

1. **v0.1** — text testimonials: two-stage widget, `review_prompt!`, throttling, public collection page + toggle, admin inbox, consent.
2. **v0.2** — video: codec spike first, then recorder flow, direct upload, poster, admin playback.
3. **v0.3** — read API (`/api/testimonials`, `/api/stats`), `public_api` toggle, CORS; `examples/` wall + card + badge + JSON-LD with screenshots.
4. **v0.4** — NPS + auto-routing + admin NPS view.
5. **v1.0** — locales, RTL, strict-CSP compliance (apply the i18n_feedback v0.8.2 lessons from day one), demo GIF, README with the "replaces $50/mo" table.

## 11. Success criteria

- Install-to-first-testimonial in under 5 minutes on a fresh Rails app.
- Widget works under Turbo Drive and strict CSP with zero host asset-pipeline involvement.
- A video recorded on Safari/iOS plays back in the admin and via the API-consumed examples in Chrome.
- A static marketing site can render a wall of love from the public API with no Rails involved.
