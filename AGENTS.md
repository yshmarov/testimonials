# AGENTS.md

Instructions for coding agents. Two audiences:

- **[Installing testimonials into a Rails app](#installing-into-a-rails-app)** — you are working in a host app and were asked to add testimonials, reviews, or NPS.
- **[Working on the gem itself](#working-on-the-gem-itself)** — you are working in this repository.

Requirements: Ruby >= 3.2, Rails >= 7.1. Active Storage only for video and avatar uploads.

If you are in a host app and this file is not in front of you, it ships inside the gem: `cat "$(bundle show testimonials)/AGENTS.md"`.

---

## Installing into a Rails app

### 1. Decide two things first — they are install-time flags

Both features can be added later, but skipping them now means smaller schema and less code reaching the database. Ask the user only if the answer isn't already obvious from their request.

| Question | If no |
| --- | --- |
| Do they want NPS (the 0–10 "how likely are you to recommend" survey)? | `--skip-nps` |
| Should the widget ever **open itself** — `testimonial_prompt!` at a success moment — rather than only on a click? | `--skip-prompt-events` |

Default to a full install when unsure. "Just let users leave reviews from a button in the menu" is the common case for `--skip-prompt-events`.

### 2. Install

```bash
bundle add testimonials
bin/rails generate testimonials:install    # + any --skip-* flags from step 1
bin/rails db:migrate
```

The generator writes `config/initializers/testimonials.rb`, one migration, and `mount_testimonials at: "/testimonials"` into `config/routes.rb`. Read the initializer it wrote — every option is documented there in comments, and it is the source of truth over any summary of it, including this file.

Every `config.…` line below belongs inside the `Testimonials.configure do |config|` block in that initializer. Uncomment and edit in place rather than appending a second `configure` block.

### 3. Wire the three things the generator cannot

**a. The widget tag.** Nothing renders until this is on the page:

```erb
<%# app/views/layouts/application.html.erb, before </body> %>
<%= testimonials_tag %>
```

The helper is injected into ActionView by the engine — no include, no import, no asset pipeline entry. It renders nothing until the widget is opened, and it must be present on any page where the widget can open.

**b. `authorize_admin` — do this before deploying.** The dashboard at `/testimonials` defaults to **development only**. It fails closed, so shipping without this is not an open door — it is a 403 telling you to set it.

```ruby
config.authorize_admin = ->(request) { request.env["warden"]&.user&.admin? }
```

**c. Attribution**, if the app has users. Optional, but without it every submission is a guest.

```ruby
config.current_user = ->(request) { request.env["warden"]&.user }   # Devise/Warden
config.user_display = ->(user) { { name: user.name, email: user.email } }
```

> **Every gate receives the raw `request`, not a controller.** `current_user`, `authorize_admin`, `enabled` and `tenant` are lambdas over `ActionDispatch::Request`. Writing `->(request) { current_user }` is the single most common mistake here — that method does not exist in this scope. Resolve the user *from the request*: Warden env, a signed cookie, `Current.user` if the app sets it in a middleware/`before_action` that has already run.

Rails 8 built-in auth:

```ruby
config.current_user = lambda do |request|
  token = request.cookies["session_token"]
  Session.find_signed(token)&.user if token
end
```

### 4. Verify

```bash
bin/rails routes | grep testimonials     # engine mounted
bin/rails testimonials:seed_demo         # optional sample data, idempotent
```

Then, in the running app: load any page and confirm `data-testimonials-config` appears in the HTML source, and that `/testimonials` renders the dashboard in development. The widget stays invisible until opened — an empty-looking page is correct.

### Opening the widget

| Way | Code | Throttled? |
| --- | --- | --- |
| Your own button | `<%= testimonials_button %>`, or any element with `data-testimonial-prompt` (`="nps"` for NPS) | No |
| JavaScript | `window.Testimonials.open()` / `window.Testimonials.openNps()` | No |
| From a controller, at a success moment | `testimonial_prompt!` / `testimonial_prompt!(:nps)` | Yes |

`testimonial_prompt!` is available in every controller (the engine includes it). It sets a flash and the widget auto-opens on the next rendered page **if** the throttle allows — already submitted, recently dismissed, or prompted `max_prompts` times means it stays shut. Call it liberally; that is the design.

```ruby
def create
  # ...
  testimonial_prompt! if current_user.invoices.count == 10
  redirect_to invoices_path
end
```

**On a `--skip-prompt-events` install `testimonial_prompt!` is a no-op** — with no history there is nothing to throttle with, and a prompt nothing can throttle would reopen on every page. Use an explicit opener instead, or add the ledger (see below).

### Rendering what was collected

The gem ships **no display UI** on purpose, and its own views are for the dashboard and the public pages only. Render approved testimonials with the host app's own markup:

```ruby
Testimonials::Testimonial.publishable.featured_first.limit(6)   # approved + publicly consented
Testimonials::Testimonial.publishable.for_tenant(key)           # multi-tenant
Testimonials::NpsResponse.score                                 # −100..100
```

`examples/` in the gem has copy-paste starting points: `wall_of_love.html.erb`, `testimonial_card.html.erb`, `badge.html.erb`, `json_ld.html.erb` (schema.org), `static_site.md`. Prefer adapting one over inventing a layout.

There is also a read API — `GET /testimonials/api/testimonials` (filters: `featured=1`, `min_rating=4`, `kind=video`, `limit=12`) and `GET /testimonials/api/stats`. Admin-only unless `config.public_api = true`. Emails and author ids are never serialized.

### Adding a skipped feature later

Order matters: **migrate first, then flip the flag.** The flag is what the code checks, so setting it before the table exists is the one broken state.

```bash
bin/rails generate testimonials:nps            # then db:migrate, then config.nps = true
bin/rails generate testimonials:prompt_events  # then db:migrate, then config.prompt_events = true
```

Both land on exactly the schema a full install produces, tenant column and indexes included.

### Multi-tenancy

One resolver returning an **opaque key** — GlobalID, id, subdomain, slug. The gem never takes a foreign key into host models:

```ruby
config.tenant = ->(request) { Current.organization&.to_gid&.to_s }
```

Optional sugar on a host model (`has_testimonials` is available on every Active Record class already):

```ruby
class Organization < ApplicationRecord
  has_testimonials   # keyed by to_gid.to_s — must match config.tenant
end
organization.testimonials.approved
```

`bin/rails generate testimonials:tenant` exists **only** to add the `tenant` column to installs made before it existed. A fresh install already has it, and running that generator will fail on a duplicate column. Do not run it as part of a new install.

### Do not

- **Do not hand-write the migration or the initializer.** Use the generators; the templates track the schema.
- **Do not copy `widget.js` into `app/javascript`, or add a `<script>` tag for it.** `testimonials_tag` renders both tags itself, and the engine serves the code at `/testimonials/widget.js` with a content fingerprint. There is no build step and nothing for esbuild/importmap/Tailwind to know about.
- **Do not edit views inside the gem.** To put the dashboard inside an existing admin, set `config.base_controller_class = "Admin::BaseController"` (it inherits that controller's layout, helpers, authentication and request context) or, for the shell alone, `config.admin_layout = "admin/application"`. The dashboard's stylesheet and script are declared by its views, so both work with nothing else wired up.
- **Do not check whether a table exists to decide if a feature is on.** `Testimonials.config.nps` and `Testimonials.config.prompt_events` are the source of truth, deliberately — nothing in the gem introspects the schema at runtime.
- **Do not set config outside the initializer.** `rate_limit` in particular is read once when the controller class loads; assigning config in a controller or per-request is a global mutation across the process.
- **Do not add `testimonials_tag` more than once per page,** and do not put it in a partial that some pages skip while still calling `testimonial_prompt!` — the prompt is consumed from the flash by whatever renders next.

### Configuration worth knowing

Everything is optional; a fresh install works with zero config. Full list with comments is in the generated initializer.

| Option | Default | Note |
| --- | --- | --- |
| `authorize_admin` | development only | **Set before deploying.** |
| `current_user`, `user_display`, `tenant`, `enabled` | no-ops | Lambdas over the raw request. |
| `nps` | `true` | `false` = no prompt, no public NPS page, no dashboard tab, no `nps_score`. |
| `prompt_events` | `true` | `false` = no prompt history, and therefore no auto-prompts at all. |
| `base_controller_class` | `ActionController::Base` | Controller the DASHBOARD inherits. Public endpoints never do, so an admin base controller here cannot gate the widget. |
| `reprompt_after`, `max_prompts` | `90.days`, `3` | Throttle for auto-prompts only. |
| `video`, `avatars` | `true` | Need Active Storage; they self-disable when it isn't loaded. |
| `public_collection` | `true` | `/testimonials/new` and `/testimonials/nps/new`. Shareable links. |
| `public_api` | `false` | Serves the read API without auth, CORS `*`. |
| `on_submit`, `on_detractor` | no-ops | Run inline after save — keep fast or enqueue a job. |
| `mount_path` | `"/testimonials"` | Must match `mount_testimonials at:` in routes. |
| `rate_limit` | `{ to: 5, within: 60 }` | Rails 7.2+; ignored on 7.1. `nil` disables. |

Turbo Drive and nonce-based CSP work out of the box; the widget config rides in a `type="application/json"` block (data, not code) and the code is a same-origin `src` script. 26 locales ship with the gem, including localized guiding questions.

### Common failure modes

| Symptom | Cause |
| --- | --- |
| `/testimonials` returns 403 "Set Testimonials.config.authorize_admin to grant access" | Exactly what it says: still at the development-only default. |
| Widget never appears | `testimonials_tag` missing from the rendered layout, or `config.enabled` returning false. |
| `testimonial_prompt!` never opens anything | `config.prompt_events` is false, or the user is throttled (submitted / dismissed recently / hit `max_prompts`). |
| `no such table: testimonials_nps_responses` (or `..._prompt_events`) | A flag was flipped to `true` before running the matching generator and `db:migrate`. |
| `/testimonials/nps_responses` 404s | `config.nps` is false. The rows are still there; flip it back to read them. |
| Video recording missing | Active Storage not installed, or `config.video = false`. |
| `NameError` for a host helper in the dashboard | `isolate_namespace` scopes `helper` to the engine. Use `config.base_controller_class` so the dashboard inherits your helpers, rather than `admin_layout` alone. |
| `NotNullViolation` attaching a video on a uuid-keyed app | The tables were generated bigint. Set `config.generators` `primary_key_type` before installing, or migrate the tables to uuid. |
| `undefined local variable current_user` in the initializer | A gate lambda treated its argument as a controller. It is a `request`. |

---

## One family

`ideasbugs`, `livechat`, `product_tours`, `i18n_proofreading` are the sibling engines. Same install shape, same host hooks (`base_controller_class`, `admin_layout`), same scoped dashboard CSS, same `primary_key_type`-aware migrations — so what you learn here transfers.

## Working on the gem itself

```bash
bundle exec rake test            # minitest, dummy app under test/dummy
bundle exec rubocop             # must be clean
BUNDLE_GEMFILE=gemfiles/rails_7.1.gemfile bundle exec rake test   # 7.1, 7.2, 8.0, 8.1 in gemfiles/
```

Layout: `app/` controllers, models, dashboard views · `lib/testimonials/` config, widget JS/CSS, seeds, engine · `lib/generators/testimonials/` install, nps, prompt_events, tenant · `config/locales/` 26 locales · `test/` minitest, `test/dummy` the host app · `examples/` display snippets for hosts.

Conventions this codebase holds to — follow them rather than the first thing that works:

- **Optional features are guarded by a config flag, never by schema introspection.** `--skip-nps` and `--skip-prompt-events` leave tables out; nothing may ask the database whether a table exists, and nothing may touch the database at boot. Guard at the entry points (one `before_action`, one model class method) so the flag is checked once, not at six call sites.
- **Every install shape gets a test that drops the table for real** (`test/integration/skip_nps_test.rb`, `skip_prompt_events_test.rb`), so a slipped guard raises `no such table` instead of passing quietly. Generator tests pin each migration and initializer shape and check the ERB still compiles as Ruby.
- **The widget is plain ES5-style JS in `lib/testimonials/widget.js`**, served by the engine, no build step, no framework. It reads its config from a JSON block on every `turbo:load`.
- **Display stays headless.** New display UI belongs in `examples/`, not in `app/views`.
- Every user-facing change bumps `lib/testimonials/version.rb` and adds a `CHANGELOG.md` entry that says what it costs, not only what it adds.
- Commit messages are prose that explains the tradeoff — read `git log` before writing one.
