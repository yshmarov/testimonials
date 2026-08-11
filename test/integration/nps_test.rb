# frozen_string_literal: true

require 'test_helper'

class NpsTest < ActionDispatch::IntegrationTest
  test 'stores a response and offers the testimonial form to eligible promoters' do
    post '/testimonials/nps', params: { nps: { score: 10, comment: 'Superb' } }

    assert_response :created
    assert response.parsed_body['offer_testimonial']
    assert_equal 10, Testimonials::NpsResponse.last.score
  end

  test 'stores only a safe query-free source page' do
    post '/testimonials/nps', params: {
      nps: { score: 8, page_url: 'https://example.com/success?session=secret#done' }
    }
    assert_equal 'https://example.com/success', Testimonials::NpsResponse.last.page_url

    post '/testimonials/nps', params: { nps: { score: 8, page_url: 'data:text/html,unsafe' } }
    assert_nil Testimonials::NpsResponse.last.page_url
  end

  test 'does not offer the testimonial form to passives or detractors' do
    post '/testimonials/nps', params: { nps: { score: 7 } }
    refute response.parsed_body['offer_testimonial']
  end

  test 'does not re-ask promoters who already submitted a testimonial' do
    Testimonials.config.current_user = ->(_request) { fake_user }
    Testimonials::PromptEvent.record!(kind: 'testimonial', action: 'submitted', author_id: '42')

    post '/testimonials/nps', params: { nps: { score: 10 } }
    refute response.parsed_body['offer_testimonial']
  end

  test 'routes detractors into on_detractor' do
    routed = []
    Testimonials.config.on_detractor = ->(nps) { routed << nps.score }

    post '/testimonials/nps', params: { nps: { score: 2, comment: 'meh' } }
    assert_equal [2], routed
  end

  test 'records the submission in the throttle ledger' do
    assert_difference -> { Testimonials::PromptEvent.where(kind: 'nps', action: 'submitted').count } do
      post '/testimonials/nps', params: { nps: { score: 8 } }
    end
  end

  test 'the dashboard reads the score against the benchmarks' do
    as_admin!
    [10, 10, 10, 5].each { |s| Testimonials::NpsResponse.create!(score: s) }

    get '/testimonials/nps_responses'

    assert_response :ok
    # 3 promoters, 1 detractor of 4: 75 - 25 = 50, which is "Great".
    assert_includes response.body, 'nps-band-great">Great'
    assert_includes response.body, 'data-nps-marker="50"'
    # Four responses is too thin a sample to read anything into.
    assert_includes response.body, 'Based on 4 responses'
    # The formula and the bands are on the page, so nobody has to go and google.
    assert_includes response.body, 'How is this calculated'
    assert_includes response.body, 'World-class, and rare.'
  end

  test 'the dashboard shows no band or marker before any responses arrive' do
    as_admin!

    get '/testimonials/nps_responses'

    assert_response :ok
    refute_includes response.body, 'data-nps-marker'
    refute_includes response.body, 'Based on 0 responses'
    # The guide stands on its own without a score to read.
    assert_includes response.body, 'How is this calculated'
  end

  test 'is off when config.nps is false' do
    Testimonials.config.nps = false
    post '/testimonials/nps', params: { nps: { score: 10 } }
    assert_response :forbidden
  end

  test 'the dashboard is gone when config.nps is false' do
    as_admin!
    response_record = Testimonials::NpsResponse.create!(score: 9)
    Testimonials.config.nps = false

    # An install run with --skip-nps has no table behind these pages.
    get '/testimonials/nps_responses'
    assert_response :not_found

    get "/testimonials/nps_responses/#{response_record.id}"
    assert_response :not_found

    # And the dashboard nav does not offer a link to them.
    get '/testimonials'
    assert_response :ok
    refute_includes response.body, 'nps_responses'
  end
end
