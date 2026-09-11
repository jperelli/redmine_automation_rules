# One row per execution of AutomationRulesChecker, shown on the plugin
# settings page so admins can verify that their cron / web / external
# scheduler is actually firing and see any errors.
#
# Consecutive runs that changed nothing (and came from the same source) are
# coalesced into a single row (+runs_count+ / +last_run_at+), so the capped
# history covers days of real activity instead of a few hours of "0 rules
# due" from the web scheduler. Adapted from Redmine Periodic Task.
class AutomationRulesRun < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  KEEP = 50
  SOURCES = %w[rake web endpoint manual].freeze

  validates :source, inclusion: { in: SOURCES }

  scope :recent, -> { order(started_at: :desc, id: :desc) }

  def self.record!(source:, started_at:, finished_at:, rules_evaluated:, issues_matched:, actions_applied:,
                   errors:, notes: [])
    attrs = { source: source, started_at: started_at, last_run_at: started_at,
              duration_ms: ((finished_at - started_at) * 1000).round,
              rules_evaluated: rules_evaluated, issues_matched: issues_matched, actions_applied: actions_applied,
              error_messages: errors.reject(&:blank?).join("\n").presence,
              notes: notes.reject(&:blank?).join("\n").presence }

    run = coalesce_target(attrs) || create!(attrs)
    prune!
    run
  end

  def self.prune!
    keep_ids = recent.limit(KEEP).pluck(:id)
    where.not(id: keep_ids).delete_all
  end

  def noop?
    rules_evaluated.zero? && error_messages.blank?
  end

  # Nothing changed and nothing failed: idle rules or rules that matched no issue.
  def uneventful?
    actions_applied.zero? && error_messages.blank?
  end

  def self.coalesce_target(attrs)
    return nil unless attrs[:actions_applied].zero? && attrs[:error_messages].nil?

    last = recent.first
    return nil unless last&.uneventful? && last.source == attrs[:source] &&
                      last.rules_evaluated == attrs[:rules_evaluated] &&
                      last.issues_matched == attrs[:issues_matched] && last.notes == attrs[:notes]

    last.update!(runs_count: last.runs_count + 1, last_run_at: attrs[:last_run_at],
                 duration_ms: attrs[:duration_ms])
    last
  end
  private_class_method :coalesce_target
end
