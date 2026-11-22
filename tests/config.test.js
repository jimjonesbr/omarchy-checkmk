// Tests of bin/checkmk-config: what it accepts before any request is made,
// how it reads old configs and how it writes servers.json.
//
//   node --test tests/
//
// Each test runs the script with a config directory of its own. Nothing is
// sent anywhere but to a closed port on this machine, and no secret is stored.

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync, spawn, spawnSync } = require("node:child_process")

const SCRIPT = path.join(__dirname, "..", "bin", "checkmk-config")
// Nothing listens here, so a request that gets this far fails at once
const CLOSED = "http://127.0.0.1:9/site"

function configDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "checkmk-config-"))
  test.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  return dir
}

function run(dir, args, input = "") {
  const r = spawnSync(SCRIPT, args, { input, encoding: "utf8", env: { ...process.env, CHECKMK_CONFIG_DIR: dir } })
  return JSON.parse(r.stdout.trim().split("\n").pop() || "null")
}

function servers(dir) {
  return JSON.parse(fs.readFileSync(path.join(dir, "servers.json"), "utf8")).servers
}

test("only http and https URLs are accepted", () => {
  const dir = configDir()
  for (const url of ["file:///etc/passwd", "ftp://host/site", "gopher://host", "host/site"]) {
    const r = run(dir, ["test"], JSON.stringify({ url, user: "u", secret: "s" }))
    assert.equal(r.ok, false, url)
    assert.match(r.message, /must start with https:\/\//, url)
  }
  assert.equal(fs.existsSync(path.join(dir, "servers.json")), false)
})

test("a user name or secret with a line break is refused, as it would add a header", () => {
  const dir = configDir()
  for (const [user, secret] of [["u\nX-Evil: 1", "s"], ["u", "s\r\nX-Evil: 1"]]) {
    for (const action of ["test", "save"]) {
      const r = run(dir, [action], JSON.stringify({ url: CLOSED, user, secret }))
      assert.equal(r.ok, false)
      assert.match(r.message, /line breaks/)
    }
  }
  assert.equal(fs.existsSync(path.join(dir, "servers.json")), false)
})

test("a proxy must be a proxy URL", () => {
  const dir = configDir()
  for (const proxy of ["file:///tmp/x", "socks5h://host:1080/path", "two words:1080"]) {
    const r = run(dir, ["test"], JSON.stringify({ url: CLOSED, user: "u", secret: "s", proxy }))
    assert.equal(r.ok, false, proxy)
    assert.match(r.message, /proxy must look like/, proxy)
  }
})

test("valid input gets as far as the request", () => {
  const dir = configDir()
  const r = run(dir, ["test"], JSON.stringify({ url: CLOSED, user: "u", secret: "s", proxy: "" }))
  assert.equal(r.ok, false)
  assert.doesNotMatch(r.message, /must|line breaks/)
})

test("curl config values stay on one line", () => {
  const value = 'http://x/\noutput = /tmp/pwned\r\nproto = "=all" \\'
  const line = execFileSync("bash", ["-c",
    'eval "$(sed -n "/^curl_option() {/,/^}/p" "$0")"; curl_option url "$1"', SCRIPT, value], { encoding: "utf8" })
  assert.equal(line.trimEnd().split("\n").length, 1)
  assert.equal(line.trimEnd(), 'url = "http://x/\\noutput = /tmp/pwned\\r\\nproto = \\"=all\\" \\\\"')
})

test("the config of 0.2.0 is read as text, never run", () => {
  const dir = configDir()
  const pwned = path.join(dir, "pwned")
  fs.writeFileSync(path.join(dir, "secret"), "s\n")
  fs.writeFileSync(path.join(dir, "config"), [
    'CMK_URL="https://monitoring.example.com/prod/check_mk/"',
    "CMK_USER=omarchy",
    `CMK_SECRET_FILE='${path.join(dir, "secret")}'`,
    `CMK_HOST_FILTER="$(touch ${pwned})"`,
    `touch ${pwned}`,
    "CMK_INSECURE=1",
    "CMK_TIMEOUT=20",
  ].join("\n") + "\n")
  run(dir, ["list"])
  assert.equal(fs.existsSync(pwned), false, "the old config was executed")
  const [s] = servers(dir)
  assert.equal(s.url, "https://monitoring.example.com/prod")
  assert.equal(s.user, "omarchy")
  assert.equal(s.hostFilter, `$(touch ${pwned})`)
  assert.equal(s.insecure, true)
  assert.equal(s.timeout, 20)
  assert.equal(s.secretFile, path.join(dir, "secret"))
  assert.equal(fs.existsSync(path.join(dir, "config.migrated")), true)
})

test("many runs at once leave servers.json whole", async () => {
  const dir = configDir()
  const base = { serviceFilter: "", hostFilter: "", insecure: false, remember: false, url: CLOSED, user: "u" }
  fs.writeFileSync(path.join(dir, "servers.json"), JSON.stringify({ servers: [
    { ...base, id: "a", name: "A" }, { ...base, id: "b", name: "B" }] }))
  const env = { ...process.env, CHECKMK_CONFIG_DIR: dir }
  const runs = []
  for (let i = 0; i < 24; i++) {
    const args = [i % 2 ? "disconnect" : "connect", i % 3 ? "a" : "b"]
    runs.push(new Promise(done => spawn(SCRIPT, args, { env, stdio: "ignore" }).on("close", done)))
  }
  await Promise.all(runs)
  assert.deepEqual(servers(dir).map(s => s.id), ["a", "b"])
  assert.deepEqual(fs.readdirSync(dir).filter(f => f.startsWith("servers.json.")), [], "temporary files left")
})
