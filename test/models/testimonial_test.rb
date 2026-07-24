# frozen_string_literal: true

require 'test_helper'

class TestimonialTest < ActiveSupport::TestCase
  test 'requires a body for text testimonials' do
    refute Testimonials::Testimonial.new(kind: 'text').valid?
    assert Testimonials::Testimonial.new(kind: 'text', body: 'Great!').valid?
  end

  test 'allows a video testimonial without a body' do
    assert Testimonials::Testimonial.new(kind: 'video').valid?
  end

  test 'validates rating range but allows nil' do
    assert Testimonials::Testimonial.new(kind: 'video', rating: nil).valid?
    assert Testimonials::Testimonial.new(kind: 'video', rating: 5).valid?
    refute Testimonials::Testimonial.new(kind: 'video', rating: 6).valid?
    refute Testimonials::Testimonial.new(kind: 'video', rating: 0).valid?
  end

  test 'publishable requires approval AND consent' do
    keeper = Testimonials::Testimonial.create!(kind: 'text', body: 'a', status: 'approved', consent_given: true)
    Testimonials::Testimonial.create!(kind: 'text', body: 'b', status: 'approved', consent_given: false)
    Testimonials::Testimonial.create!(kind: 'text', body: 'c', status: 'pending', consent_given: true)

    assert_equal [keeper], Testimonials::Testimonial.publishable.to_a
  end

  test 'quote prefers the best line, falls back to the body' do
    testimonial = Testimonials::Testimonial.new(body: 'Long story.', best_line: 'Story.')
    assert_equal 'Story.', testimonial.quote
    testimonial.best_line = nil
    assert_equal 'Long story.', testimonial.quote
  end

  test 'display_name uses the name, then the author id, then nil' do
    assert_equal 'Ada', Testimonials::Testimonial.new(name: 'Ada').display_name
    assert_equal '#42', Testimonials::Testimonial.new(author_id: '42').display_name
    assert_nil Testimonials::Testimonial.new.display_name
  end
end
