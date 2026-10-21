// Task fields recognized on a checkbox task's marker line. The extractor
// parses with these definitions and the slash commands validate with them, so
// a value a command writes is always one the extractor reads back.
//
// No CodeMirror or DOM dependency: this is bundled into the native extractor.

export const TASK_DATE_KEYS = ["due", "scheduled"];
export const PRIORITY_KEY = "p";
export const PRIORITY_VALUES = ["high", "medium", "low"];

// A valid Gregorian calendar date written `YYYY-MM-DD`, years 0001–9999 as
// Swift's `JournalDay` accepts: the index cache rejects anything else on load.
export function isTaskDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  if (year < 1) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCFullYear(year);
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

export function isTaskFieldValue(key, value) {
  if (key === PRIORITY_KEY) return PRIORITY_VALUES.includes(value);
  return TASK_DATE_KEYS.includes(key) && isTaskDate(value);
}
