# Weekly report

`{{badge: "Build passing" color=success}}` `{{badge: "Docs outdated" color=warning}}` `{{badge: "Notarization failing" color=danger}}` `{{badge: "Maintenance on Sunday" color=info}}` `{{badge: "v2.4 beta" color=accent}}` `{{badge: Archived color=neutral}}` `{{badge: Draft}}` `{{badge: Design color=#AF52DE}}`

Badge styles: `{{badge: Tint color=success}}` `{{badge: Solid style=solid color=success}}` `{{badge: Outline style=outline color=success}}` · `{{badge: Rounded kind=rounded color=info}}` `{{badge: Square kind=square style=solid color=info}}` · `{{badge: Small size=sm}}` `{{badge: Large size=lg color=accent}}` · `{{badge: "Light hex" style=solid color=#ffd60a ink=dark}}`

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
color: danger
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

<!-- card align=center -->
```progress
shape: ring
label: Quarterly target
value: 72
max: 100
color: success
---
label: Onboarding done
value: 58
max: 100
text: {value}/{max}
---
label: Revenue
value: 48
max: 52
color: accent
text: ${value}k
---
label: Tickets in SLA
value: 91
max: 100
color: warning
```
<!-- end-card -->

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

<!-- card style=outline -->
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
<!-- end-card -->

## Services

Sparklines and badges are shortcodes: inline code that sits in a sentence or a table cell.

| Service | Requests, last 8 weeks                                         | p95 latency | Status                                    |
| ------- | -------------------------------------------------------------- | ----------- | ----------------------------------------- |
| API     | `{{sparkline: 120, 132, 128, 141, 150, 147, 162, 171}}`        | 180 ms      | `{{badge: Healthy color=success}}`        |
| Search  | `{{sparkline: 80,78,90,85,70,64,60,58 color=warning}}`         | 420 ms      | `{{badge: Degraded color=warning}}`       |
| Billing | `{{sparkline: 22,31,18,35,27,40,33,44 color=danger type=bar}}` | 95 ms       | `{{badge: Healthy color=success}}`        |
| Sync    | `{{sparkline: 30,32,35,12,8,6,5,5 color=danger}}`              | 1.2 s       | `{{badge: "Incident open" color=danger}}` |

Error budget used this month: `{{progress: 72% color=warning text="{percent}"}}` · on-call handover checklist `{{progress: 5/8}}`

Release steps: `{{shape: 1}}` Freeze · `{{shape: 2}}` Test · `{{shape: 3 color=success}}` Ship · `{{shape: ✓ kind=rounded style=tint color=success}}` Done · `{{shape: 98% style=outline color=info size=lg}}` uptime

Marker kinds: `{{shape: 1}}` circle · `{{shape: 2 kind=rounded}}` rounded · `{{shape: 3 kind=square}}` square · `{{shape: 4 kind=hexagon color=info}}` hexagon · `{{shape: ! kind=diamond color=warning}}` diamond · `{{shape: v4.2 kind=pill style=tint}}` pill

Every kind in every style: `{{shape: 7 kind=hexagon}}` `{{shape: 7 kind=hexagon style=tint}}` `{{shape: 7 kind=hexagon style=outline}}` · `{{shape: 7 kind=diamond color=danger}}` `{{shape: 7 kind=diamond style=tint color=danger}}` `{{shape: 7 kind=diamond style=outline color=danger}}`

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
color: success
---
label: Open blockers
value: 3
max: 10
color: danger
---
label: Docs updated
value: 5
max: 9
color: warning
```

<!-- column -->

<!-- card style=accent bar=top color=warning fill=soft -->
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
<!-- end-card -->

<!-- end-columns -->

## Launch steps

Step numbers in card headings, with the `shape` shortcode:

<!-- columns -->
<!-- card style=accent bar=top -->
### `{{shape: 1}}` Freeze
Code freeze on Friday; only blockers land after it.
<!-- end-card -->
<!-- column -->
<!-- card style=accent bar=top color=info -->
### `{{shape: 2 color=info}}` Test
Beta group for a week, crash-free above 99.5%.
<!-- end-card -->
<!-- column -->
<!-- card style=accent bar=top color=success -->
### `{{shape: 3 color=success}}` Ship
Publish the release and the appcast.
<!-- end-card -->
<!-- end-columns -->

Card styles and shapes have their own sample: [Layout](layout.md#cards).

This block is missing its `value`, so it stays a plain code block:

```stat
label: Broken tile
```
