# frozen_string_literal: true

ReviewEngine::Engine.routes.draw do
  # Public: the widget posts testimonials and prompt-lifecycle events here.
  resources :testimonials, only: :create
  resources :events, only: :create
end
