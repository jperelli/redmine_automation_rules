module RedmineAutomationRules
  # Turns Issue / TimeEntry saves into rule triggers.
  #
  # IssuePatch captures what changed in an +after_save+ (Redmine has saved the
  # journal by then) and hands the snapshot to +dispatch_issue_event+ from an
  # +after_commit+, so rules only ever see committed data and their own saves
  # happen outside the originating transaction.
  #
  # Loop guard: rules run in a per-thread "chain". A rule fires at most once
  # per issue per chain, and a chain stops (with a log line) once saves made
  # by rules have nested MAX_DEPTH levels deep.
  module Events
    MAX_DEPTH = 3

    # What an issue save changed, captured before the transaction commits.
    IssueEvent = Struct.new(:issue_id, :created, :changes, :journal_id, :closing, :reopening, :notes,
                            keyword_init: true) do
      def changed?(attribute)
        changes.key?(attribute.to_s)
      end

      def new_value(attribute)
        changes[attribute.to_s]&.last
      end

      def old_value(attribute)
        changes[attribute.to_s]&.first
      end

      def notes?
        notes.present?
      end

      def journal
        @journal ||= journal_id && Journal.find_by(id: journal_id)
      end

      def triggers
        return ['issue_created'] if created
        return [] if changes.empty? && !notes?

        list = ['issue_updated']
        list << 'issue_closed' if closing
        list << 'issue_reopened' if reopening
        list
      end
    end

    class << self
      # Set to false to silence every trigger (fixtures, imports).
      attr_writer :enabled
      # Run asynchronous dispatches inline (tests).
      attr_accessor :synchronous

      def enabled?
        @enabled != false
      end

      def without_events
        previous = @enabled
        @enabled = false
        yield
      ensure
        @enabled = previous
      end

      def async?
        RedmineAutomationRules.setting('run_actions_async').to_s == '1' && !synchronous
      end

      # Builds the snapshot right after +issue+ was saved (before commit).
      def capture(issue)
        changes = issue.saved_changes.except('updated_on', 'lock_version', 'closed_on', 'root_id', 'lft', 'rgt')
                       .transform_values(&:dup)
        journal = issue.current_journal if issue.current_journal&.persisted?
        journal&.details&.each do |detail|
          next unless detail.property == 'cf'

          changes["cf_#{detail.prop_key}"] = [detail.old_value, detail.value]
        end
        was_closed, is_closed = Array(changes['status_id']).map { |status_id| closed_status?(status_id) }
        IssueEvent.new(issue_id: issue.id, created: issue.saved_change_to_id?, changes: changes,
                       journal_id: journal&.id, notes: journal&.notes.presence,
                       closing: !was_closed && is_closed == true,
                       reopening: was_closed == true && is_closed == false)
      end

      def dispatch_issue_event(issue, event)
        return unless enabled?

        triggers = event.triggers
        return if triggers.empty?

        dispatch(issue, triggers, event: event)
      end

      def dispatch_time_entry(time_entry)
        return unless enabled? && time_entry.issue

        dispatch(time_entry.issue, ['time_entry_logged'], time_entry: time_entry)
      end

      # Runs the active rules of +issue+'s project (and its ancestors / global
      # rules) for +triggers+, in rule order. Never raises.
      def dispatch(issue, triggers, context = {})
        if async? && chain.nil?
          dispatch_async(issue.id, triggers, context)
        else
          run_chain(issue, triggers, context)
        end
      rescue StandardError => e
        Rails.logger.error("[automation_rules] dispatch failed for issue ##{issue.id}: #{e.class}: #{e.message}")
      end

      # Rules that can fire for +issue+ on +triggers+: active event rules of
      # the project, of ancestors flagged "apply to subprojects" (their own
      # project must have the module enabled) and global rules.
      def rules_for(issue, triggers)
        return [] unless issue.project

        AutomationRule.active.with_trigger(Array(triggers)).applicable_to(issue.project).sorted
                      .includes(:project, :author)
                      .select { |rule| rule.global? || rule.project.module_enabled?(:automation_rules) }
      end

      def chain
        Thread.current[:automation_rules_chain]
      end

      private

      def closed_status?(status_id)
        return false unless status_id

        IssueStatus.find_by(id: status_id)&.is_closed? || false
      end

      def dispatch_async(issue_id, triggers, context)
        actor = User.current
        Thread.new do
          Rails.application.executor.wrap do
            User.current = actor
            issue = Issue.find_by(id: issue_id)
            run_chain(issue, triggers, context) if issue
          rescue StandardError => e
            Rails.logger.error("[automation_rules] async dispatch failed for issue ##{issue_id}: " \
                               "#{e.class}: #{e.message}")
          end
        end
      end

      def run_chain(issue, triggers, context)
        outermost = chain.nil?
        Thread.current[:automation_rules_chain] = { depth: 0, fired: Set.new } if outermost
        current = chain
        if current[:depth] >= MAX_DEPTH
          Rails.logger.warn("[automation_rules] issue ##{issue.id}: rules nested deeper than #{MAX_DEPTH} levels, " \
                            "stopping (#{triggers.join(', ')})")
          return
        end

        current[:depth] += 1
        begin
          run_rules(issue, triggers, context, current)
        ensure
          current[:depth] -= 1
        end
      ensure
        Thread.current[:automation_rules_chain] = nil if outermost
      end

      # Each rule gets a freshly loaded issue: the instance that fired the
      # callback can be stale (nested set update_all bumps lock_version on
      # Rails >= 7.1) and earlier rules in the chain may have saved it.
      def run_rules(issue, triggers, context, current)
        rules_for(issue, triggers).each do |rule|
          key = [rule.id, issue.id]
          next if current[:fired].include?(key)
          next unless rule.matches_event?(context)

          current[:fired] << key
          target = ::Issue.find_by(id: issue.id)
          break unless target

          Runner.new(rule, target, trigger: rule.trigger_type, context: context).run
        end
      end
    end
  end

  module IssuePatch
    def self.prepended(base)
      base.after_save :automation_rules_capture_event
      base.after_commit :automation_rules_dispatch_event
      base.after_rollback :automation_rules_discard_event
    end

    private

    def automation_rules_capture_event
      @automation_rules_event = Events.capture(self) if Events.enabled?
    end

    def automation_rules_dispatch_event
      event = @automation_rules_event
      @automation_rules_event = nil
      Events.dispatch_issue_event(self, event) if event
    end

    def automation_rules_discard_event
      @automation_rules_event = nil
    end
  end

  module TimeEntryPatch
    def self.prepended(base)
      base.after_commit :automation_rules_dispatch_event, on: :create
    end

    private

    def automation_rules_dispatch_event
      Events.dispatch_time_entry(self)
    end
  end
end
