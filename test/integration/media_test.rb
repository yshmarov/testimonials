# frozen_string_literal: true

require 'test_helper'

class MediaTest < ActionDispatch::IntegrationTest
  setup do
    @content = '0123456789video'
    @testimonial = Testimonials::Testimonial.create!(
      kind: 'video', status: 'pending', consent_given: true, author_id: '42'
    )
    @testimonial.video_file.attach(
      io: StringIO.new(@content), filename: 'testimonial.webm', content_type: 'video/webm'
    )
  end

  test 'streams author media without exposing an Active Storage URL' do
    Testimonials.config.current_user = ->(_request) { fake_user }

    get "/testimonials/#{@testimonial.id}/video"

    assert_response :success
    assert_equal 'video/webm', response.media_type
    assert_equal @content, response.body
    assert_equal 'bytes', response.headers['Accept-Ranges']
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 'nosniff', response.headers['X-Content-Type-Options']
    assert_nil response.headers['Location']
  end

  test 'supports byte ranges through the same authorized route' do
    as_admin!

    get "/testimonials/#{@testimonial.id}/video", headers: { 'Range' => 'bytes=2-5' }

    assert_response :partial_content
    assert_equal '2345', response.body
    assert_equal "bytes 2-5/#{@content.bytesize}", response.headers['Content-Range']
    assert_equal 'bytes', response.headers['Accept-Ranges']
    assert_nil response.headers['Location']
  end

  test 'public media requires approval, consent, and the public API switch' do
    get "/testimonials/#{@testimonial.id}/video"
    assert_response :forbidden

    @testimonial.update!(status: 'approved')
    Testimonials.config.public_api = true
    get "/testimonials/#{@testimonial.id}/video"

    assert_response :success
    assert_equal '*', response.headers['Access-Control-Allow-Origin']

    @testimonial.update!(consent_given: false)
    get "/testimonials/#{@testimonial.id}/video"
    assert_response :forbidden
  end

  test 'download disposition remains explicit while bytes stay gated' do
    as_admin!

    get "/testimonials/#{@testimonial.id}/video", params: { download: 1 }

    assert_response :success
    assert_includes response.headers['Content-Disposition'], 'attachment'
    assert_nil response.headers['Location']
  end
end
