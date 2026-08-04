# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'
require_relative '../migration_helpers'

module Testimonials
  module Generators
    # For apps that installed with --skip-nps and later want the 0–10 survey:
    # creates the testimonials_nps_responses table. A full install already has
    # it. Additive and safe — nothing reads the table until config.nps is true.
    #
    #   bin/rails generate testimonials:nps && bin/rails db:migrate
    class NpsGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      include MigrationHelpers

      source_root File.expand_path('templates', __dir__)

      desc 'Adds the NPS responses table for an install that skipped it.'

      def create_migration_file
        migration_template 'create_testimonials_nps_responses.rb.tt',
                           'db/migrate/create_testimonials_nps_responses.rb'
      end

      def post_install
        say "\nNPS table queued. Run `rails db:migrate`, then set", :green
        say 'config.nps = true in config/initializers/testimonials.rb to turn the flow on.'
      end
    end
  end
end
