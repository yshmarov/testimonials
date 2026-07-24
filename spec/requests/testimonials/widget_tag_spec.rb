# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'widget tag and prompt flow', type: :request do
  let(:user) { Struct.new(:id, :name, :email).new(42, 'Ada', 'ada@example.com') }

  it 'renders the widget with a CSP nonce and no auto-open by default' do
    get '/sample'
    expect(response.body).to include('data-testimonials-config')
    expect(response.body).to include('<script src="/testimonials/widget.js" defer nonce="testnonce"')
    expect(response.body).to include('"autoOpen":null')
  end

  it 'serves the widget code as same-origin JavaScript' do
    get '/testimonials/widget.js'
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/javascript')
    expect(response.body).to include('testimonials widget')
    expect(response.headers['ETag']).to be_present
  end

  it 'renders nothing when disabled' do
    Testimonials.config.enabled = ->(_request) { false }
    get '/sample'
    expect(response.body).not_to include('data-testimonials-config')
  end

  describe 'testimonial_prompt!' do
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
      Testimonials.config.current_user = ->(_request) { user }
      Testimonials::PromptEvent.record!(kind: 'testimonial', action: 'submitted', author_id: '42')

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

  describe 'testimonials_button' do
    it 'renders a localized opener with the gem\'s own strings' do
      get '/sample'
      expect(response.body).to include('data-testimonial-prompt')
      expect(response.body).to include('>Leave a review</button>')
    end

    it 'switches to the update label once the user has a review' do
      Testimonials.config.current_user = ->(_request) { user }
      Testimonials::Testimonial.create!(kind: 'text', body: 'Mine', author_id: '42')

      get '/sample'
      expect(response.body).to include('>Update your review</button>')
    end
  end

  describe 'existing review prefill' do
    it 'carries the signed-in user\'s review — rating, body, consent, video — in the widget config' do
      Testimonials.config.current_user = ->(_request) { user }
      Testimonials::Testimonial.create!(kind: 'text', body: 'My old review', rating: 4,
                                        author_id: '42', consent_given: true)

      get '/sample'
      expect(response.body)
        .to include('"existing":{"rating":4,"body":"My old review","consent":true,"videoUrl":null}')
    end

    it 'is null for users without a review' do
      get '/sample'
      expect(response.body).to include('"existing":null')
    end
  end

  describe 'events endpoint' do
    it 'records shown/dismissed and hands guests a visitor cookie' do
      post '/testimonials/events', params: { kind: 'testimonial', event_action: 'shown' }
      expect(response).to have_http_status(:no_content)

      event = Testimonials::PromptEvent.last
      expect(event.action).to eq('shown')
      expect(event.visitor_token).to be_present
      expect(response.cookies['testimonials_vid']).to eq(event.visitor_token)
    end

    it 'rejects unknown actions (submitted is server-side only)' do
      post '/testimonials/events', params: { kind: 'testimonial', event_action: 'submitted' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Testimonials::PromptEvent.count).to eq(0)
    end
  end

  describe 'public collection page' do
    it 'serves the inline form by default' do
      get '/testimonials/new'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testimonials-inline')
      expect(response.body).to include('"mode":"page"')
    end

    it 'disappears when public_collection is off' do
      Testimonials.config.public_collection = false
      get '/testimonials/new'
      expect(response).to have_http_status(:not_found)
    end
  end
end
