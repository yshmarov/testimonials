# testimonials

[![Gem Version](https://img.shields.io/gem/v/testimonials)](https://rubygems.org/gems/testimonials)
[![CI](https://github.com/yshmarov/testimonials/actions/workflows/ci.yml/badge.svg)](https://github.com/yshmarov/testimonials/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](MIT-LICENSE)

Testimonials, reviews and NPS for Rails. Self-hosted alternative to
Testimonial.to / Senja / Delighted.

`testimonials` collects customer testimonials — text and **video** — from
inside your app with an iOS-style "Enjoying this app?" prompt, from a
shareable public page, and from NPS promoters routed straight into the
testimonial ask. Everything lands in your own database with a minimal
dashboard to approve, feature, and pick each one’s best line. Display is **headless**: render
approved testimonials with your own markup via the models or a JSON API —
copy-paste examples included.

- **Zero UI dependencies.** The widget is plain JavaScript and styles itself.
  No Tailwind, no Stimulus, no importmap, no build step. Works with Turbo
  Drive and strict nonce-based CSP out of the box.
- **Prompt at the right moment.** Call `testimonial_prompt!` in a controller at
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
- **Consent is first-class.** Customers choose public or private use in their
  own words, with a stored text snapshot; the read API only ever serves
  approved records marked for **public** use, and never emails.
- **26 languages**, including localized best-practice guiding questions.

## How it works

1. Add `<%= testimonials_tag %>` to your layout. Nothing is visible until
   the widget opens: from an eligible `testimonial_prompt!`, from any element with
   `data-testimonial-prompt`, or from `window.Testimonials.open()`.
2. The prompt starts as a small star card ("Enjoying MyApp? ★★★★★ / Not
   now"). Tapping a star expands into the full form: guiding questions,
   text, optional video recording, consent.
3. Submissions land in `testimonials_testimonials` as `pending`. You
   approve, feature, and pick best lines at the mount path (`/testimonials`).
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
gem "testimonials"
```

```bash
bundle install
bin/rails generate testimonials:install
bin/rails db:migrate
```

The generator writes `config/initializers/testimonials.rb`, creates the
migration, and mounts the engine at `/testimonials`. Then add the widget to your
layout:

```erb
<%= testimonials_tag %>
```

## Prompting users

```ruby
class InvoicesController < ApplicationController
  def create
    # ...
    testimonial_prompt! if current_user.invoices.count == 10  # a success moment
    redirect_to invoices_path
  end
end
```

The widget auto-opens on the next rendered page **if** the throttle allows:

- submitted a testimonial → never auto-prompted again
- dismissed → not again within `reprompt_after` (default 90 days)
- auto-prompted `max_prompts` times (default 3) → never again

Explicit opens bypass throttling: any element with `data-testimonial-prompt`
(or `data-testimonial-prompt="nps"`), or `window.Testimonials.open()` /
`window.Testimonials.openNps()`.

`testimonial_prompt!(:nps)` prompts for an NPS score instead.

## Configuration

Everything lives in `config/initializers/testimonials.rb`; every option has
a working default. The essentials:

```ruby
Testimonials.configure do |config|
  config.app_name = "SupeRails"
  config.current_user = ->(request) { request.env["warden"]&.user }
  config.user_display = ->(user) { { name: user.name, email: user.email } }
  config.authorize_admin = ->(request) { request.env["warden"]&.user&.admin? }
  config.on_submit = ->(record) { SlackNotifier.ping(record) }
  config.on_detractor = ->(nps) { FeedbackEngine::Feedback.create!(kind: "other", message: nps.comment.to_s) }
end
```

`current_user` (and any admin gate) receives the raw request, so it works
with whatever auth you have:

```ruby
# Devise / Warden:
config.current_user = ->(request) { request.env["warden"]&.user }

# Rails 8 built-in auth (bin/rails generate authentication):
config.current_user = lambda do |request|
  token = request.cookies["session_token"]
  Session.find_signed(token)&.user if token
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

`/testimonials/new` is a standalone, self-styled page for customers outside the
app — drop the link into an email or DM. Guests leave name, email, optional
title/company and photo. Disable with `config.public_collection = false`.

## The read API

- `GET /testimonials/api/testimonials` — approved + consented records only;
  filters: `featured=1`, `min_rating=4`, `kind=video`, `limit=12`.
- `GET /testimonials/api/stats` — `count`, `average_rating`, `ratings_count`,
  `nps_score`.

Admin-only by default. Set `config.public_api = true` to serve them without
auth (CORS `*`) — ideal for a separate static marketing site that renders
your wall of love at build time. Emails and author ids are never serialized.
Video and avatar files are handed out by testimonial id through the same
gate, with Range support so `<video>` tags just work.

## NPS

`testimonial_prompt!(:nps)` (or the widget API) asks the classic 0–10 question.
Promoters are offered the testimonial form right away — but only if the
testimonial throttle would allow it. Detractors trigger `on_detractor`.
The dashboard shows your NPS score and every response at
`/testimonials/nps_responses`. Disable with `config.nps = false`.

## Dashboard

Browse at the mount path: pending → approved → archived tabs, search,
quick-approve, inline video playback, feature toggle, and a “Best line” picker —
the customer's words are never editable, but you choose the pull-quote.
Gated by `config.authorize_admin` (development-only until you set it).

## Multi-tenancy

Scope testimonials to a tenant — each Organization (or Product, Course, Store)
with its own collection, dashboard, widget, and read API — with one resolver:

```ruby
config.tenant = ->(request) { Current.organization&.to_gid&.to_s }
```

Return an **opaque key** — a GlobalID, an id, a subdomain, a slug. The gem
never takes a foreign key into your models and never needs to know what an
Organization is; it just stamps the key on each submission and scopes every
read (dashboard, `/api/testimonials`, `/api/stats`, NPS, the public collection
page) to it. `nil` (the default) is a single global collection — single-tenant
apps need none of this and keep working unchanged.

Authorization composes: your `authorize_admin` says *who* is an admin, the
`tenant` resolver says *which* tenant they're in, so an org admin sees only
their own tenant's dashboard and API. "One review per user" becomes one per
user **per tenant**.

Optional model sugar — a veneer over the string key, not a new coupling:

```ruby
class Organization < ApplicationRecord
  has_testimonials                     # keyed by to_gid.to_s (match config.tenant)
end

organization.testimonials.approved     # a normal Active Record relation
organization.testimonials_nps          # NPS responses for this tenant
```

Apps that skip the concern still get full multi-tenancy from the resolver
alone. Key by something other than GlobalID? Pass a matching resolver to both:
`has_testimonials(key: ->(o){ o.subdomain })` and the same in `config.tenant`.

**Upgrading an existing install:** the `tenant` column is additive and
nullable. Run `bin/rails generate testimonials:tenant && bin/rails db:migrate`
(a fresh install already includes it). Existing rows keep a `nil` tenant — the
global collection — so nothing changes until you set `config.tenant`.

## Testing

```bash
bundle exec rake test
bundle exec rubocop
```

## License

MIT.
