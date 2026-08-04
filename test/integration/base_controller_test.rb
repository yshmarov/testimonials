# frozen_string_literal: true

require 'test_helper'

# `config.base_controller_class` reparents the DASHBOARD only. The split is the
# safety property: if the public write endpoint shared a controller with the
# triage actions, pointing this at a host's admin controller would demand a
# staff session from every member leaving a review.
class BaseControllerTest < ActionDispatch::IntegrationTest
  test 'defaults to a plain ActionController::Base' do
    assert_equal 'ActionController::Base', Testimonials.config.base_controller_class
    assert_equal ActionController::Base, Testimonials.base_controller
  end

  test 'resolves the host class lazily, by name' do
    Testimonials.config.base_controller_class = 'HostAdminBaseController'

    assert_equal HostAdminBaseController, Testimonials.base_controller
  end

  # The superclass is fixed when the class body runs, so this asserts the wiring
  # rather than reparenting a loaded constant mid-process.
  test 'the dashboard hangs off the configured base controller' do
    assert_equal Testimonials.base_controller, Testimonials::DashboardController.superclass
  end

  test 'every public controller stays off the host base controller' do
    assert_equal ActionController::Base, Testimonials::ApplicationController.superclass

    [Testimonials::SubmissionsController, Testimonials::WidgetsController,
     Testimonials::EventsController, Testimonials::NpsController,
     Testimonials::CollectionController, Testimonials::MediaController,
     Testimonials::Api::BaseController].each do |controller|
      assert_equal Testimonials::ApplicationController, controller.superclass,
                   "#{controller} must not inherit the host's base controller"
    end
  end

  test 'both dashboard controllers are staff-gated through the shared root' do
    [Testimonials::TestimonialsController, Testimonials::NpsResponsesController].each do |controller|
      assert_equal Testimonials::DashboardController, controller.superclass
    end
  end

  # The widget posts to the mount path. That has to keep working no matter what
  # the dashboard inherits.
  test 'POST to the mount path routes to the public submissions controller' do
    engine = Testimonials::Engine.routes

    assert_equal({ controller: 'testimonials/submissions', action: 'create' },
                 engine.recognize_path('/', method: :post))
    assert_equal({ controller: 'testimonials/testimonials', action: 'index' },
                 engine.recognize_path('/', method: :get))
  end

  test 'a submission still succeeds while the dashboard is gated' do
    assert_difference -> { Testimonials::Testimonial.count }, 1 do
      post '/testimonials', params: { testimonial: { rating: 5, body: 'Great', consent_given: '1' } }
    end
    assert_response :created

    # Same request, no admin: the dashboard is still shut.
    get '/testimonials'
    assert_response :forbidden
  end
end
