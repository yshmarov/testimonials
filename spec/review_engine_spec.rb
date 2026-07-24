# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReviewEngine do
  describe '.questions' do
    it 'defaults to the built-in localized questions with the app name filled in' do
      questions = described_class.questions
      expect(questions.size).to eq(3)
      expect(questions.join).to include(described_class.app_name)
      expect(questions.join).not_to include('%{app}')
    end

    it 'follows the current locale' do
      french = I18n.with_locale(:fr) { described_class.questions }
      expect(french.first).to include('Qui êtes-vous')
    end

    it 'accepts literal strings' do
      described_class.config.questions = ['One?', 'Two about %{app}?']
      expect(described_class.questions).to eq(['One?', "Two about #{described_class.app_name}?"])
    end

    it 'accepts a lambda for host-side i18n' do
      described_class.config.questions = -> { ['From the host'] }
      expect(described_class.questions).to eq(['From the host'])
    end

    it 'hides the section with an empty array' do
      described_class.config.questions = []
      expect(described_class.questions).to eq([])
    end
  end

  describe '.app_name' do
    it 'defaults to the Rails application name' do
      expect(described_class.app_name).to eq('Dummy')
    end

    it 'prefers the configured name' do
      described_class.config.app_name = 'SupeRails'
      expect(described_class.app_name).to eq('SupeRails')
    end
  end

  describe '.consent_text' do
    it 'has a localized default' do
      expect(described_class.consent_text).to include('permission')
    end

    it 'prefers the configured text' do
      described_class.config.consent_text = 'Custom consent.'
      expect(described_class.consent_text).to eq('Custom consent.')
    end
  end

  it 'gates enabled? and admin? through the config lambdas' do
    request = double('request')
    expect(described_class.enabled?(request)).to be(true)
    expect(described_class.admin?(request)).to be(false) # test env is not development

    described_class.config.authorize_admin = ->(_r) { true }
    expect(described_class.admin?(request)).to be(true)
  end
end
