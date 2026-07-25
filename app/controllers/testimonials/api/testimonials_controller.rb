# frozen_string_literal: true

module Testimonials
  module Api
    class TestimonialsController < BaseController
      MAX_LIMIT = 100

      def index
        scope = Testimonial.publishable.featured_first
        scope = scope.where(featured: true) if params[:featured].present?
        scope = scope.where(kind: params[:kind]) if Testimonial::KINDS.include?(params[:kind])
        scope = scope.where(rating: params[:min_rating].to_i..) if params[:min_rating].present?
        limit = params[:limit].to_i.clamp(1, MAX_LIMIT)
        limit = MAX_LIMIT if params[:limit].blank?

        render json: { testimonials: scope.limit(limit).map { |t| serialize(t) } }
      end

      private

      # Name, title and media only — never emails, never author ids. The
      # customer consented to publication, not to leaking contact details.
      def serialize(testimonial)
        {
          id: testimonial.id,
          kind: testimonial.kind,
          body: testimonial.body,
          best_line: testimonial.best_line,
          quote: testimonial.quote,
          rating: testimonial.rating,
          name: testimonial.name,
          title_company: testimonial.title_company,
          featured: testimonial.featured?,
          created_at: testimonial.created_at.iso8601,
          avatar_url: (testimonial_avatar_url(testimonial) if testimonial.avatar_attached?),
          video_url: (testimonial_video_url(testimonial) if testimonial.video_attached?),
          poster_url: (testimonial_poster_url(testimonial) if testimonial.poster_attached?)
        }
      end
    end
  end
end
