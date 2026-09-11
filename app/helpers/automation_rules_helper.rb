module AutomationRulesHelper
  # Redmine 6 ships an SVG sprite and the sprite_icon helper; Redmine 5 has
  # neither, so fall back to the label with the classic CSS icon class.
  def automation_rules_sprite_icon(icon, label, icon_only: false)
    if respond_to?(:sprite_icon)
      sprite_icon(icon, label, icon_only: icon_only)
    else
      icon_only ? '' : label
    end
  end

  # Path of a rule action, for project (/projects/x/automation_rules/1/copy)
  # and global (/automation_rules/1/copy) rules alike.
  def automation_rule_path_for(rule, action = nil)
    polymorphic_path([action, rule.project, rule].compact)
  end

  def automation_rules_index_path_for(project)
    polymorphic_path([project, :automation_rules])
  end

  def automation_rules_fields_path_for(project)
    project ? fields_project_automation_rules_path(project) : fields_automation_rules_path
  end

  def automation_rule_scope_label(rule)
    if rule.global?
      l(:automation_rules_scope_global)
    elsif rule.apply_to_subprojects
      l(:automation_rules_scope_project_and_subprojects, project: rule.project.name)
    else
      rule.project.name
    end
  end

  def automation_rule_active_tag(rule)
    css = rule.active ? 'automation-rule-active' : 'automation-rule-inactive'
    content_tag(:span, rule.active ? l(:general_text_Yes) : l(:general_text_No), class: "automation-rule-state #{css}")
  end

  def automation_rule_last_run(rule)
    return content_tag(:span, l(:automation_rules_never_run), class: 'automation-rule-never') if rule.last_run_at.nil?

    content_tag(:span, format_time(rule.last_run_at), title: l(:automation_rules_runs_count, count: rule.runs_count))
  end

  def automation_rule_error_marker(rule)
    return '' if rule.last_error.blank?

    content_tag(:span, l(:automation_rules_label_error), class: 'automation-rule-error', title: rule.last_error)
  end

  def automation_rule_toggle_button(rule)
    label = rule.active ? l(:automation_rules_button_disable) : l(:automation_rules_button_enable)
    link_to automation_rules_sprite_icon(rule.active ? 'lock' : 'unlock', label),
            automation_rule_path_for(rule, :toggle),
            method: :post, class: "icon #{rule.active ? 'icon-lock' : 'icon-unlock'}"
  end

  # Human description of a stored condition/action row, tolerating unknown types.
  def automation_rule_row_description(kind, row)
    object = kind == :condition ? RedmineAutomationRules::Conditions.build(row) : RedmineAutomationRules::Actions.build(row)
    if object.nil?
      return content_tag(:span, l(:automation_rules_unknown_type, type: row['type']),
                         class: 'automation-rule-error')
    end

    object.describe
  end

  def automation_rule_result_change(field, change)
    before, after = change
    "#{field}: #{before.presence || '—'} → #{after.presence || '—'}"
  end

  # REST API representation of a rule (shared by index and show builders).
  def render_api_automation_rule(api, rule)
    api.automation_rule do
      api.id rule.id
      api.name rule.name
      api.description rule.description
      api.active rule.active
      api.position rule.position
      api.project(id: rule.project_id, name: rule.project.name) if rule.project
      api.apply_to_subprojects rule.apply_to_subprojects
      api.note_marker rule.note_marker
      api.author(id: rule.author_id, name: rule.author.name) if rule.author
      api.trigger_type rule.trigger_type
      api.trigger_options { render_api_automation_hash(api, rule.trigger_options) }
      api.sentence rule.sentence
      render_api_automation_rows(api, :conditions, rule.conditions)
      render_api_automation_rows(api, :actions, rule.actions)
      api.last_run_at rule.last_run_at
      api.next_run_at rule.next_run_at
      api.last_error rule.last_error
      api.runs_count rule.runs_count
      api.created_on rule.created_on
      api.updated_on rule.updated_on
      yield if block_given?
    end
  end

  def render_api_automation_rows(api, name, rows)
    api.array name do
      rows.each do |row|
        api.__send__(name.to_s.singularize) { render_api_automation_hash(api, row) }
      end
    end
  end

  def render_api_automation_hash(api, hash)
    hash.each do |key, value|
      if value.is_a?(Array)
        api.array(key) { value.each { |v| api.value v } }
      else
        api.__send__(key, value)
      end
    end
  end

  def render_api_automation_result(api, result)
    api.result do
      api.issue_id result.issue.id
      api.trigger result.trigger
      api.matched result.matched?
      api.dry_run result.dry_run
      api.error result.error
      api.array :conditions do
        result.conditions.each do |condition|
          api.condition do
            api.description condition[:description]
            api.matched condition[:matched]
          end
        end
      end
      api.array :actions do
        result.applied.each { |description| api.action description }
      end
      api.array :changes do
        result.changes.each do |field, (before, after)|
          api.change do
            api.field field
            api.old_value before.to_s
            api.new_value after.to_s
          end
        end
      end
      api.notes result.notes
    end
  end
end
