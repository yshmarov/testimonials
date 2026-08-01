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
    assert_includes response.body, '.tm-show { min-height: 100vh; overflow: auto; }'
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

  test 'dashboard can render inside a host admin layout' do
    as_admin!
    Testimonials.config.admin_layout = 'host_admin'

    get '/testimonials'

    assert_response :ok
    assert_includes response.body, 'data-host-admin-layout="testimonials"'
    assert_includes response.body, 'Wonderful tool'
    # The share link lives on the page, not in the gem's nav, so a host layout
    # keeps it.
    assert_includes response.body, 'http://www.example.com/testimonials/new'
  end

  test 'each index links to its own public page' do
    as_admin!

    get '/testimonials'
    assert_includes response.body, 'http://www.example.com/testimonials/new'
    refute_includes response.body, 'http://www.example.com/testimonials/nps/new'

    get '/testimonials/nps_responses'
    assert_includes response.body, 'http://www.example.com/testimonials/nps/new'
    refute_includes response.body, 'http://www.example.com/testimonials/new"'
  end

  test 'index share links follow the public_collection and nps switches' do
    as_admin!
    Testimonials.config.public_collection = false

    get '/testimonials'
    refute_includes response.body, '/testimonials/new'

    get '/testimonials/nps_responses'
    refute_includes response.body, '/testimonials/nps/new'

    # NPS history stays readable with NPS off, but the page it would link to
    # 404s — so the link goes away.
    Testimonials.config.public_collection = true
    Testimonials.config.nps = false
    get '/testimonials/nps_responses'
    refute_includes response.body, '/testimonials/nps/new'
  end

  test 'lists testimonials by status tab' do
    as_admin!
    get '/testimonials'
    assert_includes response.body, 'Wonderful tool'
    assert_includes response.body, "testimonial_id=#{@testimonial.id}"

    get '/testimonials', params: { status: 'approved' }
    refute_includes response.body, 'Wonderful tool'
  end

  test 'index can render a selected testimonial beside the list' do
    as_admin!

    get '/testimonials', params: { testimonial_id: @testimonial.id }

    assert_response :ok
    assert_includes response.body, 'dashboard-shell has-selected'
    assert_includes response.body, 'record-row testimonial-row active'
    assert_select '.testimonial-panel > .panel-head', false
    assert_select '.testimonial-panel dl dt', text: 'Status'
    assert_select '.testimonial-panel dl dt', text: 'Rating'
    assert_includes response.body, 'Wonderful tool'
    assert_includes response.body, 'Best line'
    assert_operator response.body.rindex('Ada'), :<, response.body.rindex('Wonderful tool')
    assert_operator response.body.rindex('Wonderful tool'), :<, response.body.rindex('Approve')
  end

  test 'shows one testimonial independently' do
    as_admin!

    get "/testimonials/#{@testimonial.id}"

    assert_response :ok
    assert_includes response.body, 'class="tm-show"'
    assert_includes response.body, 'Wonderful tool'
    assert_includes response.body, 'Best line'
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
    assert_includes response.body, 'response_id='
    # 2 promoters, 1 detractor of 3 → 67 - 33 = 33 (rounded)
    assert_includes response.body, '33'
  end

  test 'NPS index can render a selected response beside the list' do
    as_admin!
    nps_response = Testimonials::NpsResponse.create!(score: 10, comment: 'Superb', name: 'Ada')

    get '/testimonials/nps_responses', params: { response_id: nps_response.id }

    assert_response :ok
    assert_includes response.body, 'dashboard-shell has-selected'
    assert_includes response.body, 'record-row nps-row active'
    assert_includes response.body, 'Superb'
    assert_includes response.body, 'Ada'
    assert_operator response.body.rindex('Ada'), :<, response.body.rindex('Superb')
  end

  test 'shows one NPS response independently' do
    as_admin!
    nps_response = Testimonials::NpsResponse.create!(score: 10, comment: 'Superb', name: 'Ada')

    get "/testimonials/nps_responses/#{nps_response.id}"

    assert_response :ok
    assert_includes response.body, 'class="tm-show"'
    assert_includes response.body, 'Superb'
    assert_includes response.body, 'Ada'
  end
end
