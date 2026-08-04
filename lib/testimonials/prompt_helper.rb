# frozen_string_literal: true

module Testimonials
  # Included into the host's controllers. Call `testimonial_prompt!` at your
  # app's success moments — subscription renewed, tenth invoice sent, big
  # milestone hit. The widget auto-opens on the next rendered page *if* the
  # throttle allows, so calling this liberally is safe: users who submitted,
  # recently dismissed, or were already prompted max_prompts times are left
  # alone.
  #
  # An install with `config.prompt_events = false` keeps no prompt history, so
  # there is nothing to throttle with and this is a no-op — that app opens the
  # widget on a click instead.
  module PromptHelper
    def testimonial_prompt!(kind = :testimonial)
      flash[:testimonials_prompt] = kind.to_s
    end
  end
end
