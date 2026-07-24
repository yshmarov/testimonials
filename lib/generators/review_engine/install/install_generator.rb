# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module ReviewEngine
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Installs review_engine: config initializer, migration, and engine mount.'

      def create_initializer
        copy_file 'initializer.rb', 'config/initializers/review_engine.rb'
      end

      def create_migration_file
        migration_template 'create_review_engine_tables.rb.tt',
                           'db/migrate/create_review_engine_tables.rb'
      end

      def mount_engine
        route %(mount ReviewEngine::Engine => "/reviews")
      end

      def post_install
        say "\nreview_engine installed. Run `rails db:migrate`, then add", :green
        say '`<%= review_engine_tag %>` before </body> in your layout.'
        say 'Triage testimonials at /reviews (development only until you set config.authorize_admin).'
        say "Collect from outside the app via /reviews/new.\n"
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
