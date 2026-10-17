# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require_relative 'dummy/config/environment'
require 'rails/test_help'
require 'rack/test'

require_relative 'support/schema'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1200, 900]
end

module ActiveSupport
  class TestCase
    # This suite does not use transactional tests, and that is deliberate.
    #
    # Two things here escape a wrapping transaction. Attaching an Active Storage
    # blob does — the tests that record video leave their rows behind — and the
    # skip_*_test classes drop a table outright, which ends the transaction in
    # SQLite. Rollback then silently stops undoing anything, rows escape into
    # unrelated tests, and something far away fails on a count it never touched:
    # order dependent, not reproducible from the seed alone, and miserable to
    # trace back (it cost a bisect through the whole suite once already).
    #
    # So nothing here relies on rollback. Every test starts from empty tables
    # because the one before it emptied them, whatever it did.
    self.use_transactional_tests = false

    # Start every test from a fresh config, so a tweak in one test can never
    # leak into another. The rate limiter counts per IP in Rails.cache, so
    # clear that too.
    setup do
      Testimonials.instance_variable_set(:@config, Testimonials::Configuration.new)
      Rails.cache.clear
    end

    teardown do
      Testimonials.instance_variable_set(:@config, nil)
      # Generator tests only write files. They have no rows to clean up, and
      # giving them database work of their own is how a "database is locked"
      # turns up in a test that never opened a connection.
      purge_testimonials_data! unless generator_test?
    end

    private

    def generator_test?
      defined?(::Rails::Generators::TestCase) && is_a?(::Rails::Generators::TestCase)
    end

    # Wipes every table the gem owns, including the Active Storage rows its
    # attachments create. Runs after each test — see the note above.
    def purge_testimonials_data!
      # table_exists? because the skip_*_test classes drop a table for the
      # length of a test, and this must not care whether their teardown has
      # already put it back.
      [Testimonials::Testimonial, Testimonials::NpsResponse, Testimonials::PromptEvent].each do |model|
        model.delete_all if model.table_exists?
      end
      return unless defined?(::ActiveStorage)

      ActiveStorage::Attachment.delete_all
      ActiveStorage::Blob.delete_all
    end

    # Most dashboard tests need an admin; the default gate is development-only.
    def as_admin!
      Testimonials.config.authorize_admin = ->(_request) { true }
    end

    def fake_user(id: 42, name: 'Ada Lovelace', email: 'ada@example.com')
      Struct.new(:id, :name, :email).new(id, name, email)
    end

    def fake_video(name: 'testimonial.webm', content: 'fake video bytes', type: 'video/webm')
      Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: name)
    end
  end
end
