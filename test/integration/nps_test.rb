# frozen_string_literal: true

require 'test_helper'

class NpsTest < ActionDispatch::IntegrationTest
  test 'stores a response and offers the testimonial form to eligible promoters' do
    post '/testimonials/nps', params: { nps: { score: 10, comment: 'Superb' } }

    assert_response :created
    assert response.parsed_body['offer_testimonial']
    assert_equal 10, Testimonials::NpsResponse.last.score
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

  test 'is off when config.nps is false' do
    Testimonials.config.nps = false
    post '/testimonials/nps', params: { nps: { score: 10 } }
    assert_response :forbidden
  end
end
