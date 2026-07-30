# frozen_string_literal: true

require 'test_helper'

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @testimonial = Testimonials::Testimonial.create!(kind: 'text', body: 'Wonderful tool', name: 'Ada', rating: 4)
  end

  test 'is forbidden without authorize_admin' do
    get '/testimonials'
    assert_response :forbidden
  end

  test 'serves the dashboard helper script and stylesheet as same-origin static assets' do
    get '/testimonials/dashboard.js'
    assert_response :ok
    assert_equal 'text/javascript', response.media_type
    assert_includes response.body, 'data-confirm'

    get '/testimonials/dashboard.css'
    assert_response :ok
    assert_equal 'text/css', response.media_type
    assert_includes response.body, '.nav'
  end

  test 'loads dashboard assets, CSP metadata, and no inline dashboard style or JS handlers' do
    as_admin!
    get '/testimonials'
    assert_includes response.body, 'name="csp-nonce"'
    assert_includes response.body, 'href="/testimonials/dashboard.css?v='
    assert_includes response.body, 'src="/testimonials/dashboard.js?v='
    refute_includes response.body, '<style>'
    refute_includes response.body, 'onchange='
    assert_includes response.body, 'data-autosubmit'

    get "/testimonials/#{@testimonial.id}"
    refute_includes response.body, 'onsubmit='
    assert_includes response.body, 'data-confirm'
  end

  test 'lists testimonials by status tab' do
    as_admin!
    get '/testimonials'
    assert_includes response.body, 'Wonderful tool'

    get '/testimonials', params: { status: 'approved' }
    refute_includes response.body, 'Wonderful tool'
  end

  test 'searches text, name, and email' do
    as_admin!
    get '/testimonials', params: { q: 'wonder' }
    assert_includes response.body, 'Wonderful tool'

    get '/testimonials', params: { q: 'nothing-matches' }
    refute_includes response.body, 'Wonderful tool'
  end

  test 'approves, features, picks best lines, and deletes' do
    as_admin!
    patch "/testimonials/#{@testimonial.id}", params: { testimonial: { status: 'approved' } }
    assert_equal 'approved', @testimonial.reload.status

    patch "/testimonials/#{@testimonial.id}", params: { testimonial: { featured: true } }
    assert @testimonial.reload.featured

    patch "/testimonials/#{@testimonial.id}", params: { testimonial: { best_line: 'Wonderful' } }
    assert_equal 'Wonderful', @testimonial.reload.quote

    delete "/testimonials/#{@testimonial.id}"
    assert_equal 0, Testimonials::Testimonial.count
  end

  test 'shows the NPS tab with the score' do
    as_admin!
    [10, 10, 0].each { |score| Testimonials::NpsResponse.create!(score: score, comment: "c#{score}") }
    get '/testimonials/nps_responses'
    assert_includes response.body, 'c10'
    # 2 promoters, 1 detractor of 3 → 67 - 33 = 33 (rounded)
    assert_includes response.body, '33'
  end
end
