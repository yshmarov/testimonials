# frozen_string_literal: true

module Testimonials
  # Optional sugar for multi-tenant apps. `has_testimonials` on a host model
  # gives it `.testimonials` (and `.testimonials_nps`) relations, keyed by the
  # record's GlobalID — the documented tenant convention:
  #
  #   class Organization < ApplicationRecord
  #     has_testimonials
  #   end
  #   organization.testimonials.approved   # a normal Active Record relation
  #
  # It's a pure veneer over `Testimonial.for_tenant(...)` — no association, no
  # foreign key, no `owner_type` class-name coupling. Apps that don't want it
  # still get full multi-tenancy through `config.tenant` alone.
  #
  # The write side lines up automatically when the tenant resolver produces the
  # same GlobalID key, e.g. `config.tenant = ->(r){ Current.org.to_gid.to_s }`.
  # Key by something else? Pass a matching resolver: `has_testimonials(key:
  # ->(org){ org.subdomain })` — and use the same in `config.tenant`.
  module HasTestimonials
    def has_testimonials(as: :testimonials, key: nil) # rubocop:disable Naming/PredicatePrefix
      resolver = key || ->(record) { record.to_gid.to_s }

      define_method(as) { Testimonials::Testimonial.for_tenant(resolver.call(self)) }
      define_method(:"#{as}_nps") { Testimonials::NpsResponse.for_tenant(resolver.call(self)) }
    end
  end
end
