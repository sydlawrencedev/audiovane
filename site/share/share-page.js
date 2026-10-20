/* Share page — what the recipient sees after someone sends them a Vibscape
 * link. Branches on the kind of vibscape:
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

  function deepLinkURL() {
    var open = $("[data-share-open]");
    if (!open) return null;
    var slug = open.getAttribute("data-share-slug");
    if (slug) return "vibresia://open?p=" + encodeURIComponent(slug);
    if (open.hasAttribute("data-share-custom")) {
      var d = new URL(window.location.href).searchParams.get("d");
      if (!d) return null;
      return "vibresia://open?d=" + d;
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
    var dl = $("[data-share-download]");
    if (dl) dl.hidden = false;
  }

  function hideDownloadForever() {
    var dl = $("[data-share-download]");
    if (dl) dl.remove();
  }

  // --- Main --------------------------------------------------------------

  function init() {
    // Hide the download CTA if the user has clearly used Open successfully
    // before. localStorage may be unavailable in some embed contexts, so
    // wrap the read defensively.
    var alreadyInstalled = false;
    try { alreadyInstalled = localStorage.getItem(INSTALL_KEY) === "1"; } catch (_) {}
    if (alreadyInstalled) hideDownloadForever();

    var open = $("[data-share-open]");
    if (!open) return;
    var url = deepLinkURL();
    if (!url) return;

    open.addEventListener("click", function (event) {
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

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
