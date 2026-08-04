# frozen_string_literal: true

module Testimonials
  # Root of the STAFF surface: the testimonial queue and the NPS pages.
  #
  # Inherits from `config.base_controller_class` — by default a plain
  # ActionController::Base, which is why `authorize_admin` exists. Point it at
  # the controller your own admin already inherits from and the dashboard picks
  # up that stack wholesale: your layout, your helpers, your authentication,
  # and whatever request context your before_actions establish (a `Current`
  # attribute the layout reads, say). `config.admin_layout` only ever solved
  # the first of those.
  #
  # Only the dashboard hangs off it. The widget's endpoints stay on
  # ApplicationController, so wiring an admin base controller here can never
  # demand a staff session from a member leaving a review.
  class DashboardController < Testimonials.base_controller
    include RequestContext

    # A host base controller brings its own layout, and declaring one here would
    # override it — the dashboard would render in the gem's standalone shell
    # inside an app that just told us where its admin lives. So the gem only
    # claims the layout when it owns the decision: no host base controller, or a
    # host that named an `admin_layout` explicitly.
    layout :testimonials_admin_layout unless superclass != ActionController::Base &&
                                             Testimonials.config.admin_layout ==
                                             Configuration::DEFAULT_ADMIN_LAYOUT

    before_action :require_admin

    # `authorize_admin` is a gate of last resort, and it is the only one when
    # the host supplied no base controller. When they did, its default is
    # development-only, so a host whose base controller already authenticates
    # staff should widen or replace it.
    #
    # CSRF likewise: a host base controller has configured it already, and
    # declaring it twice would run the check twice.
    protect_from_forgery with: :exception if superclass == ActionController::Base
  end
end
