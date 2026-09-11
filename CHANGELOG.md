# Changelog

All notable changes to this project are documented in this file.

## Unreleased

- Scheduler for scheduled rules, copied from Redmine Periodic Task: `rake redmine:check_automation_rules`, automatic on web requests, check URL for external schedulers, scheduler log with *Run checker now* on the plugin settings page.
- Event triggers (issue created / updated / closed / reopened, time entry logged) with a loop guard and an optional asynchronous mode.
- Action engine: every action type, date macros, note variables, webhooks and emails.
- Condition engine: every condition type, including custom fields of every format.
- Rule model, migrations, CRUD UI, dry run and REST API.
- Initial scaffold: plugin skeleton, docker development and test setup, CI matrix (Redmine 5.1, 6.0, 6.1, 7.0), logo.
