# frozen_string_literal: true

module Testimonials
  # Who is asking, which tenant they are in, and the gates that answer both.
  #
  # A concern rather than inherited behaviour because the engine has two
  # controller roots: the public endpoints hang off ActionController::Base, and
  # the dashboard hangs off whatever the host set as `base_controller_class`.
  # Both need everything here.
  module RequestContext
    extend ActiveSupport::Concern

    private

    def testimonials_admin_layout
      Testimonials.config.admin_layout
    end

    def current_author
      return @current_author if defined?(@current_author)

      @current_author = Testimonials.config.current_user.call(request)
    end

    def current_author_id
      current_author.respond_to?(:id) ? current_author.id : nil
    end

    # The tenant for this request (nil = the single global collection). Every
    # read and write in the engine scopes to it, so a resolved-tenant admin
    # only ever sees and writes their own tenant's records.
    def current_tenant
      return @current_tenant if defined?(@current_tenant)

      @current_tenant = Testimonials.tenant(request)
    end

    # Every dashboard query and the create endpoint's one-per-user lookup start
    # here, so neither can reach across tenants.
    def tenant_scope
      Testimonial.for_tenant(current_tenant)
    end

    def require_enabled
      head :forbidden unless Testimonials.enabled?(request)
    end

    def render_rate_limited
      message = I18n.t('testimonials.error_rate_limited',
                       default: 'Too many submissions. Please wait a moment and try again.')
      render json: { errors: [message] }, status: :too_many_requests
    end

    # Server-side gate for the dashboard. Default: development only.
    def require_admin
      return if Testimonials.admin?(request)

      render plain: 'Forbidden. Set Testimonials.config.authorize_admin to grant access.',
             status: :forbidden
    end

    # Guests get a permanent random token so the throttle ledger can
    # remember them across visits. Signed-in users are keyed by author_id
    # instead and never receive the cookie.
    def ensure_visitor_token
      return if current_author

      cookies[:testimonials_vid].presence || begin
        token = SecureRandom.base58(24)
        cookies.permanent[:testimonials_vid] = { value: token, httponly: true, same_site: :lax }
        token
      end
    end
  end
end
