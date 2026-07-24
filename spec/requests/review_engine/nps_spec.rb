# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'NPS', type: :request do
  let(:user) { Struct.new(:id, :name, :email).new(42, 'Ada', 'ada@example.com') }

  it 'stores a response and offers the testimonial form to eligible promoters' do
    post '/reviews/nps', params: { nps: { score: 10, comment: 'Superb' } }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['offer_testimonial']).to be(true)
    expect(ReviewEngine::NpsResponse.last.score).to eq(10)
  end

  it 'does not offer the testimonial form to passives or detractors' do
    post '/reviews/nps', params: { nps: { score: 7 } }
    expect(response.parsed_body['offer_testimonial']).to be(false)
  end

  it 'does not re-ask promoters who already submitted a testimonial' do
    ReviewEngine.config.current_user = ->(_request) { user }
    ReviewEngine::PromptEvent.record!(kind: 'testimonial', action: 'submitted', author_id: '42')

    post '/reviews/nps', params: { nps: { score: 10 } }
    expect(response.parsed_body['offer_testimonial']).to be(false)
  end

  it 'routes detractors into on_detractor' do
    routed = []
    ReviewEngine.config.on_detractor = ->(nps) { routed << nps.score }

    post '/reviews/nps', params: { nps: { score: 2, comment: 'meh' } }
    expect(routed).to eq([2])
  end

  it 'records the submission in the throttle ledger' do
    expect { post '/reviews/nps', params: { nps: { score: 8 } } }
      .to change { ReviewEngine::PromptEvent.where(kind: 'nps', action: 'submitted').count }.by(1)
  end

  it 'is off when config.nps is false' do
    ReviewEngine.config.nps = false
    post '/reviews/nps', params: { nps: { score: 10 } }
    expect(response).to have_http_status(:forbidden)
  end
end
