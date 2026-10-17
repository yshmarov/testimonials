# frozen_string_literal: true

# A separate process: ractorize! freezes Rails and cannot share a process with
# the ordinary suite, whose tests deliberately replace configuration per test.
require 'tmpdir'
require 'fileutils'
require 'json'
require 'rack/mock'

ENV['RAILS_ENV'] = 'ractor'
ractor_directory = Dir.mktmpdir('testimonials-ractor-')
ENV['DATABASE_URL'] = "sqlite3:#{ractor_directory}/test.sqlite3"
at_exit { FileUtils.remove_entry(ractor_directory) }

require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'active_storage/engine' if ENV['RACTOR_MEDIA'] == '1'
require 'testimonials'
require 'global_id'
GlobalID.app = +'ractor-host'
require 'minitest/autorun'
require 'active_support/ractors'

raise 'Use Rails edge and Ruby 4.0+ for test:ractor' unless Rails::Application.method_defined?(:ractorize!) &&
                                                            defined?(Ractor.shareable_lambda)

ActiveSupport::Ractors.unshareable_proc_action = :raise
FileUtils.mkdir_p("#{ractor_directory}/config/environments")
File.write("#{ractor_directory}/config/environments/ractor.rb", "# Dedicated Ractor host\n")

class RactorHost < Rails::Application
  config.load_defaults 7.1
  config.secret_key_base = 'ractor-test-secret-not-used-outside-tests'
  config.eager_load = true
  config.enable_reloading = false
  config.hosts = []
  config.logger = ActiveSupport::Ractors::Logger.new(ENV['RACTOR_DEBUG'] ? $stderr : nil)
  config.cache_store = :null_store
  config.public_file_server.enabled = false
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
  config.active_record.maintain_test_schema = false
  config.i18n.available_locales = %i[en fr]
end
if defined?(ActiveStorage)
  RactorHost.config.active_storage.service = :ractor_test
  RactorHost.config.active_storage.service_configurations = {
    'ractor_test' => { 'service' => 'Disk', 'root' => "#{ractor_directory}/storage" }
  }
  RactorHost.config.active_job.queue_adapter = :inline
end
RactorHost.config.root = ractor_directory
File.write("#{ractor_directory}/config/routes.rb",
           "Rails.application.routes.draw { mount_testimonials at: '/testimonials' }\n")
Testimonials.config.enabled_environments = %w[ractor] if Testimonials.config.respond_to?(:enabled_environments)
# A shareable test counter. Mutable storage lives on the main Ractor, so the
# test proves that successive worker Ractors share a rate-limit bucket.
class RactorCounter
  @counts = {}

  def self.increment(key, _amount = 1, **_options)
    if Ractor.main?
      @counts[key] = @counts.fetch(key, 0) + 1
    else
      shared_key = Ractor.make_shareable(key, copy: true)
      ActiveSupport::Ractors.on_main(self) { increment(shared_key) }
    end
  end
end

Testimonials.config.rate_limit = Testimonials.config.rate_limit.merge(store: RactorCounter, to: 2, by: lambda {
  request.remote_ip
})
RactorHost.initialize!
require_relative '../support/schema'

RactorUser = Data.define(:id, :email, :name)
Testimonials.configure do |config|
  config.enabled = ->(request) { request.get_header('HTTP_X_DISABLED') != 'yes' }
  config.authorize_admin = ->(request) { request.get_header('HTTP_X_ADMIN') == 'yes' }
  config.current_user = lambda { |request|
    RactorUser.new(id: request.get_header('HTTP_X_USER'), email: 'ractor@example.com', name: 'Ractor visitor')
  }
  config.tenant = ->(request) { request.get_header('HTTP_X_TENANT') }
  config.on_submit = ->(record) { record.update_column(:title_company, 'notification ran') }
end
class RactorOrganizationBase < ActiveRecord::Base
  self.abstract_class = true
  has_testimonials(as: :parent_testimonials, key: ->(record) { record.tenant.to_s })
end

class RactorOrganization < RactorOrganizationBase
  self.table_name = 'testimonials_testimonials'
  include GlobalID::Identification

  has_testimonials(key: ->(record) { record.tenant.to_s })
  has_testimonials(as: :global_testimonials)
end
Rails.application.ractorize!

class RactorRequestsTest < Minitest::Test
  def start_request(method, path, params: {}, headers: {})
    input = params.is_a?(String) ? params : Rack::Utils.build_nested_query(params)
    content_type = headers.fetch('CONTENT_TYPE', 'application/x-www-form-urlencoded')
    options = headers.merge(method: method, 'CONTENT_TYPE' => content_type,
                            'CONTENT_LENGTH' => input.bytesize.to_s)
    env = Rack::MockRequest.env_for(path, options)
    env.delete('rack.input')
    env.delete('rack.errors')
    Ractor.new(env, input) do |environment, data|
      environment['rack.input'] = StringIO.new(data)
      environment['rack.errors'] = StringIO.new
      status, response_headers, response_body = Rails.application.call(environment)
      body = +''
      response_body.each { |part| body << part }
      response_body.close if response_body.respond_to?(:close)
      [status, response_headers, body]
    end
  end

  def request(...) = start_request(...).value

  def test_rate_limit_counts_across_worker_ractors
    headers = { 'REMOTE_ADDR' => '198.51.100.42', 'HTTP_X_USER' => 'rate-user' }
    params = { testimonial: { body: 'rate test', consent_given: '1' } }
    statuses = 3.times.map do
      request('POST', '/testimonials', params: params, headers: headers).first
    end
    assert_equal [201, 201, 429], statuses
  end

  def upload(path, fields:, field:, filename:, bytes:, content_type:, headers: {})
    boundary = 'ractor-upload-boundary'
    input = fields.map do |key, value|
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n"
    end.join
    input << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{field}\"; filename=\"#{filename}\"\r\n"
    input << "Content-Type: #{content_type}\r\n\r\n#{bytes}\r\n--#{boundary}--\r\n"
    headers = headers.merge('CONTENT_TYPE' => "multipart/form-data; boundary=#{boundary}",
                            'REMOTE_ADDR' => '198.51.100.43', 'HTTP_X_USER' => 'upload')
    request('POST', path, params: input, headers: headers)
  end

  def test_upload_runs_in_a_worker_ractor
    skip 'Run with RACTOR_MEDIA=1 for Active Storage integration' unless defined?(ActiveStorage)

    bytes = File.binread(File.expand_path('../fixtures/files/pixel.png', __dir__))
    status, _, body = upload('/testimonials',
                             fields: { 'testimonial[body]' => 'upload', 'testimonial[consent_given]' => '1' },
                             field: 'testimonial[avatar]', filename: 'pixel.png',
                             bytes: bytes, content_type: 'image/png',
                             headers: { 'HTTP_X_TENANT' => 'upload' })
    assert_equal 201, status, body
    record = Testimonials::Testimonial.find_by!(tenant: 'upload', body: 'upload')
    assert_equal bytes, record.avatar.download
    assert_equal Digest::MD5.base64digest(bytes), record.avatar.blob.checksum
  end

  def test_media_streams_through_the_authorized_engine_route
    skip 'Run with RACTOR_MEDIA=1 for Active Storage integration' unless defined?(ActiveStorage)

    bytes = 'ractor-media-bytes'
    record = Testimonials::Testimonial.create!(body: 'media', consent_given: true, tenant: 'media')
    record.avatar.attach(io: StringIO.new(bytes), filename: 'pixel.png', content_type: 'image/png',
                         metadata: { analyzed: true })
    path = "/testimonials/#{record.id}/avatar"
    allowed = { 'HTTP_X_ADMIN' => 'yes', 'HTTP_X_TENANT' => 'media' }
    status, _, body = request('GET', path, headers: { 'HTTP_X_TENANT' => 'media' })
    assert_equal 403, status, body
    status, headers, body = request('GET', path, headers: allowed)
    assert_equal 200, status, body
    assert_equal bytes, body
    assert_includes headers['cache-control'], 'private'
    assert_includes headers['cache-control'], 'no-store'
  end

  def test_host_model_resolvers_preserve_custom_and_inherited_keys
    Testimonials::Testimonial.create!(body: 'linked testimonial', tenant: 'organization')
    Testimonials::NpsResponse.create!(score: 9, tenant: 'organization')
    counts = Ractor.new do
      organization = RactorOrganization.new(tenant: 'organization')
      [organization.testimonials.where(body: 'linked testimonial').count,
       organization.testimonials_nps.count,
       organization.parent_testimonials.where(body: 'linked testimonial').count,
       organization.parent_testimonials_nps.count]
    end.value
    assert_equal [1, 1, 1, 1], counts
  end

  def test_default_global_id_resolver_runs_in_a_worker_ractor
    key = RactorOrganization.new(id: 501).to_gid.to_s
    Testimonials::Testimonial.create!(body: 'global testimonial', tenant: key)
    Testimonials::NpsResponse.create!(score: 9, tenant: key)
    counts = Ractor.new do
      organization = RactorOrganization.new(id: 501)
      [organization.global_testimonials.where(body: 'global testimonial').count,
       organization.global_testimonials_nps.count]
    end.value
    assert_equal [1, 1], counts
  end

  def test_simultaneous_worker_requests
    workers = 2.times.map { start_request('GET', '/testimonials/widget.js') }
    workers.each do |worker|
      status, _, body = worker.value
      assert_equal 200, status, body
    end
  end

  def test_assets_and_dashboard_render_in_non_main_ractors
    2.times do
      %w[widget.js dashboard.css dashboard.js].reject(&:empty?).each do |asset|
        status, headers, body = request('GET', "/testimonials/#{asset}")
        assert_equal 200, status, body
        refute_empty body
        assert_includes headers['content-type'], asset.end_with?('.css') ? 'css' : 'javascript'
      end
      status, _, body = request('GET', '/testimonials')
      assert_equal 403, status, body
      status, _, body = request('GET', '/testimonials', headers: { 'HTTP_X_ADMIN' => 'yes' })
      assert_equal 200, status, body
    end
  end

  def test_submissions_resolve_auth_tenant_and_notification_callbacks
    %w[alpha beta].each do |tenant|
      status, _, body = request('POST', '/testimonials',
                                params: { testimonial: { body: "Ractor #{tenant}", consent_given: '1' } },
                                headers: { 'HTTP_X_TENANT' => tenant, 'HTTP_X_USER' => tenant })
      assert_equal 201, status, body
      record = Testimonials::Testimonial.find_by!(tenant: tenant)
      assert_equal tenant, record.author_id
      assert_equal 'ractor@example.com', record.email
      assert_equal 'notification ran', record.title_company
    end
    status, _, body = request('GET', '/testimonials', headers: { 'HTTP_X_ADMIN' => 'yes', 'HTTP_X_TENANT' => 'alpha' })
    assert_equal 200, status, body
    assert_includes body, 'Ractor alpha'
    refute_includes body, 'Ractor beta'
    status, _, body = request('POST', '/testimonials', headers: { 'HTTP_X_DISABLED' => 'yes' })
    assert_equal 403, status, body
  end
end
