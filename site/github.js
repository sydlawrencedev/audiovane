// Changelog and open issues, straight from the GitHub API.
//
// Both are fetched from the browser rather than baked into the page, so they
// can't go stale between deploys — and neither costs anything until someone
// scrolls to them. Three things keep it honest:
//
//   * **Cached** (sessionStorage, 15 minutes) because GitHub's unauthenticated
//     API allows 60 requests an hour per IP, and every visitor here would be
//     spending from the same one.
//   * **Lazy** — the fetch starts when the section scrolls into view.
//   * **Never fatal** — if GitHub is down, rate-limiting us, or the JSON moved,
//     the section says so and leaves a link behind. A marketing page that
//     renders half-empty is worse than one that links out.
//
// Everything from GitHub is rendered through `textContent`, never innerHTML:
// issue titles are whatever someone typed into a text box.
(function () {
  "use strict";

  var REPO = "sydlawrencedev/vibresia";
  var API = "https://api.github.com/repos/" + REPO;
  var CACHE_KEY = "vibresia.github";
  var CACHE_TTL = 15 * 60 * 1000;
  var MAX_RELEASES = 6;
  var MAX_ISSUES = 8;

  function readCache() {
    try {
      var raw = sessionStorage.getItem(CACHE_KEY);
      if (!raw) return {};
      var parsed = JSON.parse(raw);
      if (!parsed || !parsed.at || Date.now() - parsed.at > CACHE_TTL) return {};
      return parsed.data || {};
    } catch (e) {
      return {}; // private mode: just fetch
    }
  }

  function writeCache(data) {
    try {
      sessionStorage.setItem(CACHE_KEY, JSON.stringify({ at: Date.now(), data: data }));
    } catch (e) { /* nothing to do */ }
  }

  var cache = readCache();

  function fetchJSON(path) {
    return fetch(API + path, {
      headers: { Accept: "application/vnd.github+json" },
    }).then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.json();
    });
  }

  function get(key, path, fallback) {
    if (cache[key]) return Promise.resolve(cache[key]);
    return fetchJSON(path).then(function (data) {
      cache[key] = data;
      writeCache(cache);
      return data;
    }).catch(function (error) {
      fallback(error);
      return null;
    });
  }

  // --- Rendering ---------------------------------------------------------

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function card(item) {
    var node = el("article", "gh-card");
    var link = el("a", "gh-card-link");
    link.href = item.url;
    link.target = "_blank";
    link.rel = "noopener";

    var head = el("div", "gh-card-head");
    if (item.meta) head.appendChild(el("span", "gh-meta", item.meta));
    head.appendChild(el("span", "gh-date", item.date));
    link.appendChild(head);
    link.appendChild(el("h3", "gh-title", item.title));
    if (item.body) link.appendChild(el("p", "gh-body", item.body));
    node.appendChild(link);
    return node;
  }

  function fill(container, items, emptyMessage) {
    container.textContent = "";
    if (!items.length) {
      container.appendChild(el("p", "gh-empty", emptyMessage));
      return;
    }
    var list = el("div", "gh-list");
    items.forEach(function (item) { list.appendChild(card(item)); });
    container.appendChild(list);
  }

  // The repository link is always present, so an empty or failed section is
  // still a way in rather than a dead end.
  function footerLink(container, label) {
    var link = el("a", "gh-more", label);
    link.href = "https://github.com/" + REPO;
    link.target = "_blank";
    link.rel = "noopener";
    container.appendChild(link);
  }

  function shortDate(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    return d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
  }

  // Release notes are plain prose today; strip the markdown that would
  // otherwise show up literally if someone starts using it.
  function plain(markdown) {
    return String(markdown || "")
      .replace(/```[\s\S]*?```/g, "")
      .replace(/^\s*#+\s*/gm, "")
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/[*_`>]/g, "")
      .replace(/\n{2,}/g, " ")
      .trim();
  }

  function renderReleases(container) {
    get("releases", "/releases?per_page=" + MAX_RELEASES, function (error) {
      console.warn("[github] releases:", error);
    }).then(function (data) {
      if (!data) return;
      var items = data.map(function (release) {
        return {
          meta: (release.tag_name || "").replace(/^v/, ""),
          date: shortDate(release.published_at),
          title: release.name || release.tag_name || "",
          body: plain(release.body),
          url: release.html_url,
        };
      }).filter(function (item) { return item.title; });
      fill(container, items, "No releases yet.");
      footerLink(container, "All releases on GitHub →");
    });
  }

  function renderIssues(container) {
    get("issues", "/issues?state=open&per_page=" + (MAX_ISSUES + 4), function (error) {
      console.warn("[github] issues:", error);
    }).then(function (data) {
      if (!data) return;
      // The issues endpoint returns pull requests too — they're issues with an
      // extra field, and they're not what's being shown here.
      var items = data
        .filter(function (issue) { return !issue.pull_request; })
        .slice(0, MAX_ISSUES)
        .map(function (issue) {
          var labels = (issue.labels || []).map(function (l) { return l.name; });
          return {
            meta: labels.length ? labels.join(" · ") : "bug",
            date: shortDate(issue.created_at),
            title: issue.title,
            url: issue.html_url,
          };
        });
      fill(container, items, "No open issues right now.");
      footerLink(container, "Report something on GitHub →");
    });
  }

  // --- Wiring ------------------------------------------------------------

  var sections = [
    { id: "changelog-list", render: renderReleases },
    { id: "issues-list", render: renderIssues },
  ].map(function (entry) {
    return { container: document.getElementById(entry.id), render: entry.render };
  }).filter(function (entry) { return entry.container; });

  if (!sections.length) return;

  function load(entry) { entry.render(entry.container); }

  if (!("IntersectionObserver" in window)) {
    sections.forEach(load);
    return;
  }
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      observer.unobserve(entry.target);
      sections.forEach(function (section) {
        if (section.container === entry.target) load(section);
      });
    });
  }, { rootMargin: "200px" });
  sections.forEach(function (section) { observer.observe(section.container); });
})();