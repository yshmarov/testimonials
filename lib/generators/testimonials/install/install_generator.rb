# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module Testimonials
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Installs testimonials: config initializer, migration, and engine mount.'

      # NPS is the one part of the gem an app can genuinely not want. Skipping
      # it leaves out the table and writes `config.nps = false`, so nothing
      # ever reaches a table that isn't there — no runtime introspection, no
      # boot-time database call. `testimonials:nps` adds it later.
      class_option :skip_nps, type: :boolean, default: false,
                              desc: 'Leave out the NPS table and turn the NPS flow off'

      def create_initializer
        template 'initializer.rb.tt', 'config/initializers/testimonials.rb'
      end

      def create_migration_file
        migration_template 'create_testimonials_tables.rb.tt',
                           'db/migrate/create_testimonials_tables.rb'
      end

      def mount_engine
        route %(mount_testimonials at: "/testimonials")
      end

      def post_install
        say "\ntestimonials installed. Run `rails db:migrate`, then add", :green
        say '`<%= testimonials_tag %>` before </body> in your layout.'
        say 'Triage testimonials at /testimonials (development only until you set config.authorize_admin).'
        samples = options[:skip_nps] ? 'testimonials' : 'testimonials and NPS'
        say "Optional: run `bin/rails testimonials:seed_demo` for sample #{samples}."
        say "Collect from outside the app via /testimonials/new.\n"
        return unless options[:skip_nps]

        say 'Installed without NPS. Add it later with `bin/rails generate testimonials:nps`.', :yellow
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
