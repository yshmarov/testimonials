# Changelog

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
