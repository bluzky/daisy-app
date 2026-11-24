---
slides: true
theme: midnight
paginate: true
font_size: 80%
title: Q3 Business Review
footer: "{title}"
---

# Q3 Business Review

Revenue, growth and delivery · October 2026

???
Welcome. Twenty minutes: where we landed, what grew, what shipped, and what we commit to next quarter.

---

## Q3 at a glance

```stat
label: Revenue
value: $48.2k
color: success
delta: +12%
trend: up
note: vs Q2
---
label: Active users
value: 3,204
delta: +18%
trend: up
---
label: Churn
value: 2.1%
delta: -0.4%
trend: down
good: down
---
label: NPS
value: 54
delta: +6
trend: up
```

```badge
text: Revenue on plan
color: success
---
text: Hiring behind
color: warning
---
text: Notarization flaky
color: danger
```

???
Four numbers to remember. Revenue, users and NPS all up; churn down, which is the direction we want.
The badges are the honest part: hiring is behind plan and notarization keeps failing in CI.

---

## Revenue grew 12% on Pro upgrades

<!-- card style=accent color=success -->
```chart
type: bar
title: Monthly revenue (k$)
height: 230
colors: #6366F1, #22C55E
grid: false
legend:
  position: top
| Month | 2025 | 2026 |
| ----- | ---- | ---- |
| Jul   | 12   | 14   |
| Aug   | 13   | 16   |
| Sep   | 15   | 18   |
```
<!-- end-card -->

<!-- column -->

<!-- card style=filled color=success padding=compact -->
### What moved it

- Annual Pro plan launched in July
- 41 teams upgraded from Free
- No price change

<!-- end-card -->

???
Every month of Q3 beat the same month last year. The jump is upgrades, not new pricing.
The annual plan did most of the work: 41 teams moved from Free to Pro.

---

## Growth

---

## Signups doubled since July

```chart
type: line
title: Weekly signups
height: 300
grid: false
colors: #22D3EE, #A78BFA
legend:
  position: right
| Week | Organic | Paid |
| ---- | ------- | ---- |
| W27  | 80      | 30   |
| W29  | 104     | 38   |
| W31  | 121     | 47   |
| W33  | 138     | 55   |
| W35  | 152     | 61   |
| W37  | 171     | 66   |
```

???
Organic is the story: it more than doubled while paid grew steadily.
The template gallery and the Quick Look extension both landed in W31, right where the organic curve bends.

---

## Pro brings in two thirds of revenue

<!-- card align=center -->
```chart
type: donut
title: Revenue by plan (k$)
height: 260
colors: #64748B, #6366F1, #F59E0B
legend:
  position: right
| Plan       | Revenue |
| ---------- | ------- |
| Free       | 3       |
| Pro        | 32      |
| Enterprise | 13      |
```
<!-- end-card -->

<!-- column -->

<!-- card style=accent edge=top color=warning -->
### Enterprise is the next lever

- 4 pilots running
- 2 contracts in legal
- Average deal 6× Pro

<!-- end-card -->

???
Free costs us little but feeds Pro. Enterprise is small today, but each deal is worth six Pro teams, so that is where Q4 sales time goes.

---

## Two of three goals on track

<!-- card align=center padding=compact -->
```chart
type: donut
title: Revenue
height: 150
values: false
colors: #22C55E, #334155
legend: none
| Part      | k$ |
| --------- | -- |
| Reached   | 92 |
| Remaining | 8  |
```

**92%** of $52k
<!-- end-card -->

<!-- column -->

<!-- card align=center padding=compact -->
```chart
type: donut
title: Onboarding
height: 150
values: false
colors: #6366F1, #334155
legend: none
| Part      | % |
| --------- | - |
| Done      | 81 |
| Remaining | 19 |
```

**81%** of new teams
<!-- end-card -->

<!-- column -->

<!-- card align=center padding=compact style=accent color=danger -->
```chart
type: donut
title: Support SLA
height: 150
values: false
colors: #F43F5E, #334155
legend: none
| Part   | % |
| ------ | - |
| In SLA | 68 |
| Late   | 32 |
```

**68%** against 90%
<!-- end-card -->

???
Revenue and onboarding are close to target. Support SLA is the miss, and the next section explains why.

---

## Delivery

---

## Release 4.2 is nearly done

<!-- card style=accent color=accent -->
```progress
label: Features
value: 9
max: 12
striped: true
---
label: Tests
value: 184
max: 190
color: success
---
label: Docs
value: 5
max: 9
color: warning
---
label: Blockers
value: 2
max: 10
color: danger
```
<!-- end-card -->

<!-- column -->

```stat
label: Days to release
value: 9
note: Code freeze on Friday
```

```badge
text: Beta feedback in
color: success
---
text: Docs behind
color: warning
```

???
Nine of twelve features are in; the striped bar is the work still moving.
Docs are the risk to the date, not code. Two blockers left, both with owners.

---

## Support load shifted to questions

```chart
type: bar
title: Tickets by week
height: 230
stacked: true
grid: false
colors: #F43F5E, #6366F1, #22C55E
legend:
  position: top
| Week | Bugs | Questions | Requests |
| ---- | ---- | --------- | -------- |
| W33  | 14   | 22        | 6        |
| W35  | 11   | 25        | 9        |
| W37  | 9    | 29        | 7        |
| W39  | 8    | 31        | 12       |
```

<!-- column -->

```chart
type: bar
title: Open tickets by team
height: 230
stacked: true
direction: horizontal
grid: false
colors: #F59E0B, #6366F1, #22C55E
legend:
  position: top
x-axis:
  visible: false
| Team     | Open | Review | Closed |
| -------- | ---- | ------ | ------ |
| Platform | 12   | 6      | 30     |
| Mobile   | 8    | 4      | 22     |
| Web      | 15   | 9      | 18     |
```

???
Bugs fell every week. Questions rose, which is why SLA slipped: the team is answering how-to questions, not fixing defects.
That points at docs and onboarding, not engineering.

---

## Q4 commitments

<!-- card style=accent edge=top color=success -->
### Grow

- 2 Enterprise deals
- $60k a month
<!-- end-card -->

<!-- column -->

<!-- card style=accent edge=top color=accent -->
### Ship

- 4.2 on Oct 18
- Cards in Quick Look
<!-- end-card -->

<!-- column -->

<!-- card style=accent edge=top color=warning -->
### Support

- SLA back to 90%
- Top 20 answers in docs
<!-- end-card -->

???
One owner per column. We review these three at the start of every month.

---

# Thank you

Questions? · numbers live in `samples/dashboard.md`
