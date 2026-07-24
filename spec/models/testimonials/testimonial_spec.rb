# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Testimonials::Testimonial do
  it 'requires a body for text testimonials' do
    expect(described_class.new(kind: 'text')).not_to be_valid
    expect(described_class.new(kind: 'text', body: 'Great!')).to be_valid
  end

  it 'allows a video testimonial without a body' do
    expect(described_class.new(kind: 'video')).to be_valid
  end

  it 'validates rating range but allows nil' do
    expect(described_class.new(kind: 'video', rating: nil)).to be_valid
    expect(described_class.new(kind: 'video', rating: 5)).to be_valid
    expect(described_class.new(kind: 'video', rating: 6)).not_to be_valid
    expect(described_class.new(kind: 'video', rating: 0)).not_to be_valid
  end

  describe '.publishable' do
    it 'requires approval AND consent' do
      approved_consented = described_class.create!(kind: 'text', body: 'a', status: 'approved', consent_given: true)
      described_class.create!(kind: 'text', body: 'b', status: 'approved', consent_given: false)
      described_class.create!(kind: 'text', body: 'c', status: 'pending', consent_given: true)

      expect(described_class.publishable).to eq([approved_consented])
    end
  end

  describe '#quote' do
    it 'prefers the excerpt, falls back to the body' do
      testimonial = described_class.new(body: 'Long story.', excerpt: 'Story.')
      expect(testimonial.quote).to eq('Story.')
      testimonial.excerpt = nil
      expect(testimonial.quote).to eq('Long story.')
    end
  end

  describe '#display_name' do
    it 'uses the name, then the author id, then nil' do
      expect(described_class.new(name: 'Ada').display_name).to eq('Ada')
      expect(described_class.new(author_id: '42').display_name).to eq('#42')
      expect(described_class.new.display_name).to be_nil
    end
  end
end
