module RedmineAutomationRules
  module Actions
    class SetTracker < Base
      param 'value', widget: 'select', options: 'tracker', required: true

      def apply(issue, _context)
        tracker = ::Tracker.find_by(id: param('value'))
        fail!(l(:automation_rules_error_record_not_found, type: l(:field_tracker), id: param('value'))) unless tracker
        unless issue.project.trackers.include?(tracker)
          fail!(l(:automation_rules_error_tracker_not_in_project, tracker: tracker.name))
        end

        issue.tracker = tracker
      end

      def describe
        l(:automation_rules_action_sentence_set_tracker, tracker: name_of(::Tracker, param('value')))
      end
    end
  end
end
