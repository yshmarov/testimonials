# frozen_string_literal: true

module Testimonials
  class NpsController < ApplicationController
    before_action :require_enabled
    before_action :require_nps

    if respond_to?(:rate_limit) && Testimonials.config.rate_limit
      rate_limit(**Testimonials.config.rate_limit, only: :create, with: -> { render_rate_limited })
    end

    def create
      nps = NpsResponse.new(nps_params)
      nps.locale = I18n.locale.to_s
      nps.tenant = current_tenant
      nps.page_url = clean_page_url(nps.page_url)
      nps.user_agent = request.user_agent
      attribute_author(nps)

      if nps.save
        PromptEvent.record!(kind: 'nps', action: 'submitted', tenant: current_tenant,
                            author_id: current_author_id, visitor_token: ensure_visitor_token)
        notify_host(nps)
        notify_detractor(nps) if nps.detractor?
        render json: { offer_testimonial: offer_testimonial?(nps) }, status: :created
      else
        render json: { errors: nps.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def require_nps
      head :forbidden unless Testimonials.config.nps
    end

    def nps_params
      params.require(:nps).permit(:score, :comment, :email, :page_url)
    end

    def attribute_author(nps)
      author = current_author
      return if author.nil?

      nps.author_id = author.id.to_s if author.respond_to?(:id)
      display = Testimonials.config.user_display.call(author) || {}
      nps.name = display[:name].presence
      nps.email = display[:email].presence || nps.email
    end

    # A promoter gets the testimonial ask right away — but only if the
    # throttle ledger would allow a testimonial prompt anyway.
    def offer_testimonial?(nps)
      nps.promoter? && PromptEvent.eligible?(
        kind: 'testimonial',
        tenant: current_tenant,
        author_id: current_author_id,
        visitor_token: cookies[:testimonials_vid]
      )
    end

    def notify_host(nps)
      Testimonials.config.on_submit.call(nps)
    rescue StandardError => e
      Rails.logger.error("testimonials: on_submit hook raised #{e.class}: #{e.message}")
    end

    def notify_detractor(nps)
      Testimonials.config.on_detractor.call(nps)
    rescue StandardError => e
      Rails.logger.error("testimonials: on_detractor hook raised #{e.class}: #{e.message}")
    end
  end
end
