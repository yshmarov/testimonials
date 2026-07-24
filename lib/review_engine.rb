# frozen_string_literal: true

require 'review_engine/version'
require 'review_engine/configuration'
require 'review_engine/engine'

# Testimonials, reviews and NPS for Rails. An iOS-style in-app widget collects
# star ratings and testimonials (text or video) at moments your code chooses;
# a public page collects them from shareable links; NPS promoters are routed
# straight into the testimonial ask. Everything lands in your own database
# with a minimal dashboard to approve, feature, and excerpt — and a read API
# to render approved testimonials wherever you like.
module ReviewEngine
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    # Can this request see the widget and submit? Checked on the server for
    # every public endpoint and by the helper before rendering.
    def enabled?(request)
      !!config.enabled.call(request)
    end

    # Can this request browse and triage submissions? Checked by every
    # dashboard action.
    def admin?(request)
      !!config.authorize_admin.call(request)
    end

    def app_name
      config.app_name.presence || rails_app_name
    end

    # The guiding questions for the current locale, with %{app} filled in.
    # I18n leaves the token alone when no interpolation values are passed,
    # so a plain gsub covers built-in, literal, and lambda-provided strings
    # alike.
    def questions
      list = config.questions
      list = list.call if list.respond_to?(:call)
      list = I18n.t('review_engine.questions', default: []) if list.nil?
      Array(list).map { |q| q.to_s.gsub('%{app}', app_name) }
    end

    def consent_text
      config.consent_text.presence ||
        I18n.t('review_engine.consent', default: 'You may publish this with my name and photo.')
    end

    private

    def rails_app_name
      Rails.application.class.module_parent_name.underscore.humanize
    rescue StandardError
      'this app'
    end
  end
end
