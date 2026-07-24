# frozen_string_literal: true

require 'json'

module ReviewEngine
  # Serves the self-contained browser widget. The JavaScript is plain ES (no
  # framework, no build step) and styles itself inline, so it drops into any
  # Rails app regardless of its CSS or JS setup. It is inlined into the page
  # rather than served as a separate asset to avoid any dependency on the
  # host's asset pipeline — and it lives under lib/ (not app/assets/) so a
  # host that *does* run a pipeline never ingests it either.
  module Widget
    SOURCE = File.expand_path('widget.js', __dir__)

    # Right-to-left scripts, so the form renders mirrored for those locales.
    # Matched on the language subtag, so region variants ("ar-EG") count too.
    RTL_LANGUAGES = %w[ar arc ckb dv fa ha he ks ku ps sd ug ur yi].freeze

    class << self
      def javascript
        @javascript ||= File.read(SOURCE)
      end

      # The two <script> tags the helper renders.
      #
      # The config rides in a `type="application/json"` block: it is *data*,
      # not code, so the browser never executes it and Turbo never tries to
      # re-run it on a soft visit — which means it needs no CSP nonce and the
      # widget can re-read the *current* page's config on every `turbo:load`.
      #
      # The code is a same-origin `src` script served by the engine — NOT
      # inlined. Under a nonce-based CSP, Turbo Drive body swaps re-run body
      # scripts against the *original* page's CSP header, so a fresh inline
      # nonce gets refused; a same-origin src is covered by `'self'` on every
      # visit. `nonce:` is still stamped for hosts whose script-src has no
      # 'self'; pass nil when the app has no nonce.
      def snippet(locale:, authenticated:, auto_open: nil, mode: 'widget', existing: nil, nonce: nil)
        json = config_json(locale:, authenticated:, auto_open:, mode:, existing:)
        nonce_attr = nonce ? %( nonce="#{nonce}") : ''
        src = "#{ReviewEngine.config.mount_path.chomp('/')}/widget.js"

        %(<script type="application/json" data-review-engine-config>#{json}</script>) +
          %(<script src="#{src}" defer#{nonce_attr} data-review-engine-widget></script>)
      end

      def config_json(locale:, authenticated:, auto_open:, mode:, existing: nil)
        config = ReviewEngine.config
        payload = {
          endpoints: {
            testimonials: config.testimonials_endpoint,
            nps: config.nps_endpoint,
            events: config.events_endpoint
          },
          locale: locale.to_s,
          rtl: rtl?(locale),
          authenticated: authenticated ? true : false,
          autoOpen: auto_open&.to_s,
          mode: mode.to_s,
          questions: ReviewEngine.questions,
          consent: ReviewEngine.consent_text,
          # The signed-in user's current review, if any: the widget opens it
          # pre-filled for editing instead of starting a second one — rating,
          # text, consent state, and a playable URL for an attached video.
          existing: existing && {
            rating: existing.rating,
            body: existing.body,
            consent: existing.consent_given ? true : false,
            videoUrl: existing_video_url(existing)
          },
          video: {
            enabled: config.video_enabled?,
            maxSeconds: config.max_video_seconds.to_i,
            maxSize: config.max_video_size.to_i
          },
          avatars: {
            enabled: config.avatars_enabled?,
            maxSize: config.max_avatar_size.to_i
          },
          nps: { enabled: config.nps ? true : false },
          labels: labels
        }
        # Escape "</" so a value can't close the <script> block early.
        payload.to_json.gsub('</', '<\/')
      end

      private

      def existing_video_url(existing)
        return unless existing.video_attached?

        "#{ReviewEngine.config.mount_path.chomp('/')}/testimonials/#{existing.id}/video"
      end

      # Every user-facing string in the widget, resolved through Rails I18n so
      # the form follows the app's current locale. Each lookup carries an
      # English default, so the widget stays fully worded even when a key is
      # missing for the active locale.
      def labels
        app = ReviewEngine.app_name
        {
          enjoying: t(:enjoying, 'Enjoying %{app}?', app: app),
          notNow: t(:not_now, 'Not now'),
          rateAria: t(:rate_aria, 'Rate %{count} of 5'),
          shareTitle: t(:share_title, 'Share your experience'),
          updateTitle: t(:update_title, 'Update your review'),
          promoterTitle: t(:promoter_title, 'Glad to hear it! Mind saying that publicly?'),
          questionsTitle: t(:questions_title, 'Questions'),
          message: t(:message, 'Your testimonial'),
          messagePlaceholder: t(:message_placeholder, 'What would you tell a friend about %{app}?', app: app),
          recordVideo: t(:record_video, 'Record a video'),
          recordVideoHint: t(:record_video_hint, 'A short video says more than a page of text.'),
          name: t(:name, 'Your name'),
          email: t(:email, 'Your email'),
          titleCompany: t(:title_company, 'Title, company'),
          photo: t(:photo, 'Your photo'),
          optional: t(:optional, 'optional'),
          submit: t(:submit, 'Send'),
          cancel: t(:cancel, 'Cancel'),
          close: t(:close, 'Close'),
          thanks: t(:thanks, 'Thank you so much!'),
          videoCheckTitle: t(:video_check_title, 'Camera check'),
          videoHint: t(:video_hint, 'Up to %{seconds} seconds. You can review it before sending.',
                       seconds: ReviewEngine.config.max_video_seconds.to_i),
          startRecording: t(:start_recording, 'Start recording'),
          stopRecording: t(:stop_recording, 'Stop'),
          recordAgain: t(:record_again, 'Record again'),
          useVideo: t(:use_video, 'Use this video'),
          uploadInstead: t(:upload_instead, 'Upload a video file instead'),
          videoAttached: t(:video_attached, 'Video attached'),
          remove: t(:remove, 'Remove'),
          npsQuestion: t(:nps_question, 'How likely are you to recommend %{app} to a friend or colleague?', app: app),
          npsLow: t(:nps_low, 'Not at all likely'),
          npsHigh: t(:nps_high, 'Extremely likely'),
          npsCommentLabel: t(:nps_comment_label, "What's the main reason for your score?"),
          errorBlank: t(:error_blank, 'Please write something or record a video.'),
          errorContact: t(:error_contact, 'Please enter your name and email.'),
          errorSave: t(:error_save, 'Could not send. Please try again.'),
          errorVideoTooLarge: t(:error_video_too_large, 'The video is too large (max %{size} MB).',
                                size: ReviewEngine.config.max_video_size.to_i / (1024 * 1024)),
          errorCamera: t(:error_camera, 'Could not access the camera. You can upload a video file instead.')
        }
      end

      def t(key, default, **args)
        I18n.t(key, scope: :review_engine, default: default, **args)
      end

      def rtl?(locale)
        RTL_LANGUAGES.include?(locale.to_s.downcase.split(/[-_]/).first)
      end
    end
  end
end
