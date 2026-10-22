/* The four most recently shared vibescapes.
 *
 * The gallery is the full list; this is a short "have a look at these" at
 * the bottom of every share page, so that somebody who has been sent one
 * vibescape can find another without going looking for the gallery.
 *
 * The list is fetched rather than written into the page: the pages for the
 * built-in vibescapes are static files, and a share somebody made is
 * rendered by the Worker, and both have to show the same four.
 */
(function () {
  var grid = document.getElementById("recent-grid");
  var section = document.getElementById("recent");
  if (!grid || !section) return;

  fetch("/api/gallery", { headers: { accept: "application/json" } })
    .then(function (response) { return response.ok ? response.json() : null; })
    .then(function (data) {
      if (!data || !data.ok || !Array.isArray(data.vibescapes)) return;

      // The ones people have shared, newest first. The built-ins are in the
      // gallery too, but they are not "recently shared" — they have been
      // there since they were made.
      var here = window.location.pathname.replace(/\/$/, "");
      var recent = [];
      for (var i = 0; i < data.vibescapes.length && recent.length < 5; i++) {
        var item = data.vibescapes[i];
        if (!item || item.builtin) continue;
        // Not this one: the page you are already on is not a suggestion.
        if (pathOf(item.url) === here) continue;
        recent.push(item);
      }
      recent = recent.slice(0, 4);
      if (!recent.length) return;

      grid.innerHTML = recent.map(function (item) {
        return '<a class="recent-card" href="' + item.url + '">' +
          '<img src="' + item.imageUrl + '" alt="" loading="lazy">' +
          "<span>" + escapeText(item.name) + "</span></a>";
      }).join("");
      section.hidden = false;
    })
    .catch(function () {
      // No gallery, no section. A missing list is not worth an error.
    });

  function pathOf(url) {
    try { return new URL(url, window.location.origin).pathname.replace(/\/$/, ""); }
    catch (e) { return ""; }
  }

  function escapeText(text) {
    return String(text || "").replace(/[&<>"']/g, function (character) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[character];
    });
  }
})();
