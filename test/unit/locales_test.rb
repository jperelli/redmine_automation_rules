require "#{File.dirname(__FILE__)}/../test_helper"

class LocalesTest < ActiveSupport::TestCase
  LOCALE_DIR = File.expand_path('../../config/locales', __dir__)
  REFERENCE = 'en'.freeze

  def test_every_locale_defines_the_same_keys_as_english
    expected = load_locale(REFERENCE).keys.sort

    each_translation_locale do |locale, translations|
      assert_equal expected, translations.keys.sort,
                   "#{locale}.yml does not define the same keys as #{REFERENCE}.yml"
    end
  end

  # Interpolations (%{name}), note variables ({{issue.subject}}) and date macros
  # (**DATE**) must survive translation.
  def test_every_locale_keeps_interpolations_and_macros
    reference = load_locale(REFERENCE)

    each_translation_locale do |locale, translations|
      translations.each do |key, value|
        assert_equal tokens(reference[key]), tokens(value),
                     "#{locale}.yml: #{key} does not use the same variables as #{REFERENCE}.yml"
      end
    end
  end

  def test_every_locale_loads_in_i18n
    each_translation_locale do |locale, _translations|
      assert_equal load_locale(locale)['label_automation_rules'],
                   I18n.t(:label_automation_rules, locale: locale, raise: true)
    end
  end

  private

  def each_translation_locale
    locales = Dir.glob("#{LOCALE_DIR}/*.yml").map { |path| File.basename(path, '.yml') } - [REFERENCE]
    assert_not_empty locales
    locales.each { |locale| yield locale, load_locale(locale) }
  end

  def load_locale(locale)
    YAML.safe_load_file("#{LOCALE_DIR}/#{locale}.yml").fetch(locale)
  end

  def tokens(value)
    values = value.is_a?(Hash) ? value.values : [value]
    values.flat_map { |v| v.to_s.scan(/%\{\w+\}|\{\{[\w.]+\}\}|\*\*[A-Z_]+\*\*/) }.uniq.sort
  end
end
