# My templates

Choose this file in **Settings → General → Templates**. Each template starts at
a marker line, `<!-- template: Name -->`, and runs to the next marker. The
marker is a comment, so it doesn't show in the preview. Everything before the
first marker, like this intro, is ignored.

A template can contain any heading, `##` included. (A file with no marker at all
falls back to one template per `##` heading.)

Variables are filled in when a template is inserted: `{{date}}`, `{{time}}`,
`{{datetime}}` and `{{weekday}}`. `{{cursor}}` isn't inserted; it marks where the
caret lands. Write `\{{` for a literal `{{`.

<!-- template: Meeting notes -->

# Meeting — {{date}} ({{weekday}})

## Attendees

- 

## Agenda

1. 

## Decisions

## Action items

- [ ] 

<!-- template: Daily standup -->

**{{date}}**

- **Yesterday:** 
- **Today:** {{cursor}}
- **Blockers:** 

<!-- template: Bug report -->

> [!WARNING]
> Describe the problem in one sentence.

### Steps to reproduce

1. 
2. 

### Expected

### Actual

<!-- template: Decision record -->

| Option | Pros | Cons |
| --- | --- | --- |
|  |  |  |

**Decision:** 
