# frozen_string_literal: true

require 'test_helper'

class WidgetTagTest < ActionDispatch::IntegrationTest
  test 'renders the widget with a CSP nonce and no auto-open by default' do
    get '/sample'
    assert_includes response.body, 'data-testimonials-config'
    assert_includes response.body, '<script src="/testimonials/widget.js?v='
    assert_includes response.body, 'nonce="testnonce"'
    assert_includes response.body, '"autoOpen":null'
  end

  test 'serves the widget code as same-origin JavaScript with an ETag' do
    get '/testimonials/widget.js'
    assert_response :ok
    assert_equal 'text/javascript', response.media_type
    assert_includes response.body, 'testimonials widget'
    assert_includes response.body, 'data-testimonial-prompt'
    assert_includes response.body, 'openNps'
    assert response.headers['ETag'].present?
  end

  test 'renders nothing when disabled' do
    Testimonials.config.enabled = ->(_request) { false }
    get '/sample'
    refute_includes response.body, 'data-testimonials-config'
  end

  test 'testimonial_prompt! auto-opens on the next page for an eligible user, once' do
    post '/sample/celebrate'
    follow_redirect!
    assert_includes response.body, '"autoOpen":"testimonial"'

    # The flash is consumed: a further page load does not re-prompt.
    get '/sample'
    assert_includes response.body, '"autoOpen":null'
  end

  test 'testimonial_prompt! supports nps' do
    post '/sample/celebrate', params: { kind: 'nps' }
    follow_redirect!
    assert_includes response.body, '"autoOpen":"nps"'
  end

  test 'testimonial_prompt! respects the throttle ledger' do
    Testimonials.config.current_user = ->(_request) { fake_user }
    Testimonials::PromptEvent.record!(kind: 'testimonial', action: 'submitted', author_id: '42')

    post '/sample/celebrate'
    follow_redirect!
    assert_includes response.body, '"autoOpen":null'
  end

  test 'testimonial_prompt! ignores unknown kinds' do
    post '/sample/celebrate', params: { kind: 'nonsense' }
    follow_redirect!
    assert_includes response.body, '"autoOpen":null'
  end

  test 'testimonials_button renders a localized opener' do
    get '/sample'
    assert_includes response.body, 'data-testimonial-prompt'
    assert_includes response.body, '>Leave a review</button>'
  end

  test 'testimonials_button switches to the update label once the user has a review' do
    Testimonials.config.current_user = ->(_request) { fake_user }
    Testimonials::Testimonial.create!(kind: 'text', body: 'Mine', author_id: '42')

    get '/sample'
    assert_includes response.body, '>Update your review</button>'
  end

  test 'carries the signed-in user\'s review in the widget config' do
    Testimonials.config.current_user = ->(_request) { fake_user }
    Testimonials::Testimonial.create!(kind: 'text', body: 'My old review', rating: 4,
                                      author_id: '42', consent_given: true)

    get '/sample'
    assert_includes response.body,
                    '"existing":{"rating":4,"body":"My old review","consent":true,' \
                    '"videoUrl":null,"posterUrl":null}'
  end

  test 'existing is null for users without a review' do
    get '/sample'
    assert_includes response.body, '"existing":null'
  end

  test 'events endpoint records shown/dismissed and hands guests a visitor cookie' do
    post '/testimonials/events', params: { kind: 'testimonial', event_action: 'shown' }
    assert_response :no_content

    event = Testimonials::PromptEvent.last
    assert_equal 'shown', event.action
    assert event.visitor_token.present?
    assert_equal event.visitor_token, cookies['testimonials_vid']
  end

  test 'events endpoint rejects unknown actions (submitted is server-side only)' do
    post '/testimonials/events', params: { kind: 'testimonial', event_action: 'submitted' }
    assert_response :unprocessable_entity
    assert_equal 0, Testimonials::PromptEvent.count
  end

  test 'public collection page serves the inline form by default' do
    get '/testimonials/new'
    assert_response :ok
    assert_includes response.body, 'data-testimonials-inline'
    assert_includes response.body, '"mode":"page"'
  end

  test 'public collection page disappears when public_collection is off' do
    Testimonials.config.public_collection = false
    get '/testimonials/new'
    assert_response :not_found
  end

  test 'public NPS page serves the inline NPS card by default' do
    get '/testimonials/nps/new'
    assert_response :ok
    assert_includes response.body, 'data-testimonials-inline'
    assert_includes response.body, '"mode":"nps_page"'
  end

  test 'public NPS page disappears when nps is off' do
    Testimonials.config.nps = false
    get '/testimonials/nps/new'
    assert_response :not_found
  end

  test 'public NPS page disappears when public_collection is off' do
    Testimonials.config.public_collection = false
    get '/testimonials/nps/new'
    assert_response :not_found
  end

  test 'public NPS page is gated by the enabled lambda' do
    Testimonials.config.enabled = ->(_request) { false }
    get '/testimonials/nps/new'
    assert_response :forbidden
  end
end
