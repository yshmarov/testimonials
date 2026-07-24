# frozen_string_literal: true

ReviewEngine::Engine.routes.draw do
  # Public: the widget posts testimonials, NPS answers, and prompt-lifecycle
  # events here; /new is the shareable collection page.
  resources :testimonials, only: %i[create index show update destroy]
  resources :events, only: :create
  resource :nps, only: :create, controller: 'nps'
  get 'new', to: 'collection#show', as: :collection

  # Media by testimonial id, gated (admin, or public_api + publishable).
  get 'testimonials/:id/video', to: 'media#video', as: :testimonial_video
  get 'testimonials/:id/avatar', to: 'media#avatar', as: :testimonial_avatar

  # Dashboard extras.
  resources :nps_responses, only: :index

  # Read-only JSON for rendering testimonials anywhere.
  namespace :api do
    resources :testimonials, only: :index
    get 'stats', to: 'stats#show'
  end

  root to: 'testimonials#index'
end
