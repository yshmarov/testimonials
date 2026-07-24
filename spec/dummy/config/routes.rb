# frozen_string_literal: true

Rails.application.routes.draw do
  mount Testimonials::Engine => "/testimonials"
  get "sample", to: "sample#show"
  post "sample/celebrate", to: "sample#celebrate"
end
