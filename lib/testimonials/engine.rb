# frozen_string_literal: true

module Testimonials
  class Engine < ::Rails::Engine
    isolate_namespace Testimonials

    initializer 'testimonials.helpers' do
      ActiveSupport.on_load(:action_view) do
        include Testimonials::WidgetHelper
      end
      ActiveSupport.on_load(:action_controller) do
        include Testimonials::PromptHelper
      end
    end

    # Make the optional `has_testimonials` model macro available on every
    # Active Record model, without requiring the host to include anything.
    initializer 'testimonials.model' do
      ActiveSupport.on_load(:active_record) do
        extend Testimonials::HasTestimonials
      end
    end
  end
end
