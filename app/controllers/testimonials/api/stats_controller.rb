# frozen_string_literal: true

module Testimonials
  module Api
    # Powers rating badges: "★ 4.9 from 87 reviews".
    class StatsController < BaseController
      def show
        scope = Testimonial.for_tenant(current_tenant).publishable
        rated = scope.where.not(rating: nil)

        render json: {
          count: scope.count,
          average_rating: rated.average(:rating)&.to_f&.round(2),
          ratings_count: rated.count,
          nps_score: (NpsResponse.score(NpsResponse.for_tenant(current_tenant)) if Testimonials.config.nps)
        }
      end
    end
  end
end
