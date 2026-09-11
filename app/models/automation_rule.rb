# Redmine 6 has ApplicationRecord; Redmine 5 (Rails 6.1) does not.
class AutomationRule < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  include Redmine::SafeAttributes
  include Redmine::I18n

  TRIGGER_TYPES = %w[issue_created issue_updated issue_closed issue_reopened time_entry_logged scheduled].freeze
  EVENT_TRIGGER_TYPES = (TRIGGER_TYPES - ['scheduled']).freeze
  UPDATE_CHANGES = %w[any field status_to assignee note done_ratio_100 due_date].freeze
  INTERVAL_UNITS = %w[minute hour day week].freeze

  belongs_to :project, optional: true
  belongs_to :author, class_name: 'User', optional: true

  # Text columns holding JSON, so the same schema works on SQLite, MySQL and PostgreSQL.
  attribute :trigger_options, :json, default: -> { {} }
  attribute :conditions, :json, default: -> { [] }
  attribute :actions, :json, default: -> { [] }
  attribute :state, :json, default: -> { {} }

  acts_as_positioned scope: :project_id

  validates :name, presence: true, length: { maximum: 255 }
  validates :trigger_type, inclusion: { in: TRIGGER_TYPES }
  validates :author, presence: true
  validate :validate_trigger_options
  validate :validate_conditions
  validate :validate_actions

  before_validation :prune_trigger_options
  before_save :compute_next_run_at

  scope :active, -> { where(active: true) }
  scope :sorted, -> { order(Arel.sql("#{table_name}.project_id IS NULL DESC"), :project_id, :position, :id) }
  scope :global, -> { where(project_id: nil) }
  scope :with_trigger, ->(type) { where(trigger_type: type) }
  scope :scheduled, -> { with_trigger('scheduled') }
  scope :event, -> { where(trigger_type: EVENT_TRIGGER_TYPES) }

  # Rules that apply to issues of +project+: its own rules, rules of ancestors
  # flagged "apply to subprojects" and global rules.
  scope :applicable_to, lambda { |project|
    ancestor_ids = project.ancestors.pluck(:id)
    scope = where(project_id: nil).or(where(project_id: project.id))
    scope = scope.or(where(project_id: ancestor_ids, apply_to_subprojects: true)) if ancestor_ids.any?
    scope
  }

  safe_attributes 'name', 'description', 'active', 'apply_to_subprojects', 'note_marker',
                  'position', 'trigger_type', 'trigger_options', 'conditions', 'actions'

  def self.trigger_type_options
    TRIGGER_TYPES.map { |type| [l("automation_rules_trigger_#{type}"), type] }
  end

  def self.update_change_options
    UPDATE_CHANGES.map { |change| [l("automation_rules_update_change_#{change}"), change] }
  end

  def self.interval_unit_options
    INTERVAL_UNITS.map { |unit| [l("automation_rules_interval_unit_#{unit}"), unit] }
  end

  # Form params arrive as an index-keyed hash ({'0' => {...}, '1' => {...}}),
  # the API sends an array, and either may contain blank rows.
  def conditions=(value)
    super(normalize_rows(value))
  end

  def actions=(value)
    super(normalize_rows(value))
  end

  def trigger_options=(value)
    value = value.to_unsafe_hash if value.respond_to?(:to_unsafe_hash)
    if value.is_a?(String)
      value = begin
        JSON.parse(value)
      rescue StandardError
        {}
      end
    end
    super(value.is_a?(Hash) ? value.stringify_keys : {})
  end

  # Runtime state kept by actions (e.g. the round-robin position), never nil.
  def state
    super.is_a?(Hash) ? super : {}
  end

  def global?
    project_id.nil?
  end

  def scheduled?
    trigger_type == 'scheduled'
  end

  def event?
    !scheduled?
  end

  def visible?(user = User.current)
    if global?
      user.admin?
    else
      user.allowed_to?(:view_automation_rules, project) || user.allowed_to?(:manage_automation_rules, project)
    end
  end

  def editable?(user = User.current)
    global? ? user.admin? : user.allowed_to?(:manage_automation_rules, project)
  end

  # Does this rule apply to issues of +project+?
  def applies_to?(other_project)
    return false if other_project.nil?
    return true if global?
    return true if other_project.id == project_id

    apply_to_subprojects && other_project.is_descendant_of?(project)
  end

  def condition_objects
    conditions.filter_map { |row| RedmineAutomationRules::Conditions.build(row) }
  end

  def action_objects
    actions.filter_map { |row| RedmineAutomationRules::Actions.build(row) }
  end

  def trigger_option(key)
    trigger_options[key.to_s]
  end

  def interval_number
    [trigger_option('interval_number').to_i, 1].max
  end

  def interval_unit
    unit = trigger_option('interval_unit').to_s
    INTERVAL_UNITS.include?(unit) ? unit : 'day'
  end

  def interval
    interval_number.public_send(interval_unit)
  end

  # "HH:MM" or nil
  def time_of_day
    value = trigger_option('time_of_day').to_s
    value =~ /\A\d{1,2}:\d{2}\z/ ? value : nil
  end

  # Next time the scheduler should evaluate this rule. With a time of day, the
  # next occurrence of that time (in the author's time zone) after +from+;
  # otherwise one interval after the last run (or after +from+ if never run).
  def compute_next_run(from = Time.current)
    return nil unless scheduled?

    if time_of_day && interval_unit.in?(%w[day week])
      hour, minute = time_of_day.split(':').map(&:to_i)
      nxt = from.in_time_zone(author&.time_zone || Time.zone).change(hour: hour, min: minute)
      nxt += interval while nxt <= from
      nxt
    else
      (last_run_at || from) + interval
    end
  end

  def due?(now = Time.current)
    scheduled? && active? && (next_run_at.nil? || next_run_at <= now)
  end

  # Issues the rule is evaluated against when run by the scheduler or "Run now".
  def candidate_issues
    scope = Issue.open
    scope = if global?
              scope
            elsif apply_to_subprojects
              scope.where(project_id: project.self_and_descendants.pluck(:id))
            else
              scope.where(project_id: project_id)
            end
    scope.order(:id)
  end

  def copy_from(other)
    self.attributes = other.attributes.except('id', 'position', 'last_run_at', 'next_run_at', 'last_error',
                                              'runs_count', 'state', 'created_on', 'updated_on')
    self.name = "#{other.name} (#{l(:button_copy).downcase})"
    self
  end

  # A one line summary of the rule: "When an issue is closed, if tracker is Bug, then set status to Closed".
  def sentence
    parts = [trigger_sentence]
    conds = condition_objects.map(&:describe)
    parts << l(:automation_rules_sentence_if, conditions: conds.to_sentence) if conds.any?
    acts = action_objects.map(&:describe)
    parts << (if acts.any?
                l(:automation_rules_sentence_then,
                  actions: acts.to_sentence)
              else
                l(:automation_rules_sentence_no_action)
              end)
    parts.join(', ')
  end

  def trigger_sentence
    case trigger_type
    when 'issue_updated' then update_trigger_sentence
    when 'scheduled' then scheduled_trigger_sentence
    else l("automation_rules_trigger_sentence_#{trigger_type}")
    end
  end

  def record_run!(error = nil)
    self.last_run_at = Time.current
    self.last_error = error&.to_s&.truncate(2000)
    self.runs_count += 1 unless error
    save(validate: false)
  end

  private

  def normalize_rows(value)
    value = value.to_unsafe_hash if value.respond_to?(:to_unsafe_hash)
    if value.is_a?(String)
      value = begin
        JSON.parse(value)
      rescue StandardError
        []
      end
    end
    rows = value.is_a?(Hash) ? value.keys.sort_by { |k| k.to_s.to_i }.map { |k| value[k] } : Array(value)
    rows.filter_map do |row|
      row = row.to_unsafe_hash if row.respond_to?(:to_unsafe_hash)
      next unless row.is_a?(Hash)

      row = row.stringify_keys
      row if row['type'].present?
    end
  end

  def validate_trigger_options
    return unless scheduled?

    errors.add(:trigger_options, :invalid) unless INTERVAL_UNITS.include?(trigger_option('interval_unit').to_s)
    errors.add(:trigger_options, :invalid) if trigger_option('interval_number').to_i < 1
    tod = trigger_option('time_of_day').to_s
    errors.add(:trigger_options, :invalid) if tod.present? && tod !~ /\A([01]?\d|2[0-3]):[0-5]\d\z/
  end

  def validate_conditions
    conditions.each_with_index do |row, index|
      condition = RedmineAutomationRules::Conditions.build(row)
      if condition.nil?
        errors.add(:base, l(:automation_rules_error_unknown_condition, type: row['type'], position: index + 1))
      else
        condition.validate.each do |message|
          errors.add(:base, l(:automation_rules_error_condition, position: index + 1, message: message))
        end
      end
    end
  end

  def validate_actions
    actions.each_with_index do |row, index|
      action = RedmineAutomationRules::Actions.build(row)
      if action.nil?
        errors.add(:base, l(:automation_rules_error_unknown_action, type: row['type'], position: index + 1))
      else
        action.validate.each do |message|
          errors.add(:base, l(:automation_rules_error_action, position: index + 1, message: message))
        end
      end
    end
  end

  # The form submits the inputs of every trigger type; keep only the options
  # that mean something for the selected one.
  def prune_trigger_options
    keys = case trigger_type
           when 'issue_updated'
             %w[change] + case trigger_option('change')
                          when 'field' then %w[field]
                          when 'status_to' then %w[status_id]
                          else []
                          end
           when 'scheduled'
             daily = %w[day week].include?(trigger_option('interval_unit').to_s)
             %w[interval_number interval_unit] + (daily ? %w[time_of_day] : [])
           else
             []
           end
    self.trigger_options = trigger_options.slice(*keys)
  end

  def compute_next_run_at
    if scheduled?
      self.next_run_at = compute_next_run if next_run_at.nil? || trigger_options_changed? || last_run_at_changed?
    else
      self.next_run_at = nil
    end
  end

  def update_trigger_sentence
    change = trigger_option('change').to_s
    case change
    when 'field'
      l(:automation_rules_trigger_sentence_issue_updated_field, field: field_label(trigger_option('field')))
    when 'status_to'
      status = IssueStatus.find_by(id: trigger_option('status_id'))
      l(:automation_rules_trigger_sentence_issue_updated_status_to, status: status&.name || '?')
    when 'assignee', 'note', 'done_ratio_100', 'due_date'
      l("automation_rules_trigger_sentence_issue_updated_#{change}")
    else
      l(:automation_rules_trigger_sentence_issue_updated)
    end
  end

  def scheduled_trigger_sentence
    every = l("automation_rules_interval_every_#{interval_unit}", count: interval_number)
    every += " #{l(:automation_rules_interval_at, time: time_of_day)}" if time_of_day && interval_unit.in?(%w[day week])
    l(:automation_rules_trigger_sentence_scheduled, every: every)
  end

  def field_label(field)
    RedmineAutomationRules::Schema.field_label(field)
  end
end
