# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReviewEngine::Widget do
  def parsed_config(snippet)
    json = snippet[%r{<script type="application/json" data-review-engine-config>(.+?)</script>}m, 1]
    JSON.parse(json.gsub('<\/', '</'))
  end

  it 'renders a JSON config block and a same-origin src script (never inline code)' do
    snippet = described_class.snippet(locale: :en, authenticated: false)
    expect(snippet).to include('data-review-engine-config')
    expect(snippet).to include('<script src="/reviews/widget.js" defer')
    expect(snippet).to include('data-review-engine-widget')
    # Inline code would be refused on Turbo body swaps under a nonce CSP.
    expect(snippet).not_to include('review_engine widget')
  end

  it 'stamps a nonce on the code script only' do
    snippet = described_class.snippet(locale: :en, authenticated: false, nonce: 'abc123')
    expect(snippet).to include('defer nonce="abc123" data-review-engine-widget')
    expect(snippet.scan('nonce=').size).to eq(1)
  end

  it 'carries endpoints, questions, and localized labels' do
    config = parsed_config(described_class.snippet(locale: :en, authenticated: true))
    expect(config['endpoints']['testimonials']).to eq('/reviews/testimonials')
    expect(config['endpoints']['nps']).to eq('/reviews/nps')
    expect(config['questions'].size).to eq(3)
    expect(config['authenticated']).to be(true)
    expect(config['labels']['enjoying']).to include('Dummy')
    expect(config['video']['maxSeconds']).to eq(120)
  end

  it 'localizes labels for the requested locale' do
    config = I18n.with_locale(:fr) { parsed_config(described_class.snippet(locale: :fr, authenticated: false)) }
    expect(config['labels']['notNow']).to eq('Pas maintenant')
  end

  it 'passes auto_open through' do
    config = parsed_config(described_class.snippet(locale: :en, authenticated: false, auto_open: 'testimonial'))
    expect(config['autoOpen']).to eq('testimonial')
  end

  it 'marks RTL locales' do
    config = parsed_config(described_class.snippet(locale: :'ar-EG', authenticated: false))
    expect(config['rtl']).to be(true)
  end

  it 'escapes closing tags so config values cannot break out of the script block' do
    ReviewEngine.config.questions = ['</script><script>alert(1)</script>']
    snippet = described_class.snippet(locale: :en, authenticated: false)
    expect(snippet).not_to include('</script><script>alert(1)')
  end
end
