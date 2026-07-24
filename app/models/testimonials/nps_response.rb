# frozen_string_literal: true

module Testimonials
  # One answer to "How likely are you to recommend us?" (0–10).
  class NpsResponse < ApplicationRecord
    validates :score, presence: true, inclusion: { in: 0..10 }

    scope :newest_first, -> { order(id: :desc) }

    def promoter? = score >= 9
    def passive? = score.between?(7, 8)
    def detractor? = score <= 6

    # The classic Net Promoter Score: %promoters − %detractors, −100..100.
    def self.score(scope = all)
      total = scope.count
      return nil if total.zero?

      promoters = scope.where(score: 9..10).count
      detractors = scope.where(score: 0..6).count
      ((promoters - detractors) * 100.0 / total).round
    end
  end
end
