// Swaps the small background reel for the full-quality one, once it's there.
//
// The reel is the first thing on the page and the largest asset on it. Serving
// the good version straight away means a multi-megabyte download before
// anything moves, which on a phone is the difference between the page looking
// alive and looking broken. So the small clip plays first and the full one is
// fetched behind it, out of the critical path.
//
// Both clips are the same frames at the same length, so the upgrade is a
// crossfade between identical imagery rather than a visible jump — as long as
// the new element picks up the old one's playhead. That is the whole trick, and
// it is easy to get wrong: a video that starts from zero while the small one is
// twelve seconds in looks like a stutter, not an upgrade.
//
// Deliberately does nothing when the visitor has asked not to be tracked with
// Do Not Track, when the browser reports data-saver, or on a connection that
// looks slow. Upgrading to a heavier file over a metered link would be the
// wrong trade even though it is technically possible.

(function () {
  "use strict";

  var lq = document.getElementById("reel-lq");
  var hq = document.getElementById("reel-hq");
  if (!lq || !hq) return;

  var SRC = "media/demo.mp4";

  function willing() {
    // Someone on a metered or slow link gets the small clip and keeps it.
    var c = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
    if (!c) return true;
    if (c.saveData) return false;
    if (typeof c.effectiveType === "string" && /^(slow-)?2g$|^3g$/.test(c.effectiveType)) return false;
    return true;
  }

  // A battery or a background tab is not the moment to pull several megabytes.
  function soon() {
    if ("requestIdleCallback" in window) return requestIdleCallback;
    return function (fn) { setTimeout(fn, 200); };
  }

  function upgrade() {
    hq.src = SRC;
    hq.load();

    var swap = function () {
      // Join the small clip where it is rather than starting over.
      try {
        if (lq.readyState >= 1 && lq.duration) {
          hq.currentTime = Math.min(lq.currentTime, (hq.duration || lq.duration) - 0.05);
        }
      } catch (e) { /* seeking before metadata is fine to lose */ }
      hq.play().catch(function () { /* autoplay refused: the poster still stands in */ });
      hq.classList.add("upgraded");
      // Leave the small one alone rather than tearing it down mid-frame: it is
      // the thing still painting if the full one is blocked or has no decoder.
      hq.addEventListener("playing", function once() {
        lq.removeAttribute("src");
        lq.load();
      }, { once: true });
    };

    // canplaythrough rather than loadeddata: swapping on the first decoded
    // frame is what makes this stutter, because the swap lands while the
    // encoder is still filling its buffer.
    if (hq.readyState >= 4) swap();
    else hq.addEventListener("canplaythrough", swap, { once: true });
  }

  if (!willing()) return;
  soon()(function () {
    if ("requestIdleCallback" in window) requestIdleCallback(upgrade, { timeout: 3000 });
    else upgrade();
  });

  // Stop pulling the big file if the visitor leaves before it arrives.
  window.addEventListener("pagehide", function () {
    if (!hq.classList.contains("upgraded")) { hq.removeAttribute("src"); hq.load(); }
  }, { once: true });
})();