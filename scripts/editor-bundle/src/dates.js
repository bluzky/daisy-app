// Calendar dates as `YYYY-MM-DD` strings in local time. Task dates name a day,
// not an instant, so arithmetic works on local year/month/day and never on
// UTC milliseconds (which would drift across daylight-saving changes).

const pad = (value, width = 2) => String(value).padStart(width, "0")

export const formatLocalDate = (date) =>
  `${pad(date.getFullYear(), 4)}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`

function localDate(year, month, day) {
  const date = new Date(2000, 0, 1)
  date.setFullYear(year, month, day)
  return date
}

// The local Date for a `YYYY-MM-DD` string, or null when it is not a real day.
export function parseLocalDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || "")
  if (!match) return null
  const [year, month, day] = [Number(match[1]), Number(match[2]) - 1, Number(match[3])]
  const date = localDate(year, month, day)
  return date.getFullYear() === year && date.getMonth() === month && date.getDate() === day ? date : null
}

export function addDays(value, days) {
  const date = parseLocalDate(value)
  return formatLocalDate(localDate(date.getFullYear(), date.getMonth(), date.getDate() + days))
}

// Same day in another month, clamped to that month's last day.
export function addMonths(value, months) {
  const date = parseLocalDate(value)
  const first = localDate(date.getFullYear(), date.getMonth() + months, 1)
  const last = localDate(first.getFullYear(), first.getMonth() + 1, 0).getDate()
  return formatLocalDate(localDate(first.getFullYear(), first.getMonth(), Math.min(date.getDate(), last)))
}
