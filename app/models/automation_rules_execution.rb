# One row per rule run whose conditions matched an issue: which actions were
# applied (or the error Redmine answered with). Shown on the rule page and in
# the issue sidebar. Only the last KEEP rows of each rule are kept.
class AutomationRulesExecution < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  KEEP = 200

  belongs_to :automation_rule
  belongs_to :issue, optional: true

  scope :recent, -> { order(id: :desc) }
  scope :failed, -> { where.not(error: nil) }

  def self.record!(result)
    rule = result.rule
    execution = create!(automation_rule: rule, issue_id: result.issue&.id, trigger: result.trigger.to_s,
                        applied: result.applied.join("\n").presence, error: result.error.presence&.truncate(2000),
                        created_at: Time.current)
    prune!(rule)
    execution
  end

  def self.prune!(rule)
    threshold = where(automation_rule_id: rule.id).recent.offset(KEEP).limit(1).pick(:id)
    where(automation_rule_id: rule.id).where('id <= ?', threshold).delete_all if threshold
  end

  # Rules that ran on +issue+, newest first, one row per rule.
  def self.rules_fired_on(issue)
    where(issue_id: issue.id).includes(:automation_rule).recent.uniq(&:automation_rule_id)
  end

  def success?
    error.blank?
  end

  def applied_list
    applied.to_s.split("\n")
  end

  def trigger_label
    if AutomationRule::TRIGGER_TYPES.include?(trigger)
      I18n.t("automation_rules_trigger_#{trigger}")
    else
      I18n.t("automation_rules_execution_trigger_#{trigger}", default: trigger)
    end
  end
end
