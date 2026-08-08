# frozen_string_literal: true

require 'stringio'
require_relative 'demo_video'

module Testimonials
  module Seeds
    TESTIMONIALS = [
      {
        seed_id: 'approved-founder',
        kind: 'text',
        body: 'We call testimonial_prompt! after a customer completes onboarding, when the value is still ' \
              'fresh. The prompt feels earned, and the quotes are much more specific than the ones we used ' \
              'to request by email.',
        best_line: 'Ask after a real success moment and the quotes become specific.',
        rating: 5,
        status: 'approved',
        featured: true,
        consent_given: true,
        consent_text: 'You can use my testimonial publicly in your marketing and sales.',
        name: 'Maya Chen',
        email: 'maya@example.com',
        title_company: 'Founder, Demo CRM',
        source: 'widget',
        page_url: '/onboarding/complete',
        locale: 'en'
      },
      {
        seed_id: 'pending-operator',
        kind: 'text',
        body: 'This response has public consent, but it is still pending. That separation gives our team a ' \
              'chance to verify the quote, choose a best line, and approve it before anything appears on the ' \
              'wall of love.',
        rating: 4,
        status: 'pending',
        featured: false,
        consent_given: true,
        consent_text: 'You can use my testimonial publicly in your marketing and sales.',
        name: 'Jon Bell',
        email: 'jon@example.com',
        title_company: 'Operations Lead, Example Co',
        source: 'nps',
        page_url: '/reports',
        locale: 'en'
      },
      {
        seed_id: 'private-archive',
        kind: 'text',
        body: 'I am happy for the team to keep this feedback internally, but I did not consent to public ' \
              'use. Archiving it keeps the learning without making it publishable.',
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
        body: 'The attached clip is intentionally generic demo media. It proves the upload, review, and ' \
              'protected playback path; replace it with a real customer recording before using this record ' \
              'anywhere public.',
        best_line: 'Video follows the same consent and approval workflow as text.',
        rating: 5,
        status: 'approved',
        featured: true,
        consent_given: true,
        consent_text: 'You can use my testimonial publicly in your marketing and sales.',
        name: 'Alex Rivera',
        email: 'alex@example.com',
        title_company: 'Head of Product, Demo Video Co',
        source: 'page',
        page_url: '/testimonials/new',
        locale: 'en'
      }
    ].freeze

    NPS_RESPONSES = [
      { seed_id: 'promoter', score: 10,
        comment: 'A 9 or 10 is a promoter. One promoter contributes positively to the NPS score.' },
      { seed_id: 'passive', score: 8,
        comment: 'A 7 or 8 is passive. Keep the feedback, but this response does not move the NPS score.' },
      { seed_id: 'detractor', score: 4,
        comment: 'A score from 0 to 6 is a detractor. With one promoter and one detractor, this demo board ' \
                 'totals 0 NPS.' }
    ].freeze

    PROMPT_EVENTS = [
      { kind: 'testimonial', action: 'shown', visitor_token: 'testimonials-demo-visitor' },
      { kind: 'testimonial', action: 'dismissed', visitor_token: 'testimonials-demo-visitor' },
      { kind: 'nps', action: 'submitted', author_id: 'testimonials-demo:nps-promoter' }
    ].freeze

    def self.load!(tenant: nil)
      {
        testimonials: load_testimonials!(tenant: tenant),
        # An install run with --skip-nps or --skip-prompt-events has no table
        # to seed into.
        nps_responses: (Testimonials.config.nps ? load_nps_responses!(tenant: tenant) : []),
        prompt_events: (Testimonials.config.prompt_events ? load_prompt_events!(tenant: tenant) : [])
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
