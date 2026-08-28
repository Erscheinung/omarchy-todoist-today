.pragma library

// Todoist Quick Add syntax recognition and completion.  This deliberately
// recognizes syntax without interpreting dates: td/Todoist remains the source
// of truth for the actual date calculation.

var COMPLETIONS = [
  "today", "today at 09:00", "tomorrow", "tomorrow at 09:00",
  "tom morning", "tom afternoon", "tom evening", "tom night",
  "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
  "next monday", "next tuesday", "next wednesday", "next thursday",
  "next friday", "next saturday", "next sunday",
  "next week", "next month", "next year", "next weekend", "this weekend",
  "later this week", "someday", "no date", "no due date",
  "in the morning", "in the afternoon", "in the evening",
  "in 2 hours", "in 3 days", "in 2 weeks",
  "every day", "every weekday", "every workday", "every week",
  "every weekend", "every month", "every quarter", "every year",
  "every monday", "every tuesday", "every wednesday", "every thursday",
  "every friday", "every saturday", "every sunday",
  "every other day", "every other week", "every other month",
  "every! 3 hours", "every! 2 weeks", "daily", "weekly", "monthly",
  "quarterly", "yearly", "starting ", "starting at ", "from ",
  "ending ", "until ", "at 09:00", "for 15m", "for 30m", "for 1h",
  "for 1h30m", "!30 min before", "!1 hour before"
]

function addMatches(output, text, regex, kind) {
  regex.lastIndex = 0
  var match
  while ((match = regex.exec(text)) !== null) {
    var value = match[1] || match[0]
    var offset = match[0].indexOf(value)
    output.push({ start: match.index + offset, end: match.index + offset + value.length, kind: kind })
    if (match[0].length === 0) regex.lastIndex++
  }
}

function highlights(text) {
  text = String(text || "")
  var found = []

  // Explicit Quick Add actions.
  addMatches(found, text, /(?:^|\s)(p[1-4])(?=\s|$)/gi, "priority")
  addMatches(found, text, /(?:^|\s)(#[^\s]+(?:\\\s[^\s]+)*)/g, "project")
  addMatches(found, text, /(?:^|\s)(%[^\s]+|@[^\s]+)(?=\s|$)/g, "label")
  addMatches(found, text, /(?:^|\s)(\+[A-Za-z][^\s]*)(?=\s|$)/g, "assignee")
  addMatches(found, text, /(?:^|\s)(\/[A-Za-z][^\s]*)(?=\s|$)/g, "section")
  addMatches(found, text, /(?:^|\s)(!(?:\d{1,2}:\d{2}|\d+\s*(?:min(?:ute)?s?|hours?|days?)\s+before))(?=\s|$)/gi, "reminder")
  addMatches(found, text, /(\{[^{}]+\})/g, "deadline")

  // Duration must use compact h/m units, and may combine them (1h15m).
  addMatches(found, text, /(?:^|\s)(for\s+(?:(?:\d+(?:\.\d+)?h)(?:\d+m)?|\d+m))(?=\s|$)/gi, "duration")

  // Recurrences, including start/end limits. Prefer the whole expression so
  // "every day from 10 May until 20 May" is presented as one Todoist token.
  addMatches(found, text,
    /(?:^|\s)((?:(?:every!?|ev)\s+(?:(?:other\s+)?(?:\d+(?:st|nd|rd|th)?\s+)?(?:hours?|days?|weeks?|weekdays?|workdays?|weekends?|months?|quarters?|years?|mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)(?:\s*,\s*(?:mon|tue|wed|thu|fri|sat|sun)(?:day)?)*)|daily|weekly|monthly|quarterly|yearly)(?:\s+(?:at\s+)?(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)?|noon))?(?:\s+(?:starting(?:\s+(?:on|from|at))?|from)\s+[^{}]+?)?(?:\s+(?:and\s+)?(?:ending|until)\s+[^{}]+?)?(?:\s+for\s+\d+\s+(?:days?|weeks?|months?|years?))?)(?=\s+(?:p[1-4]|[#%@+!/]|for\s+\d+(?:h|m))|$)/gi,
    "recurring")

  // Common one-time dates and time phrases documented by Todoist.
  addMatches(found, text,
    /(?:^|\s)((?:tod(?:ay)?|tom(?:orrow)?)(?:\s*(?:morning|afternoon|evening|night)|\s+(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm)?)?)(?=\s|$)/gi, "date")
  addMatches(found, text,
    /(?:^|\s)((?:(?:next|this)\s+(?:week|month|year|weekend|mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)|later\s+this\s+week|end\s+of\s+month|mid\s+[A-Za-z]+|someday|no\s+(?:due\s+)?date))(?!\w)/gi, "date")
  addMatches(found, text,
    /(?:^|\s)((?:in\s+|\+\s*)\d+\s+(?:hours?|days?|weeks?|months?|years?)|in\s+the\s+(?:morning|afternoon|evening))(?=\s|$)/gi, "date")
  addMatches(found, text,
    /(?:^|\s)((?:(?:mon|tue|wed|thu|fri|sat|sun)(?:day)?\s+)?(?:\d{1,2}(?::\d{2})\s*(?:am|pm)?|\d{1,2}\s*(?:am|pm)))(?=\s|$)/gi, "time")
  addMatches(found, text,
    /(?:^|\s)((?:(?:\d{1,2}(?:st|nd|rd|th)?\s+)?[A-Za-z]{3,9}\s+\d{1,2}(?:st|nd|rd|th)?|\d{1,2}(?:st|nd|rd|th)?(?:\s+[A-Za-z]{3,9})?|\d{1,4}[\/-]\d{1,2}(?:[\/-]\d{1,4})?))(?=\s|$)/gi, "date")

  // Resolve overlaps in favor of the longest match, then return display order.
  found.sort(function(a, b) {
    var lengthDiff = (b.end - b.start) - (a.end - a.start)
    return lengthDiff !== 0 ? lengthDiff : a.start - b.start
  })
  var accepted = []
  for (var i = 0; i < found.length; i++) {
    var overlaps = false
    for (var j = 0; j < accepted.length; j++)
      if (found[i].start < accepted[j].end && found[i].end > accepted[j].start) overlaps = true
    if (!overlaps) accepted.push(found[i])
  }
  accepted.sort(function(a, b) { return a.start - b.start })
  return accepted
}

function completions(text, cursor) {
  var before = String(text || "").slice(0, cursor)
  // Complete up to four trailing words. Requiring two characters prevents a
  // normal one-letter task word from opening the menu.
  var tail = before.match(/(?:^|\s)([^\s]+(?:\s+[^\s]+){0,3})$/)
  if (!tail) return { start: cursor, items: [] }
  var phrase = tail[1]
  var lower = phrase.toLowerCase()
  var bestStart = cursor - phrase.length
  var items = []
  for (var words = phrase.split(/\s+/); words.length > 0; words.shift()) {
    var query = words.join(" ").toLowerCase()
    if (query.length >= 2) {
      var candidateStart = cursor - words.join(" ").length
      for (var i = 0; i < COMPLETIONS.length; i++) {
        var candidate = COMPLETIONS[i]
        if (candidate.toLowerCase().indexOf(query) === 0 && candidate.toLowerCase() !== query)
          items.push({ value: candidate, label: candidate, kind: "date", start: candidateStart })
        if (items.length >= 8) break
      }
      if (items.length > 0) { bestStart = candidateStart; break }
    }
  }
  return { start: bestStart, items: items }
}
