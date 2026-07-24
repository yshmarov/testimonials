# frozen_string_literal: true

module Testimonials
  # Serves the widget JavaScript as a plain same-origin script. Same-origin
  # matters: under a `script-src 'self'` (or nonce-based) CSP, an external
  # script from the app's own host is always allowed — including when Turbo
  # Drive swaps the <body> and re-runs body scripts under the *original*
  # page's CSP header, where a freshly minted inline nonce would be refused.
  class WidgetsController < ApplicationController
    # The script is static and carries no user data; without this, Rails'
    # cross-origin JavaScript guard refuses to serve it to a plain
    # <script src> request.
    skip_forgery_protection

    # ETag-only freshness: the browser revalidates on every load (a cheap
    # 304), so a gem update can never leave stale widget code running
    # against updated markup. No time-based cache window on purpose.
    def show
      return unless stale?(etag: [Testimonials::VERSION, Widget.javascript])

      render plain: Widget.javascript, content_type: 'text/javascript'
    end

    def dashboard
      return unless stale?(etag: [Testimonials::VERSION, Widget.dashboard_javascript])

      render plain: Widget.dashboard_javascript, content_type: 'text/javascript'
    end
  end
end
