# frozen_string_literal: true

module ReviewEngine
  class TestimonialsController < ApplicationController
    PER_PAGE = 50

    layout 'review_engine/application', except: :create

    # create is the public widget endpoint; everything else is the dashboard.
    before_action :require_enabled, only: :create
    before_action :require_admin, except: :create
    before_action :set_testimonial, only: %i[show update destroy]

    # Throttle the public endpoint per IP so one user or bot can't flood the
    # table (a submission may carry a video). Uses the rate limiter built
    # into Rails 7.2+ (backed by Rails.cache); on Rails 7.1 this is a no-op.
    # Tune or disable via config.rate_limit — read once at boot.
    if respond_to?(:rate_limit) && ReviewEngine.config.rate_limit
      rate_limit(**ReviewEngine.config.rate_limit,
                 only: :create,
                 with: -> { render json: { errors: [I18n.t('review_engine.error_rate_limited', default: 'Too many submissions. Please wait a moment and try again.')] }, status: :too_many_requests })
    end

    def index
      @status = Testimonial::STATUSES.include?(params[:status]) ? params[:status] : 'pending'
      @kind = Testimonial::KINDS.include?(params[:kind]) ? params[:kind] : nil
      @query = params[:q].to_s.strip.presence
      @counts = Testimonial.group(:status).count

      scope = Testimonial.where(status: @status)
      scope = scope.where(kind: @kind) if @kind
      scope = search(scope) if @query
      @page = [params[:page].to_i, 1].max
      @testimonials = scope.newest_first.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @more = @testimonials.size > PER_PAGE
      @testimonials = @testimonials.first(PER_PAGE)
    end

    def show; end

    def update
      @testimonial.update!(admin_params)
      redirect_back fallback_location: testimonial_path(@testimonial), status: :see_other
    end

    def destroy
      @testimonial.destroy!
      redirect_to root_path, status: :see_other
    end

    def create
      testimonial = build_testimonial

      error = attach_video(testimonial) || attach_avatar(testimonial)
      return render json: { errors: [error] }, status: :unprocessable_entity if error

      if testimonial.save
        record_submission
        notify_host(testimonial)
        head :created
      else
        render json: { errors: testimonial.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_testimonial
      @testimonial = Testimonial.find(params[:id])
    end

    def admin_params
      params.require(:testimonial).permit(:status, :featured, :excerpt)
    end

    # Case-insensitive match on the free-text columns. LOWER() keeps it
    # portable across SQLite/PostgreSQL/MySQL, and the explicit ESCAPE makes
    # the sanitized backslash escapes work on SQLite, which has no default
    # LIKE escape character.
    def search(scope)
      pattern = "%#{Testimonial.sanitize_sql_like(@query.downcase)}%"
      scope.where(
        "LOWER(COALESCE(body, '')) LIKE :q ESCAPE '\\' OR LOWER(COALESCE(name, '')) LIKE :q ESCAPE '\\' " \
        "OR LOWER(COALESCE(email, '')) LIKE :q ESCAPE '\\'",
        q: pattern
      )
    end

    def build_testimonial
      testimonial = Testimonial.new(testimonial_params)
      testimonial.kind = params.dig(:testimonial, :video_file).present? ? 'video' : 'text'
      testimonial.source = 'widget' unless Testimonial::SOURCES.include?(testimonial.source)
      testimonial.consent_text = ReviewEngine.consent_text if testimonial.consent_given?
      testimonial.locale = I18n.locale.to_s
      testimonial.user_agent = request.user_agent
      attribute_author(testimonial)
      testimonial
    end

    def testimonial_params
      params.require(:testimonial)
            .permit(:body, :rating, :consent_given, :page_url, :source,
                    :name, :email, :title_company)
    end

    # Signed-in users are attributed server-side — the widget never sends
    # (and the endpoint never trusts) contact fields for them.
    def attribute_author(testimonial)
      author = current_author
      return if author.nil?

      testimonial.author_id = author.id.to_s if author.respond_to?(:id)
      display = ReviewEngine.config.user_display.call(author) || {}
      testimonial.name = display[:name].presence || testimonial.name
      testimonial.email = display[:email].presence || testimonial.email
      testimonial.title_company = display[:title_company].presence || testimonial.title_company
    end

    # Returns an error message, or nil when everything is fine.
    def attach_video(testimonial)
      file = params.dig(:testimonial, :video_file)
      return nil if file.blank?
      return error_label(:error_save) unless ReviewEngine.config.video_enabled?
      return error_label(:error_video_too_large) if file.size > ReviewEngine.config.max_video_size
      return error_label(:error_save) unless file.content_type.to_s.start_with?('video/', 'audio/')

      testimonial.video_file.attach(file)
      nil
    end

    def attach_avatar(testimonial)
      file = params.dig(:testimonial, :avatar)
      return nil if file.blank?
      return error_label(:error_save) unless ReviewEngine.config.avatars_enabled?
      return error_label(:error_save) if file.size > ReviewEngine.config.max_avatar_size
      return error_label(:error_save) unless file.content_type.to_s.start_with?('image/')

      testimonial.avatar.attach(file)
      nil
    end

    def record_submission
      PromptEvent.record!(kind: 'testimonial', action: 'submitted',
                          author_id: current_author_id, visitor_token: ensure_visitor_token)
    end

    # The host's hook must never turn a saved submission into a 500 — the
    # testimonial is in the database; notification failures are the host's
    # logs' problem.
    def notify_host(record)
      ReviewEngine.config.on_submit.call(record)
    rescue StandardError => e
      Rails.logger.error("review_engine: on_submit hook raised #{e.class}: #{e.message}")
    end

    def error_label(key)
      defaults = {
        error_save: 'Could not send. Please try again.',
        error_video_too_large: 'The video is too large (max %{size} MB).'
      }
      I18n.t(key, scope: :review_engine, default: defaults[key],
                  size: ReviewEngine.config.max_video_size / (1024 * 1024))
    end
  end
end
