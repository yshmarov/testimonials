# frozen_string_literal: true

module ReviewEngine
  # Included into the host's controllers. Call `review_prompt!` at your
  # app's success moments — subscription renewed, tenth invoice sent, big
  # milestone hit. The widget auto-opens on the next rendered page *if* the
  # throttle allows, so calling this liberally is safe: users who submitted,
  # recently dismissed, or were already prompted max_prompts times are left
  # alone.
  module PromptHelper
    def review_prompt!(kind = :testimonial)
      flash[:review_engine_prompt] = kind.to_s
    end
  end
end
