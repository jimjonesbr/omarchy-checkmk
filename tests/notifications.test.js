// Tests of lib/notifications.jq, which decides what a poll announces.
//
//   node --test tests/
//
// Each test runs the program with jq, as checkmk-poll does, on a previous and
// a current status built here.

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const PROGRAM = path.join(__dirname, "..", "lib", "notifications.jq")
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "checkmk-notifications-"))
test.after(() => fs.rmSync(dir, { recursive: true, force: true }))

function notes(previous, current, max = 5) {
  const prev = path.join(dir, "prev.json"), cur = path.join(dir, "cur.json")
  fs.writeFileSync(prev, JSON.stringify(previous))
  fs.writeFileSync(cur, JSON.stringify(current))
  return JSON.parse(execFileSync("jq", ["-c", "--slurpfile", "prev", prev, "--argjson", "max", String(max),
    "-f", PROGRAM, cur], { encoding: "utf8" }))
}

function server(fields) {
  return Object.assign({ id: "prod", name: "Production", ok: true, locked: false, muted: false, error: "" }, fields)
}

function service(fields) {
  const s = Object.assign({ server: "prod", serverName: "Production", host: "db01", service: "CPU load",
    state: 0, isHost: false, handled: false, stale: false, soft: false, output: "load 0.5" }, fields)
  if (!("hardState" in fields)) s.hardState = s.state
  return s
}

function status(services, servers = [server({})]) {
  return { servers, services }
}

test("a service that changed state is named, with its host and output", () => {
  const out = notes(status([service({ state: 0 })]), status([service({ state: 2, output: "load 9.1" })]))
  assert.equal(out.length, 1)
  assert.equal(out[0].urgency, "critical")
  assert.equal(out[0].title, "CRIT  CPU load")
  assert.equal(out[0].body, "db01 (was OK)\nload 9.1")
  assert.equal(out[0].target, "service:prod/db01/CPU load")
})

test("urgency follows the new state: OK is low, WARN and UNKNOWN normal", () => {
  const was = (state) => status([service({ state })])
  assert.equal(notes(was(2), was(0))[0].urgency, "low")
  assert.equal(notes(was(0), was(1))[0].urgency, "normal")
  assert.equal(notes(was(0), was(3))[0].urgency, "normal")
})

test("nothing changed, nothing to say", () => {
  const s = status([service({ state: 2 })])
  assert.deepEqual(notes(s, s), [])
})

test("a soft state stays quiet until Checkmk confirms it", () => {
  const ok = status([service({ state: 0 })])
  const soft = status([service({ state: 2, soft: true, hardState: 0 })])
  const hard = status([service({ state: 2 })])
  assert.deepEqual(notes(ok, soft), [])
  assert.equal(notes(soft, hard)[0].title, "CRIT  CPU load")
  assert.equal(notes(soft, hard)[0].body.split("\n")[0], "db01 (was OK)")
  // A blip that clears on the next check never announced anything
  assert.deepEqual(notes(soft, ok), [])
})

test("a status file from before hard states counts by the state", () => {
  const old = status([service({ state: 0 })])
  delete old.services[0].hardState
  assert.equal(notes(old, status([service({ state: 1 })]))[0].title, "WARN  CPU load")
})

test("handled, stale and new services are not announced", () => {
  const before = status([service({ state: 0 }), service({ service: "Disk", state: 0 })])
  const after = status([
    service({ state: 2, handled: true }),
    service({ service: "Disk", state: 2, stale: true }),
    service({ service: "New", state: 2 }),
  ])
  assert.deepEqual(notes(before, after), [])
})

test("a muted server announces nothing", () => {
  const muted = [server({ muted: true })]
  assert.deepEqual(notes(status([service({ state: 0 })], muted), status([service({ state: 2 })], muted)), [])
  assert.deepEqual(notes(status([], muted), status([], [server({ muted: true, ok: false, error: "down" })])), [])
})

test("a host that goes down is announced, also without a row before", () => {
  const down = service({ service: "Host", isHost: true, state: 2, output: "Host is DOWN: timeout" })
  const out = notes(status([]), status([down]))
  assert.equal(out.length, 1)
  assert.equal(out[0].title, "DOWN  db01")
  assert.equal(out[0].body, "Host is DOWN: timeout")
  assert.equal(out[0].target, "host:prod/db01")
  // Unless its server did not answer last time: then nothing is known about
  // before, and only the server's return is announced
  const back = notes(status([], [server({ ok: false })]), status([down]))
  assert.deepEqual(back.map(n => n.target), ["servers"])
})

test("servers that become unreachable or reachable again say so", () => {
  const up = status([], [server({})])
  const down = status([], [server({ ok: false, error: "Could not resolve host" })])
  const out = notes(up, down)
  assert.deepEqual(out, [{ urgency: "normal", title: "Checkmk: Production unreachable",
    body: "Could not resolve host", target: "servers" }])
  assert.equal(notes(down, up)[0].title, "Checkmk: Production reachable again")
  // Polled for the first time, locked or unlocked: nothing
  assert.deepEqual(notes(status([], []), down), [])
  assert.deepEqual(notes(up, status([], [server({ ok: false, locked: true })])), [])
})

test("with several servers, the server is named too", () => {
  const two = (state) => status([service({ state })], [server({}), server({ id: "stg", name: "Staging" })])
  assert.equal(notes(two(0), two(2))[0].body.split("\n")[0], "db01 · Production (was OK)")
})

test("more changes than max come as one summary", () => {
  const before = status(["A", "B", "C"].map(name => service({ service: name, state: 0 })))
  const after = status(["A", "B", "C"].map(name => service({ service: name, state: name === "C" ? 1 : 2 })))
  const out = notes(before, after, 2)
  assert.equal(out.length, 1)
  assert.equal(out[0].title, "Checkmk: 3 services changed state")
  assert.equal(out[0].urgency, "critical")
  assert.equal(out[0].body, "CRIT  A on db01\nCRIT  B on db01\n… and 1 more")
  assert.equal(out[0].target, "problems")
})
