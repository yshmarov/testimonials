# frozen_string_literal: true

require 'rails_helper'
require 'yaml'

RSpec.describe 'locale files' do
  locales_dir = File.expand_path('../../config/locales', __dir__)
  files = Dir[File.join(locales_dir, '*.yml')]

  def flatten_keys(hash, prefix = [])
    hash.flat_map do |key, value|
      value.is_a?(Hash) ? flatten_keys(value, prefix + [key]) : [(prefix + [key]).join('.')]
    end
  end

  reference = YAML.load_file(File.join(locales_dir, 'review_engine.en.yml')).values.first
  reference_keys = nil

  it 'ships a useful number of languages' do
    expect(files.size).to be >= 26
  end

  files.each do |file|
    locale = File.basename(file, '.yml').sub('review_engine.', '')

    describe locale do
      data = YAML.load_file(file)

      it 'is keyed by its own locale code' do
        expect(data.keys).to eq([locale])
      end

      it 'has exactly the same keys as en' do
        reference_keys ||= flatten_keys(reference).sort
        expect(flatten_keys(data.values.first).sort).to eq(reference_keys)
      end

      it 'ships three guiding questions that mention the app' do
        questions = data.values.first['review_engine']['questions']
        expect(questions.size).to eq(3)
        expect(questions.join).to include('%{app}')
      end
    end
  end
end
