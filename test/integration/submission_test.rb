# frozen_string_literal: true

require 'test_helper'

class SubmissionTest < ActionDispatch::IntegrationTest
  test 'stores a guest text testimonial with consent snapshot and locale' do
    post '/testimonials', params: {
      testimonial: { body: 'Love it!', rating: 5, consent_given: '1',
                     name: 'Grace', email: 'grace@example.com', page_url: 'http://x/pricing' }
    }

    assert_response :created
    testimonial = Testimonials::Testimonial.last
    assert_equal 'text', testimonial.kind
    assert_equal 'pending', testimonial.status
    assert_equal 5, testimonial.rating
    assert_equal 'Grace', testimonial.name
    assert testimonial.consent_given
    assert_equal Testimonials.consent_text, testimonial.consent_text
    assert_equal 'en', testimonial.locale
  end

  test 'attributes signed-in users server-side, ignoring client contact fields' do
    Testimonials.config.current_user = ->(_request) { fake_user }

    post '/testimonials', params: {
      testimonial: { body: 'Great', name: 'Mallory', email: 'spoof@example.com' }
    }

    testimonial = Testimonials::Testimonial.last
    assert_equal '42', testimonial.author_id
    assert_equal 'Ada Lovelace', testimonial.name
    assert_equal 'ada@example.com', testimonial.email
  end

  test 'records a submitted event in the throttle ledger' do
    Testimonials.config.current_user = ->(_request) { fake_user }

    assert_difference -> { Testimonials::PromptEvent.where(kind: 'testimonial', action: 'submitted').count } do
      post '/testimonials', params: { testimonial: { body: 'Great' } }
    end

    assert_equal '42', Testimonials::PromptEvent.last.author_id
  end

  test 'updates a signed-in user\'s existing review in place, back through moderation' do
    Testimonials.config.current_user = ->(_request) { fake_user }
    existing = Testimonials::Testimonial.create!(kind: 'text', body: 'Old words', rating: 3,
                                                 author_id: '42', status: 'approved',
                                                 best_line: 'Old', consent_given: true)

    post '/testimonials', params: { testimonial: { body: 'New words', rating: 5, consent_given: '1' } }

    assert_response :created
    assert_equal 1, Testimonials::Testimonial.count
    existing.reload
    assert_equal 'New words', existing.body
    assert_equal 5, existing.rating
    assert_equal 'pending', existing.status
    assert_nil existing.best_line
  end

  test 'keeps an attached video on a text-only update, and purges it when asked' do
    Testimonials.config.current_user = ->(_request) { fake_user }
    post '/testimonials', params: { testimonial: { body: '', video_file: fake_video } }
    testimonial = Testimonials::Testimonial.last

    post '/testimonials', params: { testimonial: { body: 'Now with words' } }
    testimonial.reload
    assert_equal 'video', testimonial.kind
    assert testimonial.video_file.attached?

    post '/testimonials', params: { testimonial: { body: 'Words only now', remove_video: '1' } }
    testimonial.reload
    assert_equal 'text', testimonial.kind
    refute testimonial.video_file.attached?
  end

  test 'rate-limits guest submissions per IP' do
    # Rails' rate limiter shipped in 7.2; on 7.1 the gem documents it as a no-op.
    skip 'no rate limiter on Rails 7.1' unless Testimonials::TestimonialsController.respond_to?(:rate_limit)

    statuses = 7.times.map do |i|
      post '/testimonials', params: { testimonial: { body: "spam #{i}", name: 'B', email: 'b@example.com' } }
      response.status
    end

    assert_equal [201] * 5, statuses.first(5)
    assert_equal [429, 429], statuses.last(2)
    assert_equal 5, Testimonials::Testimonial.count
  end

  test 'serves video downloads with attachment disposition' do
    Testimonials.config.current_user = ->(_request) { fake_user }
    post '/testimonials', params: { testimonial: { video_file: fake_video } }
    testimonial = Testimonials::Testimonial.last

    get "/testimonials/#{testimonial.id}/video", params: { download: 1 }
    assert_response :redirect
    assert_includes response.headers['Location'], 'disposition=attachment'

    get "/testimonials/#{testimonial.id}/video"
    assert_includes response.headers['Location'], 'disposition=inline'
  end

  test 'lets the author fetch their own video through the media route' do
    Testimonials.config.current_user = ->(_request) { fake_user }
    post '/testimonials', params: { testimonial: { video_file: fake_video } }
    testimonial = Testimonials::Testimonial.last

    get "/testimonials/#{testimonial.id}/video"
    assert_response :redirect

    Testimonials.config.current_user = ->(_request) {}
    get "/testimonials/#{testimonial.id}/video"
    assert_response :forbidden
  end

  test 'keeps guest submissions as separate records' do
    Testimonials::Testimonial.create!(kind: 'text', body: 'First guest', name: 'G', email: 'g@example.com')

    post '/testimonials', params: { testimonial: { body: 'Second guest', name: 'G', email: 'g@example.com' } }

    assert_equal 2, Testimonials::Testimonial.count
  end

  test 'rejects blank text testimonials' do
    post '/testimonials', params: { testimonial: { body: '' } }
    assert_response :unprocessable_entity
  end

  test 'accepts a video upload and flips the kind' do
    post '/testimonials', params: { testimonial: { body: '', video_file: fake_video } }

    assert_response :created
    testimonial = Testimonials::Testimonial.last
    assert_equal 'video', testimonial.kind
    assert testimonial.video_file.attached?
  end

  test 'rejects oversized videos' do
    Testimonials.config.max_video_size = 4
    post '/testimonials', params: { testimonial: { video_file: fake_video(content: 'too many bytes') } }

    assert_response :unprocessable_entity
    assert_equal 0, Testimonials::Testimonial.count
  end

  test 'rejects non-video uploads in the video slot' do
    file = fake_video(name: 'evil.html', content: '<html>', type: 'text/html')
    post '/testimonials', params: { testimonial: { video_file: file } }

    assert_response :unprocessable_entity
  end

  test 'is gated by config.enabled' do
    Testimonials.config.enabled = ->(_request) { false }
    post '/testimonials', params: { testimonial: { body: 'x' } }
    assert_response :forbidden
  end

  test 'survives a raising on_submit hook' do
    Testimonials.config.on_submit = ->(_record) { raise 'boom' }
    post '/testimonials', params: { testimonial: { body: 'Still saved' } }
    assert_response :created
    assert_equal 1, Testimonials::Testimonial.count
  end
end
