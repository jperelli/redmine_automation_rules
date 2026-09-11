module RedmineAutomationRules
  module Actions
    class AddNote < Base
      param 'text', widget: 'textarea', required: true, placeholder: :automation_rules_note_placeholder
      param 'private', widget: 'checkbox', label: :field_private_notes

      def apply(issue, context)
        text = Substitution.apply(param('text'), issue, context)
        journal = issue.init_journal(author(context))
        journal.notes = [journal.notes.presence, text].compact.join("\n\n")
        journal.private_notes = true if param('private').to_s == '1'
      end

      def describe
        l(:automation_rules_action_sentence_add_note, text: param('text').to_s.truncate(40))
      end
    end
  end
end
