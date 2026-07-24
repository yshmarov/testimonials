# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'read API', type: :request do
  before do
    Testimonials::Testimonial.create!(kind: 'text', body: 'Publishable', rating: 5, name: 'Ada',
                                      email: 'secret@example.com', status: 'approved', consent_given: true)
    Testimonials::Testimonial.create!(kind: 'text', body: 'No consent', status: 'approved', consent_given: false)
    Testimonials::Testimonial.create!(kind: 'text', body: 'Pending', status: 'pending', consent_given: true)
  end

  it 'is admin-only by default' do
    get '/testimonials/api/testimonials'
    expect(response).to have_http_status(:forbidden)

    as_admin!
    get '/testimonials/api/testimonials'
    expect(response).to have_http_status(:ok)
  end

  context 'with public_api on' do
    before { Testimonials.config.public_api = true }

    it 'serves only publishable records, without contact details' do
      get '/testimonials/api/testimonials'

      testimonials = response.parsed_body['testimonials']
      expect(testimonials.map { |t| t['body'] }).to eq(['Publishable'])
      expect(response.body).not_to include('secret@example.com')
      expect(testimonials.first).not_to have_key('email')
      expect(testimonials.first['name']).to eq('Ada')
    end

    it 'opens CORS' do
      get '/testimonials/api/testimonials'
      expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
    end

    it 'filters by featured and min_rating' do
      Testimonials::Testimonial.first.update!(featured: true)
      get '/testimonials/api/testimonials', params: { featured: '1', min_rating: 4 }
      expect(response.parsed_body['testimonials'].size).to eq(1)

      get '/testimonials/api/testimonials', params: { min_rating: 5 }
      expect(response.parsed_body['testimonials'].size).to eq(1)
    end

    it 'serves aggregate stats' do
      get '/testimonials/api/stats'
      stats = response.parsed_body
      expect(stats['count']).to eq(1)
      expect(stats['average_rating']).to eq(5.0)
      expect(stats['ratings_count']).to eq(1)
    end
  end
end
