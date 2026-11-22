// Tests of bin/checkmk-poll and bin/checkmk-graph around a server that does not
// answer: what they keep and what they refuse to send.
//
//   node --test tests/
//
// The server is a closed port on this machine, its secret a file of its own.

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

const BIN = path.join(__dirname, "..", "bin")
const CLOSED = "http://127.0.0.1:9/site"

function setup(url = CLOSED) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "checkmk-poll-"))
  test.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const config = path.join(dir, "config"), cache = path.join(dir, "cache")
  fs.mkdirSync(config)
  fs.mkdirSync(path.join(cache, "omarchy-checkmk"), { recursive: true })
  fs.writeFileSync(path.join(config, "secret"), "s3cret\n")
  const server = { id: "a", name: "A", url, user: "u", serviceFilter: "", hostFilter: "", insecure: false,
    remember: true, secretFile: path.join(config, "secret"), timeout: 2 }
  fs.writeFileSync(path.join(config, "servers.json"), JSON.stringify({ servers: [server] }))
  const env = { ...process.env, CHECKMK_CONFIG_DIR: config, XDG_CACHE_HOME: cache }
  const statusFile = path.join(cache, "omarchy-checkmk", "status.json")
  return {
    config, env, statusFile,
    previous(status) { fs.writeFileSync(statusFile, JSON.stringify(status)) },
    poll() {
      spawnSync(path.join(BIN, "checkmk-poll"), ["--quiet"], { env })
      return JSON.parse(fs.readFileSync(statusFile, "utf8"))
    },
    graph(request) {
      const r = spawnSync(path.join(BIN, "checkmk-graph"), [], { env, input: JSON.stringify(request), encoding: "utf8" })
      return JSON.parse(r.stdout)
    },
  }
}

function lastKnown(url) {
  return { servers: [{ id: "a", name: "A", url, ok: true }], services: [{ server: "a", serverName: "A",
    host: "db01", service: "CPU load", state: 2, isHost: false, handled: false,
    link: url + "/check_mk/index.py?start_url=x", metrics: [{ name: "load1" }] }] }
}

test("a server that does not answer keeps its last known services, marked stale", () => {
  const t = setup()
  t.previous(lastKnown(CLOSED))
  const status = t.poll()
  assert.equal(status.servers[0].ok, false)
  assert.equal(status.services.length, 1)
  assert.equal(status.services[0].stale, true)
})

test("after a change of URL, the old site's services are dropped", () => {
  const t = setup()
  t.previous(lastKnown("https://old-site.example/prod"))
  const status = t.poll()
  assert.equal(status.servers[0].ok, false)
  assert.deepEqual(status.services, [])
})

test("graphs are only asked for services of the server's current site", () => {
  const t = setup()
  const request = { server: "a", host: "db01", service: "CPU load", seconds: 3600, metrics: ["load1"] }
  for (const link of ["https://old-site.example/prod/check_mk/index.py", CLOSED + "x/check_mk/", undefined]) {
    const r = t.graph({ ...request, link })
    assert.equal(r.ok, false)
    assert.match(r.error, /not from the server's current site/, String(link))
  }
  // A link of the current site gets as far as the request, which fails here
  const r = t.graph({ ...request, link: CLOSED + "/check_mk/index.py?x" })
  assert.equal(r.ok, false)
  assert.doesNotMatch(r.error, /current site/)
})

test("a servers.json that cannot be read shows up as such, not as no servers", () => {
  const t = setup()
  fs.writeFileSync(path.join(t.config, "servers.json"), "{ not json")
  const status = t.poll()
  assert.equal(status.configError, true)
  assert.equal(status.unconfigured, false)
  assert.match(status.error, /cannot be read/)
})
