# Weekly dashboard

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

<!-- columns -->

```chart
type: bar
title: Sales (k$)
colors: #6366F1, #22C55E
legend:
  position: right
  visible: true
| Month | 2025 | 2026 |
| ----- | ---- | ---- |
| Jan   | 12   | 15   |
| Feb   | 18   | 21   |
| Mar   | 15   | 19   |
| Apr   | 24   | 28   |
```

<!-- column -->

```chart
type: line
title: Signups per week
grid: false
| Week | Organic | Paid |
| ---- | ------- | ---- |
| W1   | 120     | 40   |
| W2   | 135     | 52   |
| W3   | 128     | 61   |
| W4   | 160     | 58   |
```

<!-- end-columns -->

## Revenue mix

<!-- columns -->

```chart
type: pie
title: Users by plan
| Plan       | Users |
| ---------- | ----- |
| Free       | 62    |
| Pro        | 30    |
| Enterprise | 8     |
```

<!-- column -->

```chart
type: donut
title: Revenue by plan (k$)
colors: #94A3B8, #6366F1, #F59E0B
| Plan       | Revenue |
| ---------- | ------- |
| Free       | 4       |
| Pro        | 27      |
| Enterprise | 17      |
```

<!-- end-columns -->

## Goals

<!-- columns -->

```chart
type: donut
title: Quarterly target
height: 120
colors: #22C55E, #E5E7EB
legend:
  visible: false
| Part      | k$ |
| --------- | -- |
| Reached   | 72 |
| Remaining | 28 |
```

<!-- column -->

```chart
type: donut
title: Onboarding done
height: 120
colors: #6366F1, #E5E7EB
legend:
  visible: false
| Part      | Users |
| --------- | ----- |
| Done      | 58    |
| Remaining | 42    |
```

<!-- column -->

```chart
type: donut
title: Tickets in SLA
height: 120
colors: #F59E0B, #E5E7EB
legend:
  visible: false
| Part    | % |
| ------- | - |
| In SLA  | 91 |
| Late    | 9 |
```

<!-- end-columns -->

## Support

<!-- columns -->

```chart
type: bar
title: Tickets by week
height: 220
stacked: true
| Week | Bugs | Questions | Requests |
| ---- | ---- | --------- | -------- |
| W1   | 14   | 22        | 6        |
| W2   | 11   | 25        | 9        |
| W3   | 17   | 19        | 7        |
| W4   | 9    | 21        | 12       |
```

<!-- column -->

```chart
type: bar
title: Tickets by team
stacked: true
direction: horizontal
height: 220
| Team     | Open | In review | Closed |
| -------- | ---- | --------- | ------ |
| Platform | 12   | 6         | 30     |
| Mobile   | 8    | 4         | 22     |
| Web      | 15   | 9         | 18     |
```

<!-- end-columns -->

```chart
type: bar
title: First response time by channel (hours)
direction: horizontal
grid: false
colors: #0EA5E9
legend: none
x-axis:
  visible: false
| Channel | Hours |
| ------- | ----- |
| Email   | 6.5   |
| Chat    | 0.8   |
| Forum   | 14    |
| Phone   | 0.3   |
```

## Release 4.2

<!-- columns -->

```progress
label: Features
value: 7
max: 12
striped: true
---
label: Tests passing
value: 182
max: 190
color: positive
---
label: Open blockers
value: 3
max: 10
color: negative
---
label: Docs updated
value: 5
max: 9
color: warning
```

<!-- column -->

```stat
label: Days to release
value: 9
note: Code freeze on Friday
---
label: Crash-free sessions
value: 99.6%
delta: +0.2%
trend: up
```

<!-- end-columns -->

This block is missing its `value`, so it stays a plain code block:

```stat
label: Broken tile
```
