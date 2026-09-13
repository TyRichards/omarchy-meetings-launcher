#!/usr/bin/env node

const assert = require("node:assert/strict")
const Model = require("../Model.js")

function meeting(name, url) {
  return Model.meetingFromInput(name, url)
}

// Canonical HTTPS parsing and provider identity.
{
  const value = meeting("Standup", "ZOOM.US/j/123?pwd=abc")
  assert.equal(value.url, "https://zoom.us/j/123?pwd=abc")
  assert.equal(value.host, "zoom.us")
  assert.equal(value.provider, "Zoom")
  assert.equal(Model.launchUrl(value, true), "https://app.zoom.us/wc/join/123?pwd=abc")
}

assert.equal(meeting("", "https://subdomain.zoom.us/j/123").provider, "Zoom")
assert.equal(meeting("", "https://zoomgov.com/j/123").provider, "Zoom")
assert.equal(meeting("", "https://v.ringcentral.com/join/123").provider, "RingCentral")
assert.equal(meeting("", "https://meet.google.com/abc-defg-hij").provider, "Meet")

// Hostname deception, userinfo, non-HTTPS schemes, and controls.
{
  const suffixAttack = meeting("", "https://zoom.us.attacker.example/j/123")
  assert.equal(suffixAttack.host, "zoom.us.attacker.example")
  assert.equal(suffixAttack.provider, "zoom.us.attacker.example")
}
assert.equal(meeting("", "https://zoom.us@attacker.example/j/123"), null)
assert.equal(meeting("", "https://user:pass@zoom.us/j/123"), null)
assert.equal(meeting("", "http://zoom.us/j/123"), null)
assert.equal(meeting("", "javascript:alert(1)"), null)
assert.equal(meeting("", "https://zoom.us/\nattacker"), null)
assert.equal(meeting("", "\nhttps://zoom.us/j/123"), null)
assert.equal(meeting("", "https://zoom.us\t@attacker.example"), null)
assert.equal(meeting("", "https://zoom.us%40attacker.example/j/123"), null)
assert.ok(meeting("", "https://" + "a".repeat(50) + ".example/path").provider.length <= Model.MAX_LABEL_LENGTH)

// URL parser canonicalization is retained as the only launch/copy value.
{
  const value = meeting("", "https://ZOOM.US./a/../j/456#room")
  assert.equal(value.host, "zoom.us")
  assert.equal(value.url, "https://zoom.us/j/456#room")
  assert.equal(value.name, "zoom.us")
  assert.equal(Model.launchUrl(value, true), "https://app.zoom.us/wc/join/456#room")
  assert.equal(Model.launchUrl(value, false), value.url)
}

// Strict, bounded config schema.
const validText = JSON.stringify({
  version: 1,
  meetings: [{ name: "Daily", url: "meet.google.com/abc-defg-hij" }]
})
{
  const result = Model.parseConfig(validText)
  assert.equal(result.ok, true)
  assert.equal(result.meetings.length, 1)
  assert.equal(result.meetings[0].url, "https://meet.google.com/abc-defg-hij")
  assert.equal(result.meetings[0].provider, "Meet")
}
assert.equal(Model.parseConfig('{"version":2,"meetings":[]}').ok, false)
assert.equal(Model.parseConfig('{"version":1,"meetings":[],"extra":true}').ok, false)
assert.equal(Model.parseConfig('{"version":1,"meetings":[{"url":"https://example.com"}]}').ok, false)
assert.equal(Model.parseConfig('{"version":1,"meetings":[{"name":"x","url":"http://example.com"}]}').ok, false)
assert.equal(Model.parseConfig("{").ok, false)
assert.equal(Model.parseConfig("x".repeat(Model.MAX_CONFIG_BYTES + 1)).ok, false)
assert.equal(Model.parseConfig(JSON.stringify({
  version: 1,
  meetings: Array.from({ length: Model.MAX_MEETINGS + 1 }, () => ({ name: "x", url: "https://example.com" }))
})).ok, false)
assert.equal(meeting("x".repeat(Model.MAX_NAME_LENGTH + 1), "https://example.com"), null)
assert.equal(meeting("Daily\nStandup", "https://example.com"), null)
assert.equal(meeting("x", "https://example.com/" + "a".repeat(Model.MAX_URL_LENGTH)), null)

// Serialization revalidates every item and never exceeds the file cap.
{
  const value = meeting("Team", "https://teams.microsoft.com/l/meetup-join/abc")
  const text = Model.serialize([value])
  assert.ok(text.length > 0)
  assert.deepEqual(JSON.parse(text), {
    version: 1,
    meetings: [{ name: "Team", url: "https://teams.microsoft.com/l/meetup-join/abc" }]
  })
}
assert.equal(Model.serialize(Array(Model.MAX_MEETINGS + 1).fill(meeting("x", "https://example.com"))), "")
assert.equal(Model.serialize([{ name: "x", url: "http://example.com" }]), "")
assert.equal(Model.serialize([{ name: "💻".repeat(Model.MAX_NAME_LENGTH), url: "https://example.com" }]), "")

console.log("model tests passed")
