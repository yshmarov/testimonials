# frozen_string_literal: true

module Testimonials
  module Api
    # Read-only JSON. With config.public_api the endpoints answer anyone
    # (approved + consented records only, CORS open for static marketing
    # sites); otherwise they answer only requests that pass authorize_admin.
    class BaseController < ApplicationController
      skip_forgery_protection

      before_action :authorize_api
      after_action :allow_cross_origin

      private

      def authorize_api
        return if Testimonials.config.public_api
        return if Testimonials.admin?(request)

        head :forbidden
      end

      # Public testimonials are meant to be fetched from anywhere — a static
      # marketing site at build time or in the browser.
      def allow_cross_origin
        response.set_header('Access-Control-Allow-Origin', '*') if Testimonials.config.public_api
      end
    end
  end
end
