# frozen_string_literal: true

module Testimonials
  # The standalone public collection page at "#{mount_path}/new" — the link
  # you drop into an email or DM so customers outside the app can leave a
  # testimonial. Toggled by config.public_collection (ON by default).
  class CollectionController < ApplicationController
    layout 'testimonials/collection'

    def show
      head :not_found and return unless Testimonials.config.public_collection
      head :forbidden and return unless Testimonials.enabled?(request)

      # A signed-in visitor edits their existing review instead of adding one.
      @existing = current_author_id && Testimonial.where(author_id: current_author_id.to_s).newest_first.first
    end
  end
end
