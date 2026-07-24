# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReviewEngine::NpsResponse do
  it 'validates the score range' do
    expect(described_class.new(score: 0)).to be_valid
    expect(described_class.new(score: 10)).to be_valid
    expect(described_class.new(score: 11)).not_to be_valid
    expect(described_class.new(score: nil)).not_to be_valid
  end

  it 'classifies promoters, passives, and detractors' do
    expect(described_class.new(score: 9)).to be_promoter
    expect(described_class.new(score: 8)).to be_passive
    expect(described_class.new(score: 7)).to be_passive
    expect(described_class.new(score: 6)).to be_detractor
  end

  describe '.score' do
    it 'is nil with no responses' do
      expect(described_class.score).to be_nil
    end

    it 'computes %promoters minus %detractors' do
      [10, 9, 8, 3].each { |s| described_class.create!(score: s) }
      # 2 promoters, 1 passive, 1 detractor of 4: 50 - 25 = 25
      expect(described_class.score).to eq(25)
    end
  end
end
