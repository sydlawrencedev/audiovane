// Minimal PostHog client for the landing page.
//
// Deliberately not the official snippet: that pulls in session replay, surveys,
// feature flags and a cross-session cookie banner, and the page here is a
// single static HTML file. This sends the handful of events that are actually
// worth having (did they download, did they copy the install command, which
// mode cards got scrolled to) and nothing else. Same client shape as the one in
// the Mac app, so both surfaces read the same way in PostHog.
//
// What is sent: page views, which buttons got clicked, which mode cards were
// scrolled into view, and the usual anonymous install id. Never: query strings,
// anything typed into the page, or anything identifying — there is nothing to
// identify, this is a marketing page with no form and no account.
//
// To turn it off for one visit: the footer's "no thanks" link, or Do Not Track
// on. Both stop the page sending anything at all.

(function () {
  "use strict";

  function meta(name) {
    var el = document.querySelector('meta[name="' + name + '"]');
    return el ? el.content.trim() : "";
  }

  var KEY = meta("posthog-key");
  var HOST = (meta("posthog-host") || "https://us.i.posthog.com").replace(/\/+$/, "");
  var OPT_OUT_KEY = "vibresia.site.optOut";
  var ID_KEY = "vibresia.site.distinctId";

  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    // Not every browser gets randomUUID, and this id doesn't need to be
    // unguessable — it identifies an install, not a person.
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      var r = (Math.random() * 16) | 0;
      return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
    });
  }

  function optedOut() {
    try {
      if (localStorage.getItem(OPT_OUT_KEY) === "1") return true;
    } catch (e) { /* private mode: no stored opt-out, carry on */ }
    // Do Not Track is a clear enough signal, and honouring it costs nothing.
    return navigator.doNotTrack === "1" || window.doNotTrack === "1";
  }

  function distinctId() {
    var id;
    try {
      id = localStorage.getItem(ID_KEY);
      if (!id) {
        id = uuid();
        localStorage.setItem(ID_KEY, id);
      }
    } catch (e) {
      id = uuid(); // no storage: still send, just don't remember
    }
    return id;
  }

  if (!KEY || KEY.indexOf("phc_") !== 0) return; // no key in this build: stay quiet
  if (optedOut()) return;

  var id = distinctId();
  var sessionId = uuid(); // one per page load: groups a single visit together
  var queue = [];
  var flushTimer = null;
  var ENDPOINT = HOST + "/batch/";

  function baseProperties() {
    return {
      surface: "web",
      $lib: "vibresia-web",
      path: location.pathname,
      title: document.title,
      language: navigator.language || "",
      // Query strings are dropped on purpose: the page has none it needs, and
      // UTM-ish params are the classic way to smuggle personal data into an
      // analytics payload.
      referrer: document.referrer ? new URL(document.referrer).hostname : ""
    };
  }

  function track(event, properties) {
    var props = baseProperties();
    for (var k in properties) props[k] = properties[k];
    queue.push({
      api_key: KEY,
      event: event,
      distinct_id: id,
      session_id: sessionId,
      properties: props,
      timestamp: new Date().toISOString()
    });
    schedule();
  }

  function send(payload, keepalive) {
    var body = JSON.stringify(payload);
    if (keepalive && navigator.sendBeacon) {
      // The page may be going away; a beacon is the one request that survives.
      return navigator.sendBeacon(ENDPOINT, body);
    }
    return fetch(ENDPOINT, {
      method: "POST",
      // application/json because that is the only body shape /batch/ reads as
      // a batch. text/plain was here to skip the CORS preflight, and PostHog
      // does answer that preflight (allow-origin echoes, allow-headers
      // content-type), so the saving was small next to sending nothing.
      headers: { "Content-Type": "application/json" },
      body: body,
      keepalive: !!keepalive,
      mode: "cors"
    }).catch(function () { /* offline: the visit just doesn't get counted */ });
  }

  function flush(keepalive) {
    if (flushTimer) { clearTimeout(flushTimer); flushTimer = null; }
    if (!queue.length) return;
    var batch = queue;
    queue = [];
    // `/batch/` takes a JSON array of events, one per element. It used to be
    // sent as a wrapper object — {"api_key": …, "batch": [ … ]} — which
    // PostHog accepts and answers with {"status":"Ok"} while recording
    // nothing, because the object it looks at has no `event` field. That's the
    // worst kind of failure to debug: a 200 forever and an empty project.
    send(batch, keepalive);
  }

  function schedule() {
    if (flushTimer) return;
    flushTimer = setTimeout(function () { flush(false); }, 2500);
  }

  // --- "Have they downloaded before?" -----------------------------------
  //
  // The worker turns this into one line on the Discord notification ("first
  // download from this browser", or not). It rides on the download link's own
  // URL, because a plain link click can't carry a header.
  //
  // The Discord notification itself is fired by the server when it hands over
  // the download, not from here: a webhook URL in the page would be public,
  // and a click that never completes isn't a download.
  var DOWNLOADED_KEY = "vibresia.site.downloaded";

  function tagDownloadLinks() {
    var seen = "0";
    try { if (localStorage.getItem(DOWNLOADED_KEY) === "1") seen = "1"; } catch (e) { /* no storage */ }
    var links = document.querySelectorAll('a[href*="/download"]');
    for (var i = 0; i < links.length; i++) {
      var href = links[i].getAttribute("href").split("&seen=")[0];
      links[i].setAttribute("href", href + "&seen=" + seen);
    }
  }

  document.addEventListener("click", function (e) {
    if (!e.target.closest('a[href*="/download"]')) return;
    try { localStorage.setItem(DOWNLOADED_KEY, "1"); } catch (err) { /* nothing we can do */ }
  });
  tagDownloadLinks();

  // --- Events -----------------------------------------------------------

  track("page_view", {
    $current_url: location.href.split("?")[0],
    $referrer: document.referrer || ""
  });

  // Delegated, so the page can be edited without re-wiring anything here.
  document.addEventListener("click", function (e) {
    var el = e.target.closest("[data-track], a[href]");
    if (!el) return;

    if (el.hasAttribute("data-optout")) {
      e.preventDefault();
      try { localStorage.setItem(OPT_OUT_KEY, "1"); } catch (err) { /* nothing we can do */ }
      flush(false);
      var note = document.getElementById("optout-note");
      if (note) note.hidden = false;
      return;
    }

    if (el.hasAttribute("data-track")) {
      var props = { placement: el.dataset.placement || "" };
      if (el.dataset.command) props.command = el.dataset.command;
      if (el.dataset.target) props.target = el.dataset.target;
      track(el.dataset.track, props);
      return;
    }

    // Anything that leaves the site and isn't already tracked above.
    var href = el.getAttribute("href") || "";
    if (/^https?:/.test(href)) {
      var host = new URL(href, location.href).hostname;
      if (host !== location.hostname) track("outbound_clicked", { target: host });
    }
  });

  // Which mode cards people actually scroll to is the closest thing this page
  // has to a "what interested you" signal.
  if ("IntersectionObserver" in window) {
    var seen = {};
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        var mode = entry.target.dataset.mode;
        if (!entry.isIntersecting || seen[mode]) return;
        seen[mode] = true;
        track("mode_card_viewed", { target: mode });
        observer.unobserve(entry.target);
      });
    }, { rootMargin: "-20% 0px" });
    document.querySelectorAll(".mode[data-mode]").forEach(function (card) {
      observer.observe(card);
    });
  }

  var video = document.querySelector("video");
  if (video) {
    var reported = false;
    video.addEventListener("play", function () {
      if (reported) return;
      reported = true;
      track("demo_played", {});
    });
  }

  // Copy buttons log which instruction people reach for — "ask your AI
  // assistant" versus a curl pipe is a real difference in who this page
  // reaches, so it's worth knowing which one wins.
  document.querySelectorAll("[data-copy]").forEach(function (button) {
    button.addEventListener("click", function () {
      track("install_command_copied", { command: button.dataset.command || "" });
    });
  });

  window.addEventListener("pagehide", function () { flush(true); });
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "hidden") flush(true);
  });
})();