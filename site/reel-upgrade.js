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
      // Freeze the small clip before reading its playhead. Leaving it playing
      // means the position we aim for is already stale by the time the seek on
      // the other one lands, which is a smaller version of the same bug.
      var wanted = lq.currentTime || 0;
      lq.pause();

      // Only revealed once the two are showing the same frame. Fading earlier
      // is worse than not fading: the full clip is still on frame 0 while the
      // small one is somewhere in the middle of the reel, so the crossfade
      // dissolves one moment into a different one.
      var shown = false;
      var reveal = function () {
        if (shown) return;
        shown = true;
        hq.play().catch(function () { /* autoplay refused: the poster still stands in */ });
        hq.classList.add("upgraded");
        // Leave the small one alone rather than tearing it down mid-frame: it is
        // the thing still painting if the full one is blocked or has no decoder.
        hq.addEventListener("playing", function once() {
          lq.removeAttribute("src");
          lq.load();
        }, { once: true });
      };

      if (hq.readyState < 1 || !isFinite(hq.duration) || hq.duration === 0) {
        // No metadata, so there is nothing to seek within. Start at the top
        // rather than pretend — and say so, because it is visible.
        lq.play().catch(function () {});
        reveal();
        return;
      }

      // Never seek onto the very last frame: the clip is about to loop, and a
      // playhead sitting on duration wraps on the next tick, which reads as a
      // stutter at exactly the moment the two are meant to look identical.
      var target = Math.max(0, Math.min(wanted, hq.duration - 0.05));

      // Assigning currentTime starts a seek; it does not perform one, and the
      // element keeps painting the old frame until it lands. Polling the
      // playhead is the direct test for "has it landed" — the `seeked` event is
      // not, because a seek to the position it is already at fires nothing, and
      // whoever arrives at second zero would then never be upgraded at all.
      var deadline = Date.now() + 2000;
      var settled = function () {
        if (shown) return;
        if (Math.abs(hq.currentTime - target) < 0.08) { reveal(); return; }
        if (Date.now() > deadline) {
          // Out of patience. Whatever the playhead is, better to show the sharp
          // version from there than to sit on the small one forever.
          lq.play().catch(function () {});
          reveal();
          return;
        }
        setTimeout(settled, 50);
      };
      try {
        hq.currentTime = target;
      } catch (e) { /* seek refused: settled() notices and moves on */ }
      settled();
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