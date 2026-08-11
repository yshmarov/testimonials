# frozen_string_literal: true

module Testimonials
  # Included into the host's ActionView. This lives under lib and is required
  # before the engine registers its Action View load hook: a host initializer
  # may load Action View before Rails sets up application autoloaders, when an
  # app/helpers constant cannot be resolved yet.
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

    def testimonials_button(label: nil, **)
      return unless Testimonials.enabled?(request)

      tag.button(label || testimonials_cta_label, type: 'button', 'data-testimonial-prompt': '', **)
    end

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

    def testimonials_existing_testimonial
      return @testimonials_existing_testimonial if defined?(@testimonials_existing_testimonial)

      author = testimonials_author
      @testimonials_existing_testimonial =
        if author.respond_to?(:id)
          Testimonial.for_tenant(Testimonials.tenant(request))
                     .where(author_id: author.id.to_s).newest_first.first
        end
    end

    def testimonials_auto_open
      kind = flash[:testimonials_prompt].to_s
      return unless Testimonials::PromptEvent::KINDS.include?(kind)
      return if kind == 'nps' && !Testimonials.config.nps
      return unless Testimonials.config.prompt_events

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
