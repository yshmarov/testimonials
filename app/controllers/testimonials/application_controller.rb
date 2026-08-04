# frozen_string_literal: true

module Testimonials
  # Root of the engine's PUBLIC surface: widget.js, the submission endpoints,
  # the prompt-event ledger, the public collection pages, media, and the read
  # API. These stay on a plain ActionController::Base deliberately — a member
  # posting a testimonial must not be routed through a host's admin controller,
  # which would demand a staff session for the widget.
  #
  # The dashboard's root is DashboardController, and that is where
  # `config.base_controller_class` applies.
  class ApplicationController < ActionController::Base
    include RequestContext

    protect_from_forgery with: :exception
  end
end
