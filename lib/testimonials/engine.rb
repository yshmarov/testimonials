# frozen_string_literal: true

module Testimonials
  class Engine < ::Rails::Engine
    initializer 'testimonials.ractor_middleware' do |app|
      app.middleware.insert_before 0, RactorSupport::Middleware
    end

    isolate_namespace Testimonials

    initializer 'testimonials.ractorize', before: 'action_controller.ractorize' do
      if Rails::Application.method_defined?(:ractorize!)
        Engine.routes.singleton_class.prepend(RactorSupport::MountedRoutes)
      end
      ActiveSupport.on_load(:before_ractorize) { Testimonials::RactorSupport.prepare! }
    end

    rake_tasks do
      load File.expand_path('../tasks/testimonials_tasks.rake', __dir__)
    end

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

    initializer 'testimonials.routing' do
      ActionDispatch::Routing::Mapper.include(Module.new do
        def mount_testimonials(at: Testimonials.config.mount_path, **options)
          Testimonials.config.mount_path = at
          mount Testimonials::Engine, at:, **options
        end
      end)
    end
  end
end
