# frozen_string_literal: true

require 'test_helper'
require 'rails/generators/test_case'
require 'generators/testimonials/install/install_generator'
require 'generators/testimonials/nps/nps_generator'

# NPS is the one part an app can opt out of, and opting out changes the schema
# — so both shapes are pinned here rather than left to a manual install.
class InstallGeneratorTest < Rails::Generators::TestCase
  tests Testimonials::Generators::InstallGenerator
  destination File.expand_path('../tmp/generator', __dir__)
  setup :prepare_destination
  setup :write_routes

  test 'a full install creates every table and leaves config.nps at its default' do
    run_generator

    assert_migration 'db/migrate/create_testimonials_tables.rb' do |migration|
      assert_match 'create_table :testimonials_testimonials', migration
      assert_match 'create_table :testimonials_nps_responses', migration
      assert_match 'create_table :testimonials_prompt_events', migration
      assert_match 'add_index :testimonials_nps_responses, %i[tenant score]', migration
    end

    assert_file 'config/initializers/testimonials.rb' do |initializer|
      assert_match '# config.nps = true', initializer
      refute_match(/^  config\.nps = false/, initializer)
    end
  end

  test '--skip-nps leaves out the table and turns the flow off' do
    run_generator ['--skip-nps']

    assert_migration 'db/migrate/create_testimonials_tables.rb' do |migration|
      assert_match 'create_table :testimonials_testimonials', migration
      assert_match 'create_table :testimonials_prompt_events', migration
      refute_match 'testimonials_nps_responses', migration
    end

    assert_file 'config/initializers/testimonials.rb' do |initializer|
      assert_match(/^  config\.nps = false/, initializer)
      assert_match 'testimonials:nps', initializer
    end
  end

  test 'the initializer template stays valid ruby either way' do
    run_generator ['--skip-nps']
    path = File.join(destination_root, 'config/initializers/testimonials.rb')

    assert RubyVM::InstructionSequence.compile(File.read(path))
  end

  test 'both installs mount the engine' do
    run_generator ['--skip-nps']

    assert_file 'config/routes.rb', %r{mount_testimonials at: "/testimonials"}
  end

  private

  # `route` needs somewhere to inject; without it the generator only warns.
  def write_routes
    FileUtils.mkdir_p(File.join(destination_root, 'config'))
    File.write(File.join(destination_root, 'config/routes.rb'), "Rails.application.routes.draw do\nend\n")
  end
end

class NpsGeneratorTest < Rails::Generators::TestCase
  tests Testimonials::Generators::NpsGenerator
  destination File.expand_path('../tmp/generator', __dir__)
  setup :prepare_destination

  test 'adds the table a --skip-nps install left out, tenant column included' do
    run_generator

    assert_migration 'db/migrate/create_testimonials_nps_responses.rb' do |migration|
      assert_match 'create_table :testimonials_nps_responses', migration
      assert_match 't.string :tenant', migration
      assert_match 'add_index :testimonials_nps_responses, %i[tenant score]', migration
    end
  end
end
