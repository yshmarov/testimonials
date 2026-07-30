# frozen_string_literal: true

module Testimonials
  # One testimonial — text or video. Author attribution is optional and
  # stored as loose fields (no foreign key to the host's user table) so the
  # model is portable across apps with different user models.
  class Testimonial < ApplicationRecord
    KINDS = %w[text video].freeze
    STATUSES = %w[pending approved archived].freeze
    SOURCES = %w[widget page nps].freeze

    if defined?(::ActiveStorage)
      # Read at class load, which happens after the host's initializers, so
      # a storage_service set in config/initializers/testimonials.rb is
      # visible here. nil falls through to the environment's default service.
      storage = Testimonials.config.storage_service
      has_one_attached :video_file, service: storage
      has_one_attached :poster, service: storage # a still frame for the video, captured at record time
      has_one_attached :avatar, service: storage
    end

    validates :kind, inclusion: { in: KINDS }
    validates :status, inclusion: { in: STATUSES }
    validates :source, inclusion: { in: SOURCES }
    validates :body, presence: true, if: -> { kind == 'text' }
    validates :rating, inclusion: { in: 1..5 }, allow_nil: true

    # Multi-tenancy: everything is scoped to an opaque tenant key (nil = the
    # single global collection). Loose-coupled like author_id — a string, no
    # FK into the host's tables. See Testimonials.config.tenant.
    scope :for_tenant, ->(tenant) { where(tenant: tenant.presence) }

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

    def poster_attached?
      respond_to?(:poster) && poster.attached?
    end

    def avatar_attached?
      respond_to?(:avatar) && avatar.attached?
    end

    def display_name
      name.presence || (author_id.present? ? "##{author_id}" : nil)
    end

    # The curated pull-quote when the admin picked one, else the full text.
    def quote
      best_line.presence || body
    end
  end
end
