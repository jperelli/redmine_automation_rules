# Mails sent by the "send email" action. Subclasses Redmine's Mailer so the
# delivery method, headers, layout and async delivery settings are the same
# as for notifications.
class AutomationRulesMailer < Mailer
  # +user+ is the rule author, whose language the mail is rendered in;
  # +recipient+ is a User or an email address.
  def rule_email(_user, recipient, issue, subject, body)
    @issue = issue
    @body_text = body
    @issue_url = url_for(controller: 'issues', action: 'show', id: issue)
    redmine_headers 'Project' => issue.project.identifier, 'Issue-Id' => issue.id
    references issue
    mail to: recipient, subject: subject
  end

  def self.deliver_rule_email(user, recipient, issue, subject, body)
    rule_email(user, recipient, issue, subject, body).deliver_later
  end
end
