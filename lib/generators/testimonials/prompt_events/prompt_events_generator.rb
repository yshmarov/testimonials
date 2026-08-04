# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module Testimonials
  module Generators
    # For apps that installed with --skip-prompt-events and later want
    # auto-prompts: creates the testimonials_prompt_events table, the ledger
    # the throttle reads. A full install already has it. Additive and safe —
    # nothing reads or writes the table until config.prompt_events is true.
    #
    #   bin/rails generate testimonials:prompt_events && bin/rails db:migrate
    class PromptEventsGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Adds the prompt history table for an install that skipped it.'

      def create_migration_file
        migration_template 'create_testimonials_prompt_events.rb.tt',
                           'db/migrate/create_testimonials_prompt_events.rb'
      end

      def post_install
        say "\nPrompt history table queued. Run `rails db:migrate`, then set", :green
        say 'config.prompt_events = true in config/initializers/testimonials.rb to let'
        say 'testimonial_prompt! auto-open the widget again.'
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
