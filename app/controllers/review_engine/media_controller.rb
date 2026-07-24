# frozen_string_literal: true

module ReviewEngine
  # Hands out video and avatar files by testimonial id, so consumers never
  # need to know about Active Storage. Admins can fetch anything; everyone
  # else only reaches media of publishable (approved + consented)
  # testimonials, and only when the read API is public. The actual bytes are
  # served by Active Storage's own controllers (signed, expiring URLs, with
  # Range support — video elements need that).
  class MediaController < ApplicationController
    before_action :set_testimonial
    before_action :authorize_media

    def video
      head :not_found and return unless @testimonial.video_attached?

      redirect_to main_app.rails_blob_path(@testimonial.video_file, disposition: 'inline')
    end

    def avatar
      head :not_found and return unless @testimonial.avatar_attached?

      redirect_to main_app.rails_blob_path(@testimonial.avatar, disposition: 'inline')
    end

    private

    def set_testimonial
      @testimonial = Testimonial.find(params[:id])
    end

    def authorize_media
      return if ReviewEngine.admin?(request)
      # Authors can always see their own media — the widget replays their
      # attached video when they edit their review.
      return if current_author_id.present? && @testimonial.author_id == current_author_id.to_s
      return if ReviewEngine.config.public_api && @testimonial.approved? && @testimonial.consent_given?

      head :forbidden
    end
  end
end
