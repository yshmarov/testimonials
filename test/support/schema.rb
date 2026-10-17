# frozen_string_literal: true

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :testimonials_testimonials, force: true do |t|
    t.string :kind, null: false, default: 'text'
    t.text :body
    t.integer :rating
    t.text :best_line
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
    t.string :tenant
    t.timestamps
  end
  add_index :testimonials_testimonials, :status
  add_index :testimonials_testimonials, %i[tenant status consent_given]

  create_table :testimonials_nps_responses, force: true do |t|
    t.integer :score, null: false
    t.text :comment
    t.string :author_id
    t.string :name
    t.string :email
    t.string :page_url
    t.string :user_agent
    t.string :locale
    t.string :tenant
    t.timestamps
  end
  add_index :testimonials_nps_responses, %i[tenant score]

  create_table :testimonials_prompt_events, force: true do |t|
    t.string :kind, null: false
    t.string :action, null: false
    t.string :author_id
    t.string :visitor_token
    t.string :tenant
    t.timestamps
  end
  add_index :testimonials_prompt_events, %i[tenant author_id kind]
  add_index :testimonials_prompt_events, %i[tenant visitor_token kind]

  # Active Storage tables, so video and avatar attachments work in tests.
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
