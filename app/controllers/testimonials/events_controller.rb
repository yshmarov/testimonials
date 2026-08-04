# frozen_string_literal: true

module Testimonials
  # The widget reports auto-prompt lifecycle here: "shown" when it opened
  # itself, "dismissed" when the user closed it without submitting.
  # ("submitted" is recorded server-side by the create endpoints.) These
  # events feed PromptEvent.eligible?, which is what keeps auto-prompts from
  # nagging anyone.
  class EventsController < ApplicationController
    CLIENT_ACTIONS = %w[shown dismissed].freeze

    before_action :require_enabled
    # An install run with --skip-prompt-events has no ledger to write to, and
    # the widget it serves knows not to post here in the first place.
    before_action :require_prompt_events

    def create
      kind = params[:kind].to_s
      action = params[:event_action].to_s
      head :unprocessable_entity and return unless PromptEvent::KINDS.include?(kind) &&
                                                   CLIENT_ACTIONS.include?(action)

      PromptEvent.record!(kind: kind, action: action, tenant: current_tenant,
                          author_id: current_author_id, visitor_token: ensure_visitor_token)
      head :no_content
    end

    private

    def require_prompt_events
      head :forbidden unless Testimonials.config.prompt_events
    end
  end
end
