# frozen_string_literal: true

require 'test_helper'

class ApiTest < ActionDispatch::IntegrationTest
  setup do
    Testimonials::Testimonial.create!(kind: 'text', body: 'Publishable', rating: 5, name: 'Ada',
                                      email: 'secret@example.com', status: 'approved', consent_given: true)
    Testimonials::Testimonial.create!(kind: 'text', body: 'No consent', status: 'approved', consent_given: false)
    Testimonials::Testimonial.create!(kind: 'text', body: 'Pending', status: 'pending', consent_given: true)
  end

  test 'is admin-only by default' do
    get '/testimonials/api'
    assert_response :forbidden

    as_admin!
    get '/testimonials/api'
    assert_response :ok
  end

  test 'serves only publishable records, without contact details' do
    Testimonials.config.public_api = true
    get '/testimonials/api'

    testimonials = response.parsed_body['testimonials']
    assert_equal(['Publishable'], testimonials.map { |t| t['body'] })
    refute_includes response.body, 'secret@example.com'
    refute testimonials.first.key?('email')
    assert_equal 'Ada', testimonials.first['name']
  end

  test 'opens CORS when public' do
    Testimonials.config.public_api = true
    get '/testimonials/api'
    assert_equal '*', response.headers['Access-Control-Allow-Origin']
  end

  test 'filters by featured and min_rating' do
    Testimonials.config.public_api = true
    Testimonials::Testimonial.first.update!(featured: true)

    get '/testimonials/api', params: { featured: '1', min_rating: 4 }
    assert_equal 1, response.parsed_body['testimonials'].size

    get '/testimonials/api', params: { min_rating: 5 }
    assert_equal 1, response.parsed_body['testimonials'].size
  end

  test 'serves aggregate stats' do
    Testimonials.config.public_api = true
    get '/testimonials/api/stats'

    stats = response.parsed_body
    assert_equal 1, stats['count']
    assert_in_delta 5.0, stats['average_rating']
    assert_equal 1, stats['ratings_count']
  end
end
