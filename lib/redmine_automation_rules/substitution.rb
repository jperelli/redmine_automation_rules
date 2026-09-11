module RedmineAutomationRules
  # Replaces {{variables}} in note, email and template texts.
  #
  #   {{issue.id}} {{issue.subject}} {{issue.description}} {{issue.tracker}}
  #   {{issue.status}} {{issue.priority}} {{issue.author}} {{issue.assigned_to}}
  #   {{issue.category}} {{issue.fixed_version}} {{issue.start_date}}
  #   {{issue.due_date}} {{issue.done_ratio}} {{issue.estimated_hours}}
  #   {{issue.spent_hours}} {{issue.url}} {{issue.cf.Field name}} {{issue.Field name}}
  #   {{project.name}} {{project.identifier}} {{user}} {{rule.name}} {{date}} {{time}}
  #
  # Unknown variables are left in place.
  module Substitution
    VARIABLE = /\{\{\s*([\w.\- ]+?)\s*\}\}/

    ISSUE_ATTRIBUTES = %w[id subject description tracker status priority author assigned_to category
                          fixed_version start_date due_date done_ratio estimated_hours spent_hours url].freeze

    module_function

    def apply(text, issue, context = {})
      return text if text.blank?

      text.to_s.gsub(VARIABLE) do |match|
        value = resolve(Regexp.last_match(1), issue, context)
        value.nil? ? match : value.to_s
      end
    end

    def resolve(name, issue, context)
      scope, rest = name.split('.', 2)
      case scope
      when 'issue' then issue_value(issue, rest)
      when 'project' then project_value(issue.project, rest)
      when 'user' then rest.nil? ? (context[:user] || User.current).name : nil
      when 'rule' then rest == 'name' ? context[:rule]&.name : nil
      when 'date' then rest.nil? ? User.current.today.to_s : nil
      when 'time' then rest.nil? ? Time.current.strftime('%H:%M') : nil
      end
    end

    def issue_value(issue, attribute)
      return nil if attribute.blank?

      case attribute
      when 'url'
        Rails.application.routes.url_helpers.issue_url(issue, Mailer.default_url_options)
      when 'assigned_to', 'author', 'tracker', 'status', 'priority', 'category', 'fixed_version'
        issue.public_send(attribute)&.to_s
      when *ISSUE_ATTRIBUTES
        issue.public_send(attribute).to_s
      else
        custom_field_value(issue, attribute.delete_prefix('cf.'))
      end
    end

    def project_value(project, attribute)
      case attribute
      when 'name', nil then project.name
      when 'identifier' then project.identifier
      end
    end

    def custom_field_value(issue, name)
      cf_value = issue.custom_field_values.find { |v| v.custom_field.name.casecmp?(name) }
      return nil unless cf_value

      format_value = cf_value.custom_field.format.formatted_custom_value(nil, cf_value, false)
      format_value.to_s
    rescue StandardError
      cf_value.value.to_s
    end
  end
end
