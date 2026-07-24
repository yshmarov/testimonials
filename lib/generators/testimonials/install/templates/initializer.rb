# frozen_string_literal: true

Testimonials.configure do |config|
  # Shown in the widget ("Enjoying %{app}?") and interpolated into the
  # default questions. Defaults to your Rails application name.
  # config.app_name = "My App"

  # Who sees the widget and can submit. Return false to hide and reject for
  # this request. Defaults to everyone.
  # config.enabled = ->(request) { true }

  # Who can triage testimonials at the mount path. Defaults to development
  # only — override before deploying.
  # config.authorize_admin = ->(request) { request.env["warden"]&.user&.admin? }

  # Attribute submissions to a user (optional). Return an object responding
  # to #id, or nil. Receives the request.
  # config.current_user = ->(request) { request.env["warden"]&.user }

  # Attribution stored with a signed-in user's submission.
  # config.user_display = ->(user) { { name: user.name, email: user.email } }

  # Guiding prompts shown above the message field (not form fields).
  # Default nil = the gem's built-in localized questions. Override with
  # literal strings, or a lambda for host-side i18n. [] hides the section.
  # config.questions = ["How has %{app} helped you?", "What's the best part?"]
  # config.questions = -> { I18n.t("reviews.questions") }

  # Video testimonials (requires Active Storage).
  # config.video = true
  # config.max_video_seconds = 120
  # config.max_video_size = 50.megabytes

  # Guest headshot upload on the public collection page (requires Active Storage).
  # config.avatars = true
  # config.max_avatar_size = 5.megabytes

  # Auto-prompt throttling. Explicit opens (user clicked your link) bypass it.
  # config.reprompt_after = 90.days
  # config.max_prompts = 3

  # Consent line stored verbatim with each submission. nil = localized default:
  # "I give permission to use this testimonial across social channels and
  # other marketing efforts."
  # config.consent_text = "..."

  # The standalone collection page at /testimonials/new — share it with customers
  # outside the app. Set false to disable.
  # config.public_collection = true

  # Unauthenticated read access to GET /testimonials/api/testimonials and
  # /testimonials/api/stats (approved + consented records only). Off = admins only.
  # config.public_api = false

  # NPS surveys. Promoters (9–10) are offered the testimonial form right away.
  # config.nps = true
  # config.nps_reprompt_after = 90.days

  # Called with each saved Testimonial or NpsResponse — notify Slack, email…
  # config.on_submit = ->(record) {}

  # Called with each NPS response scored 0–6.
  # config.on_detractor = ->(nps) {}

  # Per-IP throttle for public endpoints (Rails 7.2+; ignored on 7.1).
  # config.rate_limit = { to: 5, within: 1.minute }

  # Keep in sync with the `mount` in config/routes.rb.
  # config.mount_path = "/testimonials"
end
