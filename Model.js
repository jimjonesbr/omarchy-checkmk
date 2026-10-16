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

function metricValue(m) {
  return formatNumber(m.value) + (m.unit || "")
}

function metricLevels(m) {
  if (!m.warn && !m.crit) return ""
  return "warn " + (m.warn || "-") + " · crit " + (m.crit || "-")
}
