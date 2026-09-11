module RedmineAutomationRules
  # Describes what the rule form can offer for a project: trigger types,
  # condition and action types (with their parameters) and the option lists
  # the select widgets are filled with. Served as JSON by
  # AutomationRulesController#fields and rendered by automation_rules.js.
  module Schema
    extend Redmine::I18n

    ISSUE_FIELDS = %w[tracker_id status_id priority_id assigned_to_id author_id category_id fixed_version_id
                      subject description start_date due_date done_ratio estimated_hours is_private parent_id].freeze

    module_function

    def for_project(project = nil)
      {
        'triggers' => AutomationRule.trigger_type_options.map { |lbl, val| [lbl, val] },
        'update_changes' => AutomationRule.update_change_options,
        'interval_units' => AutomationRule.interval_unit_options,
        'conditions' => Conditions.schema(project),
        'actions' => Actions.schema(project),
        'options' => options(project),
        'custom_fields' => custom_fields(project),
        'labels' => {
          'select' => "--- #{l(:actionview_instancetag_blank_option)} ---",
          'button_delete' => l(:button_delete),
          'button_sort' => l(:button_sort)
        }
      }
    end

    # Option lists keyed by the +options+ name used in param definitions.
    def options(project = nil)
      {
        'tracker' => pairs(trackers(project)),
        'status' => pairs(IssueStatus.sorted),
        'priority' => pairs(IssuePriority.active),
        'user' => users(project),
        'group' => pairs(Group.givable.sorted),
        'role' => pairs(Role.givable.sorted),
        'category' => pairs(project ? project.issue_categories : IssueCategory.none),
        'version' => pairs(project ? project.shared_versions.open : Version.none),
        'field' => ISSUE_FIELDS.map { |field| [field_label(field), field] },
        'custom_field' => pairs(custom_field_records(project)),
        'boolean' => [[l(:general_text_Yes), '1'], [l(:general_text_No), '0']],
        'relation_type' => IssueRelation::TYPES.map { |type, opts| [l(opts[:name]), type] }
      }
    end

    def custom_fields(project = nil)
      custom_field_records(project).map do |cf|
        {
          'id' => cf.id.to_s,
          'name' => cf.name,
          'format' => cf.field_format,
          'multiple' => cf.multiple?,
          'possible_values' => custom_field_values(cf, project)
        }
      end
    end

    def field_label(field)
      return l("field_#{field.sub(/_id\z/, '')}") if ISSUE_FIELDS.include?(field.to_s)

      cf = CustomField.find_by(id: field.to_s.delete_prefix('cf_'))
      cf&.name || field.to_s
    end

    def trackers(project)
      project ? project.trackers : Tracker.sorted
    end

    def users(project)
      scope = project ? project.users : User.active
      scope.sorted.map { |user| [user.name, user.id.to_s] }
    end

    def custom_field_records(project)
      scope = IssueCustomField.sorted
      if project
        scope.select { |cf| cf.is_for_all? || cf.projects.include?(project) }
      else
        scope.to_a
      end
    end

    def custom_field_values(custom_field, project)
      case custom_field.field_format
      when 'list' then custom_field.possible_values.map { |v| [v, v] }
      when 'bool' then [[l(:general_text_Yes), '1'], [l(:general_text_No), '0']]
      when 'user', 'version'
        return [] unless project

        custom_field.format.possible_custom_value_options(CustomFieldValue.new(custom_field: custom_field,
                                                                               customized: Issue.new(project: project)))
                    .map do |lbl, val|
          [lbl, val.to_s]
        end
      when 'enumeration' then custom_field.enumerations.active.map { |e| [e.name, e.id.to_s] }
      else []
      end
    end

    def pairs(records)
      records.map { |record| [record.name, record.id.to_s] }
    end
  end
end
