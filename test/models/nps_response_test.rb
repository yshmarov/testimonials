# frozen_string_literal: true

require 'test_helper'

class NpsResponseTest < ActiveSupport::TestCase
  test 'validates the score range' do
    assert Testimonials::NpsResponse.new(score: 0).valid?
    assert Testimonials::NpsResponse.new(score: 10).valid?
    refute Testimonials::NpsResponse.new(score: 11).valid?
    refute Testimonials::NpsResponse.new(score: nil).valid?
  end

  test 'classifies promoters, passives, and detractors' do
    assert Testimonials::NpsResponse.new(score: 9).promoter?
    assert Testimonials::NpsResponse.new(score: 8).passive?
    assert Testimonials::NpsResponse.new(score: 7).passive?
    assert Testimonials::NpsResponse.new(score: 6).detractor?
  end

  test 'score is nil with no responses' do
    assert_nil Testimonials::NpsResponse.score
  end

  test 'score is %promoters minus %detractors' do
    [10, 9, 8, 3].each { |s| Testimonials::NpsResponse.create!(score: s) }
    # 2 promoters, 1 passive, 1 detractor of 4: 50 - 25 = 25
    assert_equal 25, Testimonials::NpsResponse.score
  end

  test 'bands a score against the industry benchmarks' do
    assert_nil Testimonials::NpsResponse.band(nil)
    assert_equal :needs_work, Testimonials::NpsResponse.band(-100)
    assert_equal :needs_work, Testimonials::NpsResponse.band(-1)
    assert_equal :good, Testimonials::NpsResponse.band(0)
    assert_equal :good, Testimonials::NpsResponse.band(29)
    assert_equal :great, Testimonials::NpsResponse.band(30)
    assert_equal :great, Testimonials::NpsResponse.band(69)
    assert_equal :excellent, Testimonials::NpsResponse.band(70)
    assert_equal :excellent, Testimonials::NpsResponse.band(100)
  end
end
