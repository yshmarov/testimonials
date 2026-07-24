# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Testimonials::PromptEvent do
  def eligible?(**args)
    described_class.eligible?(kind: 'testimonial', **args)
  end

  it 'treats a brand-new visitor (no identity at all) as eligible' do
    expect(eligible?).to be(true)
  end

  it 'is eligible with an identity and no history' do
    expect(eligible?(author_id: '42')).to be(true)
    expect(eligible?(visitor_token: 'v1')).to be(true)
  end

  it 'never re-prompts for a testimonial after a submission' do
    described_class.record!(kind: 'testimonial', action: 'submitted', author_id: '42')
    expect(eligible?(author_id: '42')).to be(false)
  end

  it 're-allows NPS after nps_reprompt_after' do
    described_class.record!(kind: 'nps', action: 'submitted', author_id: '42')
    expect(described_class.eligible?(kind: 'nps', author_id: '42')).to be(false)

    described_class.update_all(created_at: Time.current - Testimonials.config.nps_reprompt_after - 60)
    expect(described_class.eligible?(kind: 'nps', author_id: '42')).to be(true)
  end

  it 'blocks after a recent dismissal, then relents' do
    described_class.record!(kind: 'testimonial', action: 'dismissed', author_id: '42')
    expect(eligible?(author_id: '42')).to be(false)

    described_class.update_all(created_at: Time.current - Testimonials.config.reprompt_after - 60)
    expect(eligible?(author_id: '42')).to be(true)
  end

  it 'stops for good after max_prompts shows' do
    Testimonials.config.max_prompts = 2
    2.times { described_class.record!(kind: 'testimonial', action: 'shown', author_id: '42') }
    described_class.update_all(created_at: Time.current - Testimonials.config.reprompt_after - 60)

    expect(eligible?(author_id: '42')).to be(false)
  end

  it 'keys authors and visitors separately' do
    described_class.record!(kind: 'testimonial', action: 'submitted', visitor_token: 'v1')
    expect(eligible?(visitor_token: 'v1')).to be(false)
    expect(eligible?(author_id: '42')).to be(true)
    expect(eligible?(visitor_token: 'v2')).to be(true)
  end

  it 'records nothing without an identity' do
    described_class.record!(kind: 'testimonial', action: 'shown')
    expect(described_class.count).to eq(0)
  end
end
