# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require_relative 'spec_helper'
require_relative 'dummy/config/environment'
require 'rspec/rails'

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :testimonials_testimonials, force: true do |t|
    t.string :kind, null: false, default: 'text'
    t.text :body
    t.integer :rating
    t.text :excerpt
    t.string :status, null: false, default: 'pending'
    t.boolean :featured, null: false, default: false
    t.boolean :consent_given, null: false, default: false
    t.string :consent_text
    t.string :author_id
    t.string :name
    t.string :email
    t.string :title_company
    t.string :source, null: false, default: 'widget'
    t.string :page_url
    t.string :user_agent
    t.string :locale
    t.timestamps
  end
  add_index :testimonials_testimonials, :status
  add_index :testimonials_testimonials, %i[status consent_given]

  create_table :testimonials_nps_responses, force: true do |t|
    t.integer :score, null: false
    t.text :comment
    t.string :author_id
    t.string :name
    t.string :email
    t.string :page_url
    t.string :user_agent
    t.string :locale
    t.timestamps
  end
  add_index :testimonials_nps_responses, :score

  create_table :testimonials_prompt_events, force: true do |t|
    t.string :kind, null: false
    t.string :action, null: false
    t.string :author_id
    t.string :visitor_token
    t.timestamps
  end
  add_index :testimonials_prompt_events, %i[author_id kind]
  add_index :testimonials_prompt_events, %i[visitor_token kind]

  # Active Storage tables, so video and avatar attachments work in specs.
  create_table :active_storage_blobs, force: true do |t|
    t.string :key, null: false
    t.string :filename, null: false
    t.string :content_type
    t.text :metadata
    t.string :service_name, null: false
    t.bigint :byte_size, null: false
    t.string :checksum
    t.datetime :created_at, null: false
    t.index [:key], unique: true
  end

  create_table :active_storage_attachments, force: true do |t|
    t.string :name, null: false
    t.string :record_type, null: false
    t.bigint :record_id, null: false
    t.bigint :blob_id, null: false
    t.datetime :created_at, null: false
    t.index [:blob_id]
    t.index %i[record_type record_id name blob_id],
            unique: true, name: 'index_active_storage_attachments_uniqueness'
  end

  create_table :active_storage_variant_records, force: true do |t|
    t.bigint :blob_id, null: false
    t.string :variation_digest, null: false
    t.index %i[blob_id variation_digest],
            unique: true, name: 'index_active_storage_variant_records_uniqueness'
  end
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!

  # Start every example from a fresh config, so a stub in one example can never
  # leak into another under random order.
  config.around do |example|
    Testimonials.instance_variable_set(:@config, Testimonials::Configuration.new)
    example.run
    Testimonials.instance_variable_set(:@config, nil)
  end

  # The rate limiter counts per IP in Rails.cache; without a reset, create
  # requests from earlier examples would trip the limit for later ones.
  config.before { Rails.cache.clear }
end

# Most request specs need an admin; the default gate is development-only.
def as_admin!
  Testimonials.config.authorize_admin = ->(_request) { true }
end
