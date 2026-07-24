# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'dashboard', type: :request do
  let!(:testimonial) do
    ReviewEngine::Testimonial.create!(kind: 'text', body: 'Wonderful tool', name: 'Ada', rating: 4)
  end

  it 'is forbidden without authorize_admin' do
    get '/reviews'
    expect(response).to have_http_status(:forbidden)
  end

  context 'as an admin' do
    before { as_admin! }

    it 'lists testimonials by status tab' do
      get '/reviews'
      expect(response.body).to include('Wonderful tool')

      get '/reviews', params: { status: 'approved' }
      expect(response.body).not_to include('Wonderful tool')
    end

    it 'searches text, name, and email' do
      get '/reviews', params: { q: 'wonder' }
      expect(response.body).to include('Wonderful tool')

      get '/reviews', params: { q: 'nothing-matches' }
      expect(response.body).not_to include('Wonderful tool')
    end

    it 'approves, features, excerpts, and deletes' do
      patch "/reviews/#{testimonial.id}", params: { testimonial: { status: 'approved' } }
      expect(testimonial.reload.status).to eq('approved')

      patch "/reviews/#{testimonial.id}", params: { testimonial: { featured: true } }
      expect(testimonial.reload.featured).to be(true)

      patch "/reviews/#{testimonial.id}", params: { testimonial: { excerpt: 'Wonderful' } }
      expect(testimonial.reload.quote).to eq('Wonderful')

      delete "/reviews/#{testimonial.id}"
      expect(ReviewEngine::Testimonial.count).to eq(0)
    end

    it 'shows the NPS tab with the score' do
      [10, 10, 0].each { |score| ReviewEngine::NpsResponse.create!(score: score, comment: "c#{score}") }
      get '/reviews/nps_responses'
      expect(response.body).to include('c10')
      # 2 promoters, 1 detractor of 3 → 67 - 33 = 33 (rounded)
      expect(response.body).to include('33')
    end
  end
end
