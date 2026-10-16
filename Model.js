.pragma library

var NAMES = ["OK", "WARN", "CRIT", "UNKN"]

// Checkmk orders states OK < WARN < UNKNOWN < CRIT
function severity(state) {
  return [0, 1, 3, 2][state] || 0
}

function stateName(state) {
  return NAMES[state] || "?"
}

// okColor defaults to the foreground, so OK stays unobtrusive in the bar
function stateColor(state, foreground, urgent, okColor) {
  if (state === 2) return urgent
  if (state === 1) return "#e5c07b"
  if (state === 3) return "#d19a66"
  return okColor || foreground
}

var OK_COLOR = "#98c379"

function parseStatus(text) {
  try {
    var status = JSON.parse(text)
    if (!status || typeof status !== "object") return null
    // Before the first successful poll there are no services yet
    if (!Array.isArray(status.services)) status.services = []
    if (!Array.isArray(status.hosts)) status.hosts = []
    if (!Array.isArray(status.servers)) status.servers = []
    // Status files of the single server version know nothing about reachability
    if (status.reachable === undefined) status.reachable = status.ok === true
    if (!status.counts) status.counts = { ok: 0, warn: 0, crit: 0, unknown: 0, unhandled: 0 }
    return status
  } catch (e) {}
  return null
}

// "45s", "12m", "3h 20m", "2d 4h"
function age(seconds) {
  seconds = Math.max(0, Math.floor(seconds))
  if (seconds < 60) return seconds + "s"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h" + (minutes % 60 ? " " + (minutes % 60) + "m" : "")
  var days = Math.floor(hours / 24)
  return days + "d" + (hours % 24 ? " " + (hours % 24) + "h" : "")
}

function problems(services, includeHandled) {
  return services.filter(function(s) {
    return s.state !== 0 && (includeHandled || !s.handled)
  })
}

function summary(status) {
  if (!status) return "Checkmk: no data yet"
  var c = status.counts || {}
  var parts = []
  if (c.crit) parts.push(c.crit + " CRIT")
  if (c.unknown) parts.push(c.unknown + " UNKNOWN")
  if (c.warn) parts.push(c.warn + " WARN")
  var text = parts.length ? parts.join(", ") : "All " + (c.ok || 0) + " services OK"
  var down = status.servers.filter(function(s) { return !s.ok }).map(function(s) { return s.name })
  if (!status.reachable) text = "Checkmk unreachable: " + status.error + "\nLast known: " + text
  else if (down.length) text += "\nUnreachable: " + down.join(", ")
  return text
}

function hostServices(services, server, host) {
  return services.filter(function(s) { return s.server === server && s.host === host && !s.isHost })
}

// An empty server matches the first host of that name on any server
function findHost(hosts, server, name) {
  for (var i = 0; i < hosts.length; i++)
    if (hosts[i].host === name && (!server || hosts[i].server === server)) return hosts[i]
  return null
}

// Configured servers joined with their state from the last poll
function serverRows(configured, polled) {
  return configured.map(function(c) {
    var live = null
    for (var i = 0; i < polled.length; i++) if (polled[i].id === c.id) live = polled[i]
    return {
      id: c.id, name: c.name, url: c.url, user: c.user,
      polled: !!live,
      ok: live ? live.ok : false,
      error: live ? live.error : "",
      hosts: live ? live.hosts : 0,
      counts: live ? live.counts : null
    }
  })
}

// Non-zero counts of a host, worst first: [{state, count}]
function hostCounts(host) {
  var c = host.counts || {}
  return [{ state: 2, count: c.crit }, { state: 3, count: c.unknown }, { state: 1, count: c.warn }, { state: 0, count: c.ok }]
    .filter(function(e) { return e.count > 0 })
}

function formatNumber(value) {
  if (Math.abs(value) >= 1000000) return (value / 1000000).toFixed(2).replace(/\.?0+$/, "") + "M"
  if (Math.abs(value) >= 10000) return (value / 1000).toFixed(1).replace(/\.0$/, "") + "k"
  return Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/\.?0+$/, "")
}

// Labels and units for common metrics; anything else gets a cleaned up name
var METRICS = {
  mem_used_percent: { label: "Memory used", unit: "%" },
  mem_used: { label: "Memory used", unit: "B" },
  swap_used: { label: "Swap used", unit: "B" },
  fs_used_percent: { label: "Filesystem used", unit: "%" },
  fs_used: { label: "Filesystem used", unit: "B" },
  fs_size: { label: "Filesystem size", unit: "B" },
  load1: { label: "Load 1 min" },
  load5: { label: "Load 5 min" },
  load15: { label: "Load 15 min" },
  util: { label: "CPU utilization", unit: "%" },
  user: { label: "CPU user", unit: "%" },
  system: { label: "CPU system", unit: "%" },
  io_wait: { label: "CPU I/O wait", unit: "%" },
  in: { label: "Receiving", unit: "B/s" },
  out: { label: "Sending", unit: "B/s" },
  if_in_bps: { label: "Receiving", unit: "bit/s" },
  if_out_bps: { label: "Sending", unit: "bit/s" },
  response_time: { label: "Response time", unit: "s" },
  execution_time: { label: "Execution time", unit: "s" },
  user_time: { label: "User time", unit: "s" },
  system_time: { label: "System time", unit: "s" },
  uptime: { label: "Uptime", unit: "s" },
  days_left: { label: "Days left" },
  replay_lag: { label: "Replay lag", unit: "s" },
  "total_connections%": { label: "Connections used", unit: "%" },
  total: { label: "Connections" },
  idle_connections: { label: "Idle" },
  idle_transaction: { label: "Idle in transaction" },
  active: { label: "Active" },
  internal: { label: "Internal" }
}

function metricLabel(m) {
  var known = METRICS[m.name]
  if (known) return known.label
  var label = m.name.replace(/%$/, "").replace(/_percent$/, "").replace(/[_.]+/g, " ").trim()
  return label.charAt(0).toUpperCase() + label.slice(1)
}

function metricUnit(m) {
  if (m.unit) return m.unit
  var known = METRICS[m.name]
  if (known && known.unit) return known.unit
  return /%$|_percent$/.test(m.name) ? "%" : ""
}

function scaled(value, base, units) {
  var i = 0
  while (Math.abs(value) >= base && i < units.length - 1) { value /= base; i++ }
  return formatNumber(value) + " " + units[i]
}

function formatValue(value, unit) {
  if (unit === "%") return formatNumber(value) + "%"
  if (unit === "s" || unit === "ms") {
    var seconds = unit === "ms" ? value / 1000 : value
    if (seconds < 1) return formatNumber(seconds * 1000) + " ms"
    if (seconds < 60) return formatNumber(seconds) + " s"
    return age(seconds)
  }
  if (unit === "B") return scaled(value, 1024, ["B", "KiB", "MiB", "GiB", "TiB"])
  if (unit === "B/s") return scaled(value, 1000, ["B/s", "kB/s", "MB/s", "GB/s"])
  if (unit === "bit/s") return scaled(value, 1000, ["bit/s", "kbit/s", "Mbit/s", "Gbit/s"])
  return formatNumber(value) + (unit ? (unit.length > 1 ? " " : "") + unit : "")
}

function metricValue(m) {
  return formatValue(m.value, metricUnit(m))
}

// 0, 1 or 2 by the levels of the metric. Levels where crit lies below warn are
// lower levels, e.g. days left of a certificate.
function metricState(m) {
  var warn = parseFloat(m.warn), crit = parseFloat(m.crit)
  if (isNaN(warn) && isNaN(crit)) return 0
  var lower = !isNaN(warn) && !isNaN(crit) && crit < warn
  if (lower) return m.value <= crit ? 2 : (m.value <= warn ? 1 : 0)
  if (!isNaN(crit) && m.value >= crit) return 2
  if (!isNaN(warn) && m.value >= warn) return 1
  return 0
}

function metricLevels(m) {
  var unit = metricUnit(m)
  var warn = parseFloat(m.warn), crit = parseFloat(m.crit)
  var parts = []
  if (!isNaN(warn)) parts.push("warn at " + formatValue(warn, unit))
  if (!isNaN(crit)) parts.push("crit at " + formatValue(crit, unit))
  return parts.join(" · ")
}

// Full text of an expanded service: the summary plus the long output. Checkmk keeps
// the first line of a multi-line output in the summary only, and appends
// "Mem used percent: 93.70" for each metric of a local check, which the metrics
// grid shows already.
function detailsText(service) {
  // "load1" is written "Load 1", "total_connections%" "Total connections%"
  function key(name) { return name.toLowerCase().replace(/[^a-z0-9]/g, "") }
  var names = (service.metrics || []).map(function(m) { return key(m.name) })
  var details = String(service.details || "").split("\n").filter(function(line) {
    var match = /^(.+?): -?[0-9.]+$/.exec(line.trim())
    return !match || names.indexOf(key(match[1])) === -1
  }).join("\n").trim()
  var summary = String(service.output || "")
  if (!details || details.indexOf(summary) === 0) return details || summary
  return summary + "\n" + details
}
