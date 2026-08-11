# frozen_string_literal: true

# A host may configure Action View from an application initializer. That fires
# ActiveSupport.on_load(:action_view) before Rails finishes setting up app
# autoloaders, so every constant used by the gem's hook must already be loaded.
# If WidgetHelper drifts back under app/helpers, the dummy app fails to boot.
ActionView::Base.field_error_proc = proc { |html_tag, _instance| html_tag }
