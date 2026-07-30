# frozen_string_literal: true

module Testimonials
  # Host-tunable settings. Everything has a safe default, so a fresh install
  # works with zero configuration; the hooks below let an app decide who gets
  # prompted, who can triage, and how submissions are attributed.
  class Configuration
    # Shown in the widget ("Enjoying %{app}?") and interpolated into the
    # default questions. nil resolves to the Rails application name.
    attr_accessor :app_name

    # Per-request gate for the widget and the submission endpoints. Return
    # false to hide the widget and reject submissions for this request.
    attr_accessor :enabled

    # Per-request gate for the built-in dashboard. Defaults to development
    # only — override it before deploying, e.g. with an admin check.
    attr_accessor :authorize_admin

    # Resolve the current user for attribution (optional). Return an object
    # responding to #id, or nil. Receives the request.
    attr_accessor :current_user

    # Resolve the current tenant (optional, for multi-tenant apps). Return an
    # opaque key — a GlobalID, an id, a subdomain, a slug — or nil. Receives
    # the request; shaped exactly like current_user/authorize_admin. nil (the
    # default) is a single, global collection: today's behavior, unchanged.
    # Testimonials, NPS, the dashboard and the read API all scope to whatever
    # this returns. The recommended key is a GlobalID (`record.to_gid.to_s`),
    # which also matches the `has_testimonials` model concern.
    attr_accessor :tenant

    # Turn a resolved user into the attribution stored with a submission.
    # Return a hash with :name, :email, and optionally :title_company.
    # Receives whatever #current_user returned.
    attr_accessor :user_display

    # Guiding prompts shown above the message field and while recording —
    # they fight blank-page paralysis, they are not form fields. nil uses the
    # gem's built-in localized questions (`testimonials.questions`, with
    # %{app} interpolated). Override with an array of literal strings, or a
    # callable for host-side i18n: `-> { I18n.t("myapp.review_questions") }`.
    # An empty array hides the section.
    attr_accessor :questions

    # Video testimonials (recording and upload). Requires Active Storage.
    attr_accessor :video
    attr_accessor :max_video_seconds, :max_video_size

    # Headshot upload for guests on the public collection page. Requires
    # Active Storage.
    attr_accessor :avatars
    attr_accessor :max_avatar_size

    # The Active Storage service that stores uploads — video, its poster
    # frame, guest avatars — as a service name from the host's
    # config/storage.yml (e.g. a dedicated bucket or folder). nil, the
    # default, uses the environment's default service.
    attr_accessor :storage_service

    # Auto-prompt throttling. A user who dismissed the widget is not
    # auto-prompted again within `reprompt_after`; a user auto-prompted
    # `max_prompts` times without submitting is never auto-prompted again;
    # a user who submitted a testimonial is done for good. Explicit opens
    # (clicking your link) always work.
    attr_accessor :reprompt_after, :max_prompts

    # Consent line stored verbatim with each submission. nil uses the
    # localized default.
    attr_accessor :consent_text

    # The standalone collection page at "#{mount_path}/new" — for links you
    # send to customers outside the app. ON by default; set false to 404 it.
    attr_accessor :public_collection

    # Unauthenticated read access to the JSON API (approved + consented
    # records only). OFF by default: the API then answers only for admins.
    attr_accessor :public_api

    # NPS surveys ("How likely are you to recommend…", 0–10). Promoters
    # (9–10) are offered the testimonial form right after scoring.
    attr_accessor :nps
    attr_accessor :nps_reprompt_after

    # Called with each saved Testimonials::Testimonial or
    # Testimonials::NpsResponse — notify Slack, send an email. Runs inline
    # after save; keep it fast or hand off to a job.
    attr_accessor :on_submit

    # Called with each NPS response scored 0–6. Route it into your feedback
    # tool, e.g. create a FeedbackEngine::Feedback from nps.comment.
    attr_accessor :on_detractor

    # Per-IP throttle for the public endpoints, as keyword arguments for
    # Rails' rate limiter (Rails 7.2+; ignored on 7.1). Read once when the
    # controller loads — set it in an initializer. nil disables throttling.
    attr_accessor :rate_limit

    # Where the engine is mounted. The widget posts to paths under it, so
    # keep this in sync with the `mount` line in your routes.
    attr_accessor :mount_path

    def initialize
      @app_name = nil
      @enabled = ->(_request) { true }
      @authorize_admin = ->(_request) { Rails.env.development? }
      @current_user = ->(_request) {}
      @tenant = ->(_request) {}
      @user_display = lambda { |user|
        { name: user.try(:name), email: user.try(:email) }
      }
      @questions = nil
      @video = true
      @max_video_seconds = 120
      @max_video_size = 50 * 1024 * 1024
      @avatars = true
      @max_avatar_size = 5 * 1024 * 1024
      @storage_service = nil
      @reprompt_after = 90 * 24 * 60 * 60
      @max_prompts = 3
      @consent_text = nil
      @public_collection = true
      @public_api = false
      @nps = true
      @nps_reprompt_after = 90 * 24 * 60 * 60
      @on_submit = ->(_record) {}
      @on_detractor = ->(_nps_response) {}
      @rate_limit = { to: 5, within: 60 }
      @mount_path = '/testimonials'
    end

    def testimonials_endpoint = mount_path.chomp('/')
    def nps_endpoint = "#{mount_path.chomp('/')}/nps"
    def events_endpoint = "#{mount_path.chomp('/')}/events"

    # Video and avatars need Active Storage — both the config switch and the
    # host actually having it loaded.
    def video_enabled?
      video && defined?(::ActiveStorage) ? true : false
    end

    def avatars_enabled?
      avatars && defined?(::ActiveStorage) ? true : false
    end
  end
end
