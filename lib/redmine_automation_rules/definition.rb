module RedmineAutomationRules
  # Shared class-level DSL for condition and action types: a registry key, a
  # label and an ordered list of parameters, each rendered by the rule form as
  # a widget. The same description is served as JSON to the form's JavaScript.
  #
  #   param 'value', widget: 'select', options: 'status'
  #   param 'days',  widget: 'number', when: { 'operator' => %w[within_days] }
  #
  # +widget+ is one of select, text, textarea, number, date, checkbox or
  # custom_field_value. +options+ is a key of Schema#options (tracker, status,
  # user, ...) or an inline array of [label, value] pairs. +when+ shows the
  # parameter only when another parameter of the row has one of the values.
  module Definition
    module ClassMethods
      include Redmine::I18n

      def key
        name.demodulize.underscore
      end

      def label
        l("#{i18n_prefix}_#{key}")
      end

      def param(name, widget:, options: nil, label: nil, only_if: nil, required: false, placeholder: nil)
        param_definitions << { 'name' => name.to_s, 'widget' => widget.to_s, 'options' => options, 'label' => label,
                               'when' => only_if&.transform_keys(&:to_s)&.transform_values { |v| Array(v).map(&:to_s) },
                               'required' => required, 'placeholder' => placeholder }.compact
      end

      def param_definitions
        @param_definitions ||= []
      end

      def params
        param_definitions
      end

      def schema(_project = nil)
        {
          'key' => key,
          'label' => label,
          'params' => params.map do |definition|
            definition.merge(
              'label' => definition['label'] ? l(definition['label']) : nil,
              'placeholder' => definition['placeholder'] ? l(definition['placeholder']) : nil,
              'options' => if definition['options'].is_a?(Array)
                             definition['options'].map do |lbl, val|
                               [lbl.is_a?(Symbol) ? l(lbl) : lbl, val.to_s]
                             end
                           else
                             definition['options']
                           end
            ).compact
          end
        }
      end

      # Which parameter definitions are active for the given row values.
      def active_params(row)
        params.select do |definition|
          (definition['when'] || {}).all? { |name, values| values.include?(row[name].to_s) }
        end
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    include Redmine::I18n

    attr_reader :params

    def initialize(params = {})
      @params = (params || {}).to_h.stringify_keys
    end

    def key
      self.class.key
    end

    def label
      self.class.label
    end

    def param(name)
      value = params[name.to_s]
      value.is_a?(String) ? value.strip : value
    end

    def param?(name)
      value = param(name)
      value.is_a?(Array) ? value.any?(&:present?) : value.present?
    end

    # Error messages (already localized) for a stored row; empty when valid.
    def validate
      self.class.active_params(params).filter_map do |definition|
        next unless definition['required'] && !param?(definition['name'])

        l(:automation_rules_error_param_blank, param: definition['label'] ? l(definition['label']) : definition['name'])
      end
    end

    def valid?
      validate.empty?
    end

    # Name of a record referenced by id, or the raw value when not found.
    def name_of(klass, id)
      return '?' if id.blank?

      klass.find_by(id: id)&.to_s || "##{id}"
    end

    def to_h
      params
    end
  end
end
