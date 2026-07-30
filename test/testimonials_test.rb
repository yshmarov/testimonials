# frozen_string_literal: true

require 'test_helper'

class TestimonialsTest < ActiveSupport::TestCase
  test 'questions default to the built-in localized set with the app name filled in' do
    questions = Testimonials.questions
    assert_equal 3, questions.size
    assert_includes questions.join, Testimonials.app_name
    refute_includes questions.join, '%{app}'
  end

  test 'questions follow the current locale' do
    french = I18n.with_locale(:fr) { Testimonials.questions }
    assert_includes french.first, 'Qui êtes-vous'
  end

  test 'questions accept literal strings' do
    Testimonials.config.questions = ['One?', 'Two about %{app}?']
    assert_equal ['One?', "Two about #{Testimonials.app_name}?"], Testimonials.questions
  end

  test 'questions accept a lambda for host-side i18n' do
    Testimonials.config.questions = -> { ['From the host'] }
    assert_equal ['From the host'], Testimonials.questions
  end

  test 'an empty questions array hides the section' do
    Testimonials.config.questions = []
    assert_empty Testimonials.questions
  end

  test 'app_name defaults to the application module name, verbatim' do
    assert_equal 'Dummy', Testimonials.app_name
  end

  test 'app_name prefers the configured name' do
    Testimonials.config.app_name = 'SupeRails'
    assert_equal 'SupeRails', Testimonials.app_name
  end

  test 'consent_text has a localized default and a private variant' do
    assert_includes Testimonials.consent_text, 'publicly'
    assert_includes Testimonials.consent_text_private, 'privately'
  end

  test 'consent_text_for picks public or private by the choice' do
    assert_equal Testimonials.consent_text, Testimonials.consent_text_for(true)
    assert_equal Testimonials.consent_text_private, Testimonials.consent_text_for(false)
  end

  test 'consent_text prefers the configured text' do
    Testimonials.config.consent_text = 'Custom consent.'
    assert_equal 'Custom consent.', Testimonials.consent_text
  end

  test 'enabled? and admin? run through the config lambdas' do
    request = Object.new
    assert Testimonials.enabled?(request)
    refute Testimonials.admin?(request) # test env is not development

    Testimonials.config.authorize_admin = ->(_r) { true }
    assert Testimonials.admin?(request)
  end

  test 'mount_testimonials keeps config.mount_path in sync with the route' do
    routes = ActionDispatch::Routing::RouteSet.new

    routes.draw do
      mount_testimonials at: '/reviews'
    end

    assert_equal '/reviews', Testimonials.config.mount_path
  end
end
