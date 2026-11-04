---
slides: true
---

# Daisy slides
A Markdown file shown as a deck

???
Open with View ▸ Present (⌥⌘P). Arrow keys, Space and a clicker's
Page Up/Down move between slides; Esc ends the presentation.

---

## How a deck works

- `slides: true` in the frontmatter turns a file into a deck
- `---` on its own line starts the next slide
- `???` starts the speaker notes for a slide
- The layout of each slide comes from what is on it[^layout]

???

Notes show under each slide in Read Mode and never on the presented slide.

[^layout]: Title, section, quote, code, math, image, split and columns layouts.

---

## Reveal step by step

- Arrows and Space reveal one item at a time
- Items marked with a step comment wait for a click <!-- step -->
- `step: 2` puts several items on the same click <!-- step -->

???
The steps all show in Read Mode and in a PDF.

---

## Beside a picture

![bg right fit](../docs/daisy-logo.png)

- `![bg right]` puts the image on one half
- `![bg]` alone fills the whole slide
- `fit` shows all of the image

---

## Columns

- `<!-- column -->` on its own line
- starts the next column

<!-- column -->

- The heading stays across the top
- Columns share the width equally

<!-- end-columns -->

<!-- space -->

`<!-- end-columns -->` puts the rest of the slide below the columns, and `<!-- space -->` adds an empty line.

---

## A gallery

![Daisy icon](../docs/app-icon.png)

<!-- column -->

![Read Mode](../docs/screenshot-main.png)

<!-- column -->

![Edit Mode](../docs/screenshot-edit-mode.png)

???
Images side by side are columns: each image fits inside its column.

---

# Text on a picture

`![bg dim blur](…)` darkens and blurs the image behind the text

![bg dim blur](../docs/screenshot-main.png)

---

<!-- _class: invert center -->

## Classes

`<!-- _class: invert center -->` darkens and centres this slide

---

<!-- layout: section -->

## Part two

---

> The best way to predict the future is to invent it.

---

## Code

```swift
let deck = SlideDeck(document: Document(parsing: markdown))
print(deck.slides.count)
```

---

## Math

$$
e^{i\pi} + 1 = 0
$$

---

## A diagram

```mermaid
graph LR
  Markdown --> SlideDeck --> HTML --> Slides
```

---

## Long mermaid

```mermaid
flowchart TD
    A[Client] -->|POST /orders| B(API Gateway)
    B --> C{Valid schema?}
    C -->|yes| D[Order Service]
    C -->|no| E[400 Bad Request]
    D --> F[(Orders DB)]
    D --> G[[Pricing Engine]]
    G --> H{In stock?}
    H -->|yes| I[Fulfilment Queue]
    H -->|no| J[Backorder Queue]
    I --> K[Warehouse Worker]
    J --> K
    K --> L([Shipped])
```


---
# The end

Thanks for watching.
