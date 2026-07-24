# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'testimonial submission', type: :request do
  let(:user) { Struct.new(:id, :name, :email).new(42, 'Ada Lovelace', 'ada@example.com') }

  it 'stores a guest text testimonial with consent snapshot and locale' do
    post '/testimonials', params: {
      testimonial: { body: 'Love it!', rating: 5, consent_given: '1',
                     name: 'Grace', email: 'grace@example.com', page_url: 'http://x/pricing' }
    }

    expect(response).to have_http_status(:created)
    testimonial = Testimonials::Testimonial.last
    expect(testimonial.kind).to eq('text')
    expect(testimonial.status).to eq('pending')
    expect(testimonial.rating).to eq(5)
    expect(testimonial.name).to eq('Grace')
    expect(testimonial.consent_given).to be(true)
    expect(testimonial.consent_text).to eq(Testimonials.consent_text)
    expect(testimonial.locale).to eq('en')
  end

  it 'attributes signed-in users server-side, ignoring client contact fields' do
    Testimonials.config.current_user = ->(_request) { user }

    post '/testimonials', params: {
      testimonial: { body: 'Great', name: 'Mallory', email: 'spoof@example.com' }
    }

    testimonial = Testimonials::Testimonial.last
    expect(testimonial.author_id).to eq('42')
    expect(testimonial.name).to eq('Ada Lovelace')
    expect(testimonial.email).to eq('ada@example.com')
  end

  it 'records a submitted event in the throttle ledger' do
    Testimonials.config.current_user = ->(_request) { user }

    expect do
      post '/testimonials', params: { testimonial: { body: 'Great' } }
    end.to change { Testimonials::PromptEvent.where(kind: 'testimonial', action: 'submitted').count }.by(1)

    expect(Testimonials::PromptEvent.last.author_id).to eq('42')
  end

  it 'updates a signed-in user\'s existing review in place, back through moderation' do
    Testimonials.config.current_user = ->(_request) { user }
    existing = Testimonials::Testimonial.create!(kind: 'text', body: 'Old words', rating: 3,
                                                 author_id: '42', status: 'approved',
                                                 best_line: 'Old', consent_given: true)

    post '/testimonials', params: { testimonial: { body: 'New words', rating: 5, consent_given: '1' } }

    expect(response).to have_http_status(:created)
    expect(Testimonials::Testimonial.count).to eq(1)
    existing.reload
    expect(existing.body).to eq('New words')
    expect(existing.rating).to eq(5)
    expect(existing.status).to eq('pending')
    expect(existing.best_line).to be_nil
  end

  it 'keeps an attached video on a text-only update, and purges it when asked' do
    Testimonials.config.current_user = ->(_request) { user }
    file = Rack::Test::UploadedFile.new(
      StringIO.new('fake video bytes'), 'video/webm', original_filename: 'testimonial.webm'
    )
    post '/testimonials', params: { testimonial: { body: '', video_file: file } }
    testimonial = Testimonials::Testimonial.last

    post '/testimonials', params: { testimonial: { body: 'Now with words' } }
    testimonial.reload
    expect(testimonial.kind).to eq('video')
    expect(testimonial.video_file).to be_attached

    post '/testimonials', params: { testimonial: { body: 'Words only now', remove_video: '1' } }
    testimonial.reload
    expect(testimonial.kind).to eq('text')
    expect(testimonial.video_file).not_to be_attached
  end

  it 'rate-limits guest submissions per IP' do
    statuses = 7.times.map do |i|
      post '/testimonials', params: { testimonial: { body: "spam #{i}", name: 'B', email: 'b@example.com' } }
      response.status
    end

    expect(statuses.first(5)).to all(eq(201))
    expect(statuses.last(2)).to all(eq(429))
    expect(Testimonials::Testimonial.count).to eq(5)
  end

  it 'serves video downloads with attachment disposition' do
    Testimonials.config.current_user = ->(_request) { user }
    file = Rack::Test::UploadedFile.new(
      StringIO.new('fake video bytes'), 'video/webm', original_filename: 'testimonial.webm'
    )
    post '/testimonials', params: { testimonial: { video_file: file } }
    testimonial = Testimonials::Testimonial.last

    get "/testimonials/#{testimonial.id}/video", params: { download: 1 }
    expect(response).to have_http_status(:redirect)
    expect(response.headers['Location']).to include('disposition=attachment')

    get "/testimonials/#{testimonial.id}/video"
    expect(response.headers['Location']).to include('disposition=inline')
  end

  it 'lets the author fetch their own video through the media route' do
    Testimonials.config.current_user = ->(_request) { user }
    file = Rack::Test::UploadedFile.new(
      StringIO.new('fake video bytes'), 'video/webm', original_filename: 'testimonial.webm'
    )
    post '/testimonials', params: { testimonial: { video_file: file } }
    testimonial = Testimonials::Testimonial.last

    get "/testimonials/#{testimonial.id}/video"
    expect(response).to have_http_status(:redirect)

    Testimonials.config.current_user = ->(_request) {}
    get "/testimonials/#{testimonial.id}/video"
    expect(response).to have_http_status(:forbidden)
  end

  it 'keeps guest submissions as separate records' do
    Testimonials::Testimonial.create!(kind: 'text', body: 'First guest', name: 'G', email: 'g@example.com')

    post '/testimonials', params: {
      testimonial: { body: 'Second guest', name: 'G', email: 'g@example.com' }
    }

    expect(Testimonials::Testimonial.count).to eq(2)
  end

  it 'rejects blank text testimonials' do
    post '/testimonials', params: { testimonial: { body: '' } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'accepts a video upload and flips the kind' do
    file = Rack::Test::UploadedFile.new(
      StringIO.new('fake video bytes'), 'video/webm', original_filename: 'testimonial.webm'
    )
    post '/testimonials', params: { testimonial: { body: '', video_file: file } }

    expect(response).to have_http_status(:created)
    testimonial = Testimonials::Testimonial.last
    expect(testimonial.kind).to eq('video')
    expect(testimonial.video_file).to be_attached
  end

  it 'rejects oversized videos' do
    Testimonials.config.max_video_size = 4
    file = Rack::Test::UploadedFile.new(
      StringIO.new('too many bytes'), 'video/webm', original_filename: 'testimonial.webm'
    )
    post '/testimonials', params: { testimonial: { video_file: file } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Testimonials::Testimonial.count).to eq(0)
  end

  it 'rejects non-video uploads in the video slot' do
    file = Rack::Test::UploadedFile.new(
      StringIO.new('<html>'), 'text/html', original_filename: 'evil.html'
    )
    post '/testimonials', params: { testimonial: { video_file: file } }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'is gated by config.enabled' do
    Testimonials.config.enabled = ->(_request) { false }
    post '/testimonials', params: { testimonial: { body: 'x' } }
    expect(response).to have_http_status(:forbidden)
  end

  it 'survives a raising on_submit hook' do
    Testimonials.config.on_submit = ->(_record) { raise 'boom' }
    post '/testimonials', params: { testimonial: { body: 'Still saved' } }
    expect(response).to have_http_status(:created)
    expect(Testimonials::Testimonial.count).to eq(1)
  end
end
