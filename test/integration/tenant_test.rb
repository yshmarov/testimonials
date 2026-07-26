# frozen_string_literal: true

require 'test_helper'

module Testimonials
  # Multi-tenancy: with config.tenant set, every read and write scopes to the
  # resolved tenant. Here the resolver reads a request param so a single test
  # can act as different tenants; a real app would resolve from the session,
  # subdomain, or Current.
  class TenantTest < ActionDispatch::IntegrationTest
    setup do
      Testimonials.config.tenant = ->(request) { request.params[:tenant].presence }
    end

    def approved!(body:, tenant:, rating: 5)
      Testimonial.create!(kind: 'text', body: body, rating: rating,
                          status: 'approved', consent_given: true, tenant: tenant)
    end

    # --- writes stamp the tenant --------------------------------------------

    test 'a widget submission is stamped with the resolved tenant' do
      post '/testimonials', params: { tenant: 'acme', testimonial: { body: 'Acme is great', rating: 5 } }
      assert_response :created
      assert_equal 'acme', Testimonial.last.tenant
    end

    test 'with no tenant resolved a submission stays in the global collection' do
      post '/testimonials', params: { testimonial: { body: 'no tenant', rating: 4 } }
      assert_response :created
      assert_nil Testimonial.last.tenant
    end

    # --- dashboard is scoped -------------------------------------------------

    test 'the dashboard shows only the current tenant, with scoped counts' do
      approved!(body: 'Acme testimonial', tenant: 'acme').update!(status: 'pending')
      approved!(body: 'Globex testimonial', tenant: 'globex').update!(status: 'pending')
      as_admin!

      get '/testimonials', params: { tenant: 'acme' }
      assert_response :ok
      assert_includes response.body, 'Acme testimonial'
      assert_not_includes response.body, 'Globex testimonial'
    end

    test 'an admin cannot open, edit, or delete another tenant record' do
      other = approved!(body: 'Globex only', tenant: 'globex')
      as_admin!

      get "/testimonials/#{other.id}", params: { tenant: 'acme' }
      assert_response :not_found

      patch "/testimonials/#{other.id}", params: { tenant: 'acme', testimonial: { featured: true } }
      assert_response :not_found

      delete "/testimonials/#{other.id}", params: { tenant: 'acme' }
      assert_response :not_found
      assert Testimonial.exists?(other.id)
    end

    # --- read API is scoped --------------------------------------------------

    test 'the read API returns only the current tenant testimonials' do
      approved!(body: 'Acme public', tenant: 'acme')
      approved!(body: 'Globex public', tenant: 'globex')
      Testimonials.config.public_api = true

      get '/testimonials/api/testimonials', params: { tenant: 'acme' }
      bodies = response.parsed_body['testimonials'].map { |t| t['body'] }
      assert_equal ['Acme public'], bodies
    end

    test 'stats count only the current tenant' do
      approved!(body: 'a', tenant: 'acme', rating: 5)
      approved!(body: 'b', tenant: 'acme', rating: 3)
      approved!(body: 'c', tenant: 'globex', rating: 1)
      Testimonials.config.public_api = true

      get '/testimonials/api/stats', params: { tenant: 'acme' }
      body = response.parsed_body
      assert_equal 2, body['count']
      assert_equal 4.0, body['average_rating']
    end

    # --- one review per user, per tenant -------------------------------------

    test 'the same signed-in user gets a separate review in each tenant' do
      Testimonials.config.current_user = ->(_request) { fake_user }

      post '/testimonials', params: { tenant: 'acme', testimonial: { body: 'in acme', rating: 5 } }
      post '/testimonials', params: { tenant: 'globex', testimonial: { body: 'in globex', rating: 5 } }
      assert_equal 2, Testimonial.count

      # A re-submission in acme edits the acme review in place, not globex's.
      post '/testimonials', params: { tenant: 'acme', testimonial: { body: 'edited in acme', rating: 4 } }
      assert_equal 2, Testimonial.count
      assert_equal 1, Testimonial.for_tenant('acme').where(author_id: '42').count
      assert_equal 'edited in acme', Testimonial.for_tenant('acme').where(author_id: '42').first.body
    end

    # --- NPS is scoped -------------------------------------------------------

    test 'NPS submissions are stamped and the NPS dashboard is scoped' do
      post '/testimonials/nps', params: { tenant: 'acme', nps: { score: 9 } }
      assert_response :created
      assert_equal 'acme', NpsResponse.last.tenant

      NpsResponse.create!(score: 0, tenant: 'globex')
      as_admin!
      get '/testimonials/nps_responses', params: { tenant: 'acme' }
      assert_response :ok
      # One promoter in acme, the globex detractor is not counted.
      assert_includes response.body, '1'
    end

    # --- media isolation -----------------------------------------------------

    test 'media of another tenant is not reachable' do
      testimonial = Testimonial.create!(kind: 'video', tenant: 'acme',
                                        status: 'approved', consent_given: true)
      testimonial.video_file.attach(io: StringIO.new('bytes'), filename: 'v.webm', content_type: 'video/webm')
      as_admin!

      get "/testimonials/#{testimonial.id}/video", params: { tenant: 'globex' }
      assert_response :not_found

      get "/testimonials/#{testimonial.id}/video", params: { tenant: 'acme' }
      assert_response :redirect # found in-tenant, handed to Active Storage
    end
  end
end
