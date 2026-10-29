# Query blocks

Query blocks list matching Markdown files or checkbox tasks from an initialized workspace. Add a fenced `tasks` or `notes` block to any Markdown file:

````markdown
```tasks
+daisy is:open due:<=7d
sort:due
```
````

- `tasks` lists checkbox tasks. Checking a result updates its source file.
- `notes` lists Markdown files.
- Queries use saved workspace data. Choose **File → Initialize Workspace** first; unsaved changes outside current document do not appear until saved.
- Empty blocks stay ordinary code blocks. Put caret in a rendered block to reveal and edit its source.

Each query term is separated by whitespace. Terms on same line, or on separate lines, work identically.

## Examples

### Open tasks due this week

````markdown
```tasks
is:open due:<=7d
sort:due
```
````

### Work projects, sorted latest due date first

````markdown
```tasks
+work -is:done
sort:-due
```
````

### Files in a folder with frontmatter

````markdown
```notes
in:projects/ status:active
sort:title
```
````

### Two alternative task groups

````markdown
```tasks
+client due:<=7d OR @phone is:open
sort:due
```
````

Query syntax has no parentheses: `OR` splits alternatives. Above query means “tasks in `+client` due within seven days, or open tasks in `@phone`.”

## Filters

Terms are combined with AND by default. Add uppercase `OR` between groups of terms for alternatives:

```text
+client p:high OR @phone is:open
```

Lowercase `or` is not an operator. There are no parentheses. Prefix supported filter with `-` to exclude it:

```text
-#waiting -is:done -p:low
```

Use a comma for any-of values within one term:

```text
p:high,medium
is:open,done
+client,internal
```

### Names

| Syntax | Matches |
| --- | --- |
| `#design` | Tag `#design` and descendants such as `#design/mobile` |
| `@phone` | Context `@phone` and descendants |
| `+daisy` | Project `+daisy` and descendants |

Names match case-insensitively. Use `/` to create hierarchies, such as `#area/mobile`. A parent name matches descendants; `#area` matches `#area/mobile`.

### Task state and metadata

| Term | Matches |
| --- | --- |
| `is:open` | Unchecked tasks |
| `is:done` | Checked tasks |
| `due:2026-10-23` | Exact due date |
| `due:<=7d` | Due on or before seven days from today |
| `scheduled:>-2w` | Scheduled after two weeks before today |
| `p:high` | High priority |
| `p:high,medium` | High or medium priority |
| `has:due` | Has a due date |
| `has:p` | Has a priority |

`is:` applies to `tasks` blocks. Valid priorities: `high`, `medium`, `low`.

Dates accept `today`, a signed day or week offset such as `7d` or `-2w`, or `YYYY-MM-DD`. Date comparisons use `<`, `<=`, `>`, and `>=` immediately after colon:

```text
due:<today
scheduled:>=2026-11-01
```

### File, text, link, and frontmatter filters

| Term | Matches |
| --- | --- |
| `in:notes/` | Files in root-relative `notes/` folder and descendants |
| `links:projects/plan.md` | Markdown links to root-relative file path |
| `text:review` | Task text or file name containing text, case-insensitively |
| `title:Weekly` | File title; frontmatter `title` or file name fallback |
| `status:active` | Frontmatter field value |
| `rating:>=4` | Frontmatter numeric value |
| `has:status` | Files or tasks with frontmatter field |
| `file.name:Inbox.md` | File name |
| `file.folder:notes` | File folder |
| `file.path:notes/Inbox.md` | Root-relative file path |
| `file.size:>1000` | File size in bytes |
| `file.created:>=2026-01-01` | File creation date |
| `file.modified:>=today` | File modification date |

`tasks` queries read task metadata first, then file metadata and frontmatter. A task's `links:` filter only matches links on that task's line.

Use double quotes when a value includes spaces:

```text
title:"Weekly planning"
text:"call Alex"
```

Field keys are case-insensitive. A field must exist somewhere in workspace frontmatter before Daisy can validate it; unknown or misspelled fields show an inline problem.

## Sort and limit

`sort:` and `limit:` affect whole query, wherever written. They do not filter rows.

```text
sort:due,-p,title
limit:20
```

Sort keys run left to right. Prefix key with `-` for descending order. Useful keys:

| Key | Meaning |
| --- | --- |
| `due`, `scheduled`, `p` or `priority` | Task metadata |
| `title` | Frontmatter title or file name |
| `text` | Task text or file name |
| `path` | Root-relative file path |
| `line` | Task line number |
| `file.name`, `file.folder`, `file.path`, `file.created`, `file.modified`, `file.size` | File details |
| Any frontmatter key | That field's value |

Missing values always sort last. Equal values break ties by file path, then line number. `limit:` takes non-negative whole number and applies after sorting, before grouping.

## Groups and tables

Display options start with `$`; ordinary `group:`, `view:`, and `columns:` remain frontmatter filters.

### Groups

```text
$group:project
$group:due
$group:status
$group:file
```

Group by tag, context, or project using `#`/`tag`, `@`/`context`, or `+`/`project`. Other choices include `due`, `scheduled`, `p`/`priority`, `title`, `file`, `folder`, `path`, file details, and frontmatter keys.

A row with several names appears in each matching name group. Rows without group value appear under a “No …” group. `done` and `text` cannot be group keys.

### Tables

```text
$view:table
$columns:done,text,due,p,project,file
```

`$view:list` is default. `$view:table` makes table view. `$columns:` also selects table view when `$view:` is absent; repeat it to add columns:

```text
$columns:text,due
$columns:project,file
```

Columns support `done` (tasks only), `text`, `file`, `folder`, `path`, names (`#`, `tag`, `@`, `context`, `+`, `project`), dates, priority, file details, and frontmatter keys.

Default table columns:

| Block | Columns |
| --- | --- |
| `tasks` | Done, Task, Due, Priority, File |
| `notes` | Title, Folder |

`$columns:` cannot combine with `$view:list`.

## Problems

Daisy displays query problems below results. It leaves bad term out and still evaluates remaining valid terms. A block containing only invalid filters returns no rows; a block containing only `sort:`, `limit:`, or display options lists every item from its source.

Use explicit terms. Bare words, unmatched comparison operators, malformed dates, invalid priorities, and unsupported display options show a problem with correction guidance.
