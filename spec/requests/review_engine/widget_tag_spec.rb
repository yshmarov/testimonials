# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'widget tag and prompt flow', type: :request do
  let(:user) { Struct.new(:id, :name, :email).new(42, 'Ada', 'ada@example.com') }

  it 'renders the widget with a CSP nonce and no auto-open by default' do
    get '/sample'
    expect(response.body).to include('data-review-engine-config')
    expect(response.body).to include('data-review-engine-widget nonce="testnonce"')
    expect(response.body).to include('"autoOpen":null')
  end

  it 'renders nothing when disabled' do
    ReviewEngine.config.enabled = ->(_request) { false }
    get '/sample'
    expect(response.body).not_to include('data-review-engine-config')
  end

  describe 'review_prompt!' do
    it 'auto-opens on the next page for an eligible user' do
      post '/sample/celebrate'
      follow_redirect!
      expect(response.body).to include('"autoOpen":"testimonial"')

      # The flash is consumed: a further page load does not re-prompt.
      get '/sample'
      expect(response.body).to include('"autoOpen":null')
    end

    it 'supports nps prompts' do
      post '/sample/celebrate', params: { kind: 'nps' }
      follow_redirect!
      expect(response.body).to include('"autoOpen":"nps"')
    end

    it 'respects the throttle ledger' do
      ReviewEngine.config.current_user = ->(_request) { user }
      ReviewEngine::PromptEvent.record!(kind: 'testimonial', action: 'submitted', author_id: '42')

      post '/sample/celebrate'
      follow_redirect!
      expect(response.body).to include('"autoOpen":null')
    end

    it 'ignores unknown kinds' do
      post '/sample/celebrate', params: { kind: 'nonsense' }
      follow_redirect!
      expect(response.body).to include('"autoOpen":null')
    end
  end

  describe 'events endpoint' do
    it 'records shown/dismissed and hands guests a visitor cookie' do
      post '/reviews/events', params: { kind: 'testimonial', event_action: 'shown' }
      expect(response).to have_http_status(:no_content)

      event = ReviewEngine::PromptEvent.last
      expect(event.action).to eq('shown')
      expect(event.visitor_token).to be_present
      expect(response.cookies['review_engine_vid']).to eq(event.visitor_token)
    end

    it 'rejects unknown actions (submitted is server-side only)' do
      post '/reviews/events', params: { kind: 'testimonial', event_action: 'submitted' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(ReviewEngine::PromptEvent.count).to eq(0)
    end
  end

  describe 'public collection page' do
    it 'serves the inline form by default' do
      get '/reviews/new'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-review-engine-inline')
      expect(response.body).to include('"mode":"page"')
    end

    it 'disappears when public_collection is off' do
      ReviewEngine.config.public_collection = false
      get '/reviews/new'
      expect(response).to have_http_status(:not_found)
    end
  end
end
