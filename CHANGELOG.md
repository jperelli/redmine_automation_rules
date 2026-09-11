# Changelog

All notable changes to this project are documented in this file.

## 0.1.0 - 2026-09-11

First release.

- Rules per project (optionally applying to subprojects) or global (administrators), with an active flag, ordering, author, and a description.
- Triggers: issue created, issue updated (any change, or restricted to a field, a status, the assignee, a note, 100% done, the due date), issue closed, issue reopened, time entry logged, and scheduled (every N minutes / hours / days / weeks, optionally at a time of day).
- Conditions on tracker, status, priority, assignee, author, category, target version, % done, due and start dates, subject, description, watchers, parent and subtasks, private flag, time spent, created / updated age, and custom fields of every core format.
- Actions: set status, assignee (user, author, current user, previous, round-robin in a group, nobody), priority, tracker, category, target version, dates (absolute, today, relative, working-day shift), % done, custom fields (with date macros), private flag; add a note with `{{variables}}`; add and remove watchers; close and reopen; create a subtask or related issue; send an email; call a webhook; update the parent issue.
- Actions run as the rule author through Redmine's validations, workflow and permissions; refusals are recorded, never raised into the request.
- Event triggers with a loop guard (a rule never re-fires on the same issue in the same chain, chains stop after 3 levels) and an optional asynchronous mode.
- Scheduler for scheduled rules, copied from Redmine Periodic Task: `rake redmine:check_automation_rules`, automatic on web requests, check URL for external schedulers, scheduler log (last 50 runs, uneventful runs coalesced) with *Run checker now* on the plugin settings page.
- Eleven built-in recipes (*New rule from recipe*): auto-close resolved issues, reopen when the reporter comments on a closed issue, close the parent when all subtasks are closed, round-robin assignment, start date on In Progress, finish on close, escalate unassigned high-priority issues, due-date reminder, stale issues, assign by category, time budget exceeded.
- Per-rule execution log (last 200 executions) on the rule page and through the API, and an *Automation* block in the issue sidebar listing the rules that fired on the issue.
- Dry run (*Test on issue*) showing the matched conditions and the changes the actions would make, without saving; *Run for real* afterwards.
- REST API (JSON and XML) for listing, creating, updating, deleting, testing and running rules.
- English and Spanish.
- Docker development and test setup, CI on Redmine 5.1, 6.0, 6.1 and 7.0.
