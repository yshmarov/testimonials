# frozen_string_literal: true

require 'test_helper'

module Testimonials
  class StorageServiceTest < ActiveSupport::TestCase
    MODEL_PATH = Engine.root.join('app/models/testimonials/testimonial.rb').to_s

    test 'attachments use the app default service by default' do
      assert_nil Testimonial.attachment_reflections['video_file'].options[:service_name]
    end

    test 'storage_service routes every attachment to the named service' do
      Testimonials.config.storage_service = :testimonial_uploads
      reload_model!

      %w[video_file poster avatar].each do |attachment|
        assert_equal :testimonial_uploads,
                     Testimonial.attachment_reflections[attachment].options[:service_name]
      end

      testimonial = Testimonial.create!(kind: 'text', body: 'Great app!')
      testimonial.avatar.attach(io: StringIO.new('bytes'), filename: 'a.png',
                                content_type: 'image/png')
      assert_equal 'testimonial_uploads', testimonial.avatar.blob.service_name
    ensure
      Testimonials.config.storage_service = nil
      reload_model!
    end

    private

    # The service name is read when the model class loads, so exercising a
    # different value means re-evaluating the class body.
    def reload_model!
      Testimonials.send(:remove_const, :Testimonial)
      load MODEL_PATH
    end
  end
end
