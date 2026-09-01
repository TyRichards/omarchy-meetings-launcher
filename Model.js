// Data helpers for the Meetings plugin: config parsing, provider
// detection, and the Zoom web-client rewrite.

function parseMeetings(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    var list = parsed && Array.isArray(parsed.meetings) ? parsed.meetings : []
    return list.filter(function(entry) {
      return entry && typeof entry.url === "string" && entry.url.trim() !== ""
    }).map(function(entry) {
      return {
        name: String(entry.name || "").trim() || hostOf(entry.url),
        url: String(entry.url).trim()
      }
    })
  } catch (error) {
    return []
  }
}

function serialize(meetings) {
  return JSON.stringify({
    version: 1,
    meetings: meetings.map(function(entry) {
      return { name: entry.name, url: entry.url }
    })
  }, null, 2) + "\n"
}

function hostOf(url) {
  var match = String(url || "").match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^/?#]+)/)
  return match ? match[1].replace(/^www\./, "") : ""
}

function providerLabel(url) {
  var host = hostOf(url).toLowerCase()
  if (host.indexOf("zoom.us") !== -1 || host.indexOf("zoomgov.com") !== -1) return "Zoom"
  if (host === "meet.google.com") return "Meet"
  if (host.indexOf("ringcentral.com") !== -1) return "RingCentral"
  if (host.indexOf("teams.microsoft.com") !== -1 || host.indexOf("teams.live.com") !== -1) return "Teams"
  if (host.indexOf("webex.com") !== -1) return "Webex"
  if (host.indexOf("whereby.com") !== -1) return "Whereby"
  if (host.indexOf("meet.jit.si") !== -1 || host.indexOf("jitsi") !== -1) return "Jitsi"
  if (host.indexOf("discord") !== -1) return "Discord"
  if (host.indexOf("around.co") !== -1) return "Around"
  return host || "Link"
}

function isValidUrl(url) {
  return /^https?:\/\/[^\s/?#]+/.test(String(url || "").trim())
}

// Zoom /j/<id> join links normally land on an interstitial that pushes the
// desktop client. Rewriting to app.zoom.us/wc/join/<id> drops straight into
// the browser client, which is what a tiled web-app window wants. Vanity
// links (zoom.us/my/<name>) can't be rewritten and pass through untouched.
function launchUrl(url, zoomWebClient) {
  url = String(url || "").trim()
  if (zoomWebClient === false) return url
  var match = url.match(/^https?:\/\/(?:[a-z0-9-]+\.)?zoom\.us\/j\/(\d+)(?:\?(.*))?$/i)
  if (!match) return url
  return "https://app.zoom.us/wc/join/" + match[1] + (match[2] ? "?" + match[2] : "")
}
