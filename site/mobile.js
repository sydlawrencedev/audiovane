// The phone version of the page.
//
// Two things, both of them about a phone that cannot do what a Mac can.
//
// The first is a way back to the Mac. "Download for Mac" hands a phone a
// zip it cannot install, which is a dead end at the top of the page and at
// the bottom of it. What a phone can do is hand the *link* to the Mac
// through the share sheet — which is where AirDrop and "Send to my Mac"
// live. So on a phone the button says that instead, and shares the link
// rather than the file. Where there is no share sheet, the link is copied:
// one tap, and the paste goes to the Mac.
//
// The second is the install instructions. A phone cannot run
// `curl … | bash`, the command is wider than the screen, and both of those
// are reasons to fold the block away rather than to leave it lying open.
//
// The phone test is the screen being small *and* the pointer being coarse,
// so a narrow window on a Mac still gets the download button it wants.

(function () {
  "use strict";

  var PHONE = "(max-width: 640px) and (pointer: coarse)";

  function phone() {
    return window.matchMedia(PHONE).matches;
  }

  /// What a Mac should get: the link to this page.
  ///
  /// On a share page that is the vibescape's own link, which is the thing
  /// worth sending. On the homepage it is the site, which is the thing
  /// worth opening on the Mac.
  function linkFor(el) {
    return el.getAttribute("data-send-url") || location.href;
  }

  /// Says something on the button for a moment.
  function say(button, text) {
    if (!button) return;
    var original = button.getAttribute("data-say-original") || button.textContent;
    button.setAttribute("data-say-original", original);
    button.textContent = text;
    setTimeout(function () { button.textContent = original; }, 2500);
  }

  /// Puts the link in the clipboard, and says so.
  function copy(url, button) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url).then(function () {
        say(button, "Link copied");
      }).catch(function () {
        say(button, "Copy this: " + url);
      });
    } else {
      say(button, "Copy this: " + url);
    }
  }

  /// The share sheet, or the clipboard.
  function share(el, button) {
    var url = linkFor(el);
    if (!navigator.share) {
      copy(url, button);
      return;
    }
    navigator.share({
      title: document.title,
      text: "Vibresia — free visual worlds for your music",
      url: url
    }).catch(function () {
      // The sheet was cancelled, or it said no. Either way the link is the
      // useful thing, so it goes to the clipboard where it can be pasted.
      copy(url, button);
    });
  }

  /// The install block, folded away on a phone.
  function foldInstall(small) {
    var install = document.getElementById("install");
    if (!install) return;
    function apply(isPhone) {
      if (isPhone) {
        install.removeAttribute("open");
      } else {
        install.setAttribute("open", "");
      }
    }
    // Somebody who followed a link straight to the install steps should
    // find them open, phone or not.
    if (location.hash === "#install") {
      install.setAttribute("open", "");
    } else {
      apply(small.matches);
    }
    small.addEventListener("change", function (e) { apply(e.matches); });
  }

  /// A share page on a phone.
  ///
  /// "Open in Vibresia" is a scheme a Mac app answers to, so on a phone it
  /// goes nowhere — which used to mean clicking it and then being offered a
  /// macOS zip. On a phone the button that works is the one that sends the
  /// link, so it is the button that is there.
  function sharePage(small) {
    function apply(isPhone) {
      var open = document.querySelectorAll("[data-share-open]");
      var download = document.querySelectorAll("[data-share-download]");
      for (var i = 0; i < open.length; i++) {
        open[i].hidden = isPhone;
      }
      for (var j = 0; j < download.length; j++) {
        if (isPhone) download[j].hidden = false;
      }
    }
    apply(small.matches);
    small.addEventListener("change", function (e) { apply(e.matches); });
  }

  function setup() {
    var buttons = Array.prototype.slice.call(document.querySelectorAll("[data-install]"));
    var small = window.matchMedia(PHONE);

    // Remember what the button said and what it counted as, so going back
    // to a Mac is the same as it was.
    buttons.forEach(function (el) {
      el.setAttribute("data-download-label", el.textContent.trim());
      el.setAttribute("data-download-track", el.getAttribute("data-track") || "");
    });

    function apply() {
      var isPhone = small.matches;
      buttons.forEach(function (el) {
        if (isPhone) {
          el.textContent = "Send to my Mac";
          el.setAttribute("data-track", "send_to_mac_clicked");
        } else {
          el.textContent = el.getAttribute("data-download-label");
          el.setAttribute("data-track", el.getAttribute("data-download-track"));
        }
      });
    }
    apply();
    small.addEventListener("change", apply);

    document.addEventListener("click", function (e) {
      var el = e.target.closest("[data-install]");
      if (!el || !small.matches) return; // a Mac gets the zip, as before
      e.preventDefault();
      share(el, el);
    });

    foldInstall(small);
    sharePage(small);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", setup);
  } else {
    setup();
  }
})();
