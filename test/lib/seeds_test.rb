# frozen_string_literal: true

require 'test_helper'

class SeedsTest < ActiveSupport::TestCase
  test 'loads idempotent demo testimonials, nps, and prompt events' do
    first = Testimonials::Seeds.load!
    second = Testimonials::Seeds.load!

    assert_equal first[:testimonials].map(&:id), second[:testimonials].map(&:id)
    assert_equal first[:nps_responses].map(&:id), second[:nps_responses].map(&:id)
    assert_equal first[:prompt_events].map(&:id), second[:prompt_events].map(&:id)
    assert_equal 4, Testimonials::Testimonial.where("author_id LIKE 'testimonials-demo:%'").count
    assert_equal 3, Testimonials::NpsResponse.where("author_id LIKE 'testimonials-demo:nps-%'").count
    assert_equal 3, Testimonials::PromptEvent.where("visitor_token LIKE 'testimonials-demo-%' OR author_id LIKE 'testimonials-demo:%'").count
    assert_equal %w[approved archived pending], first[:testimonials].map(&:status).uniq.sort
    assert_equal 0, Testimonials::NpsResponse.score
  end

  test 'attaches a real demo video when Active Storage is available' do
    Testimonials::Seeds.load!

    video = Testimonials::Testimonial.find_by!(author_id: 'testimonials-demo:approved-video')
    assert video.video?
    assert video.video_attached?
    assert_equal 'testimonials-demo-flower.mp4', video.video_file.filename.to_s
    assert_equal 'video/mp4', video.video_file.content_type
  end
end
