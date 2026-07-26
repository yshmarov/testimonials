# frozen_string_literal: true

module Testimonials
  # Included into the host's ActionView. Drop `<%= testimonials_tag %>`
  # before </body> in your layout; it renders nothing unless reviews are
  # enabled for the request. The widget stays invisible until opened — by a
  # `testimonial_prompt!` from a controller (throttled), by any element with a
  # `data-testimonial-prompt` attribute, or by `window.Testimonials.open()`.
  #
  # `testimonials_button` renders a ready-made opener with a localized
  # label ("Leave a review", or "Update your review" once the user has one),
  # so hosts get a user-facing entry point without any i18n setup.
  module WidgetHelper
    def testimonials_tag
      return unless Testimonials.enabled?(request)

      Widget.snippet(
        locale: I18n.locale,
        authenticated: testimonials_author.present?,
        auto_open: testimonials_auto_open,
        existing: testimonials_existing_testimonial,
        nonce: (content_security_policy_nonce if respond_to?(:content_security_policy_nonce))
      ).html_safe
    end

    # A plain, unstyled <button> so it picks up the host's own styles. Put it
    # anywhere on a page that also renders testimonials_tag. Pass label: to
    # override the localized default, and any other options (class:, etc.)
    # through to the tag.
    def testimonials_button(label: nil, **)
      return unless Testimonials.enabled?(request)

      tag.button(label || testimonials_cta_label, type: 'button', 'data-testimonial-prompt': '', **)
    end

    # The localized call-to-action on its own — "Leave a review", or "Update
    # your review" once the user has one — for hosts composing their own
    # opener markup (icons, list items) around a data-testimonial-prompt element.
    def testimonials_cta_label
      if testimonials_existing_testimonial
        I18n.t(:update_title, scope: :testimonials, default: 'Update your review')
      else
        I18n.t(:cta, scope: :testimonials, default: 'Leave a review')
      end
    end

    private

    def testimonials_author
      return @testimonials_author if defined?(@testimonials_author)

      @testimonials_author = Testimonials.config.current_user.call(request)
    end

    # One review per signed-in user (per tenant): this is the record the widget
    # opens pre-filled, and the one the create endpoint updates in place.
    def testimonials_existing_testimonial
      return @testimonials_existing_testimonial if defined?(@testimonials_existing_testimonial)

      author = testimonials_author
      @testimonials_existing_testimonial =
        if author.respond_to?(:id)
          Testimonial.for_tenant(Testimonials.tenant(request))
                     .where(author_id: author.id.to_s).newest_first.first
        end
    end

    # A prompt requested via testimonial_prompt! rides the flash, so it survives
    # the usual redirect-after-create. It only reaches the page if the
    # throttle ledger agrees — call testimonial_prompt! as often as you like.
    def testimonials_auto_open
      kind = flash[:testimonials_prompt].to_s
      return unless Testimonials::PromptEvent::KINDS.include?(kind)
      return if kind == 'nps' && !Testimonials.config.nps

      author = testimonials_author
      return unless Testimonials::PromptEvent.eligible?(
        kind: kind,
        tenant: Testimonials.tenant(request),
        author_id: author.respond_to?(:id) ? author.id : nil,
        visitor_token: cookies[:testimonials_vid]
      )

      kind
    end
  end
end
