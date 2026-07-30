# frozen_string_literal: true

Rails.application.routes.draw do
  mount_testimonials at: "/testimonials"
  get "sample", to: "sample#show"
  post "sample/celebrate", to: "sample#celebrate"
end
