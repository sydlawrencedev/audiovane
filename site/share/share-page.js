/* Share page — what the recipient sees after someone sends them a Vibescape
 * link. Branches on the kind of vibescape:
 *
 *   - Built-in: the URL is `/share/<slug>`, the open button carries
 *     `data-share-slug`, the JS calls `vibresia://open?p=<slug>`.
 *
 *   - Custom: the URL is `/share?d=<base64>`, the open button carries
 *     `data-share-custom`, the JS reads `d=` from the URL and calls
 *     `vibresia://open?d=<base64>`.
 *
 * Both branches share the same install-detection dance: try the URL scheme,
 * mark the install on visibility-hidden or blur, and after 1500ms show the
 * download CTA (only the first time around — once `localStorage.vibresia_installed`
 * is set the CTA stays hidden, so a returning recipient doesn't see it).
 *
 * No framework, no analytics vendor — PostHog is loaded the same way the
 * homepage loads it (same `data-` attributes if you ever want to track
 * share-recipient behaviour).
 */
(function () {
  "use strict";

  var INSTALL_KEY = "vibresia_installed";
  var OPEN_TIMEOUT_MS = 1500;

  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  // --- URL construction --------------------------------------------------

  function deepLinkURL(button) {
    var open = button || $("[data-share-open]");
    if (!open) return null;
    var slug = open.getAttribute("data-share-slug");
    if (slug) return "vibresia://open?p=" + encodeURIComponent(slug);
    if (open.hasAttribute("data-share-custom")) {
      // The query string for the long form of the link, the global for the
      // short form the Worker serves. See site/share/index.html.
      var d = new URL(window.location.href).searchParams.get("d")
        || (window.__VIBRESIA_SHARE__ && window.__VIBRESIA_SHARE__.d);
      if (!d) return null;
      // Which share this is, so the app can hand the same link back if the
      // vibescape is shared on. Without it the app works the link out from
      // the vibescape's contents instead, which usually lands on the same
      // answer — but "usually" is not "always", and the id is free.
      var s = window.__VIBRESIA_SHARE__ && window.__VIBRESIA_SHARE__.id;
      return "vibresia://open?d=" + d + (s ? "&s=" + encodeURIComponent(s) : "");
    }
    return null;
  }

  // --- Install detection -------------------------------------------------

  // macOS offers the URL to a registered app and the page loses focus or
  // becomes hidden. We watch for either signal in the first ~1500ms after
  // the user clicks Open. If neither fires, no app owns the scheme and the
  // download CTA takes over.
  function tryOpenAndDetect(url) {
    return new Promise(function (resolve) {
      var settled = false;
      function settle(installed) {
        if (settled) return;
        settled = true;
        resolve(installed);
      }

      var onHide = function () {
        window.removeEventListener("blur", onBlur);
        document.removeEventListener("visibilitychange", onVis);
        // The app is in the foreground now. A short settle lets macOS finish
        // the switch before we mark "installed" — we don't want a flapping
        // activation to look like a fail.
        setTimeout(function () { settle(true); }, 200);
      };
      function onBlur() { onHide(); }
      function onVis() {
        if (document.visibilityState === "hidden") onHide();
      }
      window.addEventListener("blur", onBlur);
      document.addEventListener("visibilitychange", onVis);

      setTimeout(function () { settle(false); }, OPEN_TIMEOUT_MS);

      // Trigger the URL scheme last so the listeners are attached first.
      window.location.href = url;
    });
  }

  function markInstalled() {
    try { localStorage.setItem(INSTALL_KEY, "1"); } catch (_) {}
  }

  // --- Download CTA ------------------------------------------------------

  function showDownloadFallback() {
    var dls = $$("[data-share-download]");
    dls.forEach(function (dl) { dl.hidden = false; });
  }

  function hideDownloadForever() {
    var dls = $$("[data-share-download]");
    dls.forEach(function (dl) { dl.remove(); });
  }

  // --- Wiring the button ---------------------------------------------------

  /* Attaches the click handler to a button, once.
   *
   * The handler is attached by id rather than by a flag the page sets, because
   * the page and this script are separate files and either could reasonably
   * change: this script may run before the page has built its button, and the
   * page may replace the button afterwards. Whichever happens, the button ends
   * up wired exactly once.
   */
  function wire(button) {
    if (!button || button.dataset.vibresiaWired === "1") return;
    var url = deepLinkURL(button);
    if (!url) return;

    button.dataset.vibresiaWired = "1";
    button.addEventListener("click", function (event) {
      event.preventDefault();
      tryOpenAndDetect(url).then(function (installed) {
        if (installed) {
          markInstalled();
          hideDownloadForever();
          // Browser will switch back to the tab a moment later if the user
          // returns to the page from the app, so nothing to do here.
        } else {
          showDownloadFallback();
        }
      });
    });
  }

  /* Wires every button on the page, now and later.
   *
   * The button is normally in the markup, so the first pass finds it at
   * DOMContentLoaded. The watcher is for the other case: a page that builds
   * its button after the payload has been decoded. That is exactly what the
   * custom share page used to do, and it is why "Open in Vibresia" stopped
   * opening the app — the decoder became async, so the button arrived after
   * this script had already looked for it and given up.
   */
  function wireAll(root) {
    var buttons = $$("[data-share-open]", root || document);
    buttons.forEach(wire);
  }

  // --- Main --------------------------------------------------------------

  function init() {
    // Hide the download CTA if the user has clearly used Open successfully
    // before. localStorage may be unavailable in some embed contexts, so
    // wrap the read defensively.
    var alreadyInstalled = false;
    try { alreadyInstalled = localStorage.getItem(INSTALL_KEY) === "1"; } catch (_) {}
    if (alreadyInstalled) hideDownloadForever();

    wireAll();

    // A button that appears later still gets wired. Cheap: the observer only
    // fires when the DOM changes, and the check inside it is a query.
    if (window.MutationObserver && document.body) {
      var observer = new MutationObserver(function (mutations) {
        for (var i = 0; i < mutations.length; i++) {
          var added = mutations[i].addedNodes;
          for (var j = 0; j < added.length; j++) {
            var node = added[j];
            if (node.nodeType !== 1) continue;
            if (node.matches && node.matches("[data-share-open]")) wire(node);
            wireAll(node);
          }
        }
      });
      observer.observe(document.body, { childList: true, subtree: true });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
