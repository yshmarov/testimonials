# frozen_string_literal: true

require 'test_helper'

class WidgetSystemTest < ApplicationSystemTestCase
  test 'hands an NPS promoter through testimonial moderation into the public API' do
    Testimonials.config.video = false
    Testimonials.config.avatars = false
    Testimonials.config.public_api = true
    as_admin!

    visit '/sample'
    click_button 'Open NPS'

    within '#tml-overlay' do
      assert_text 'How likely are you to recommend'
      click_button '10'
      fill_in "What's the main reason for your score? (optional)", with: 'The workflow is effortless.'
      click_button 'Send'

      assert_text 'Glad to hear it! Mind saying that publicly?'
      fill_in 'Your testimonial', with: 'This is the clearest Rails workflow I have used.'
      fill_in 'Your name', with: 'Grace Hopper'
      fill_in 'Your email', with: 'grace@example.com'
      click_button 'Send'
      assert_text 'Thank you so much!'
    end

    assert_equal 10, Testimonials::NpsResponse.last.score
    testimonial = Testimonials::Testimonial.last
    assert_equal 'nps', testimonial.source
    assert_equal 'pending', testimonial.status

    visit '/testimonials'
    click_link 'This is the clearest Rails workflow I have used.'
    within '.detail-panel' do
      click_button 'Approve'
    end
    assert_selector '.detail-panel .status-approved', text: 'Approved'

    visit '/testimonials/api/testimonials'
    assert_text 'This is the clearest Rails workflow I have used.'
    assert_no_text 'grace@example.com'
  end
end
