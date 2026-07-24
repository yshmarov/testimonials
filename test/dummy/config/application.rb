# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "active_storage/engine"

require "testimonials"

module Dummy
  class Application < Rails::Application
    # Pin the root to spec/dummy; otherwise Rails walks up to the gem repo (it has
    # a Gemfile) and can't find config/database.yml.
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 7.1
    config.eager_load = false
    # The schema is defined inline by test_helper; there is no db/schema.rb.
    config.active_record.maintain_test_schema = false
    config.secret_key_base = "testimonials-dummy-secret"
    config.i18n.available_locales = %i[en fr]
    config.i18n.default_locale = :en

    # A nonce-based CSP, so specs can assert the widget script is nonced.
    config.content_security_policy do |policy|
      policy.script_src :self
    end
    config.content_security_policy_nonce_generator = ->(_request) { "testnonce" }
    config.content_security_policy_nonce_directives = %w[script-src]
  end
end
