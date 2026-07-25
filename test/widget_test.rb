# frozen_string_literal: true

require 'test_helper'

class WidgetTest < ActiveSupport::TestCase
  def parsed_config(snippet)
    json = snippet[%r{<script type="application/json" data-testimonials-config>(.+?)</script>}m, 1]
    JSON.parse(json.gsub('<\/', '</'))
  end

  test 'renders a JSON config block and a same-origin src script, never inline code' do
    snippet = Testimonials::Widget.snippet(locale: :en, authenticated: false)
    assert_includes snippet, 'data-testimonials-config'
    assert_includes snippet, '<script src="/testimonials/widget.js?v='
    assert_includes snippet, 'data-testimonials-widget'
    # Inline code would be refused on Turbo body swaps under a nonce CSP.
    refute_includes snippet, 'testimonials widget'
  end

  test 'stamps a nonce on the code script only' do
    snippet = Testimonials::Widget.snippet(locale: :en, authenticated: false, nonce: 'abc123')
    assert_includes snippet, 'defer nonce="abc123" data-testimonials-widget'
    assert_equal 1, snippet.scan('nonce=').size
  end

  test 'carries endpoints, questions, and localized labels' do
    config = parsed_config(Testimonials::Widget.snippet(locale: :en, authenticated: true))
    assert_equal '/testimonials', config['endpoints']['testimonials']
    assert_equal '/testimonials/nps', config['endpoints']['nps']
    assert_equal 3, config['questions'].size
    assert config['authenticated']
    assert_includes config['labels']['enjoying'], 'Dummy'
    assert_equal 120, config['video']['maxSeconds']
  end

  test 'localizes labels for the requested locale' do
    config = I18n.with_locale(:fr) do
      parsed_config(Testimonials::Widget.snippet(locale: :fr, authenticated: false))
    end
    assert_equal 'Pas maintenant', config['labels']['notNow']
  end

  test 'passes auto_open through' do
    snippet = Testimonials::Widget.snippet(locale: :en, authenticated: false, auto_open: 'testimonial')
    assert_equal 'testimonial', parsed_config(snippet)['autoOpen']
  end

  test 'marks RTL locales' do
    assert parsed_config(Testimonials::Widget.snippet(locale: :'ar-EG', authenticated: false))['rtl']
  end

  test 'escapes closing tags so config values cannot break out of the script block' do
    Testimonials.config.questions = ['</script><script>alert(1)</script>']
    snippet = Testimonials::Widget.snippet(locale: :en, authenticated: false)
    refute_includes snippet, '</script><script>alert(1)'
  end

  test 'serializes an existing testimonial with rating, body, consent, and video url' do
    testimonial = Testimonials::Testimonial.create!(kind: 'text', body: 'Mine', rating: 4,
                                                    author_id: '42', consent_given: true)
    snippet = Testimonials::Widget.snippet(locale: :en, authenticated: true, existing: testimonial)
    existing = parsed_config(snippet)['existing']
    assert_equal({ 'rating' => 4, 'body' => 'Mine', 'consent' => true,
                   'videoUrl' => nil, 'posterUrl' => nil }, existing)
  end
end
