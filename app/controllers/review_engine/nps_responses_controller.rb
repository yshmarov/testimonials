# frozen_string_literal: true

module ReviewEngine
  # The NPS side of the dashboard: overall score plus the response list.
  class NpsResponsesController < ApplicationController
    PER_PAGE = 50

    layout 'review_engine/application'

    before_action :require_admin

    def index
      @score = NpsResponse.score
      @total = NpsResponse.count
      @promoters = NpsResponse.where(score: 9..10).count
      @passives = NpsResponse.where(score: 7..8).count
      @detractors = NpsResponse.where(score: 0..6).count

      @page = [params[:page].to_i, 1].max
      @responses = NpsResponse.newest_first.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @more = @responses.size > PER_PAGE
      @responses = @responses.first(PER_PAGE)
    end
  end
end
