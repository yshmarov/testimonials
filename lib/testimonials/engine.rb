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
  end
end
