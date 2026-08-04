# frozen_string_literal: true

Testimonials::Engine.routes.draw do
  # Everything with a fixed name goes first; the flat testimonial routes at
  # the bottom own "/:id".
  get 'widget.js', to: 'widgets#show', as: :widget
  get 'dashboard.js', to: 'widgets#dashboard', as: :dashboard_script
  get 'dashboard.css', to: 'widgets#dashboard_stylesheet', as: :dashboard_stylesheet
  get 'new', to: 'collection#show', as: :collection
  get 'nps/new', to: 'collection#nps', as: :nps_collection
  resources :events, only: :create
  resource :nps, only: :create, controller: 'nps'
  resources :nps_responses, only: %i[index show]

  # Read-only JSON for rendering testimonials anywhere. Plain REST: the
  # collection is a noun. Under a same-named mount this reads
  # "/testimonials/api/testimonials"; mount the engine at a shorter path
  # (e.g. "/reviews") for "/reviews/api/testimonials".
  namespace :api do
    resources :testimonials, only: :index
    get 'stats', to: 'stats#show'
  end

  # Media by testimonial id, gated (admin, author, or public_api + publishable).
  get ':id/video', to: 'media#video', as: :testimonial_video
  get ':id/poster', to: 'media#poster', as: :testimonial_poster
  get ':id/avatar', to: 'media#avatar', as: :testimonial_avatar

  # Flat, human URLs: the mount path IS the resource. /testimonials is the
  # dashboard, POST /testimonials the widget endpoint, /testimonials/2 a testimonial.
  #
  # No `id: /\d+/` constraint: it made these routes bigint-only, which forced
  # the tables to be bigint too, which meant a uuid-keyed host could never
  # attach a video or avatar (its active_storage_attachments.record_id is a
  # uuid column). The constraint was never load-bearing — every fixed-name
  # route above is declared first, so ordering already does the disambiguating,
  # and an id that matches no record still 404s, just via RecordNotFound rather
  # than a routing error.
  #
  # POST goes to SubmissionsController, not to this resource: the widget's write
  # endpoint is public and the rest is staff-only, and only the staff half
  # inherits config.base_controller_class. Sharing one controller would put a
  # host's admin authentication in front of a member leaving a review.
  post '', to: 'submissions#create', as: :submissions
  resources :testimonials, path: '', only: %i[index show update destroy]

  root to: 'testimonials#index'
end
