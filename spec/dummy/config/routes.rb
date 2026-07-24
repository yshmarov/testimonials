# frozen_string_literal: true

Rails.application.routes.draw do
  mount ReviewEngine::Engine => "/reviews"
  get "sample", to: "sample#show"
  post "sample/celebrate", to: "sample#celebrate"
end
