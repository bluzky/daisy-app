// Tag, context and project names (`#name`, `@name`, `+name`). The extractor
// reads them with these rules and the completion menu writes and matches with
// them, so a name the menu inserts is always one the extractor reads back.
//
// No CodeMirror or DOM dependency: this is bundled into the native extractor.

export const METADATA_MARKERS = { "#": "tags", "@": "contexts", "+": "projects" };

export const TOKEN_START = /[\p{L}\p{N}_-]/u;
// Combining marks (`\p{M}`) continue a token so decomposed accents and
// scripts such as Devanagari or Thai keep their whole names.
export const TOKEN_CHARACTER = /[\p{L}\p{M}\p{N}_\-/]/u;
const LETTER = /\p{L}/u;

// Lookup keys: NFKC, then lowercase. Source spelling is kept separately.
export const normalizedKey = (value) =>
  value.normalize("NFKC").toLocaleLowerCase("en-US");

// A whole name after its marker: at least one letter and no empty hierarchy
// segment. `value` must already consist of token characters.
export const isMetadataValue = (value) =>
  (!value.includes("/") || value.split("/").every(Boolean)) &&
  LETTER.test(value);

// The same check for arbitrary text, such as a name a host passes in.
export function isMetadataName(value) {
  if (typeof value !== "string" || !value) return false;
  const characters = Array.from(value);
  return (
    TOKEN_START.test(characters[0]) &&
    characters.every((character) => TOKEN_CHARACTER.test(character)) &&
    isMetadataValue(value)
  );
}
