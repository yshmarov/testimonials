# frozen_string_literal: true

module ReviewEngine
  # Included into the host's ActionView. Drop `<%= review_engine_tag %>`
  # before </body> in your layout; it renders nothing unless reviews are
  # enabled for the request. The widget stays invisible until opened — by a
  # `review_prompt!` from a controller (throttled), by any element with a
  # `data-review-prompt` attribute, or by `window.ReviewEngine.open()`.
  module WidgetHelper
    def review_engine_tag
      return unless ReviewEngine.enabled?(request)

      Widget.snippet(
        locale: I18n.locale,
        authenticated: review_engine_author.present?,
        auto_open: review_engine_auto_open,
        nonce: (content_security_policy_nonce if respond_to?(:content_security_policy_nonce))
      ).html_safe
    end

    private

    def review_engine_author
      return @review_engine_author if defined?(@review_engine_author)

      @review_engine_author = ReviewEngine.config.current_user.call(request)
    end

    # A prompt requested via review_prompt! rides the flash, so it survives
    # the usual redirect-after-create. It only reaches the page if the
    # throttle ledger agrees — call review_prompt! as often as you like.
    def review_engine_auto_open
      kind = flash[:review_engine_prompt].to_s
      return unless ReviewEngine::PromptEvent::KINDS.include?(kind)
      return if kind == 'nps' && !ReviewEngine.config.nps

      author = review_engine_author
      return unless ReviewEngine::PromptEvent.eligible?(
        kind: kind,
        author_id: author.respond_to?(:id) ? author.id : nil,
        visitor_token: cookies[:review_engine_vid]
      )

      kind
    end
  end
end
