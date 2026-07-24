# frozen_string_literal: true

require 'test_helper'

class PromptEventTest < ActiveSupport::TestCase
  def eligible?(**args)
    Testimonials::PromptEvent.eligible?(kind: 'testimonial', **args)
  end

  test 'a brand-new visitor with no identity at all is eligible' do
    assert eligible?
  end

  test 'an identity with no history is eligible' do
    assert eligible?(author_id: '42')
    assert eligible?(visitor_token: 'v1')
  end

  test 'never re-prompts for a testimonial after a submission' do
    Testimonials::PromptEvent.record!(kind: 'testimonial', action: 'submitted', author_id: '42')
    refute eligible?(author_id: '42')
  end

  test 're-allows NPS after nps_reprompt_after' do
    Testimonials::PromptEvent.record!(kind: 'nps', action: 'submitted', author_id: '42')
    refute Testimonials::PromptEvent.eligible?(kind: 'nps', author_id: '42')

    Testimonials::PromptEvent.update_all(created_at: Time.current - Testimonials.config.nps_reprompt_after - 60)
    assert Testimonials::PromptEvent.eligible?(kind: 'nps', author_id: '42')
  end

  test 'blocks after a recent dismissal, then relents' do
    Testimonials::PromptEvent.record!(kind: 'testimonial', action: 'dismissed', author_id: '42')
    refute eligible?(author_id: '42')

    Testimonials::PromptEvent.update_all(created_at: Time.current - Testimonials.config.reprompt_after - 60)
    assert eligible?(author_id: '42')
  end

  test 'stops for good after max_prompts shows' do
    Testimonials.config.max_prompts = 2
    2.times { Testimonials::PromptEvent.record!(kind: 'testimonial', action: 'shown', author_id: '42') }
    Testimonials::PromptEvent.update_all(created_at: Time.current - Testimonials.config.reprompt_after - 60)

    refute eligible?(author_id: '42')
  end

  test 'keys authors and visitors separately' do
    Testimonials::PromptEvent.record!(kind: 'testimonial', action: 'submitted', visitor_token: 'v1')
    refute eligible?(visitor_token: 'v1')
    assert eligible?(author_id: '42')
    assert eligible?(visitor_token: 'v2')
  end

  test 'records nothing without an identity' do
    Testimonials::PromptEvent.record!(kind: 'testimonial', action: 'shown')
    assert_equal 0, Testimonials::PromptEvent.count
  end
end
