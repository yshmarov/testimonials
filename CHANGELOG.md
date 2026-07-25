# Changelog

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
