# frozen_string_literal: true

ReviewEngine::Engine.routes.draw do
  # Everything with a fixed name goes first; the flat testimonial routes at
  # the bottom own "/:id".
  get 'widget.js', to: 'widgets#show', as: :widget
  get 'new', to: 'collection#show', as: :collection
  resources :events, only: :create
  resource :nps, only: :create, controller: 'nps'
  resources :nps_responses, only: :index

  # Read-only JSON for rendering testimonials anywhere.
  namespace :api do
    resources :testimonials, only: :index
    get 'stats', to: 'stats#show'
  end

  # Media by testimonial id, gated (admin, author, or public_api + publishable).
  get ':id/video', to: 'media#video', as: :testimonial_video, constraints: { id: /\d+/ }
  get ':id/avatar', to: 'media#avatar', as: :testimonial_avatar, constraints: { id: /\d+/ }

  # Flat, human URLs: the mount path IS the resource. /reviews is the
  # dashboard, POST /reviews the widget endpoint, /reviews/2 a testimonial.
  resources :testimonials, path: '', only: %i[create index show update destroy],
                           constraints: { id: /\d+/ }

  root to: 'testimonials#index'
end
