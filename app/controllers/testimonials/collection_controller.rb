# frozen_string_literal: true

module Testimonials
  # The standalone public pages — the links you drop into an email or DM so
  # people outside the app can answer: "#{mount_path}/new" for a testimonial,
  # "#{mount_path}/nps/new" for the 0–10 score. Both are toggled by
  # config.public_collection (ON by default); the NPS one also needs
  # config.nps.
  class CollectionController < ApplicationController
    layout 'testimonials/collection'
    before_action :require_public_collection

    def show
      # A signed-in visitor edits their existing review (in this tenant)
      # instead of adding one.
      @existing = current_author_id &&
                  Testimonial.for_tenant(current_tenant)
                             .where(author_id: current_author_id.to_s).newest_first.first
    end

    # The same widget code, opened straight onto the NPS card. A promoter is
    # offered the testimonial form right after scoring, inline on this page.
    def nps
      head :not_found unless Testimonials.config.nps
    end

    private

    def require_public_collection
      head :not_found and return unless Testimonials.config.public_collection

      head :forbidden unless Testimonials.enabled?(request)
    end
  end
end
