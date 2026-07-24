# review_engine

[![Gem Version](https://img.shields.io/gem/v/review_engine)](https://rubygems.org/gems/review_engine)
[![CI](https://github.com/yshmarov/testimonials-engine/actions/workflows/ci.yml/badge.svg)](https://github.com/yshmarov/testimonials-engine/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](MIT-LICENSE)

Testimonials, reviews and NPS for Rails. Self-hosted alternative to
Testimonial.to / Senja / Delighted.

`review_engine` collects customer testimonials — text and **video** — from
inside your app with an iOS-style "Enjoying this app?" prompt, from a
shareable public page, and from NPS promoters routed straight into the
testimonial ask. Everything lands in your own database with a minimal
dashboard to approve, feature, and excerpt. Display is **headless**: render
approved testimonials with your own markup via the models or a JSON API —
copy-paste examples included.

- **Zero UI dependencies.** The widget is plain JavaScript and styles itself.
  No Tailwind, no Stimulus, no importmap, no build step. Works with Turbo
  Drive and strict nonce-based CSP out of the box.
- **Prompt at the right moment.** Call `review_prompt!` in a controller at
  your success moments (subscription renewed, milestone hit). Built-in
  throttling means you can call it liberally — nobody gets nagged.
- **Real attribution.** Signed-in users are attributed server-side to your
  user records; guests leave name and email. No external tool can do this.
- **Video testimonials** recorded in the browser (MediaRecorder) with a
  review step, or uploaded as a file. Plain multipart upload via Active
  Storage.
- **NPS built in.** 0–10 with a comment; promoters (9–10) are immediately
  offered the testimonial form, detractors flow into `on_detractor` (pairs
  well with [feedback_engine](https://github.com/yshmarov/feedback-engine)).
- **Consent is first-class.** A consent checkbox with a stored text snapshot;
  the API only ever serves approved **and** consented records, and never
  emails.
- **26 languages**, including localized best-practice guiding questions.

## How it works

1. Add `<%= review_engine_tag %>` to your layout. Nothing is visible until
   the widget opens: from an eligible `review_prompt!`, from any element with
   `data-review-prompt`, or from `window.ReviewEngine.open()`.
2. The prompt starts as a small star card ("Enjoying MyApp? ★★★★★ / Not
   now"). Tapping a star expands into the full form: guiding questions,
   text, optional video recording, consent.
3. Submissions land in `review_engine_testimonials` as `pending`. You
   approve, feature, and excerpt them at the mount path (`/reviews`).
4. You render approved testimonials wherever you like — see
   [`examples/`](examples/) for a wall of love, quote card, rating badge,
   JSON-LD rich snippets, and a static-site (Astro) recipe.

## Requirements

- Ruby >= 3.2
- Rails >= 7.1
- Active Storage (only if you want video/avatar uploads)

## Installation

```ruby
# Gemfile
gem "review_engine"
```

```bash
bundle install
bin/rails generate review_engine:install
bin/rails db:migrate
```

The generator writes `config/initializers/review_engine.rb`, creates the
migration, and mounts the engine at `/reviews`. Then add the widget to your
layout:

```erb
<%= review_engine_tag %>
```

## Prompting users

```ruby
class InvoicesController < ApplicationController
  def create
    # ...
    review_prompt! if current_user.invoices.count == 10  # a success moment
    redirect_to invoices_path
  end
end
```

The widget auto-opens on the next rendered page **if** the throttle allows:

- submitted a testimonial → never auto-prompted again
- dismissed → not again within `reprompt_after` (default 90 days)
- auto-prompted `max_prompts` times (default 3) → never again

Explicit opens bypass throttling: any element with `data-review-prompt`
(or `data-review-prompt="nps"`), or `window.ReviewEngine.open()` /
`window.ReviewEngine.openNps()`.

`review_prompt!(:nps)` prompts for an NPS score instead.

## Configuration

Everything lives in `config/initializers/review_engine.rb`; every option has
a working default. The essentials:

```ruby
ReviewEngine.configure do |config|
  config.app_name = "SupeRails"
  config.current_user = ->(request) { request.env["warden"]&.user }
  config.user_display = ->(user) { { name: user.name, email: user.email } }
  config.authorize_admin = ->(request) { request.env["warden"]&.user&.admin? }
  config.on_submit = ->(record) { SlackNotifier.ping(record) }
  config.on_detractor = ->(nps) { FeedbackEngine::Feedback.create!(kind: "other", message: nps.comment.to_s) }
end
```

### Guiding questions, localized

The questions shown above the form ("How has %{app} helped you?") fight
blank-page paralysis — they are prompts, not form fields. By default they
come from the gem's own locale files, so all 26 languages get good questions
with your app name interpolated. Override with literal strings or a lambda
for host-side i18n:

```ruby
config.questions = ["What convinced you to try %{app}?", "What changed since?"]
config.questions = -> { I18n.t("reviews.questions") }  # your own locale keys
config.questions = []                                  # hide the section
```

## The public collection page

`/reviews/new` is a standalone, self-styled page for customers outside the
app — drop the link into an email or DM. Guests leave name, email, optional
title/company and photo. Disable with `config.public_collection = false`.

## The read API

- `GET /reviews/api/testimonials` — approved + consented records only;
  filters: `featured=1`, `min_rating=4`, `kind=video`, `limit=12`.
- `GET /reviews/api/stats` — `count`, `average_rating`, `ratings_count`,
  `nps_score`.

Admin-only by default. Set `config.public_api = true` to serve them without
auth (CORS `*`) — ideal for a separate static marketing site that renders
your wall of love at build time. Emails and author ids are never serialized.
Video and avatar files are handed out by testimonial id through the same
gate, with Range support so `<video>` tags just work.

## NPS

`review_prompt!(:nps)` (or the widget API) asks the classic 0–10 question.
Promoters are offered the testimonial form right away — but only if the
testimonial throttle would allow it. Detractors trigger `on_detractor`.
The dashboard shows your NPS score and every response at
`/reviews/nps_responses`. Disable with `config.nps = false`.

## Dashboard

Browse at the mount path: pending → approved → archived tabs, search,
quick-approve, inline video playback, feature toggle, and an excerpt picker —
the customer's words are never editable, but you choose the pull-quote.
Gated by `config.authorize_admin` (development-only until you set it).

## Testing

```bash
bundle exec rspec
bundle exec rubocop
```

## License

MIT.
