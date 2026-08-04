# Changelog

## 0.8.1

- Dropped the redundant `(tenant, status)` index from the install and tenant
  migration templates. A B-tree serves any leftmost prefix, so
  `(tenant, status, consent_given)` already covers it, and every scope on the
  model starts with `for_tenant` — carrying both only cost write time and disk.
  Flagged by `active_record_doctor` in a host app.
- Existing installs keep the index until they drop it themselves; nothing
  breaks either way. To reclaim it:

  ```ruby
  class RemoveRedundantTestimonialsIndex < ActiveRecord::Migration[8.0]
    def change
      remove_index :testimonials_testimonials, %i[tenant status]
    end
  end
  ```

- A generator test now fails the build if any index is a leftmost prefix of
  another on the same table.

## 0.8.0

- **`config.admin_layout` now works on its own.** The dashboard's stylesheet and
  script were declared in the gem's layout, so replacing that layout dropped
  both: the dashboard rendered unstyled with its delete confirmations and
  auto-submitting filter dead. They move into the views (a shared
  `testimonials/shared/_dashboard` partial), so every layout gets them with
  nothing asked of the host.
- **The dashboard stylesheet no longer claims selectors it does not own.** It
  styled bare `body`, `a`, `table` and `*`, and its `.card`, `.badge`, `.tabs`
  and `.container` are names Bootstrap and daisyUI use too, so a host that did
  load it had its sidebar and topbar restyled. Component rules now nest inside a
  `.tml-dashboard` wrapper the views render, every custom property is `--tml-`
  prefixed, and `.container`/`.nav` became `.tml-page`/`.tml-nav`. The
  full-viewport rules stay keyed to the `tm-index`/`tm-nps-index`/`tm-show` body
  classes that only the gem's own layout sets, so inside a host admin the
  dashboard scrolls with the host's page instead of fighting it for the
  viewport. Two tests fail the build if a selector or property escapes again.
- **Added `config.base_controller_class`.** Name the controller your own admin
  inherits from and the dashboard adopts its layout, helpers, authentication and
  request context — the things `admin_layout` cannot give you, and which hosts
  were hand-wiring as a shim layout plus a concern to populate `Current`. Same
  hook pgbus, avo and mission_control-jobs use. Default is unchanged.
  Layout precedence with it: a host base controller keeps its own layout, unless the host also named an `admin_layout` explicitly.
- **Migrations follow the host's `primary_key_type`,** the same
  `Rails.configuration.generators` lookup Rails' own Active Storage, Action Text
  and Action Mailbox migrations do. A uuid-keyed app has a uuid
  `active_storage_attachments.record_id`, so bigint tables here could never hold
  a video or avatar — `attach` raised `NotNullViolation`. A host that set
  nothing gets no `id:` option and an identical migration to before.
- **Dropped the `id: /\d+/` route constraints,** which were what forced the
  tables to be bigint in the first place: uuid tables would have 404d show,
  update, destroy and all three media routes. The constraint was never
  load-bearing, since every fixed-name route is declared before the flat
  `/:id` routes.
- **`create` moved to `Testimonials::SubmissionsController`** and `POST` to the
  mount path routes there. One controller used to serve both the widget's write
  endpoint and the triage actions, which meant `base_controller_class` would
  have put staff authentication in front of every member leaving a review. If
  you referenced `Testimonials::TestimonialsController#create`, that is the
  breaking change in this release; the URL is unchanged.
- The shared request context (`current_author`, `current_tenant`,
  `tenant_scope`, the gates) is now a `Testimonials::RequestContext` concern,
  since the engine has two controller roots.

## 0.7.10

- The prompt-history ledger is now optional too. `bin/rails generate
  testimonials:install --skip-prompt-events` leaves out the
  `testimonials_prompt_events` table and writes `config.prompt_events = false`,
  for apps that open the widget from their own button. `bin/rails generate
  testimonials:prompt_events` adds the table later, like `testimonials:nps`.
- With the flag off **nothing auto-opens**: `testimonial_prompt!` is a no-op,
  because the history exists only to throttle auto-prompts and a prompt nothing
  can throttle would reopen on every page. Explicit opens
  (`data-testimonial-prompt`, `window.Testimonials.open()`), both public pages,
  the dashboard and every submission path work unchanged.
- `POST /testimonials/events` is refused when the flag is off, and the widget
  stops posting shown/dismissed at all (`promptEvents.enabled` in its config).
- `testimonials:seed_demo` skips the demo prompt history when the ledger is
  off, and the `testimonials:tenant` migration skips either optional table when
  it isn't there.
- Adds `AGENTS.md`: install and integration instructions written for coding
  agents, covering the request-shaped config lambdas, both skip flags, and the
  mistakes agents actually make. It ships inside the gem, so
  `cat "$(bundle show testimonials)/AGENTS.md"` works from a host app —
  `examples/` now ships for the same reason.

## 0.7.9

- NPS is now optional at install time. `bin/rails generate testimonials:install
  --skip-nps` leaves out the `testimonials_nps_responses` table and writes
  `config.nps = false`, so an app that only wants testimonials carries neither
  the table nor the NPS tab. `bin/rails generate testimonials:nps` adds the
  table later, mirroring the `testimonials:tenant` upgrade path.
- The guard is `config.nps`, not table introspection — nothing checks the
  schema at runtime and nothing touches the database at boot. Consequently
  `/testimonials/nps_responses` now 404s when `config.nps` is false instead of
  still serving history; flip the flag back to read old responses. The
  dashboard nav already hid the tab, so only a typed URL reached it.
- `testimonials:seed_demo` skips NPS rows when the flow is off, and the
  `testimonials:tenant` migration skips the NPS table when it isn't there.

## 0.7.8

- The NPS dashboard now says what the score means. The card carries the band
  the number falls into (needs work / good / great / excellent), a scale
  showing where it sits between −100 and +100, and a note when fewer than 30
  responses make the number too thin to read. A collapsed "How is this
  calculated, and what is a good score?" panel spells out the formula, the four
  bands, and the caveats — industry, trend, comments. Translated into all 26
  locales.
- The marker's position rides on a `data-nps-marker` attribute that
  `dashboard.js` reads, so the page still ships no inline styles for a strict
  `style-src` to refuse.

## 0.7.7

- Shrank the gem from 1.0 MB back to ~90 KB by dropping the bundled 1.1 MB demo
  video. `testimonials:seed_demo` now writes a ~4 KB embedded clip (three
  seconds of 320x180 H.264) to Active Storage at seed time, so the demo
  testimonial still plays and no app downloads media it never uses. Seeding
  needs no ffmpeg and no network.

## 0.7.6

- Added a standalone public NPS page at `/testimonials/nps/new`, the shareable
  counterpart to `/testimonials/new` — the link for an email campaign, where
  there is no app session to prompt inside of. A promoter who scores 9–10 gets
  the testimonial form inline on the same page. Needs `config.public_collection`
  and `config.nps`.
- Moved the shareable-link buttons out of the dashboard nav and onto the
  testimonial and NPS index pages, so each index links to its own public page
  and the links survive a host `config.admin_layout`.
- Dropped the dismiss controls that could not work on the public pages (the
  dialog ×, "Not now", and a Cancel button that did nothing); on the NPS page
  Cancel now returns to the 0–10 scale instead.
- Fixed `dashboard.collection_page` and `dashboard.download_video`, which were
  nested under `sources:` in every locale file while the views looked them up
  under `dashboard:` — all 26 languages silently fell back to English.
- Added `bin/rails testimonials:seed_demo` and `Testimonials::Seeds`, idempotent
  demo data with a real attached video, NPS responses, and prompt history.

## 0.7.5

- Moved the selected testimonial status and rating into the main metadata card,
  removing the extra detail-pane header from the admin review view.
- Fixed the trusted publishing workflow by building and pushing the gem
  directly with RubyGems OIDC credentials after the test suite passes.

## 0.7.4

- Added `config.admin_layout`, letting host apps render the testimonial and NPS
  dashboards inside their own admin layout while keeping the standalone gem
  layout as the default.

## 0.7.3

- Redesigned the testimonial and NPS admin dashboards into two-column review
  layouts with status filters, selected-record panes, and refreshed
  before/after screenshots.
- Kept standalone testimonial and NPS response show pages working
  independently, including scrollable detail content on narrow screens.

## 0.7.2

- Added `mount_testimonials at: "/testimonials"` as the install-time route
  helper. It keeps `config.mount_path` synchronized with the mounted engine
  path while preserving manual `mount Testimonials::Engine` compatibility.
- Extracted the dashboard stylesheet into a same-origin, fingerprinted
  `/dashboard.css` endpoint and added CSP meta tags to the engine layouts.
  The public widget remains pipeline-free and controller-served.

## 0.7.1

- Renamed the default admin dashboard title to `Testimonials` across shipped
  locales while keeping it overridable through `testimonials.dashboard.title`.

## 0.7.0

- New `config.storage_service`: store uploads (video, its poster frame, guest
  avatars) on a named Active Storage service from the host's
  `config/storage.yml` instead of the environment default. Point it at a
  dedicated bucket or folder — or a service entry carrying provider options
  like Cloudinary's `folder:`/`tags:` — to keep testimonial media separate
  from the rest of the media library. `nil` (the default) keeps today's
  behavior.

## 0.6.0

- **The full-screen mobile dialog now survives the on-screen keyboard.** On
  phones the dialog is a fixed, full-height (`100dvh`) element, but iOS Safari
  raises the keyboard without resizing it — so the composer and Submit/Cancel
  row slid behind the keyboard. While the dialog is open the widget now tracks
  `window.visualViewport` and pins the overlay (and the dialog filling it) to
  the visible viewport, so the action row sits just above the keyboard. Gated on
  the `max-width:480px` mobile media query, so desktop is untouched; browsers
  without `visualViewport` no-op and keep the previous behavior. Shared change
  across the gem family.
- The "🎥 Video attached | Remove" row under a video preview is replaced with a
  discreet round ✕ button in the top-right corner of the preview (the standard
  "remove attachment" affordance) — clearly a delete control, but no longer a
  full-width, easy-to-mis-tap target. Applies to both a just-recorded/uploaded
  clip and an existing video being edited; remove behavior is unchanged.

## 0.5.2

- A just-recorded or just-uploaded video now shows a playable preview on the
  form (with its captured poster), matching the review step and the
  edit-existing case — previously "Use this video" left only a "Video
  attached" chip with no preview until the review was saved and reopened.

## 0.5.1

- The widget's injected stylesheet now refreshes when its content changes
  instead of once-and-never-again — so a shipped widget update takes effect on
  the next Turbo visit instead of needing a full page reload (Turbo keeps
  `<head>` across visits, which could otherwise pin old CSS while fresh
  widget.js runs). Backported from livechat 0.4.5.

## 0.5.0

- **Multi-tenancy.** Scope testimonials to a tenant — each Organization (or
  Product, Course, Store) with its own collection, dashboard, widget, and read
  API — via one resolver: `config.tenant = ->(request) {
  Current.organization&.to_gid&.to_s }`. The key is an opaque string (GlobalID,
  id, subdomain, slug); the gem takes no foreign key into your models, exactly
  like author attribution. Every write is stamped and every read — dashboard,
  `/api/testimonials`, `/api/stats`, NPS, the public collection page, media —
  is scoped to the resolved tenant. Authorization composes: `authorize_admin`
  says who's an admin, `tenant` says which tenant, so an org admin sees only
  their own. "One review per user" becomes one per user *per tenant*, and a
  cross-tenant id 404s instead of leaking.
- Optional `has_testimonials` model concern (veneer over the string key, no
  new coupling): `organization.testimonials.approved`,
  `organization.testimonials_nps` — plus `Testimonials.for(record)` /
  `.nps_for(record)`.
- **Single-tenant apps are unchanged** — `config.tenant` defaults to nil, one
  global collection. Upgrading: the `tenant` column is additive and nullable;
  run `bin/rails generate testimonials:tenant && bin/rails db:migrate` (fresh
  installs already include it). Existing rows keep a nil tenant.

## 0.4.2

- Uploaded videos now get a poster frame too (grabbed from the file
  client-side), so Safari shows a preview instead of a black frame before
  play — previously only recorded videos captured a poster. Best-effort;
  legacy videos with no stored poster are unaffected (re-upload to add one).

## 0.4.1

- Video poster frames: a still is captured from the camera at record time and
  shown via `<video poster>`, so recorded videos display a real thumbnail
  instead of a black box in every browser (Safari won't paint a
  fragmented-MP4 frame from the file itself). Served at `/:id/poster`,
  exposed as `poster_url` in the API.

## 0.4.0

- Consent is now an explicit public/private choice instead of a single
  checkbox: "You can use my testimonial publicly…" vs "…only privately in
  your marketing and sales." Public maps to the existing `consent_given`
  (served by the read API); private is stored, admin-visible, and never
  public. No migration. Both choices snapshot their exact wording.
  Localized in all 26 languages. (Locale key `testimonials.consent` was
  replaced by `consent_prompt` / `consent_public` / `consent_private`; if you
  overrode it, update your keys. `config.consent_text` now overrides the
  public line.)

## 0.3.0

- Reverted 0.2.0's API path change: the read API collection is back at
  `<mount>/api/testimonials` (plain REST — the collection is a noun). The
  bare `<mount>/api` from 0.2.0 read as the API root rather than a
  collection, and was asymmetric with `<mount>/api/stats`. If the
  same-named echo under a `/testimonials` mount bothers you, mount the
  engine at a shorter path (e.g. `/reviews`).

## 0.2.0

- **Breaking (API paths):** the read API's collection moved from
  `<mount>/api/testimonials` to `<mount>/api` — so it reads clean under any
  mount instead of echoing the resource name (e.g. `/testimonials/api`
  rather than `/testimonials/api/testimonials`). `<mount>/api/stats` is
  unchanged. Update any hardcoded API URLs. (Off by default: only affects
  apps that set `config.public_api = true` or call the API as an admin.)

## 0.1.5

- Docs: show how to wire `current_user` with Rails 8's built-in authentication
  (`bin/rails generate authentication`), alongside the existing Devise/Warden
  example — in the README and the generated initializer.

## 0.1.4

- Validation and submit errors are announced to screen readers: every
  `.tml-error` container is a `role="alert"` region from creation, and text
  is inserted only after the region is exposed.
- Page scroll is locked behind the open widget dialog and restored on close;
  a Turbo body swap that removes the overlay releases the lock too. The
  inline collection-page form is unaffected.

## 0.1.3

- Video playback no longer pauses itself moments after play in Firefox: the
  `#t=0.1` poster-frame fragment made Firefox seek a MediaRecorder webm that
  has no seek index, stalling the stream. The fragment is gone (widget and
  dashboard); `preload="metadata"` still paints the first frame in Chrome
  and Firefox.

## 0.1.2

- The widget dialog goes full-screen on mobile (no bottom sheet, no animations):
  inputs render at 16px to prevent iOS focus-zoom, the action row gains
  safe-area padding, and the dialog's scroll is contained (no page rubber-banding).

## 0.1.1

- Repository renamed to [yshmarov/testimonials](https://github.com/yshmarov/testimonials);
  gemspec metadata URLs updated accordingly.
- First release published via RubyGems trusted publishing (tag-triggered CI).

## 0.1.0

- Initial release: in-app testimonial widget (text + video), public collection
  page, prompt throttling, `testimonial_prompt!`, NPS with promoter auto-routing,
  triage dashboard, read API (`/api/testimonials`, `/api/stats`), localized
  best-practice questions.
