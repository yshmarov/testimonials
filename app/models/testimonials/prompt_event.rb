# frozen_string_literal: true

module Testimonials
  # The throttling ledger. Every auto-open is a "shown", every close without
  # submitting is a "dismissed", every saved submission is a "submitted" —
  # keyed by author_id for signed-in users, by a visitor cookie otherwise.
  # eligible? reads this history so the widget never nags:
  #
  #   * submitted a testimonial     -> never auto-prompted for one again
  #   * submitted NPS               -> not again within nps_reprompt_after
  #   * shown or dismissed recently -> not again within reprompt_after
  #   * shown max_prompts times     -> never auto-prompted for that kind again
  #
  # Explicit opens (the user clicked something) bypass all of this.
  #
  # The ledger is optional: an install run with --skip-prompt-events has no
  # table behind this class and config.prompt_events is false, so record! is a
  # no-op and eligible? answers without a query. Every write and every read
  # goes through the two methods below, so that flag is the only guard needed
  # — nothing here asks the schema at runtime.
  class PromptEvent < ApplicationRecord
    KINDS = %w[testimonial nps].freeze
    ACTIONS = %w[shown dismissed submitted].freeze

    validates :kind, inclusion: { in: KINDS }
    validates :action, inclusion: { in: ACTIONS }

    class << self
      def record!(kind:, action:, author_id: nil, visitor_token: nil, tenant: nil)
        return unless Testimonials.config.prompt_events
        return if author_id.blank? && visitor_token.blank?

        create!(kind: kind.to_s, action: action.to_s, tenant: tenant.presence,
                author_id: author_id.presence, visitor_token: visitor_token.presence)
      end

      # Throttling is per-tenant: a user prompted in one tenant is still
      # eligible in another, so each collection can ask independently.
      def eligible?(kind:, author_id: nil, visitor_token: nil, tenant: nil)
        kind = kind.to_s
        return false unless KINDS.include?(kind)
        # No identity, no history: a brand-new visitor is always eligible.
        return true if author_id.blank? && visitor_token.blank?
        # No ledger, no history either — the same answer, one flag earlier.
        # This is not a licence to nag: with the ledger off nothing auto-opens
        # (see WidgetHelper#testimonials_auto_open), and the one caller left is
        # the promoter offered the form inside a flow they opened themselves.
        return true unless Testimonials.config.prompt_events

        history = subject(author_id, visitor_token, tenant).where(kind: kind)
        config = Testimonials.config

        return false if submitted_recently?(history, kind, config)
        return false if history.where(action: %w[shown dismissed])
                               .exists?(created_at: (Time.current - config.reprompt_after)..)

        history.where(action: 'shown').count < config.max_prompts
      end

      private

      def subject(author_id, visitor_token, tenant = nil)
        scope = where(tenant: tenant.presence)
        author_id.present? ? scope.where(author_id: author_id.to_s) : scope.where(visitor_token: visitor_token)
      end

      def submitted_recently?(history, kind, config)
        submitted = history.where(action: 'submitted')
        return submitted.exists? if kind == 'testimonial'

        submitted.exists?(created_at: (Time.current - config.nps_reprompt_after)..)
      end
    end
  end
end
