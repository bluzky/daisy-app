---
dashboard: true
---

# Weekly dashboard

```stat
label: Revenue
value: $48.2k
delta: +12%
trend: up
note: vs last month
link: #sales-by-month
---
label: Active users
value: 3,204
delta: +3.1%
trend: up
---
label: Churn
value: 2.1%
delta: -0.4%
trend: down
good: down
---
label: Support backlog
value: 41
delta: +6
trend: up
good: down
```

## Sales by month

```mermaid
xychart-beta
    x-axis [Jan, Feb, Mar, Apr]
    y-axis "Sales" 0 --> 30
    bar [12, 18, 15, 24]
    line [7, 9, 8, 11]
```

## Revenue mix

```mermaid
pie showData title Revenue mix
    "Free" : 40
    "Pro" : 45
    "Enterprise" : 15
```

## Release 4.2

```progress
label: Features
value: 7
max: 12
---
label: Tests passing
value: 182
max: 190
```

```badge
text: Build passing
status: ok
---
text: Docs outdated
status: warn
---
text: Notarization failing
status: fail
```

This block is missing its `value`, so it stays a plain code block:

```stat
label: Broken tile
```
