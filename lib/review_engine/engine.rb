# frozen_string_literal: true

module ReviewEngine
  class Engine < ::Rails::Engine
    isolate_namespace ReviewEngine

    initializer 'review_engine.helpers' do
      ActiveSupport.on_load(:action_view) do
        include ReviewEngine::WidgetHelper
      end
      ActiveSupport.on_load(:action_controller) do
        include ReviewEngine::PromptHelper
      end
    end
  end
end
