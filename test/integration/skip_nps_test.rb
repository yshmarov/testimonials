# frozen_string_literal: true

require 'test_helper'

# The --skip-nps install shape: no testimonials_nps_responses table at all.
# The design guards on config.nps rather than asking the schema at runtime, so
# what has to hold is that nothing reaches the table when the flag is off. This
# drops the table for real — a guard that slips anywhere raises "no such table"
# instead of quietly passing.
class SkipNpsTest < ActionDispatch::IntegrationTest
  setup do
    Testimonials.config.nps = false
    ActiveRecord::Base.connection.drop_table(:testimonials_nps_responses, if_exists: true)
  end

  teardown do
    ActiveRecord::Base.connection.create_table :testimonials_nps_responses, force: true do |t|
      t.integer :score, null: false
      t.text :comment
      t.string :author_id
      t.string :name
      t.string :email
      t.string :page_url
      t.string :user_agent
      t.string :locale
      t.string :tenant
      t.timestamps
    end
    ActiveRecord::Base.connection.add_index :testimonials_nps_responses, %i[tenant score]
  end

  test 'the dashboard works and offers no NPS tab' do
    as_admin!
    Testimonials::Testimonial.create!(kind: 'text', body: 'Wonderful tool', name: 'Ada')

    get '/testimonials'

    assert_response :ok
    assert_includes response.body, 'Wonderful tool'
    refute_includes response.body, 'nps_responses'
  end

  test 'the NPS pages are gone rather than broken' do
    as_admin!

    get '/testimonials/nps_responses'
    assert_response :not_found

    get '/testimonials/nps_responses/1'
    assert_response :not_found

    get '/testimonials/nps/new'
    assert_response :not_found

    post '/testimonials/nps', params: { nps: { score: 10 } }
    assert_response :forbidden
  end

  test 'the widget and the read API never reach for the table' do
    get '/testimonials/widget.js'
    assert_response :ok

    # The widget config on a host page carries the NPS switch, off.
    get '/sample'
    assert_response :ok
    assert_includes response.body, '"nps":{"enabled":false}'

    Testimonials.config.public_api = true
    get '/testimonials/api/stats'
    assert_response :ok
    assert_nil response.parsed_body['nps_score']

    get '/testimonials/api/testimonials'
    assert_response :ok
  end

  test 'the public collection page still collects testimonials' do
    get '/testimonials/new'
    assert_response :ok

    assert_difference -> { Testimonials::Testimonial.count } do
      post '/testimonials', params: {
        testimonial: { kind: 'text', body: 'Collected without NPS', name: 'Ada', email: 'ada@example.com' }
      }
    end
  end

  test 'seed_demo seeds everything but NPS' do
    result = Testimonials::Seeds.load!

    assert_empty result[:nps_responses]
    assert_equal 4, result[:testimonials].size
    assert_equal 3, result[:prompt_events].size
  end
end
