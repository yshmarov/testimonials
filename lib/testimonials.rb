# frozen_string_literal: true

require 'testimonials/version'
require 'testimonials/configuration'
require 'testimonials/widget'
require 'testimonials/widget_helper'
require 'testimonials/prompt_helper'
require 'testimonials/has_testimonials'
require 'testimonials/seeds'
require 'testimonials/engine'

# Testimonials, reviews and NPS for Rails. An iOS-style in-app widget collects
# star ratings and testimonials (text or video) at moments your code chooses;
# a public page collects them from shareable links; NPS promoters are routed
# straight into the testimonial ask. Everything lands in your own database
# with a minimal dashboard to approve, feature, and pick best lines — and a read API
# to render approved testimonials wherever you like.
module Testimonials
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

    # The class Testimonials::DashboardController inherits from. Resolved on
    # every call rather than memoized, so a host that reassigns
    # base_controller_class in a reloadable initializer is not pinned to a
    # stale, unloaded constant.
    def base_controller
      config.base_controller_class.to_s.constantize
    end

    # Can this request browse and triage submissions? Checked by every
    # dashboard action.
    def admin?(request)
      !!config.authorize_admin.call(request)
    end

    def app_name
      config.app_name.presence || rails_app_name
    end

    # The tenant key for this request, or nil for the single global collection.
    # Normalized to a string so `where(tenant:)` is consistent whether the
    # resolver returns a GlobalID, an integer id, or a slug. Blank resolves to
    # nil — an app that only sometimes has a tenant falls back to global.
    def tenant(request)
      config.tenant.call(request).presence&.to_s
    end

    # Testimonials belonging to a host record, keyed by its GlobalID — the
    # documented tenant convention. Sugar for `Testimonial.for_tenant(...)`;
    # the `has_testimonials` model concern is built on this.
    def for(record)
      Testimonial.for_tenant(tenant_key_for(record))
    end

    # The NPS responses belonging to a host record, same keying as `.for`.
    def nps_for(record)
      NpsResponse.for_tenant(tenant_key_for(record))
    end

    # The guiding questions for the current locale, with %{app} filled in.
    # I18n leaves the token alone when no interpolation values are passed,
    # so a plain gsub covers built-in, literal, and lambda-provided strings
    # alike.
    def questions
      list = config.questions
      list = list.call if list.respond_to?(:call)
      list = I18n.t('testimonials.questions', default: []) if list.nil?
      Array(list).map { |q| q.to_s.gsub('%{app}', app_name) }
    end

    # The public-use consent line, stored verbatim when a customer allows
    # their testimonial to be shown publicly. Override with config.consent_text.
    def consent_text
      config.consent_text.presence ||
        I18n.t('testimonials.consent_public',
               default: 'You can use my testimonial publicly in your marketing and sales.')
    end

    # The private-use line, stored when a customer allows only internal use.
    def consent_text_private
      I18n.t('testimonials.consent_private',
             default: 'You can only use my testimonial privately in your marketing and sales.')
    end

    # The exact line the customer agreed to, given their public/private choice.
    def consent_text_for(public_use)
      public_use ? consent_text : consent_text_private
    end

    private

    # A host record's tenant key: its GlobalID string. Kept in one place so
    # `.for`, `.nps_for` and the `has_testimonials` concern agree — and so a
    # host wiring `config.tenant = ->(r){ Current.org.to_gid.to_s }` lines up
    # with `organization.testimonials`.
    def tenant_key_for(record)
      record.respond_to?(:to_gid) ? record.to_gid.to_s : record.to_s
    end

    # The application's module name, verbatim ("EthicsPortal", "SupeRails") —
    # no inflection games. Set config.app_name for anything fancier.
    def rails_app_name
      Rails.application.class.module_parent_name
    rescue StandardError
      'this app'
    end
  end
end
