// Bounded data helpers for the Meetings plugin. Every accepted meeting URL is
// parsed and canonicalized once; the resulting URL and host then drive storage,
// provider identity, copying, and launch behavior.

var MAX_CONFIG_BYTES = 65536
var MAX_MEETINGS = 100
var MAX_NAME_LENGTH = 120
var MAX_URL_LENGTH = 4096
var MAX_LABEL_LENGTH = 48

function utf8ByteLength(value) {
  try {
    return unescape(encodeURIComponent(String(value))).length
  } catch (error) {
    return MAX_CONFIG_BYTES + 1
  }
}

function hasControlCharacters(value) {
  return /[\u0000-\u001f\u007f]/.test(String(value || ""))
}

function hasExactKeys(value, expected) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false
  var keys = Object.keys(value).sort()
  var wanted = expected.slice().sort()
  if (keys.length !== wanted.length) return false
  for (var i = 0; i < keys.length; i++) {
    if (keys[i] !== wanted[i]) return false
  }
  return true
}

function domainMatches(host, domain) {
  return host === domain || host.slice(-(domain.length + 1)) === "." + domain
}

function providerForHost(host) {
  if (domainMatches(host, "zoom.us") || domainMatches(host, "zoomgov.com")) return "Zoom"
  if (host === "meet.google.com") return "Meet"
  if (domainMatches(host, "ringcentral.com")) return "RingCentral"
  if (domainMatches(host, "teams.microsoft.com") || domainMatches(host, "teams.live.com")) return "Teams"
  if (domainMatches(host, "webex.com")) return "Webex"
  if (domainMatches(host, "whereby.com")) return "Whereby"
  if (host === "meet.jit.si") return "Jitsi"
  if (domainMatches(host, "discord.com") || host === "discord.gg") return "Discord"
  if (domainMatches(host, "around.co")) return "Around"
  return host.slice(0, MAX_LABEL_LENGTH) || "Link"
}

// Accept a pasted HTTPS URL with or without its scheme. URL is the platform URL
// parser (available in both QML's JavaScript runtime and Node-based tests).
// Reject controls and userinfo before retaining the parser's canonical href.
function parseMeetingUrl(input) {
  var original = String(input === undefined || input === null ? "" : input)
  if (original.length > MAX_URL_LENGTH || hasControlCharacters(original)) return null
  var raw = original.trim()
  if (raw === "") return null

  var candidate = raw
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(candidate)) candidate = "https://" + candidate

  try {
    var parsed = new URL(candidate)
    if (parsed.protocol !== "https:") return null
    if (parsed.username !== "" || parsed.password !== "") return null

    var host = String(parsed.hostname || "").toLowerCase()
    // A final dot is DNS-equivalent but would otherwise evade exact provider
    // labels. Store one canonical spelling and let URL rebuild href from it.
    if (host.charAt(host.length - 1) === ".") host = host.slice(0, -1)
    if (host === "" || host.length > 253 || hasControlCharacters(host)) return null
    parsed.hostname = host

    var canonical = String(parsed.href || "")
    if (canonical === "" || canonical.length > MAX_URL_LENGTH || hasControlCharacters(canonical)) return null

    return {
      url: canonical,
      host: host,
      pathname: String(parsed.pathname || "/"),
      search: String(parsed.search || ""),
      hash: String(parsed.hash || ""),
      provider: providerForHost(host)
    }
  } catch (error) {
    return null
  }
}

function meetingFromInput(name, url) {
  var originalName = String(name === undefined || name === null ? "" : name)
  if (originalName.length > MAX_NAME_LENGTH || hasControlCharacters(originalName)) return null
  var rawName = originalName.trim()

  var parsed = parseMeetingUrl(url)
  if (!parsed) return null

  return {
    name: rawName || parsed.host.slice(0, MAX_NAME_LENGTH),
    url: parsed.url,
    host: parsed.host,
    pathname: parsed.pathname,
    search: parsed.search,
    hash: parsed.hash,
    provider: parsed.provider
  }
}

function parseConfig(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw)
  if (text === "") return { ok: true, meetings: [], error: "" }
  if (utf8ByteLength(text) > MAX_CONFIG_BYTES) {
    return { ok: false, meetings: [], error: "Config exceeds 64 KiB" }
  }

  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (error) {
    return { ok: false, meetings: [], error: "Config is not valid JSON" }
  }

  if (!hasExactKeys(parsed, ["version", "meetings"]) || parsed.version !== 1 || !Array.isArray(parsed.meetings)) {
    return { ok: false, meetings: [], error: "Config must contain only version 1 and a meetings array" }
  }
  if (parsed.meetings.length > MAX_MEETINGS) {
    return { ok: false, meetings: [], error: "Config contains too many meetings" }
  }

  var meetings = []
  for (var i = 0; i < parsed.meetings.length; i++) {
    var entry = parsed.meetings[i]
    if (!hasExactKeys(entry, ["name", "url"]) || typeof entry.name !== "string" || typeof entry.url !== "string") {
      return { ok: false, meetings: [], error: "Meeting entries must contain only string name and url fields" }
    }
    var meeting = meetingFromInput(entry.name, entry.url)
    if (!meeting) return { ok: false, meetings: [], error: "Config contains an invalid meeting" }
    meetings.push(meeting)
  }

  return { ok: true, meetings: meetings, error: "" }
}

function serialize(meetings) {
  if (!Array.isArray(meetings) || meetings.length > MAX_MEETINGS) return ""

  var output = []
  for (var i = 0; i < meetings.length; i++) {
    var entry = meetings[i]
    if (!entry || typeof entry.name !== "string" || typeof entry.url !== "string") return ""
    var meeting = meetingFromInput(entry.name, entry.url)
    if (!meeting) return ""
    output.push({ name: meeting.name, url: meeting.url })
  }

  var text = JSON.stringify({ version: 1, meetings: output }, null, 2) + "\n"
  return utf8ByteLength(text) <= MAX_CONFIG_BYTES ? text : ""
}

function isValidUrl(url) {
  return parseMeetingUrl(url) !== null
}

// Zoom /j/<id> links normally land on an interstitial that pushes the desktop
// client. Rewriting canonical Zoom links to app.zoom.us opens the web client.
function launchUrl(meeting, zoomWebClient) {
  if (!meeting || typeof meeting.url !== "string") return ""
  if (zoomWebClient === false) return meeting.url
  if (!domainMatches(String(meeting.host || ""), "zoom.us")) return meeting.url

  var match = String(meeting.pathname || "").match(/^\/j\/(\d+)\/?$/)
  if (!match) return meeting.url
  return "https://app.zoom.us/wc/join/" + match[1] + String(meeting.search || "") + String(meeting.hash || "")
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_CONFIG_BYTES: MAX_CONFIG_BYTES,
    MAX_MEETINGS: MAX_MEETINGS,
    MAX_NAME_LENGTH: MAX_NAME_LENGTH,
    MAX_URL_LENGTH: MAX_URL_LENGTH,
    MAX_LABEL_LENGTH: MAX_LABEL_LENGTH,
    utf8ByteLength: utf8ByteLength,
    domainMatches: domainMatches,
    providerForHost: providerForHost,
    parseMeetingUrl: parseMeetingUrl,
    meetingFromInput: meetingFromInput,
    parseConfig: parseConfig,
    serialize: serialize,
    isValidUrl: isValidUrl,
    launchUrl: launchUrl
  }
}
