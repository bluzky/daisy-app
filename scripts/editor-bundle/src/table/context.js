// Pending native context-menu request for a table cell. ES module bindings
// are read-only for importers, so the mutable state lives on one object.
export const tableContext = { nextToken: 1, pending: null }
