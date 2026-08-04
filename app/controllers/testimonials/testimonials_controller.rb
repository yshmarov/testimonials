# frozen_string_literal: true

module Testimonials
  # The testimonial queue: triage, search, best lines. Staff only.
  #
  # POST to the mount path is SubmissionsController — the public write endpoint
  # cannot share a controller with these, because this one inherits whatever the
  # host set as base_controller_class.
  class TestimonialsController < DashboardController
    PER_PAGE = 50

    before_action :set_testimonial, only: %i[show update destroy]

    def index
      @status = Testimonial::STATUSES.include?(params[:status]) ? params[:status] : 'pending'
      @kind = Testimonial::KINDS.include?(params[:kind]) ? params[:kind] : nil
      @query = params[:q].to_s.strip.presence
      @counts = tenant_scope.group(:status).count

      scope = tenant_scope.where(status: @status)
      scope = scope.where(kind: @kind) if @kind
      scope = search(scope) if @query
      @page = [params[:page].to_i, 1].max
      @testimonials = scope.newest_first.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @more = @testimonials.size > PER_PAGE
      @testimonials = @testimonials.first(PER_PAGE)

      @selected_testimonial = tenant_scope.find_by(id: params[:testimonial_id]) if params[:testimonial_id].present?
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

    private

    def set_testimonial
      @testimonial = tenant_scope.find(params[:id])
    end

    def admin_params
      params.require(:testimonial).permit(:status, :featured, :best_line)
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
  end
end
