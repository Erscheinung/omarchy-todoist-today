.pragma library

var colorMap = {
  "berry_red": "#b8255f",
  "red": "#db4035",
  "orange": "#ff9933",
  "yellow": "#fad000",
  "olive_green": "#afb83b",
  "lime_green": "#7ecc49",
  "green": "#299438",
  "mint_green": "#6accbc",
  "teal": "#158fad",
  "sky_blue": "#14aaf5",
  "light_blue": "#96c3eb",
  "blue": "#4073ff",
  "grape": "#884dff",
  "violet": "#af38eb",
  "lavender": "#eb96eb",
  "magenta": "#e05194",
  "salmon": "#ff8d85",
  "charcoal": "#808080",
  "grey": "#b8b8b8",
  "taupe": "#ccac93"
}

function projectColor(name, fallback) {
  return colorMap[String(name || "")] || fallback
}

function priorityColor(priority, fallback, urgent) {
  var p = Number(priority) || 1
  if (p >= 4) return urgent
  if (p === 3) return "#f2994a"
  if (p === 2) return "#4073ff"
  return fallback
}

function dueDate(task) {
  if (!task || !task.due || !task.due.date) return null
  var raw = String(task.due.date)
  if (raw.indexOf("T") < 0) return null
  var parsed = new Date(raw)
  return isNaN(parsed.getTime()) ? null : parsed
}

function durationMinutes(task) {
  if (!task || !task.duration) return 30
  var amount = Number(task.duration.amount)
  if (!isFinite(amount) || amount <= 0) return 30
  if (String(task.duration.unit) === "day") return amount * 24 * 60
  return amount
}

function minuteOfDay(date) {
  return date.getHours() * 60 + date.getMinutes()
}

function sortTasks(tasks) {
  var result = (tasks || []).slice()
  result.sort(function(a, b) {
    var ad = dueDate(a)
    var bd = dueDate(b)
    if (ad && bd) {
      var delta = ad.getTime() - bd.getTime()
      if (delta !== 0) return delta
    } else if (ad) return -1
    else if (bd) return 1

    var ao = Number(a.day_order) || 0
    var bo = Number(b.day_order) || 0
    if (ao !== bo) return ao - bo
    return String(a.content || "").localeCompare(String(b.content || ""))
  })
  return result
}

function allDayTasks(tasks) {
  return sortTasks(tasks).filter(function(task) { return dueDate(task) === null })
}

function timedTasks(tasks) {
  return sortTasks(tasks).filter(function(task) { return dueDate(task) !== null })
}

function calendarBounds(tasks, currentHour) {
  var nowHour = Math.max(0, Math.min(23, Number(currentHour) || 0))
  var timed = timedTasks(tasks)
  if (timed.length === 0) {
    return {
      startHour: Math.min(7, nowHour),
      endHour: Math.max(21, nowHour + 1)
    }
  }

  var earliest = 24 * 60
  var latest = 0
  for (var i = 0; i < timed.length; i++) {
    var start = minuteOfDay(dueDate(timed[i]))
    earliest = Math.min(earliest, start)
    latest = Math.max(latest, start + durationMinutes(timed[i]))
  }
  return {
    startHour: Math.max(0, Math.min(7, nowHour, Math.floor(earliest / 60))),
    endHour: Math.min(24, Math.max(21, nowHour + 1, Math.ceil(latest / 60)))
  }
}

// Assign overlapping events to lanes so cards remain readable on the day rail.
function layout(tasks, startHour) {
  var timed = timedTasks(tasks)
  var output = []
  var cluster = []
  var clusterEnd = -1
  var laneEnds = []

  function finishCluster() {
    var count = laneEnds.length
    for (var n = 0; n < cluster.length; n++) cluster[n].laneCount = Math.max(1, count)
    cluster = []
    laneEnds = []
    clusterEnd = -1
  }

  for (var i = 0; i < timed.length; i++) {
    var task = timed[i]
    var date = dueDate(task)
    var start = minuteOfDay(date)
    var duration = Math.max(20, Math.min(240, durationMinutes(task)))
    var end = start + duration

    if (cluster.length > 0 && start >= clusterEnd) finishCluster()

    var lane = 0
    while (lane < laneEnds.length && laneEnds[lane] > start) lane++
    if (lane === laneEnds.length) laneEnds.push(end)
    else laneEnds[lane] = end

    var item = {}
    for (var key in task) item[key] = task[key]
    item.startMinute = start
    item.durationMinutes = duration
    item.offsetMinutes = start - startHour * 60
    item.lane = lane
    item.laneCount = 1
    item.timeText = Qt.formatTime(date, "HH:mm")
    item.endTimeText = Qt.formatTime(new Date(date.getTime() + duration * 60000), "HH:mm")
    output.push(item)
    cluster.push(item)
    clusterEnd = Math.max(clusterEnd, end)
  }
  finishCluster()
  return output
}
