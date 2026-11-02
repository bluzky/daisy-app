# Mermaid

Version: **12.2.0** (also recorded in `Mermaid-VERSION`).

`mermaid.min.js` and `LICENSE` are copied without modification from the official
[`mermaid@12.2.0` npm package](https://registry.npmjs.org/mermaid/-/mermaid-12.2.0.tgz)
(`dist/mermaid.min.js` and `LICENSE`). The package SHA-512 integrity is:

```
sha512-w7nr/SFrLO7BaVTs3dQTvYSV6nYSBj0Yy9DjBhsIJtAcHqRzXSq4Pg32ujHZ/AdWsAMNEvvhbm5dt9E2tOiHzw==
```

The app and Quick Look use this same offline renderer. Since 12.0, Mermaid
bundles the ELK layout engine and lays out flowcharts with it by default, so
no separate `@mermaid-js/layout-elk` package is needed. The block-arrow fix
from 11.15.0 ([upstream PR](https://github.com/mermaid-js/mermaid/pull/7633)),
which preserves dotted strokes and arrowheads in `block-beta` diagrams, is
still covered by `samples/mermaid-block-arrows.md` and `MermaidBlockArrowTests`
using the production HTML in WebKit.
