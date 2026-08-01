# frozen_string_literal: true

namespace :testimonials do
  desc 'Create or refresh testimonials demo data'
  task seed_demo: :environment do
    result = Testimonials::Seeds.load!
    puts "Seeded #{result[:testimonials].size} testimonials, " \
         "#{result[:nps_responses].size} NPS responses, and " \
         "#{result[:prompt_events].size} prompt events."
  end
end
