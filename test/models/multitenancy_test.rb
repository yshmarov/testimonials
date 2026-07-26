# frozen_string_literal: true

require 'test_helper'

module Testimonials
  class MultitenancyTest < ActiveSupport::TestCase
    def text!(body:, tenant:)
      Testimonial.create!(kind: 'text', body: body, tenant: tenant)
    end

    test 'for_tenant isolates by key, and nil is the global collection' do
      global = text!(body: 'global', tenant: nil)
      acme = text!(body: 'acme', tenant: 'acme')

      assert_equal [global], Testimonial.for_tenant(nil).to_a
      assert_equal [acme], Testimonial.for_tenant('acme').to_a
      assert_equal [global], Testimonial.for_tenant('').to_a # blank normalizes to global
    end

    test 'Testimonials.tenant normalizes the resolver result to a string or nil' do
      Testimonials.config.tenant = ->(_request) { 'acme' }
      assert_equal 'acme', Testimonials.tenant(nil)

      Testimonials.config.tenant = ->(_request) { 123 }
      assert_equal '123', Testimonials.tenant(nil)

      Testimonials.config.tenant = ->(_request) { '' }
      assert_nil Testimonials.tenant(nil)

      Testimonials.config.tenant = ->(_request) {}
      assert_nil Testimonials.tenant(nil)
    end

    test 'Testimonials.for and .nps_for key a host record by its GlobalID' do
      record = Object.new
      def record.to_gid = 'gid://dummy/Org/5'

      mine = text!(body: 'mine', tenant: 'gid://dummy/Org/5')
      text!(body: 'theirs', tenant: 'gid://dummy/Org/6')
      nps = NpsResponse.create!(score: 10, tenant: 'gid://dummy/Org/5')

      assert_equal [mine], Testimonials.for(record).to_a
      assert_equal [nps], Testimonials.nps_for(record).to_a
    end

    test 'has_testimonials gives a host model scoped relations' do
      klass = Class.new do
        extend Testimonials::HasTestimonials

        has_testimonials key: ->(record) { "org-#{record.oid}" }

        attr_reader :oid

        def initialize(oid) = @oid = oid
      end

      org = klass.new(7)
      mine = text!(body: 'ours', tenant: 'org-7')
      text!(body: 'not ours', tenant: 'org-8')

      assert_includes org.testimonials, mine
      assert_equal 1, org.testimonials.count
      assert_respond_to org, :testimonials_nps
      assert_equal 0, org.testimonials_nps.count
    end

    test 'prompt-event eligibility is tracked per tenant' do
      PromptEvent.record!(kind: 'testimonial', action: 'submitted',
                          author_id: '42', tenant: 'acme')

      # Submitted in acme → not eligible there again…
      assert_not PromptEvent.eligible?(kind: 'testimonial', author_id: '42', tenant: 'acme')
      # …but a clean slate in globex.
      assert PromptEvent.eligible?(kind: 'testimonial', author_id: '42', tenant: 'globex')
    end
  end
end
