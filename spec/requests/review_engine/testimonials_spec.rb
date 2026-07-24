# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'testimonial submission', type: :request do
  let(:user) { Struct.new(:id, :name, :email).new(42, 'Ada Lovelace', 'ada@example.com') }

  it 'stores a guest text testimonial with consent snapshot and locale' do
    post '/reviews/testimonials', params: {
      testimonial: { body: 'Love it!', rating: 5, consent_given: '1',
                     name: 'Grace', email: 'grace@example.com', page_url: 'http://x/pricing' }
    }

    expect(response).to have_http_status(:created)
    testimonial = ReviewEngine::Testimonial.last
    expect(testimonial.kind).to eq('text')
    expect(testimonial.status).to eq('pending')
    expect(testimonial.rating).to eq(5)
    expect(testimonial.name).to eq('Grace')
    expect(testimonial.consent_given).to be(true)
    expect(testimonial.consent_text).to eq(ReviewEngine.consent_text)
    expect(testimonial.locale).to eq('en')
  end

  it 'attributes signed-in users server-side, ignoring client contact fields' do
    ReviewEngine.config.current_user = ->(_request) { user }

    post '/reviews/testimonials', params: {
      testimonial: { body: 'Great', name: 'Mallory', email: 'spoof@example.com' }
    }

    testimonial = ReviewEngine::Testimonial.last
    expect(testimonial.author_id).to eq('42')
    expect(testimonial.name).to eq('Ada Lovelace')
    expect(testimonial.email).to eq('ada@example.com')
  end

  it 'records a submitted event in the throttle ledger' do
    ReviewEngine.config.current_user = ->(_request) { user }

    expect do
      post '/reviews/testimonials', params: { testimonial: { body: 'Great' } }
    end.to change { ReviewEngine::PromptEvent.where(kind: 'testimonial', action: 'submitted').count }.by(1)

    expect(ReviewEngine::PromptEvent.last.author_id).to eq('42')
  end

  it 'updates a signed-in user\'s existing review in place, back through moderation' do
    ReviewEngine.config.current_user = ->(_request) { user }
    existing = ReviewEngine::Testimonial.create!(kind: 'text', body: 'Old words', rating: 3,
                                                 author_id: '42', status: 'approved',
                                                 excerpt: 'Old', consent_given: true)

    post '/reviews/testimonials', params: { testimonial: { body: 'New words', rating: 5, consent_given: '1' } }

    expect(response).to have_http_status(:created)
    expect(ReviewEngine::Testimonial.count).to eq(1)
    existing.reload
    expect(existing.body).to eq('New words')
    expect(existing.rating).to eq(5)
    expect(existing.status).to eq('pending')
    expect(existing.excerpt).to be_nil
  end

  it 'keeps guest submissions as separate records' do
    ReviewEngine::Testimonial.create!(kind: 'text', body: 'First guest', name: 'G', email: 'g@example.com')

    post '/reviews/testimonials', params: {
      testimonial: { body: 'Second guest', name: 'G', email: 'g@example.com' }
    }

    expect(ReviewEngine::Testimonial.count).to eq(2)
  end

  it 'rejects blank text testimonials' do
    post '/reviews/testimonials', params: { testimonial: { body: '' } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'accepts a video upload and flips the kind' do
    file = Rack::Test::UploadedFile.new(
      StringIO.new('fake video bytes'), 'video/webm', original_filename: 'testimonial.webm'
    )
    post '/reviews/testimonials', params: { testimonial: { body: '', video_file: file } }

    expect(response).to have_http_status(:created)
    testimonial = ReviewEngine::Testimonial.last
    expect(testimonial.kind).to eq('video')
    expect(testimonial.video_file).to be_attached
  end

  it 'rejects oversized videos' do
    ReviewEngine.config.max_video_size = 4
    file = Rack::Test::UploadedFile.new(
      StringIO.new('too many bytes'), 'video/webm', original_filename: 'testimonial.webm'
    )
    post '/reviews/testimonials', params: { testimonial: { video_file: file } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(ReviewEngine::Testimonial.count).to eq(0)
  end

  it 'rejects non-video uploads in the video slot' do
    file = Rack::Test::UploadedFile.new(
      StringIO.new('<html>'), 'text/html', original_filename: 'evil.html'
    )
    post '/reviews/testimonials', params: { testimonial: { video_file: file } }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'is gated by config.enabled' do
    ReviewEngine.config.enabled = ->(_request) { false }
    post '/reviews/testimonials', params: { testimonial: { body: 'x' } }
    expect(response).to have_http_status(:forbidden)
  end

  it 'survives a raising on_submit hook' do
    ReviewEngine.config.on_submit = ->(_record) { raise 'boom' }
    post '/reviews/testimonials', params: { testimonial: { body: 'Still saved' } }
    expect(response).to have_http_status(:created)
    expect(ReviewEngine::Testimonial.count).to eq(1)
  end
end
