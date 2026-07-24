# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module Testimonials
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Installs testimonials: config initializer, migration, and engine mount.'

      def create_initializer
        copy_file 'initializer.rb', 'config/initializers/testimonials.rb'
      end

      def create_migration_file
        migration_template 'create_testimonials_tables.rb.tt',
                           'db/migrate/create_testimonials_tables.rb'
      end

      def mount_engine
        route %(mount Testimonials::Engine => "/testimonials")
      end

      def post_install
        say "\ntestimonials installed. Run `rails db:migrate`, then add", :green
        say '`<%= testimonials_tag %>` before </body> in your layout.'
        say 'Triage testimonials at /testimonials (development only until you set config.authorize_admin).'
        say "Collect from outside the app via /testimonials/new.\n"
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
