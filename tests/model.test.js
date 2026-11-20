// Tests of Model.js, the logic of the panel and the bar icon.
//
//   node --test tests/
//
// Model.js is a QML JavaScript library: it is loaded the way QML sees it, in a
// sandbox of its own, without the ".pragma library" line node does not know.

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const M = vm.createContext({})
vm.runInContext(source, M)

// Arrays and objects from the sandbox have its prototypes: compare plain copies
function same(actual, expected) {
  assert.deepEqual(JSON.parse(JSON.stringify(actual)), expected)
}

function service(fields) {
  return Object.assign({ server: "prod", serverName: "Production", host: "db01", service: "CPU", state: 0,
    handled: false, isHost: false }, fields)
}

test("severity orders OK < WARN < UNKNOWN < CRIT, as Checkmk does", () => {
  const order = [0, 1, 2, 3].sort((a, b) => M.severity(a) - M.severity(b))
  same(order, [0, 1, 3, 2])
})

test("state colours are fixed, OK falls back to the foreground", () => {
  assert.equal(M.stateColor(2, "#fff"), M.CRIT_COLOR)
  assert.equal(M.stateColor(1, "#fff"), M.WARN_COLOR)
  assert.equal(M.stateColor(3, "#fff"), M.UNKNOWN_COLOR)
  assert.equal(M.stateColor(0, "#fff"), "#fff")
  assert.equal(M.stateColor(0, "#fff", M.OK_COLOR), M.OK_COLOR)
})

test("parseStatus rejects garbage and fills in what older status files lack", () => {
  assert.equal(M.parseStatus("not json"), null)
  assert.equal(M.parseStatus("42"), null)
  const status = M.parseStatus('{"ok": true}')
  same(status.services, [])
  same(status.hosts, [])
  same(status.servers, [])
  assert.equal(status.reachable, true)
  assert.equal(status.counts.unhandled, 0)
})

test("age reads like 45s, 12m, 3h 20m, 2d 4h", () => {
  assert.equal(M.age(45), "45s")
  assert.equal(M.age(12 * 60), "12m")
  assert.equal(M.age(3 * 3600 + 20 * 60), "3h 20m")
  assert.equal(M.age(3 * 3600), "3h")
  assert.equal(M.age(2 * 86400 + 4 * 3600), "2d 4h")
  assert.equal(M.age(-5), "0s")
})

test("timingText tells when a service was checked, and cached or overdue data", () => {
  const now = 1000
  assert.equal(M.timingText({}, now), "")
  assert.equal(M.timingText({ checked: 960, interval: 60 }, now), "Checked 40s ago · every 1m")
  assert.equal(M.timingText({ checked: 820, interval: 300, cached: true }, now), "Data from 3m ago · every 5m, cached")
  assert.equal(M.timingText({ checked: 700, interval: 60, overdue: true }, now), "Checked 5m ago · every 1m · overdue")
})

test("problems leave out OK services, and handled ones unless asked for", () => {
  const list = [service({ state: 0 }), service({ state: 2 }), service({ state: 1, handled: true })]
  assert.equal(M.problems(list, false).length, 1)
  assert.equal(M.problems(list, true).length, 2)
  assert.equal(M.byState(list, 2).length, 1)
  assert.equal(M.byState(list, -1).length, 3)
})

test("summary names the problems, unreachable and locked servers", () => {
  assert.equal(M.summary(null), "Checkmk: no data yet")
  assert.equal(M.summary(M.parseStatus('{"disconnected": true}')), "Checkmk: all servers disconnected")
  const ok = M.parseStatus('{"reachable": true, "counts": {"ok": 7}, "servers": [{"name": "A", "ok": true}]}')
  assert.equal(M.summary(ok), "All 7 services OK")
  const bad = M.parseStatus(JSON.stringify({ reachable: true, counts: { crit: 2, warn: 1 },
    servers: [{ name: "A", ok: true }, { name: "B", ok: false }, { name: "C", ok: false, locked: true }] }))
  assert.equal(M.summary(bad), "2 CRIT, 1 WARN\nUnreachable: B\nLocked: C")
  const locked = M.parseStatus('{"reachable": false, "servers": [{"name": "A", "ok": false, "locked": true}]}')
  assert.equal(M.summary(locked), "Checkmk locked: click to unlock")
})

test("groupByHost keeps each host together, the one with the worst problem first", () => {
  // As the poller sorts them: worst first
  const sorted = [
    service({ host: "db03", service: "Memory", state: 2 }),
    service({ host: "web01", service: "Disk", state: 2 }),
    service({ host: "db03", service: "Disk", state: 1 }),
    service({ host: "db04", service: "Replication", state: 1 }),
    service({ server: "stg", host: "db03", service: "CPU", state: 1 }),
  ]
  const grouped = M.groupByHost(sorted).map(s => s.server + "/" + s.host + " " + s.service)
  same(grouped, [
    "prod/db03 Memory", "prod/db03 Disk",
    "prod/web01 Disk",
    "prod/db04 Replication",
    // A host of the same name on another server is a host of its own
    "stg/db03 CPU",
  ])
  same(M.groupByHost([]), [])
})

test("serverRows joins the configured servers with the last poll", () => {
  const configured = [
    { id: "a", name: "A", url: "u", user: "x", secretStore: "session", unlocked: true, expires: "7h" },
    { id: "b", name: "B", url: "u", user: "x", disconnected: true, muted: true, remember: false },
  ]
  const polled = [{ id: "a", ok: false, locked: true, error: "Locked", hosts: 0 }]
  const rows = M.serverRows(configured, polled)
  assert.equal(rows[0].polled, true)
  assert.equal(rows[0].locked, true)
  assert.equal(rows[0].remember, true)
  assert.equal(rows[1].polled, false)
  assert.equal(rows[1].disconnected, true)
  assert.equal(rows[1].muted, true)
  assert.equal(rows[1].remember, false)
})

test("hostCounts lists the non-zero counts, worst first", () => {
  const counts = M.hostCounts({ counts: { ok: 3, warn: 1, crit: 0, unknown: 2 } })
  same(counts.map(c => c.state + ":" + c.count), ["3:2", "1:1", "0:3"])
})

test("metric values get their unit and a readable size", () => {
  assert.equal(M.formatNumber(1234567), "1.23M")
  assert.equal(M.formatNumber(12345), "12.3k")
  assert.equal(M.formatNumber(2.5), "2.5")
  assert.equal(M.formatValue(93.7, "%"), "93.7%")
  assert.equal(M.formatValue(0.25, "s"), "250 ms")
  assert.equal(M.formatValue(3 * 1024 * 1024 * 1024, "B"), "3 GiB")
  assert.equal(M.formatValue(1500, "bit/s"), "1.5 kbit/s")
  assert.equal(M.metricLabel({ name: "load1" }), "Load 1 min")
  assert.equal(M.metricLabel({ name: "total_connections%" }), "Connections used")
  assert.equal(M.metricLabel({ name: "replay_lag_seconds" }), "Replay lag seconds")
  assert.equal(M.metricUnit({ name: "fs_used_percent" }), "%")
  assert.equal(M.metricUnit({ name: "cpu", unit: "ms" }), "ms")
})

test("metricState reads upper and lower levels", () => {
  assert.equal(M.metricState({ value: 95, warn: "80", crit: "90" }), 2)
  assert.equal(M.metricState({ value: 85, warn: "80", crit: "90" }), 1)
  assert.equal(M.metricState({ value: 50, warn: "80", crit: "90" }), 0)
  // Crit below warn: lower levels, e.g. days left of a certificate
  assert.equal(M.metricState({ value: 3, warn: "30", crit: "7" }), 2)
  assert.equal(M.metricState({ value: 20, warn: "30", crit: "7" }), 1)
  assert.equal(M.metricState({ value: 5, warn: "", crit: "" }), 0)
})

test("detailsText drops the metric lines the metrics grid shows already", () => {
  const s = { output: "RAM used: 93.7%", details: "RAM used: 93.7%\nMem used percent: 93.70\nSwap: none",
    metrics: [{ name: "mem_used_percent" }] }
  assert.equal(M.detailsText(s), "RAM used: 93.7%\nSwap: none")
  assert.equal(M.detailsText({ output: "All fine", details: "" }), "All fine")
})
