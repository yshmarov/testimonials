# frozen_string_literal: true

require 'stringio'
require_relative 'demo_video'

module Testimonials
  module Seeds
    TESTIMONIALS = [
      {
        seed_id: 'approved-founder',
        kind: 'text',
        body: 'We added the widget after onboarding and collected better customer quotes in the first week.',
        best_line: 'Collected better customer quotes in the first week.',
        rating: 5,
        status: 'approved',
        featured: true,
        consent_given: true,
        consent_text: 'You can use my testimonial publicly in your marketing and sales.',
        name: 'Maya Chen',
        email: 'maya@example.com',
        title_company: 'Founder, DemoCRM',
        source: 'widget',
        page_url: '/onboarding/complete',
        locale: 'en'
      },
      {
        seed_id: 'pending-operator',
        kind: 'text',
        body: 'The NPS prompt felt lightweight and did not interrupt the workflow.',
        rating: 4,
        status: 'pending',
        featured: false,
        consent_given: true,
        consent_text: 'You can use my testimonial publicly in your marketing and sales.',
        name: 'Jon Bell',
        email: 'jon@example.com',
        title_company: 'Operations Lead, ExampleCo',
        source: 'nps',
        page_url: '/reports',
        locale: 'en'
      },
      {
        seed_id: 'private-archive',
        kind: 'text',
        body: 'Useful for our internal rollout notes, but please do not publish my name.',
        rating: 3,
        status: 'archived',
        featured: false,
        consent_given: false,
        consent_text: 'You can only use my testimonial privately in your marketing and sales.',
        name: 'Priya Rao',
        email: 'priya@example.com',
        title_company: 'Customer Success, SampleOps',
        source: 'page',
        page_url: '/testimonials/new',
        locale: 'en'
      },
      {
        seed_id: 'approved-video',
        kind: 'video',
        body: 'Short demo video testimonial with a real MP4 attachment.',
        best_line: 'A real video testimonial is ready to review.',
        rating: 5,
        status: 'approved',
        featured: true,
        consent_given: true,
        consent_text: 'You can use my testimonial publicly in your marketing and sales.',
        name: 'Alex Rivera',
        email: 'alex@example.com',
        title_company: 'Head of Product, VideoDemo',
        source: 'page',
        page_url: '/testimonials/new',
        locale: 'en'
      }
    ].freeze

    NPS_RESPONSES = [
      { seed_id: 'promoter', score: 10,
        comment: 'Fast to install and easy to trust because the data stays in our app.' },
      { seed_id: 'passive', score: 8, comment: 'The flow is useful, but I would like more display examples.' },
      { seed_id: 'detractor', score: 4, comment: 'I was not sure when the prompt would appear again.' }
    ].freeze

    PROMPT_EVENTS = [
      { kind: 'testimonial', action: 'shown', visitor_token: 'testimonials-demo-visitor' },
      { kind: 'testimonial', action: 'dismissed', visitor_token: 'testimonials-demo-visitor' },
      { kind: 'nps', action: 'submitted', author_id: 'testimonials-demo:nps-promoter' }
    ].freeze

    def self.load!(tenant: nil)
      {
        testimonials: load_testimonials!(tenant: tenant),
        nps_responses: load_nps_responses!(tenant: tenant),
        prompt_events: load_prompt_events!(tenant: tenant)
      }
    end

    def self.load_testimonials!(tenant:)
      TESTIMONIALS.map do |attributes|
        seed_id = attributes.fetch(:seed_id)
        testimonial = Testimonials::Testimonial.find_or_initialize_by(
          author_id: "testimonials-demo:#{seed_id}",
          tenant: tenant.presence
        )
        testimonial.assign_attributes(
          attributes.except(:seed_id).merge(tenant: tenant.presence, user_agent: 'testimonials demo seed')
        )
        testimonial.save!
        attach_demo_video!(testimonial) if seed_id == 'approved-video'
        testimonial
      end
    end
    private_class_method :load_testimonials!

    def self.load_nps_responses!(tenant:)
      NPS_RESPONSES.map do |attributes|
        seed_id = attributes.fetch(:seed_id)
        response = Testimonials::NpsResponse.find_or_initialize_by(
          author_id: "testimonials-demo:nps-#{seed_id}",
          tenant: tenant.presence
        )
        response.assign_attributes(
          attributes.except(:seed_id).merge(
            name: 'Demo Respondent',
            email: "#{seed_id}@example.com",
            page_url: '/dashboard',
            user_agent: 'testimonials demo seed',
            locale: 'en',
            tenant: tenant.presence
          )
        )
        response.save!
        response
      end
    end
    private_class_method :load_nps_responses!

    def self.load_prompt_events!(tenant:)
      PROMPT_EVENTS.map do |attributes|
        event = Testimonials::PromptEvent.find_or_initialize_by(
          attributes.slice(:kind, :action, :author_id, :visitor_token).merge(tenant: tenant.presence)
        )
        event.save!
        event
      end
    end
    private_class_method :load_prompt_events!

    def self.attach_demo_video!(testimonial)
      return unless Testimonials.config.video_enabled?
      return unless testimonial.respond_to?(:video_file)
      return if testimonial.video_file.attached?

      testimonial.video_file.attach(
        io: StringIO.new(DemoVideo.bytes),
        filename: DemoVideo::FILENAME,
        content_type: DemoVideo::CONTENT_TYPE
      )
    end
    private_class_method :attach_demo_video!
  end
end
