# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'dashboard', type: :request do
  let!(:testimonial) do
    Testimonials::Testimonial.create!(kind: 'text', body: 'Wonderful tool', name: 'Ada', rating: 4)
  end

  it 'is forbidden without authorize_admin' do
    get '/testimonials'
    expect(response).to have_http_status(:forbidden)
  end

  it 'serves the dashboard helper script (CSP-safe, no inline handlers)' do
    get '/testimonials/dashboard.js'
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/javascript')
    expect(response.body).to include('data-confirm')
  end

  context 'as an admin' do
    before { as_admin! }

    it 'loads the helper script and uses no inline JS handlers' do
      get '/testimonials'
      expect(response.body).to include('src="/testimonials/dashboard.js?v=')
      expect(response.body).not_to include('onchange=')
      expect(response.body).to include('data-autosubmit')

      get "/testimonials/#{testimonial.id}"
      expect(response.body).not_to include('onsubmit=')
      expect(response.body).to include('data-confirm')
    end

    it 'lists testimonials by status tab' do
      get '/testimonials'
      expect(response.body).to include('Wonderful tool')

      get '/testimonials', params: { status: 'approved' }
      expect(response.body).not_to include('Wonderful tool')
    end

    it 'searches text, name, and email' do
      get '/testimonials', params: { q: 'wonder' }
      expect(response.body).to include('Wonderful tool')

      get '/testimonials', params: { q: 'nothing-matches' }
      expect(response.body).not_to include('Wonderful tool')
    end

    it 'approves, features, excerpts, and deletes' do
      patch "/testimonials/#{testimonial.id}", params: { testimonial: { status: 'approved' } }
      expect(testimonial.reload.status).to eq('approved')

      patch "/testimonials/#{testimonial.id}", params: { testimonial: { featured: true } }
      expect(testimonial.reload.featured).to be(true)

      patch "/testimonials/#{testimonial.id}", params: { testimonial: { excerpt: 'Wonderful' } }
      expect(testimonial.reload.quote).to eq('Wonderful')

      delete "/testimonials/#{testimonial.id}"
      expect(Testimonials::Testimonial.count).to eq(0)
    end

    it 'shows the NPS tab with the score' do
      [10, 10, 0].each { |score| Testimonials::NpsResponse.create!(score: score, comment: "c#{score}") }
      get '/testimonials/nps_responses'
      expect(response.body).to include('c10')
      # 2 promoters, 1 detractor of 3 → 67 - 33 = 33 (rounded)
      expect(response.body).to include('33')
    end
  end
end
