# frozen_string_literal: true

module Testimonials
  # Hands out video and avatar files by testimonial id, so consumers never
  # need to know about Active Storage. Admins can fetch anything; everyone
  # else only reaches media of publishable (approved + consented)
  # testimonials, and only when the read API is public. The actual bytes are
  # streamed here after authorization. Keeping the browser on this route means
  # an Active Storage URL cannot outlive the gate; Range support remains for
  # video playback and seeking.
  class MediaController < ApplicationController
    include ActiveStorage::Streaming if defined?(::ActiveStorage::Streaming)

    before_action :set_testimonial
    before_action :authorize_media

    def video
      head :not_found and return unless @testimonial.video_attached?

      stream(@testimonial.video_file)
    end

    def poster
      head :not_found and return unless @testimonial.poster_attached?

      stream(@testimonial.poster)
    end

    def avatar
      head :not_found and return unless @testimonial.avatar_attached?

      stream(@testimonial.avatar)
    end

    private

    def stream(attachment)
      blob = attachment.blob
      response.headers['X-Content-Type-Options'] = 'nosniff'
      response.headers['Cache-Control'] = 'private, no-store'
      if request.headers['Range'].present?
        send_blob_byte_range_data(blob, request.headers['Range'], disposition: disposition)
      else
        response.headers['Accept-Ranges'] = 'bytes'
        response.headers['Content-Length'] = blob.byte_size.to_s
        send_blob_stream(blob, disposition: disposition)
      end
    end

    # ?download=1 explicitly requests a file download. Without it we request
    # inline playback; Active Storage may still force attachment disposition
    # for content types outside the host's safe-inline allowlist.
    def disposition
      params[:download].present? ? 'attachment' : 'inline'
    end

    # Scoped to the tenant, so a cross-tenant id can never reach another
    # tenant's media — it simply isn't found.
    def set_testimonial
      @testimonial = Testimonial.for_tenant(current_tenant).find(params[:id])
    end

    def authorize_media
      return if Testimonials.admin?(request)
      # Authors can always see their own media — the widget replays their
      # attached video when they edit their review.
      return if current_author_id.present? && @testimonial.author_id == current_author_id.to_s

      if Testimonials.config.public_api && @testimonial.approved? && @testimonial.consent_given?
        response.set_header('Access-Control-Allow-Origin', '*')
        return
      end

      head :forbidden
    end
  end
end
