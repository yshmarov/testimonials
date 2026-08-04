# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'
require_relative '../migration_helpers'

module Testimonials
  module Generators
    # For apps that installed testimonials before multi-tenancy: adds the
    # nullable `tenant` column (and its indexes) to the three tables. A fresh
    # install already gets these via the install generator — run this one only
    # to upgrade an existing install. Additive and safe: existing rows keep a
    # nil tenant (the single global collection), so nothing changes until you
    # set config.tenant.
    #
    #   bin/rails generate testimonials:tenant && bin/rails db:migrate
    class TenantGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      include MigrationHelpers

      source_root File.expand_path('templates', __dir__)

      desc 'Adds the tenant column to existing testimonials tables (multi-tenancy upgrade).'

      def create_migration_file
        migration_template 'add_tenant_to_testimonials.rb.tt',
                           'db/migrate/add_tenant_to_testimonials.rb'
      end

      def post_install
        say "\ntenant column queued. Run `rails db:migrate`, then set", :green
        say 'config.tenant in config/initializers/testimonials.rb to scope per tenant.'
      end
    end
  end
end
