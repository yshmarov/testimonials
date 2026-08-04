# frozen_string_literal: true

require 'test_helper'
require 'rails/generators/test_case'
require 'generators/testimonials/install/install_generator'
require 'generators/testimonials/nps/nps_generator'
require 'generators/testimonials/prompt_events/prompt_events_generator'

# NPS and the prompt-history ledger are the two parts an app can opt out of,
# and opting out changes the schema — so every shape is pinned here rather than
# left to a manual install.
class InstallGeneratorTest < Rails::Generators::TestCase
  tests Testimonials::Generators::InstallGenerator
  destination File.expand_path('../tmp/generator', __dir__)
  setup :prepare_destination
  setup :write_routes

  test 'a full install creates every table and leaves both flags at their defaults' do
    run_generator

    assert_migration 'db/migrate/create_testimonials_tables.rb' do |migration|
      assert_match 'create_table :testimonials_testimonials', migration
      assert_match 'create_table :testimonials_nps_responses', migration
      assert_match 'create_table :testimonials_prompt_events', migration
      assert_match 'add_index :testimonials_nps_responses, %i[tenant score]', migration
      assert_match 'add_index :testimonials_prompt_events, %i[tenant author_id kind]', migration
    end

    assert_file 'config/initializers/testimonials.rb' do |initializer|
      assert_match '# config.nps = true', initializer
      assert_match '# config.prompt_events = true', initializer
      refute_match(/^  config\.nps = false/, initializer)
      refute_match(/^  config\.prompt_events = false/, initializer)
    end
  end

  # A uuid-keyed host has a uuid `active_storage_attachments.record_id`, so
  # bigint tables here could never hold a video or avatar — the attachment's
  # foreign key has nowhere to point. Follow the host's setting, like Rails'
  # own Active Storage / Action Text / Action Mailbox migrations do.
  test 'the tables follow the host generators primary_key_type' do
    with_primary_key_type(:uuid) do
      run_generator

      assert_migration 'db/migrate/create_testimonials_tables.rb' do |migration|
        assert_match 'create_table :testimonials_testimonials, id: :uuid', migration
        assert_match 'create_table :testimonials_nps_responses, id: :uuid', migration
        assert_match 'create_table :testimonials_prompt_events, id: :uuid', migration
      end
    end
  end

  test 'the tables take no id option when the host sets nothing' do
    with_primary_key_type(nil) do
      run_generator

      assert_migration 'db/migrate/create_testimonials_tables.rb' do |migration|
        assert_match 'create_table :testimonials_testimonials do |t|', migration
        refute_match 'id:', migration
      end
    end
  end

  # A template is expanded at generate time, so the option has to be the
  # resolved value. Emitting the helper's name would leave `id: primary_key_type`
  # in the migration, which raises NameError on db:migrate.
  test 'the generated migration carries no unresolved helper call' do
    with_primary_key_type(:uuid) do
      run_generator

      assert_migration 'db/migrate/create_testimonials_tables.rb' do |migration|
        refute_match 'primary_key_type', migration
      end
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
      refute_match(/^  config\.prompt_events = false/, initializer)
    end
  end

  test '--skip-prompt-events leaves out the ledger and turns auto-prompts off' do
    run_generator ['--skip-prompt-events']

    assert_migration 'db/migrate/create_testimonials_tables.rb' do |migration|
      assert_match 'create_table :testimonials_testimonials', migration
      assert_match 'create_table :testimonials_nps_responses', migration
      refute_match 'testimonials_prompt_events', migration
    end

    assert_file 'config/initializers/testimonials.rb' do |initializer|
      assert_match(/^  config\.prompt_events = false/, initializer)
      assert_match 'testimonials:prompt_events', initializer
      refute_match(/^  config\.nps = false/, initializer)
    end
  end

  test 'skipping both leaves the testimonials table alone' do
    run_generator %w[--skip-nps --skip-prompt-events]

    assert_migration 'db/migrate/create_testimonials_tables.rb' do |migration|
      assert_match 'create_table :testimonials_testimonials', migration
      refute_match 'testimonials_nps_responses', migration
      refute_match 'testimonials_prompt_events', migration
    end

    assert_file 'config/initializers/testimonials.rb' do |initializer|
      assert_match(/^  config\.nps = false/, initializer)
      assert_match(/^  config\.prompt_events = false/, initializer)
    end
  end

  # The migration and the initializer are both ERB with conditional bodies, so
  # every combination has to come out as compilable Ruby.
  test 'the templates stay valid ruby in every shape' do
    [[], %w[--skip-nps], %w[--skip-prompt-events], %w[--skip-nps --skip-prompt-events]].each do |flags|
      prepare_destination
      write_routes
      run_generator flags

      assert_ruby File.join(destination_root, 'config/initializers/testimonials.rb')
      assert_ruby Dir[File.join(destination_root, 'db/migrate/*_create_testimonials_tables.rb')].sole
    end
  end

  test 'every install shape mounts the engine' do
    run_generator %w[--skip-nps --skip-prompt-events]

    assert_file 'config/routes.rb', %r{mount_testimonials at: "/testimonials"}
  end

  private

  def assert_ruby(path)
    assert RubyVM::InstructionSequence.compile(File.read(path)), "#{path} is not valid Ruby"
  end

  # `route` needs somewhere to inject; without it the generator only warns.
  def write_routes
    FileUtils.mkdir_p(File.join(destination_root, 'config'))
    File.write(File.join(destination_root, 'config/routes.rb'), "Rails.application.routes.draw do\nend\n")
  end

  def with_primary_key_type(type)
    config = Rails.configuration.generators
    previous = config.options[config.orm][:primary_key_type]
    config.options[config.orm][:primary_key_type] = type
    yield
  ensure
    config.options[config.orm][:primary_key_type] = previous
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

class PromptEventsGeneratorTest < Rails::Generators::TestCase
  tests Testimonials::Generators::PromptEventsGenerator
  destination File.expand_path('../tmp/generator', __dir__)
  setup :prepare_destination

  test 'adds the ledger a --skip-prompt-events install left out, tenant column included' do
    run_generator

    assert_migration 'db/migrate/create_testimonials_prompt_events.rb' do |migration|
      assert_match 'create_table :testimonials_prompt_events', migration
      assert_match 't.string :tenant', migration
      assert_match 'add_index :testimonials_prompt_events, %i[tenant author_id kind]', migration
      assert_match 'add_index :testimonials_prompt_events, %i[tenant visitor_token kind]', migration
    end
  end
end
