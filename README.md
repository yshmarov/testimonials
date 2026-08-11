# testimonials

[![Gem Version](https://img.shields.io/gem/v/testimonials)](https://rubygems.org/gems/testimonials)
[![Downloads](https://img.shields.io/gem/dt/testimonials)](https://rubygems.org/gems/testimonials)
[![CI](https://github.com/yshmarov/testimonials/actions/workflows/ci.yml/badge.svg)](https://github.com/yshmarov/testimonials/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](MIT-LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/yshmarov/testimonials?style=social)](https://github.com/yshmarov/testimonials/stargazers)

**Testimonials, reviews and NPS for Rails.** Text and **video**, collected
inside your own app, stored in your own database. Self-hosted alternative to
Testimonial.to / Senja / Delighted.

![The testimonials widget: star prompt, full form, and video review step](https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/hero.jpg)

## Install

```ruby
# Gemfile
gem "testimonials"
```

```bash
bundle install
bin/rails generate testimonials:install
bin/rails db:migrate
```

```erb
<%# app/views/layouts/application.html.erb %>
<%= testimonials_tag %>
```

The generator writes the initializer, the migration, and mounts the engine at
`/testimonials`. Nothing renders until the widget is opened.

Two parts are optional at install time, and skipping either leaves out its
table:

```bash
bin/rails generate testimonials:install --skip-nps            # no NPS at all
bin/rails generate testimonials:install --skip-prompt-events  # no auto-prompts
```

`--skip-nps` drops the 0–10 survey: no table, no dashboard tab, no prompt.
`--skip-prompt-events` drops the prompt history — for apps that open the widget
from their own button and never call `testimonial_prompt!`, since that history
exists only to throttle auto-prompts. See
[Prompting users](#prompting-users) for what changes.

Changed your mind later: `bin/rails generate testimonials:nps` or
`bin/rails generate testimonials:prompt_events`, migrate, and set the matching
flag (`config.nps`, `config.prompt_events`) to `true`.

Optional demo data:

```bash
bin/rails testimonials:seed_demo
```

It creates idempotent text testimonials, one approved video testimonial with a
real playable MP4 (a ~4 KB clip written at seed time, so the gem ships no media),
three NPS responses, and prompt-history examples. Running the task again
refreshes those records instead of duplicating them.

> [!IMPORTANT]
> The dashboard defaults to **development only**. Set `authorize_admin` before
> you deploy — see [Configure](#configure).

Ruby >= 3.2 · Rails >= 7.1 and < 9 · Active Storage only if you want
video/avatar uploads.

Installing with a coding agent? Point it at [AGENTS.md](AGENTS.md) — the same
steps in the order an agent needs them, plus the gates it tends to get wrong
and the things it should not do. It ships inside the gem, so
`cat "$(bundle show testimonials)/AGENTS.md"` works from any app that bundles it.

## What you get

|                 |                                                                         |
| --------------- | ----------------------------------------------------------------------- |
| **Widget**      | iOS-style star prompt → rating, guiding questions, text, video, consent  |
| **Video**       | Recorded in-browser (MediaRecorder) with a review step, or uploaded      |
| **NPS**         | 0–10 + comment. Promoters routed into the testimonial ask                |
| **Public pages** | `/testimonials/new` and `/testimonials/nps/new` — shareable links       |
| **Dashboard**   | Pending → approved → archived, search, feature toggle, best-line picker  |
| **Display**     | Headless. Your markup, via the models or a JSON API                      |
| **Deps**        | None. Plain JS — no Tailwind, no Stimulus, no importmap, no build step   |
| **Auth**        | Lambdas over the raw request — Devise, Rails 8 auth, anything            |
| **i18n**        | 26 languages, including localized guiding questions                      |
| **Turbo/CSP**   | Turbo Drive and strict nonce-based CSP out of the box                    |

## Why self-host it

|                                     | `testimonials`                       | A third-party embed             |
| ----------------------------------- | ------------------------------------ | ------------------------------- |
| Cost                                | Free, MIT                            | Monthly subscription            |
| Where testimonials live             | Your database                        | The vendor's                    |
| Attribution to *your* user records  | Server-side, from the session        | Whatever the visitor types      |
| Prompting at in-app success moments | One method call in a controller      | Not reachable from your backend |
| Page weight                         | One `<script>`, no framework, no CDN | Third-party bundle + requests   |
| Consent record                      | Stored text snapshot, in your rows   | Vendor's terms                  |
| Multi-tenant                        | Built in, one resolver               | Usually a plan upgrade          |
| Rendering                           | Your markup, your CSS                | Their widget, their branding    |
| If the vendor disappears            | Nothing happens                      | You lose the wall of love       |

## The whole flow

| 1. A star card appears at a success moment | 2. Tapping a star expands the full form |
| --- | --- |
| ![The star prompt card](https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/01-prompt.png) | ![The expanded testimonial form](https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/02-form.png) |
| Nothing renders until it's eligible. "Not now" is always one tap away. | Guiding questions fight blank-page paralysis. Video is offered, never required. |
| **3. Camera check before recording** | **4. Review it before sending** |
| ![The camera check step](https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/03-camera-check.jpg) | ![Reviewing the recorded video](https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/04-video-review.jpg) |
| A countdown and a preview, so nobody is caught mid-blink. | Record again as often as they like. The blob stays in the browser until Send. |
| **5. Attached, written, consented** | **6. Lands in your dashboard as `pending`** |
| ![The form with a video attached](https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/05-video-attached.png) | ![The triage dashboard](https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/dashboard-index.png) |
| Consent is an explicit choice in the customer's own words. | Nothing is public until you approve it. |

## Prompting users

Call it at a success moment. Throttling is built in, so call it liberally:

```ruby
testimonial_prompt!        # ask for a testimonial
testimonial_prompt!(:nps)  # ask for an NPS score instead
```

```ruby
class InvoicesController < ApplicationController
  def create
    # ...
    testimonial_prompt! if current_user.invoices.count == 10
    redirect_to invoices_path
  end
end
```

The widget auto-opens on the next rendered page **if** the throttle allows:

| Situation | Result |
| --- | --- |
| Already submitted | Never auto-prompted again |
| Dismissed | Not again within `reprompt_after` (90 days) |
| Auto-prompted `max_prompts` times (3) | Never again |

**Explicit opens bypass throttling** — any element with
`data-testimonial-prompt` (or `="nps"`), or `window.Testimonials.open()` /
`window.Testimonials.openNps()`.

That history lives in `testimonials_prompt_events`, one row per shown,
dismissed or submitted, and it is optional. `config.prompt_events = false` —
what `--skip-prompt-events` writes at install — keeps no history at all, and so
**nothing auto-opens**: `testimonial_prompt!` becomes a no-op, because a prompt
nothing can throttle would reopen on every page. Explicit opens, the public
pages, and everything above them are untouched, so an app that opens the widget
from its own button loses nothing. Want auto-prompts back:
`bin/rails generate testimonials:prompt_events`, migrate, flip the flag.

## Configure

Everything is optional — a fresh install works with zero config. In
`config/initializers/testimonials.rb`:

| Option | Default | What it does |
| --- | --- | --- |
| `authorize_admin` | development only | **Who can read the dashboard.** Override before deploying |
| `base_controller_class` | `ActionController::Base` | The controller the dashboard inherits — name your admin's and it adopts its layout, helpers and auth |
| `admin_layout` | the gem's own | Just the shell, if you don't want the whole controller |
| `app_name` | Rails app name | Shown as "Enjoying %{app}?" and in the questions |
| `enabled` | everyone | Who gets the widget. `false` hides it and rejects posts |
| `current_user` | `nil` | Attribute a submission to a user. Receives the request |
| `user_display` | `{ name:, email: }` | Turns that user into stored attribution |
| `tenant` | `nil` | One collection per tenant — see [Multi-tenancy](#multi-tenancy) |
| `questions` | localized built-ins | Guiding prompts. Array, callable, or `[]` to hide |
| `consent_text` | localized default | The wording customers agree to |
| `video` | `true` | Video recording and upload (needs Active Storage) |
| `max_video_seconds` | `120` | Recording cap |
| `max_video_size` | `50.megabytes` | Enforced server-side |
| `avatars` | `true` | Headshot upload for guests on the public page |
| `max_avatar_size` | `5.megabytes` | Enforced server-side |
| `storage_service` | app default | Active Storage service for uploads (a `storage.yml` key) |
| `reprompt_after` | `90.days` | Cooldown after a dismissal |
| `max_prompts` | `3` | Lifetime auto-prompt cap per user |
| `prompt_events` | `true` | The prompt history the throttle reads. `false` = no history, no auto-prompts |
| `public_collection` | `true` | The shareable `/testimonials/new` and `/testimonials/nps/new` pages |
| `public_api` | `false` | Serve the read API without auth (CORS `*`) |
| `nps` | `true` | The 0–10 NPS flow |
| `nps_reprompt_after` | `90.days` | Cooldown between NPS asks |
| `rate_limit` | `{ to: 5, within: 1.minute }` | Per-IP throttle (Rails 7.2+). `nil` disables |
| `mount_path` | `"/testimonials"` | Keep in sync with `mount` in `routes.rb` |
| `on_submit` | no-op | Runs after each save — Slack, email, CRM |
| `on_detractor` | no-op | Runs for NPS 0–6 |

A typical initializer:

```ruby
Testimonials.configure do |config|
  config.app_name        = "SupeRails"
  config.current_user    = ->(request) { request.env["warden"]&.user }
  config.user_display    = ->(user) { { name: user.name, email: user.email } }
  config.authorize_admin = ->(request) { request.env["warden"]&.user&.admin? }
  config.on_submit       = ->(record) { SlackNotifier.ping(record) }
  config.on_detractor    = ->(nps) { Ideasbugs::Feedback.create!(kind: "other", message: nps.comment.to_s) }
end
```

Gates receive the **raw request**, so they work with any auth:

```ruby
# Devise / Warden
config.current_user = ->(request) { request.env["warden"]&.user }

# Rails 8 built-in auth (bin/rails generate authentication)
config.current_user = lambda do |request|
  token = request.cookies["session_token"]
  Session.find_signed(token)&.user if token
end
```

<details>
<summary><b>Guiding questions, localized</b></summary>

The questions above the form ("How has %{app} helped you?") fight blank-page
paralysis — they are prompts, not form fields. By default they come from the
gem's locale files, so all 26 languages get good questions with your app name
interpolated.

```ruby
config.questions = ["What convinced you to try %{app}?", "What changed since?"]
config.questions = -> { I18n.t("reviews.questions") }  # your own locale keys
config.questions = []                                  # hide the section
```

</details>

## Dashboard

Pending → approved → archived tabs, search, quick-approve, inline video
playback, feature toggle, and a **Best line** picker.

<img src="https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/dashboard-show.jpg" alt="A single testimonial in the dashboard: video playback, best-line picker, attribution metadata, and approve/archive/feature/delete actions" width="620">

Every submission keeps its provenance — who sent it, the exact consent text
they agreed to, the query-free page URL, locale, browser, timestamp. **Best line** is the only
thing you write: the customer's words stay verbatim, you just choose which
sentence your landing page pulls out.

## The read API

| Endpoint | Returns |
| --- | --- |
| `GET /testimonials/api/testimonials` | Approved + publicly-consented records. Filters: `featured=1`, `min_rating=4`, `kind=video`, `limit=12` |
| `GET /testimonials/api/stats` | `count`, `average_rating`, `ratings_count`, `nps_score` |

Admin-only by default. `config.public_api = true` serves them without auth
(CORS `*`) — ideal for a static marketing site rendering your wall of love at
build time. **Emails and author ids are never serialized.** Video and avatar
files go through the same gate, with Range support so `<video>` just works.
The media response stays on that authorized engine URL with a private,
`no-store` cache policy; it never redirects to a reusable signed blob URL.

## Rendering what you collect

The gem ships **no display UI** on purpose. [`examples/`](examples/) has
copy-paste starting points:

| Example | What it renders |
| --- | --- |
| [`wall_of_love.html.erb`](examples/wall_of_love.html.erb) | A responsive grid of text + video testimonials |
| [`testimonial_card.html.erb`](examples/testimonial_card.html.erb) | A single quote card for a landing/pricing page |
| [`badge.html.erb`](examples/badge.html.erb) | The "★ 4.9 from 87 reviews" chip |
| [`json_ld.html.erb`](examples/json_ld.html.erb) | schema.org markup for Google rich snippets |
| [`static_site.md`](examples/static_site.md) | Rendering on a separate marketing site (Astro & friends) |

## NPS

`testimonial_prompt!(:nps)` asks the classic 0–10 question. Promoters (9–10)
are offered the testimonial form immediately — but only if the testimonial
throttle would allow it. Detractors (0–6) trigger `on_detractor`, which pairs
well with [ideasbugs](https://github.com/yshmarov/ideasbugs). Your score and
every response live at `/testimonials/nps_responses`.

| 1. One question, eleven taps | 2. The reason, optional |
| --- | --- |
| ![The NPS prompt: how likely are you to recommend us, scored 0 to 10](https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/nps-01-score.jpg) | ![The follow-up asking for the main reason behind the score](https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/nps-02-comment.png) |
| Ten seconds of work, and "Not now" is always there. | The comment is where the actionable half lives. Promoters go straight on to the testimonial form. |

The score is `% promoters − % detractors`, from −100 to +100, and the dashboard
reads it against the usual benchmarks so nobody has to go and google them:
below 0 needs work, 0–29 is good, 30–69 is great, 70 and up is world-class. A
scale under the number shows where you sit, and under 30 responses the card
says the sample is too thin to read much into.

<img src="https://raw.githubusercontent.com/yshmarov/testimonials/main/docs/screenshots/nps-dashboard.jpg" alt="The NPS dashboard: a score of 41 badged Great, a scale marking where it sits between −100 and +100, promoter/passive/detractor counts, and the collapsed panel explaining the formula and the benchmarks" width="820">

`/testimonials/nps/new` is the same question on its own page — the link for an
email campaign, where there is no app session to prompt inside of. A promoter
who scores 9–10 gets the testimonial form right there on the page.

NPS is optional. `config.nps = false` — what `--skip-nps` writes at install —
turns off the prompt, the public page, the `/api/stats` score and the dashboard
tab, and `/testimonials/nps_responses` then 404s. Turning it off on an install
that has the table hides existing responses along with everything else; flip it
back to read them.

## The public pages

Two standalone, self-styled pages for people outside the app — drop either link
into an email or DM:

| | |
| --- | --- |
| `/testimonials/new` | Leave a testimonial: name, email, optional title/company and photo |
| `/testimonials/nps/new` | Score 0–10 with an optional comment (needs `config.nps`) |

Disable both with `config.public_collection = false`.

## Multi-tenancy

Scope testimonials to a tenant — each Organization (or Product, Course, Store)
with its own collection, dashboard, widget and read API — with one resolver:

```ruby
config.tenant = ->(request) { Current.organization&.to_gid&.to_s }
```

Return an **opaque key**: a GlobalID, an id, a subdomain, a slug. The gem never
takes a foreign key into your models and never needs to know what an
Organization is. It stamps the key on each submission and scopes every read —
dashboard, `/api/testimonials`, `/api/stats`, NPS, the public page. `nil` — the
default — is a single global collection, so single-tenant apps need none of
this.

Authorization composes: `authorize_admin` says *who* is an admin, `tenant` says
*which* tenant they're in. "One review per user" becomes one per user **per
tenant**.

<details>
<summary><b>Optional model sugar, and upgrading an existing install</b></summary>

A veneer over the string key, not a new coupling:

```ruby
class Organization < ApplicationRecord
  has_testimonials                     # keyed by to_gid.to_s (match config.tenant)
end

organization.testimonials.approved     # a normal Active Record relation
organization.testimonials_nps          # NPS responses for this tenant
```

Apps that skip the concern still get full multi-tenancy from the resolver
alone. Keying by something other than GlobalID? Pass a matching resolver to
both: `has_testimonials(key: ->(o){ o.subdomain })` and the same in
`config.tenant`.

**Upgrading:** the `tenant` column is additive and nullable. Run
`bin/rails generate testimonials:tenant && bin/rails db:migrate` (a fresh
install already includes it). Existing rows keep a `nil` tenant — the global
collection — so nothing changes until you set `config.tenant`.

</details>

## Compatibility and public API

The following are the model and integration contracts that 1.x will keep
stable under semantic versioning:

- `Testimonials::Testimonial`, including `KINDS`, `STATUSES`, `SOURCES`, its
  persisted fields, attachment predicates, status predicates, `for_tenant`,
  `newest_first`, `approved`, `publishable`, `featured_first`, `display_name`,
  and `quote`.
- `Testimonials::NpsResponse`, including its persisted fields, `for_tenant`,
  `newest_first`, `promoter?`, `passive?`, `detractor?`, `.score`, and `.band`
  when NPS is installed.
- `Testimonials::PromptEvent`, including `KINDS`, `ACTIONS`, its persisted
  fields, `.eligible?`, and `.record!` when prompt events are installed.
- `has_testimonials`, `Testimonials.configure`, `mount_testimonials`,
  `testimonials_tag`, the opener helpers/attributes, and `testimonial_prompt!`.
- `config.on_submit` and `config.on_detractor`, each receiving the documented
  saved record.

Those domain model names are intentional and will not become a generic `Post`
during 1.x. Engine controllers, partials, CSS classes, generated HTML, and
widget implementation objects are private. Incompatible changes to the public
list above wait for a new major version; a deprecation normally ships first.

### Upgrading from 0.x

Version 1.0.0 keeps the existing domain models and schema. There is no
migration, initializer change, compatibility alias, or rename: continue using
`Testimonials::Testimonial`, `Testimonials::NpsResponse`, and
`Testimonials::PromptEvent`. Rails 9 is excluded until a 1.x release explicitly
adds it. Media URLs are unchanged, but their responses now contain the gated
bytes instead of redirecting to an Active Storage URL.

## Security and deletion

See [SECURITY.md](https://github.com/yshmarov/testimonials/blob/main/SECURITY.md)
for private vulnerability reporting and the stored-data, consent, media,
deletion, and retention boundaries. In short: the public API is off by default;
when enabled it returns only approved, publicly consented records without email
or author ids. Deleting the live testimonial, NPS, and prompt-event rows is the
host's responsibility, as are object-store, backup, analytics, cache, and export
retention policies.

## Who's using it

- [PaidCollabs](https://paidcollabs.com) — the screenshots above

Shipping it? [Open a PR](https://github.com/yshmarov/testimonials/pulls) and
add yourself.

## Development

```bash
bundle exec rake test
bundle exec rake test:system
bundle exec rubocop
node --check lib/testimonials/widget.js
node --check lib/testimonials/dashboard.js
```

The default suite covers the Rails engine contract. The system task drives a
real headless Chrome session from NPS through promoter handoff, testimonial
submission, moderation, and public read. CI runs Rails 7.1, 7.2, 8.0, and 8.1
against Ruby 3.2 through 4.0.

Bug reports and pull requests welcome. The fastest way to help is to install it
in a real app and
[tell me where it hurt](https://github.com/yshmarov/testimonials/issues).

## One family

Five Rails engines built on the same backbone, so adopting a second one is
mostly muscle memory:

| Gem | What it does |
| --- | --- |
| **testimonials** *(this gem)* | Testimonials, reviews and NPS — text and video, collected in your own app |
| [ideasbugs](https://github.com/yshmarov/ideasbugs) | In-app bug reports and feature requests, with a triage queue |
| [livechat](https://github.com/yshmarov/livechat) | Live chat between your visitors and your agents, self-hosted |
| [product_tours](https://github.com/yshmarov/product_tours) | Product tours and video tutorials, shown in-app at the right moment |
| [i18n_proofreading](https://github.com/yshmarov/i18n_proofreading) | In-context translation fixes suggested by your own users |

They share the install shape (`generate <gem>:install`, mount, one initializer),
the same host hooks (`base_controller_class` to inherit your admin's controller,
`admin_layout` for just the shell), one dashboard design system — the same
two-pane layout, colour tokens and components in all five, scoped so it cannot
touch your own CSS — and migrations that follow your app's `primary_key_type`.

## License

MIT. If it saved you a subscription, a
[⭐](https://github.com/yshmarov/testimonials) is a fair trade.
