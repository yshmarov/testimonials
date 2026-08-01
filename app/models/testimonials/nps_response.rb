# frozen_string_literal: true

module Testimonials
  # One answer to "How likely are you to recommend us?" (0–10).
  class NpsResponse < ApplicationRecord
    validates :score, presence: true, inclusion: { in: 0..10 }

    scope :for_tenant, ->(tenant) { where(tenant: tenant.presence) }
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

    # The industry-standard reading of an NPS number, so the dashboard can say
    # whether a score is good without anyone having to go and google it.
    def self.band(nps)
      return nil if nps.nil?

      case nps
      when ...0 then :needs_work
      when 0...30 then :good
      when 30...70 then :great
      else :excellent
      end
    end

    # Below this many responses a single answer swings the score by several
    # points, so the dashboard says so instead of implying the number is solid.
    THIN_SAMPLE = 30
  end
end
