# frozen_string_literal: true

require 'test_helper'
require 'yaml'

class LocalesTest < ActiveSupport::TestCase
  LOCALES_DIR = File.expand_path('../config/locales', __dir__)
  FILES = Dir[File.join(LOCALES_DIR, '*.yml')]

  def self.flatten_keys(hash, prefix = [])
    hash.flat_map do |key, value|
      value.is_a?(Hash) ? flatten_keys(value, prefix + [key]) : [(prefix + [key]).join('.')]
    end
  end

  REFERENCE_KEYS =
    flatten_keys(YAML.load_file(File.join(LOCALES_DIR, 'testimonials.en.yml')).values.first).sort

  test 'ships a useful number of languages' do
    assert_operator FILES.size, :>=, 26
  end

  FILES.each do |file|
    locale = File.basename(file, '.yml').sub('testimonials.', '')

    define_method("test_#{locale.tr('-', '_')}_locale") do
      data = YAML.load_file(file)

      assert_equal [locale], data.keys, "#{file} must be keyed by its own locale code"
      assert_equal REFERENCE_KEYS, self.class.flatten_keys(data.values.first).sort,
                   "#{file} must have exactly the same keys as en"

      questions = data.values.first['testimonials']['questions']
      assert_equal 3, questions.size, "#{file} must ship three guiding questions"
      assert_includes questions.join, '%{app}', "#{file} questions must mention the app"
      assert_equal 'Testimonials', data.values.first['testimonials']['dashboard']['title'],
                   "#{file} must keep the admin title branded"
    end
  end
end
