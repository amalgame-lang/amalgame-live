/* Amalgame Live — client logic, zero dependencies.
 *
 * Two entry points: Amalgame.projector() for the big screen, and
 * Amalgame.phone() for attendees. Everything renders via textContent,
 * never innerHTML, so nothing the room types can execute on the
 * projector. */
(function () {
  "use strict";

  function getJSON(url) {
    return fetch(url, { cache: "no-store" }).then(function (r) { return r.json(); });
  }
  function postJSON(url, body) {
    return fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }).then(function (r) { return r.json(); });
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  /* ---- projector ---- */
  function projector() {
    var joinUrl = location.origin + "/join";
    var urlEl = document.getElementById("joinurl");
    if (urlEl) urlEl.textContent = location.host + "/join";

    var qr = document.getElementById("qr");
    if (qr) {
      // Prefer a self-hosted /qr.png if it exists; otherwise fall back
      // to a public QR image service. The URL text above always works
      // even if the image never loads.
      qr.src = "/qr.png";
      qr.onerror = function () {
        qr.onerror = null;
        qr.src = "https://api.qrserver.com/v1/create-qr-code/?size=320x320&margin=8&data="
          + encodeURIComponent(joinUrl);
      };
    }

    function renderPoll(state) {
      document.getElementById("question").textContent = state.question;

      var total = 0;
      state.options.forEach(function (o) { total += o.votes; });

      var poll = document.getElementById("poll");
      poll.textContent = "";
      state.options.forEach(function (o) {
        var pct = total > 0 ? Math.round((o.votes / total) * 100) : 0;
        var row = el("div", "bar-row");
        var head = el("div", "bar-head");
        head.appendChild(el("span", "bar-label", o.label));
        head.appendChild(el("span", "bar-count", o.votes + " · " + pct + "%"));
        var track = el("div", "bar-track");
        var fill = el("div", "bar-fill");
        fill.style.width = pct + "%";
        track.appendChild(fill);
        row.appendChild(head);
        row.appendChild(track);
        poll.appendChild(row);
      });
    }

    var lastCount = -1;
    function renderWall(state) {
      var wall = document.getElementById("wall");
      // Only rebuild when the message list changed, so older cards
      // keep their entry animation instead of restarting every second.
      if (state.messages.length === lastCount) return;
      lastCount = state.messages.length;
      wall.textContent = "";
      // Newest first on screen.
      state.messages.slice().reverse().forEach(function (m) {
        var card = el("div", "card");
        card.appendChild(el("span", "card-emoji", m.emoji || "💬"));
        if (m.text) card.appendChild(el("span", "card-text", m.text));
        wall.appendChild(card);
      });
    }

    function tick() {
      getJSON("/api/state").then(function (s) {
        renderPoll(s);
        renderWall(s);
      }).catch(function () {});
    }
    tick();
    setInterval(tick, 1000);
  }

  /* ---- phone ---- */
  function phone() {
    var toastTimer = null;
    function toast(msg) {
      var t = document.getElementById("toast");
      t.textContent = msg;
      t.classList.add("show");
      clearTimeout(toastTimer);
      toastTimer = setTimeout(function () { t.classList.remove("show"); }, 1400);
    }

    function renderOptions(state) {
      document.getElementById("question").textContent = state.question;
      var box = document.getElementById("options");
      box.textContent = "";
      state.options.forEach(function (o, i) {
        var b = el("button", "opt", o.label);
        b.addEventListener("click", function () {
          postJSON("/api/vote", { i: i }).then(function () {
            toast("Vote pris en compte ✓");
          }).catch(function () { toast("Oups, réessayez"); });
        });
        box.appendChild(b);
      });
    }

    document.querySelectorAll(".emoji").forEach(function (b) {
      b.addEventListener("click", function () {
        postJSON("/api/react", { emoji: b.dataset.emoji, text: "" })
          .then(function () { toast(b.dataset.emoji + " envoyé !"); })
          .catch(function () { toast("Oups, réessayez"); });
      });
    });

    var form = document.getElementById("msgform");
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      var input = document.getElementById("msg");
      var text = (input.value || "").trim();
      if (!text) return;
      postJSON("/api/react", { emoji: "💬", text: text }).then(function () {
        input.value = "";
        toast("Message envoyé ✓");
      }).catch(function () { toast("Oups, réessayez"); });
    });

    function tick() {
      getJSON("/api/state").then(renderOptions).catch(function () {});
    }
    tick();
    setInterval(tick, 3000);
  }

  window.Amalgame = { projector: projector, phone: phone };
})();
