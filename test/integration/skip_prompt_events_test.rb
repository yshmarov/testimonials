# frozen_string_literal: true

require 'test_helper'

# The --skip-prompt-events install shape: no testimonials_prompt_events table
# at all. As with NPS, the design guards on config.prompt_events rather than
# asking the schema at runtime, so what has to hold is that nothing reaches the
# table when the flag is off — and every submission path writes to that ledger,
# so this covers more code than the NPS switch does. The table is dropped for
# real: a guard that slips anywhere raises "no such table" instead of quietly
# passing.
class SkipPromptEventsTest < ActionDispatch::IntegrationTest
  setup do
    Testimonials.config.prompt_events = false
    ActiveRecord::Base.connection.drop_table(:testimonials_prompt_events, if_exists: true)
  end

  teardown do
    ActiveRecord::Base.connection.create_table :testimonials_prompt_events, force: true do |t|
      t.string :kind, null: false
      t.string :action, null: false
      t.string :author_id
      t.string :visitor_token
      t.string :tenant
      t.timestamps
    end
    ActiveRecord::Base.connection.add_index :testimonials_prompt_events, %i[tenant author_id kind]
    ActiveRecord::Base.connection.add_index :testimonials_prompt_events, %i[tenant visitor_token kind]
  end

  test 'the widget renders and tells the browser not to report events' do
    get '/sample'

    assert_response :ok
    assert_includes response.body, 'data-testimonials-config'
    assert_includes response.body, '"promptEvents":{"enabled":false}'
  end

  # The heart of it: with no ledger there is no way to know who has been asked,
  # so an auto-open would reopen on every page. testimonial_prompt! goes quiet.
  test 'testimonial_prompt! does not auto-open' do
    post '/sample/celebrate'
    follow_redirect!

    assert_includes response.body, '"autoOpen":null'
  end

  test 'testimonial_prompt!(:nps) does not auto-open either' do
    post '/sample/celebrate', params: { kind: 'nps' }
    follow_redirect!

    assert_includes response.body, '"autoOpen":null'
  end

  test 'the button and explicit opens are untouched' do
    get '/sample'

    assert_includes response.body, 'data-testimonial-prompt'
    assert_includes response.body, '>Leave a review</button>'
  end

  test 'the events endpoint is refused rather than broken' do
    post '/testimonials/events', params: { kind: 'testimonial', event_action: 'shown' }
    assert_response :forbidden

    post '/testimonials/events', params: { kind: 'nps', event_action: 'dismissed' }
    assert_response :forbidden
  end

  test 'submitting a testimonial never reaches the ledger' do
    Testimonials.config.current_user = ->(_request) { fake_user }

    assert_difference -> { Testimonials::Testimonial.count } do
      post '/testimonials', params: { testimonial: { kind: 'text', body: 'No ledger needed' } }
    end
    assert_response :created
  end

  test 'submitting NPS never reaches the ledger, and promoters are still offered the form' do
    assert_difference -> { Testimonials::NpsResponse.count } do
      post '/testimonials/nps', params: { nps: { score: 10 } }
    end
    assert_response :created
    # Nothing throttles the follow-up ask, but nothing auto-opened to get here
    # either: the promoter opened the NPS card themselves.
    assert response.parsed_body['offer_testimonial']
  end

  test 'a detractor is not offered the testimonial form' do
    post '/testimonials/nps', params: { nps: { score: 3 } }

    assert_response :created
    refute response.parsed_body['offer_testimonial']
  end

  test 'the dashboard and the public pages work' do
    as_admin!
    Testimonials::Testimonial.create!(kind: 'text', body: 'Wonderful tool', name: 'Ada')

    get '/testimonials'
    assert_response :ok
    assert_includes response.body, 'Wonderful tool'

    get '/testimonials/new'
    assert_response :ok

    get '/testimonials/nps/new'
    assert_response :ok
  end

  test 'seed_demo seeds everything but the prompt history' do
    result = Testimonials::Seeds.load!

    assert_empty result[:prompt_events]
    assert_equal 4, result[:testimonials].size
    assert_equal 3, result[:nps_responses].size
  end
end
