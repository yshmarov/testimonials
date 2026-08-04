# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
  config.active_support.deprecation = :stderr
  config.active_storage.service = :test
  # Not the default :async adapter. Attaching a video enqueues Active Storage's
  # analysis job, and :async runs it on a background thread that checks out its
  # own connection — writes that no test transaction covers, landing in the
  # middle of whatever runs next. That is where "cannot rollback - no
  # transaction is active" and "database is locked" came from, and why the same
  # seed could pass and fail. Nothing here needs a job to actually run.
  config.active_job.queue_adapter = :test
  # In-process store so the rate limiter has a working counter in specs.
  config.cache_store = :memory_store
end
