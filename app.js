/* ParcelTrace — package tracking demo UI. Vanilla JS, reads window.PACKAGES. */
(function () {
  "use strict";

  var PKGS = (window.PACKAGES || []).slice();

  var STATUS_LABEL = {
    DELIVERED: "Delivered",
    IN_TRANSIT: "In transit",
    OUT_FOR_DELIVERY: "Out for delivery",
    EXCEPTION: "Exception",
    LABEL_CREATED: "Label created",
    RETURNED: "Returned",
  };
  var STATUS_ORDER = ["DELIVERED", "IN_TRANSIT", "OUT_FOR_DELIVERY", "EXCEPTION", "LABEL_CREATED", "RETURNED"];
  var MODE_ICON = { air: "✈️", truck: "🚚", rail: "🚆" };

  var state = { q: "", status: "", carrier: "", service: "", sortKey: "status", sortDir: 1 };

  // ---------- helpers ----------
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function fmtDate(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    return d.toLocaleDateString(undefined, { month: "short", day: "numeric" }) +
      ", " + d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  }
  function fmtDateShort(iso) {
    if (!iso) return "—";
    return new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric" });
  }
  function place(p) { return p.city + (p.state ? ", " + p.state : ", " + p.country); }
  function routeStr(p) { return p.origin.city + " → " + p.destination.city; }

  function badge(status) {
    return '<span class="badge" data-s="' + status + '"><span class="dot" data-s="' + status + '"></span>' +
      (STATUS_LABEL[status] || status) + "</span>";
  }

  // ---------- filtering + sorting ----------
  function filtered() {
    var q = state.q.trim().toLowerCase();
    var list = PKGS.filter(function (p) {
      if (state.status && p.status !== state.status) return false;
      if (state.carrier && p.carrier !== state.carrier) return false;
      if (state.service && p.serviceLevel !== state.service) return false;
      if (!q) return true;
      var hay = [p.trackingId, p.carrier, p.status, p.origin.city, p.destination.city,
        p.currentLocation.city, p.recipient.name, p.sender.name, p.sender.company,
        p.package.contentsCategory].join(" ").toLowerCase();
      return hay.indexOf(q) !== -1;
    });

    var k = state.sortKey, dir = state.sortDir;
    list.sort(function (a, b) {
      var av, bv;
      if (k === "route") { av = routeStr(a); bv = routeStr(b); }
      else if (k === "weightKg") { av = a.package.weightKg; bv = b.package.weightKg; }
      else if (k === "status") { av = STATUS_ORDER.indexOf(a.status); bv = STATUS_ORDER.indexOf(b.status); }
      else { av = a[k]; bv = b[k]; }
      if (av < bv) return -1 * dir;
      if (av > bv) return 1 * dir;
      return 0;
    });
    return list;
  }

  // ---------- render: stats ----------
  function renderStats() {
    var counts = {};
    PKGS.forEach(function (p) { counts[p.status] = (counts[p.status] || 0) + 1; });
    var cards = [{ key: "", label: "All", n: PKGS.length }].concat(
      STATUS_ORDER.filter(function (s) { return counts[s]; }).map(function (s) {
        return { key: s, label: STATUS_LABEL[s], n: counts[s] };
      })
    );
    document.getElementById("stats").innerHTML = cards.map(function (c) {
      return '<div class="stat' + (state.status === c.key ? " active" : "") + '" data-status="' + c.key + '">' +
        '<div class="n">' + c.n + "</div><div class=\"l\">" + c.label + "</div></div>";
    }).join("");
  }

  // ---------- render: filter dropdowns ----------
  function renderFilterOptions() {
    var carriers = {}, services = {};
    PKGS.forEach(function (p) { carriers[p.carrier] = 1; services[p.serviceLevel] = 1; });
    var cf = document.getElementById("carrierFilter");
    var sf = document.getElementById("serviceFilter");
    Object.keys(carriers).sort().forEach(function (c) {
      cf.insertAdjacentHTML("beforeend", '<option value="' + esc(c) + '">' + esc(c) + "</option>");
    });
    var svOrder = ["Overnight", "Express", "Standard", "Economy"];
    svOrder.filter(function (s) { return services[s]; }).forEach(function (s) {
      sf.insertAdjacentHTML("beforeend", '<option value="' + esc(s) + '">' + esc(s) + "</option>");
    });
  }

  // ---------- render: table ----------
  function renderTable() {
    var list = filtered();
    document.getElementById("resultCount").textContent =
      list.length + " of " + PKGS.length + " shipments";
    var tbody = document.getElementById("rows");
    document.getElementById("empty").style.display = list.length ? "none" : "block";

    tbody.innerHTML = list.map(function (p) {
      return '<tr data-id="' + esc(p.trackingId) + '">' +
        '<td class="mono tid">' + esc(p.trackingId) + "</td>" +
        '<td class="hide-sm muted">' + esc(p.carrier) + "</td>" +
        '<td class="hide-sm muted">' + esc(p.serviceLevel) + "</td>" +
        "<td>" + badge(p.status) + "</td>" +
        '<td class="route">' + esc(p.origin.city) + '<span class="arw">→</span>' + esc(p.destination.city) + "</td>" +
        '<td class="hide-sm muted">' + fmtDateShort(p.estimatedDelivery) + "</td>" +
        '<td class="hide-sm muted">' + p.package.weightKg + " kg</td>" +
        "</tr>";
    }).join("");

    // sort indicators
    Array.prototype.forEach.call(document.querySelectorAll("thead th"), function (th) {
      var a = th.querySelector(".arrow");
      if (!a) return;
      a.textContent = th.dataset.sort === state.sortKey ? (state.sortDir === 1 ? "▲" : "▼") : "";
    });
  }

  // ---------- render: detail drawer ----------
  function progressForStatus(status) {
    return { LABEL_CREATED: 8, IN_TRANSIT: 55, EXCEPTION: 55, OUT_FOR_DELIVERY: 90,
      DELIVERED: 100, RETURNED: 100 }[status] || 0;
  }

  function openDetail(id) {
    var p = PKGS.find(function (x) { return x.trackingId === id; });
    if (!p) return;

    document.getElementById("drawerHead").innerHTML =
      '<div class="top"><div><div class="tid">' + esc(p.trackingId) + "</div>" +
      '<div class="sub">' + esc(p.carrier) + " &middot; " + esc(p.serviceLevel) +
      " &middot; " + esc(p.package.contentsCategory) + "</div></div>" +
      '<button class="close-btn" id="closeBtn">&times;</button></div>' +
      '<div style="margin-top:14px">' + badge(p.status) + "</div>" +
      '<div class="progress"><div class="bar"><div class="fill" style="width:' +
      progressForStatus(p.status) + '%"></div></div>' +
      '<div class="labels"><span>' + esc(p.origin.city) + "</span><span>" +
      esc(p.destination.city) + "</span></div></div>";

    var body = "";

    if (p.exception) {
      body += '<div class="excbanner"><span style="font-size:16px">⚠️</span><div>' +
        '<div class="code">' + esc(p.exception.code) + "</div>" +
        '<div class="muted">' + esc(p.exception.description) + "</div></div></div>";
    }

    // key facts grid
    var dims = p.package.dimensionsCm;
    body += '<div class="info-grid">' +
      infoCard("Estimated delivery", fmtDate(p.estimatedDelivery)) +
      infoCard(p.deliveredAt ? "Delivered" : "Shipped",
        p.deliveredAt ? fmtDate(p.deliveredAt) : fmtDate(p.shippedAt)) +
      infoCard("Current location", place(p.currentLocation)) +
      infoCard("Weight", p.package.weightKg + " kg <small>&middot; " + p.package.pieces +
        (p.package.pieces > 1 ? " pieces" : " piece") + "</small>") +
      infoCard("Dimensions", dims.length + " &times; " + dims.width + " &times; " + dims.height + " cm") +
      infoCard("Declared value", "$" + p.package.declaredValueUSD.toLocaleString()) +
      '</div>';

    // flags/tags
    var tags = [];
    if (p.international) tags.push("International");
    if (p.package.fragile) tags.push("Fragile");
    if (p.package.signatureRequired) tags.push("Signature required");
    if (tags.length) {
      body += '<div class="tags">' + tags.map(function (t) {
        return '<span class="tag">' + esc(t) + "</span>";
      }).join("") + "</div>";
    }

    // sender / recipient
    body += '<div class="section-title">Sender &amp; recipient</div>' +
      '<div class="info-grid">' +
      infoCard("From", esc(p.sender.name) + (p.sender.company ? " <small>&middot; " + esc(p.sender.company) + "</small>" : "") +
        "<br><small>" + place(p.origin) + "</small>") +
      infoCard("To", esc(p.recipient.name) + "<br><small>" + place(p.destination) + "</small>") +
      "</div>";

    // itinerary
    if (p.itinerary && p.itinerary.length) {
      body += '<div class="section-title">Planned itinerary</div>';
      body += p.itinerary.map(function (leg) {
        return '<div class="leg"><div class="mode">' + (MODE_ICON[leg.mode] || "📦") + "</div>" +
          '<div class="path"><div class="r">' + esc(leg.from) + " → " + esc(leg.to) + "</div>" +
          '<div class="t">' + esc(leg.mode) + " &middot; dep " + fmtDateShort(leg.plannedDeparture) +
          " &middot; arr " + fmtDateShort(leg.plannedArrival) + "</div></div></div>";
      }).join("");
    }

    // scan timeline (most recent first)
    body += '<div class="section-title">Tracking history &middot; ' + p.scanEvents.length + " scans</div>";
    body += '<div class="timeline">';
    var evs = p.scanEvents.slice().reverse();
    body += evs.map(function (e, i) {
      return '<div class="ev' + (i === 0 ? " head" : "") + '">' +
        '<div class="desc">' + esc(e.description) + "</div>" +
        '<div class="meta">' + esc(e.facility) + " &middot; " + esc(place(e)) + "</div>" +
        '<div class="time">' + fmtDate(e.timestamp) + "</div></div>";
    }).join("");
    body += "</div>";

    document.getElementById("drawerBody").innerHTML = body;
    document.getElementById("drawerBody").scrollTop = 0;
    document.getElementById("drawer").classList.add("open");
    document.getElementById("overlay").classList.add("open");
    document.getElementById("drawer").setAttribute("aria-hidden", "false");
    document.getElementById("closeBtn").addEventListener("click", closeDetail);
  }

  function infoCard(k, v) {
    return '<div class="info-card"><div class="k">' + k + '</div><div class="v">' + v + "</div></div>";
  }

  function closeDetail() {
    document.getElementById("drawer").classList.remove("open");
    document.getElementById("overlay").classList.remove("open");
    document.getElementById("drawer").setAttribute("aria-hidden", "true");
  }

  // ---------- events ----------
  document.getElementById("search").addEventListener("input", function (e) {
    state.q = e.target.value; renderTable();
  });
  document.getElementById("stats").addEventListener("click", function (e) {
    var el = e.target.closest(".stat"); if (!el) return;
    state.status = el.dataset.status; renderStats(); renderTable();
  });
  document.getElementById("carrierFilter").addEventListener("change", function (e) {
    state.carrier = e.target.value; renderTable();
  });
  document.getElementById("serviceFilter").addEventListener("change", function (e) {
    state.service = e.target.value; renderTable();
  });
  document.querySelector("thead").addEventListener("click", function (e) {
    var th = e.target.closest("th"); if (!th || !th.dataset.sort) return;
    var k = th.dataset.sort;
    if (state.sortKey === k) state.sortDir *= -1; else { state.sortKey = k; state.sortDir = 1; }
    renderTable();
  });
  document.getElementById("rows").addEventListener("click", function (e) {
    var tr = e.target.closest("tr"); if (!tr) return;
    openDetail(tr.dataset.id);
  });
  document.getElementById("overlay").addEventListener("click", closeDetail);
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") closeDetail(); });

  // ---------- init ----------
  if (!PKGS.length) {
    document.getElementById("rows").innerHTML =
      '<tr><td colspan="7" class="empty">No data loaded. Did data/packages.js load?</td></tr>';
  } else {
    renderStats();
    renderFilterOptions();
    renderTable();
  }
})();
