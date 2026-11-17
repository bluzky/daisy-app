<!--
Design-Before-Code PR: one PR = one phase ticket ([P<n>]).
scripts/check_pr.py (run by Lucy's pr-prepare) parses this description: keep the headings.
Small change outside the flow? Only the ticket link is required.
-->

## Ticket

<!-- Phase ticket: ClickUp link, or GitHub #<n>, or (no tracker) "Phase: P<n>" -->
- Phase ticket: https://app.clickup.com/t/<phase_ticket_id>
- Feature Spec: docs/features/<feature-slug>.md
- Plan: docs/features/<feature-slug>-plan.md → P<n>

## Scope

- ACs covered: AC-1.1, AC-1.2 (all ACs of the phase's stories)

## Evidence

| AC | Evidence |
| --- | --- |
| AC-1.1 | <screenshot / recording / test output> |
| AC-1.2 | <screenshot / recording / test output> |

## Tests

<test command and summary>

## Migration / config

<migrations, feature flags, config keys, or "None">

## Differences from the spec

<what differs from the approved spec and why (and confirm the spec is updated), or "None">
