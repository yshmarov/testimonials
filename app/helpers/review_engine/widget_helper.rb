# frozen_string_literal: true

module ReviewEngine
  # Included into the host's ActionView. Drop `<%= review_engine_tag %>`
  # before </body> in your layout; it renders nothing unless reviews are
  # enabled for the request. The widget stays invisible until opened — by a
  # `review_prompt!` from a controller (throttled), by any element with a
  # `data-review-prompt` attribute, or by `window.ReviewEngine.open()`.
  #
  # `review_engine_button` renders a ready-made opener with a localized
  # label ("Leave a review", or "Update your review" once the user has one),
  # so hosts get a user-facing entry point without any i18n setup.
  module WidgetHelper
    def review_engine_tag
      return unless ReviewEngine.enabled?(request)

      Widget.snippet(
        locale: I18n.locale,
        authenticated: review_engine_author.present?,
        auto_open: review_engine_auto_open,
        existing: review_engine_existing_testimonial,
        nonce: (content_security_policy_nonce if respond_to?(:content_security_policy_nonce))
      ).html_safe
    end

    # A plain, unstyled <button> so it picks up the host's own styles. Put it
    # anywhere on a page that also renders review_engine_tag. Pass label: to
    # override the localized default, and any other options (class:, etc.)
    # through to the tag.
    def review_engine_button(label: nil, **)
      return unless ReviewEngine.enabled?(request)

      tag.button(label || review_engine_cta_label, type: 'button', 'data-review-prompt': '', **)
    end

    # The localized call-to-action on its own — "Leave a review", or "Update
    # your review" once the user has one — for hosts composing their own
    # opener markup (icons, list items) around a data-review-prompt element.
    def review_engine_cta_label
      if review_engine_existing_testimonial
        I18n.t(:update_title, scope: :review_engine, default: 'Update your review')
      else
        I18n.t(:cta, scope: :review_engine, default: 'Leave a review')
      end
    end

    private

    def review_engine_author
      return @review_engine_author if defined?(@review_engine_author)

      @review_engine_author = ReviewEngine.config.current_user.call(request)
    end

    # One review per signed-in user: this is the record the widget opens
    # pre-filled, and the one the create endpoint updates in place.
    def review_engine_existing_testimonial
      return @review_engine_existing_testimonial if defined?(@review_engine_existing_testimonial)

      author = review_engine_author
      @review_engine_existing_testimonial =
        author.respond_to?(:id) ? Testimonial.where(author_id: author.id.to_s).newest_first.first : nil
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
