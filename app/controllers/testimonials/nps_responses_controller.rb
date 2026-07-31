# frozen_string_literal: true

module Testimonials
  # The NPS side of the dashboard: overall score plus the response list.
  class NpsResponsesController < ApplicationController
    PER_PAGE = 50

    layout :testimonials_admin_layout

    before_action :require_admin
    before_action :set_response, only: :show

    def index
      scope = NpsResponse.for_tenant(current_tenant)
      @score = NpsResponse.score(scope)
      @total = scope.count
      @promoters = scope.where(score: 9..10).count
      @passives = scope.where(score: 7..8).count
      @detractors = scope.where(score: 0..6).count

      @page = [params[:page].to_i, 1].max
      @responses = scope.newest_first.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @more = @responses.size > PER_PAGE
      @responses = @responses.first(PER_PAGE)

      @selected_response = scope.find_by(id: params[:response_id]) if params[:response_id].present?
    end

    def show; end

    private

    def set_response
      @response = NpsResponse.for_tenant(current_tenant).find(params[:id])
    end
  end
end
