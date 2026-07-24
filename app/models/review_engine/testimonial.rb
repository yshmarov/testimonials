# frozen_string_literal: true

module ReviewEngine
  # One testimonial — text or video. Author attribution is optional and
  # stored as loose fields (no foreign key to the host's user table) so the
  # model is portable across apps with different user models.
  class Testimonial < ApplicationRecord
    KINDS = %w[text video].freeze
    STATUSES = %w[pending approved archived].freeze
    SOURCES = %w[widget page nps].freeze

    if defined?(::ActiveStorage)
      has_one_attached :video_file
      has_one_attached :avatar
    end

    validates :kind, inclusion: { in: KINDS }
    validates :status, inclusion: { in: STATUSES }
    validates :source, inclusion: { in: SOURCES }
    validates :body, presence: true, if: -> { kind == 'text' }
    validates :rating, inclusion: { in: 1..5 }, allow_nil: true

    scope :newest_first, -> { order(id: :desc) }
    scope :approved, -> { where(status: 'approved') }
    # What the read API serves: approved by an admin AND consented by the
    # customer. Both, always.
    scope :publishable, -> { approved.where(consent_given: true) }
    scope :featured_first, -> { order(featured: :desc, id: :desc) }

    STATUSES.each do |status|
      define_method(:"#{status}?") { self.status == status }
    end

    def video? = kind == 'video'

    def video_attached?
      respond_to?(:video_file) && video_file.attached?
    end

    def avatar_attached?
      respond_to?(:avatar) && avatar.attached?
    end

    def display_name
      name.presence || (author_id.present? ? "##{author_id}" : nil)
    end

    # The curated pull-quote when the admin picked one, else the full text.
    def quote
      excerpt.presence || body
    end
  end
end
