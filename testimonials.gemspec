# frozen_string_literal: true

require_relative 'lib/testimonials/version'

Gem::Specification.new do |spec|
  spec.name = 'testimonials'
  spec.version = Testimonials::VERSION
  spec.authors = ['Yaroslav Shmarov']
  spec.email = ['yaroslav.shmarov@clickfunnels.com']

  spec.summary = 'Testimonials, reviews and NPS for Rails: in-app collection widget, ' \
                 'public collection page, triage dashboard, and a read API.'
  spec.description = <<~DESC
    A mountable Rails engine that collects customer testimonials — text and
    video — and NPS scores from inside your app. An iOS-style "Enjoying this
    app?" widget prompts users at moments your code chooses (with built-in
    throttling), a public page collects testimonials from a shareable link,
    and a minimal dashboard lets you approve, feature, and excerpt what comes
    in. Display is headless: approved testimonials are served through your
    models or an optional JSON API, and you render them with your own markup.
    Framework-agnostic: no CSS or JS framework required.
  DESC
  spec.homepage = 'https://github.com/yshmarov/testimonials'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'app/**/*',
    'config/**/*',
    'lib/**/*',
    'MIT-LICENSE',
    'Rakefile',
    'README.md',
    'CHANGELOG.md',
    # Ships so an agent working in a host app can read the install guide
    # straight out of the bundle: `cat "$(bundle show testimonials)/AGENTS.md"`.
    'AGENTS.md',
    'examples/**/*'
  ]
  spec.require_paths = ['lib']

  spec.add_dependency 'rails', '>= 7.1'
end
