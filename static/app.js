/* AI Spend Tracker — low CPU: 60s poll, pause when hidden. Local UI prefs only. */
(() => {
  function syncViewportClass() {
    try {
      const params = new URLSearchParams(location.search);
      const desk = params.has('desk')
        || params.get('source') === 'pwa'
        || window.matchMedia('(display-mode: standalone)').matches
        || window.matchMedia('(display-mode: minimal-ui)').matches;
      const mobile = window.matchMedia('(max-width: 720px)').matches
        || /Mobi|Android|iPhone|iPad/i.test(navigator.userAgent || '');
      document.documentElement.classList.toggle('desk', !!desk && !mobile);
      document.documentElement.classList.toggle('mobile', !!mobile);
      const hint = document.getElementById('privacy-hint');
      if (hint) {
        hint.textContent = mobile
          ? (document.body.classList.contains('privacy') ? 'Tap masked values to reveal' : 'Privacy mask optional')
          : 'Privacy mask optional';
      }
    } catch (_) {}
  }
  syncViewportClass();
  try {
    window.matchMedia('(max-width: 720px)').addEventListener('change', syncViewportClass);
  } catch (_) {}

  const POLL_MS = 60_000;
  const REFRESH_TIMEOUT_MS = 30_000;
  const DEFAULT_VISIBLE = ["xai-console", "grok-cursor", "higgsfield", "suno"];
  const PREF_KEY = "ai-spend-tracker-prefs-v3";
  const PREF_KEY_LEGACY = "ai-spend-tracker-prefs-v2";
  const THEME_COLORS = { dark: "#141820", light: "#f7f8fb" };

  const modal = document.getElementById("modal");
  const titlebar = document.getElementById("titlebar");
  const tbody = document.getElementById("rows");
  const updatedEl = document.getElementById("updated");
  const statusEl = document.getElementById("poll-status");
  const refreshBtn = document.getElementById("refresh");
  const refreshLabel = refreshBtn ? refreshBtn.querySelector(".btn-label") : null;
  const errEl = document.getElementById("error");
  const privacyEl = document.getElementById("privacy");
  const filterEl = document.getElementById("filter");
  const themeEl = document.getElementById("theme");
  const manageBtn = document.getElementById("manage-rows");
  const rowPanel = document.getElementById("row-panel");
  const rowList = document.getElementById("row-list");
  const rowDone = document.getElementById("row-panel-done");
  const fetchChip = document.getElementById("fetch-chip");
  const themeColorMeta = document.getElementById("theme-color")
    || document.querySelector('meta[name="theme-color"]');

  let timer = null;
  let fetchedAgoTimer = null;
  let fetching = false;
  let abortCtrl = null;
  let lastFetchAt = 0;
  let lastData = { rows: [] };
  let demoMode = false;
  let prefs = loadPrefs();
  let systemThemeMql = null;

  function defaults() {
    return {
      privacy: false,
      filter: "all",
      theme: "system",
      order: DEFAULT_VISIBLE.slice(),
      hidden: [],
    };
  }
  function loadPrefs() {
    try {
      let raw = localStorage.getItem(PREF_KEY);
      if (!raw) {
        const legacy = localStorage.getItem(PREF_KEY_LEGACY);
        if (legacy) {
          const parsed = JSON.parse(legacy);
          const migrated = { ...defaults(), ...parsed, theme: parsed.theme || "system" };
          localStorage.setItem(PREF_KEY, JSON.stringify(migrated));
          return migrated;
        }
      } else {
        return { ...defaults(), ...JSON.parse(raw) };
      }
    } catch (_) {}
    return defaults();
  }
  function savePrefs() {
    localStorage.setItem(PREF_KEY, JSON.stringify(prefs));
  }

  function resolvedTheme() {
    const t = prefs.theme || "system";
    if (t === "light" || t === "dark") return t;
    try {
      return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
    } catch (_) {
      return "dark";
    }
  }

  function applyTheme() {
    const mode = prefs.theme || "system";
    const resolved = resolvedTheme();
    if (mode === "system") {
      document.documentElement.removeAttribute("data-theme");
    } else {
      document.documentElement.setAttribute("data-theme", mode);
    }
    if (themeColorMeta) {
      themeColorMeta.setAttribute("content", THEME_COLORS[resolved] || THEME_COLORS.dark);
    }
    if (themeEl) themeEl.value = mode;
  }

  function bindSystemThemeListener() {
    try {
      if (systemThemeMql) {
        systemThemeMql.removeEventListener("change", onSystemThemeChange);
      }
      systemThemeMql = window.matchMedia("(prefers-color-scheme: light)");
      systemThemeMql.addEventListener("change", onSystemThemeChange);
    } catch (_) {}
  }
  function onSystemThemeChange() {
    if ((prefs.theme || "system") === "system") applyTheme();
  }

  function fmt(v) {
    if (v == null || v === "") return "—";
    return String(v);
  }

  function limitCell(row) {
    const lim = row.limit;
    const per = row.limit_period;
    if (lim == null || lim === "") {
      return per ? `— / ${per}` : "—";
    }
    const limStr = String(lim);
    if (!per) return limStr;
    const perL = String(per).toLowerCase();
    const limL = limStr.toLowerCase();
    if (limL.includes(perL) || (perL === "month" && /\/\s*mo\b|\bper\s*month\b|\bmonthly\b/.test(limL))) {
      return limStr;
    }
    if (perL === "week" && /\/\s*wk\b|\bweekly\b/.test(limL)) return limStr;
    return `${limStr} / ${per}`;
  }

  function badgeClass(status) {
    const s = (status || "").toUpperCase();
    if (["OK", "STALE", "EMAIL", "CONNECTOR", "NEEDS_API", "NEEDS_LOGIN", "NEEDS_BROWSER", "NEEDS_MGMT_KEY"].includes(s)) {
      return s;
    }
    return "STALE";
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function maskText(s) {
    const t = String(s);
    if (!t || t === "—") return t;
    return "×".repeat(Math.min(Math.max(t.replace(/\s+/g, " ").trim().length, 6), 28));
  }

  function sensitiveSpan(kind, text) {
    const real = fmt(text);
    if (!prefs.privacy || real === "—") {
      return escapeHtml(real);
    }
    const masked = maskText(real);
    return `<span class="maskable" data-kind="${kind}" data-real="${escapeHtml(real)}" data-mask="${escapeHtml(masked)}">${escapeHtml(masked)}</span>`;
  }

  function catalogRows(data) {
    const byId = {};
    for (const r of data.rows || []) {
      if (r && r.id) byId[r.id] = r;
    }
    const seen = new Set(prefs.order);
    for (const id of DEFAULT_VISIBLE) {
      if (!seen.has(id) && byId[id]) {
        prefs.order.push(id);
        seen.add(id);
      }
    }
    for (const id of Object.keys(byId)) {
      if (!seen.has(id)) {
        prefs.order.push(id);
        seen.add(id);
      }
    }
    return prefs.order.map((id) => byId[id]).filter(Boolean);
  }

  function visibleRows(data) {
    const hidden = new Set(prefs.hidden || []);
    let rows = catalogRows(data).filter((r) => !hidden.has(r.id));
    if (prefs.filter === "ok") {
      rows = rows.filter((r) => String(r.status || "").toUpperCase() === "OK");
    } else if (prefs.filter === "issues") {
      rows = rows.filter((r) => String(r.status || "").toUpperCase() !== "OK");
    }
    return rows;
  }

  function bindMaskHover(root) {
    root.querySelectorAll(".maskable").forEach((el) => {
      el.addEventListener("pointerenter", () => {
        if (window.matchMedia("(hover: hover)").matches) {
          el.textContent = el.getAttribute("data-real") || "";
        }
      });
      el.addEventListener("pointerleave", () => {
        if (window.matchMedia("(hover: hover)").matches) {
          el.textContent = el.getAttribute("data-mask") || "";
        }
      });
      el.addEventListener("click", (e) => {
        if (!prefs.privacy) return;
        e.preventDefault();
        const showing = el.getAttribute("data-showing") === "1";
        if (showing) {
          el.textContent = el.getAttribute("data-mask") || "";
          el.setAttribute("data-showing", "0");
        } else {
          el.textContent = el.getAttribute("data-real") || "";
          el.setAttribute("data-showing", "1");
        }
      });
    });
  }

  function render(data) {
    lastData = data || lastData;
    updatedEl.textContent = lastData.updated_at_pt || lastData.meta?.updated_at_pt || "—";
    document.body.classList.toggle("privacy", !!prefs.privacy);
    privacyEl.checked = !!prefs.privacy;
    filterEl.value = prefs.filter || "all";

    const rows = visibleRows(lastData);
    if (!rows.length) {
      tbody.innerHTML = `<tr><td colspan="6" class="empty">No rows (check filter / hidden)</td></tr>`;
      return;
    }
    tbody.innerHTML = rows.map((r) => {
      const st = (r.status || "?").toUpperCase();
      const note = r.note
        ? `<div class="note">${sensitiveSpan("note", r.note)}</div>`
        : "";
      return `<tr data-id="${escapeHtml(r.id)}">
        <td class="account" data-label="Account">${escapeHtml(r.account || r.id || "?")}${note}<span class="status-inline"><span class="badge ${badgeClass(st)}">${escapeHtml(st)}</span></span></td>
        <td class="sub" data-label="Plan">${escapeHtml(fmt(r.sub_level))}</td>
        <td class="limit" data-label="Limit">${sensitiveSpan("limit", limitCell(r))}</td>
        <td class="current" data-label="Spend / balance">${sensitiveSpan("current", fmt(r.current))}</td>
        <td class="reset" data-label="Next reset">${escapeHtml(fmt(r.next_reset))}</td>
        <td class="status" data-label="Status"><span class="badge ${badgeClass(st)}">${escapeHtml(st)}</span></td>
      </tr>`;
    }).join("");
    bindMaskHover(tbody);
  }

  function renderRowPanel() {
    const byId = {};
    for (const r of lastData.rows || []) if (r.id) byId[r.id] = r;
    const hidden = new Set(prefs.hidden || []);
    rowList.innerHTML = catalogRows(lastData).map((r) => {
      const isHidden = hidden.has(r.id);
      return `<li draggable="true" data-id="${escapeHtml(r.id)}" class="${isHidden ? "hidden-row" : ""}">
        <span class="handle" title="Drag">⋮⋮</span>
        <button type="button" class="eye" data-id="${escapeHtml(r.id)}" title="${isHidden ? "Show" : "Hide"}">${isHidden ? "Show" : "Hide"}</button>
        <span>${escapeHtml(r.account || r.id)}</span>
      </li>`;
    }).join("");

    let dragId = null;
    rowList.querySelectorAll("li").forEach((li) => {
      li.addEventListener("dragstart", () => { dragId = li.getAttribute("data-id"); });
      li.addEventListener("dragover", (e) => { e.preventDefault(); });
      li.addEventListener("drop", (e) => {
        e.preventDefault();
        const toId = li.getAttribute("data-id");
        if (!dragId || !toId || dragId === toId) return;
        const order = prefs.order.slice();
        const from = order.indexOf(dragId);
        const to = order.indexOf(toId);
        if (from < 0 || to < 0) return;
        order.splice(from, 1);
        order.splice(to, 0, dragId);
        prefs.order = order;
        savePrefs();
        render(lastData);
        renderRowPanel();
      });
    });
    rowList.querySelectorAll(".eye").forEach((btn) => {
      btn.addEventListener("click", () => {
        const id = btn.getAttribute("data-id");
        const set = new Set(prefs.hidden || []);
        if (set.has(id)) set.delete(id); else set.add(id);
        prefs.hidden = [...set];
        savePrefs();
        render(lastData);
        renderRowPanel();
      });
    });
  }

  function setRefreshBusy(busy) {
    if (!refreshBtn) return;
    refreshBtn.disabled = !!busy;
    refreshBtn.classList.toggle("busy", !!busy);
    if (refreshLabel) refreshLabel.textContent = busy ? "Refreshing…" : "Refresh";
  }

  function showError(msg, canRetry) {
    if (!errEl) return;
    errEl.textContent = "";
    errEl.appendChild(document.createTextNode(msg));
    if (canRetry) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "retry-link";
      btn.textContent = "Retry";
      btn.addEventListener("click", () => fetchSpend(true));
      errEl.appendChild(btn);
    }
  }

  function clearError() {
    if (errEl) errEl.textContent = "";
  }

  function flashChip(text, kind) {
    if (!fetchChip) return;
    fetchChip.hidden = false;
    fetchChip.textContent = text;
    fetchChip.className = "chip " + (kind || "") + " flash";
    window.clearTimeout(flashChip._t);
    flashChip._t = window.setTimeout(() => {
      fetchChip.classList.remove("flash");
    }, 1400);
  }

  function formatAgo(ms) {
    if (!ms || ms < 0) return "just now";
    const s = ms / 1000;
    if (s < 1.05) return "just now";
    if (s < 60) return `${s.toFixed(1)}s ago`;
    const m = Math.floor(s / 60);
    return `${m}m ago`;
  }

  function updateStatusLine(extra) {
    if (!statusEl) return;
    if (document.hidden) {
      statusEl.textContent = "Paused (tab hidden)";
      return;
    }
    if (fetching) {
      statusEl.textContent = extra || "Refreshing…";
      return;
    }
    const parts = [demoMode ? "Demo · 60s" : "Live · 60s"];
    if (lastFetchAt) {
      parts.push(`Fetched ${formatAgo(Date.now() - lastFetchAt)}`);
    }
    if (extra) parts.push(extra);
    statusEl.textContent = parts.join(" · ");
  }

  function startFetchedAgoTicker() {
    if (fetchedAgoTimer) clearInterval(fetchedAgoTimer);
    fetchedAgoTimer = setInterval(() => {
      if (!fetching && !document.hidden && lastFetchAt) updateStatusLine();
    }, 1000);
  }

  async function fetchSpend(manual = false) {
    if (fetching) return;
    fetching = true;
    if (abortCtrl) {
      try { abortCtrl.abort(); } catch (_) {}
    }
    abortCtrl = new AbortController();
    const timeoutId = setTimeout(() => {
      try { abortCtrl.abort(); } catch (_) {}
    }, REFRESH_TIMEOUT_MS);

    if (manual) setRefreshBusy(true);
    updateStatusLine(manual ? "Refreshing…" : "Polling…");
    if (manual && fetchChip) {
      fetchChip.hidden = false;
      fetchChip.className = "chip warn";
      fetchChip.textContent = demoMode ? "Demo…" : "Refreshing…";
    }

    const t0 = performance.now();
    const DEMO_URLS = ["/demo-spend.json", "/cache/spend.example.json"];
    // Live static drop-ins (Hatch / private host overwrite) — tried before demo.
    const LIVE_STATIC_URLS = ["/spend-live.json", "/spend.json"];

    async function loadJson(url) {
      const res = await fetch(url, {
        method: "GET",
        cache: "no-store",
        signal: abortCtrl.signal,
      });
      if (!res.ok) {
        const err = new Error("HTTP " + res.status);
        err.status = res.status;
        throw err;
      }
      return res.json();
    }

    async function loadDemo() {
      let lastErr = null;
      for (const u of DEMO_URLS) {
        try {
          const data = await loadJson(u);
          demoMode = true;
          return data;
        } catch (e) {
          lastErr = e;
        }
      }
      throw lastErr || new Error("Demo JSON missing");
    }

    async function loadLiveStatic() {
      const bust = manual ? "?t=" + Date.now() : "";
      let lastErr = null;
      for (const u of LIVE_STATIC_URLS) {
        try {
          const data = await loadJson(u + bust);
          demoMode = false;
          return data;
        } catch (e) {
          lastErr = e;
        }
      }
      throw lastErr || new Error("No live static JSON");
    }

    try {
      let data;
      let fromDemo = false;
      if (demoMode) {
        data = await loadDemo();
        fromDemo = true;
      } else {
        try {
          const bust = manual ? "?t=" + Date.now() : "";
          const url = (manual ? "/api/spend/refresh" : "/api/spend") + bust;
          data = await loadJson(url);
          demoMode = false;
        } catch (e) {
          const st = e && e.status;
          const tryStatic = (st === 404 || st === 405 || st === 501)
            || /Failed to fetch|NetworkError|Load failed/i.test(String(e.message || e));
          if (tryStatic) {
            try {
              data = await loadLiveStatic();
              fromDemo = false;
            } catch (_) {
              try {
                data = await loadDemo();
                fromDemo = true;
              } catch (e2) {
                throw e;
              }
            }
          } else {
            throw e;
          }
        }
      }

      const elapsedMs = Math.round(performance.now() - t0);
      const durationMs = (data.refresh && data.refresh.duration_ms) || elapsedMs;
      clearError();
      render(data);
      if (!rowPanel.hidden) renderRowPanel();
      lastFetchAt = Date.now();

      if (fromDemo || demoMode) {
        if (fetchChip) {
          fetchChip.hidden = false;
          fetchChip.className = "chip ok";
          fetchChip.textContent = "Demo";
        }
        if (manual) {
          const secs = (durationMs / 1000).toFixed(1);
          flashChip("Demo", "ok");
          updateStatusLine("Demo reload " + secs + "s");
          window.setTimeout(() => updateStatusLine(), 2500);
        } else {
          updateStatusLine();
        }
      } else if (manual) {
        const ok = !data.refresh || data.refresh.ok !== false;
        const secs = (durationMs / 1000).toFixed(1);
        flashChip(ok ? "Refreshed " + secs + "s" : "Refresh issue", ok ? "ok" : "warn");
        updateStatusLine("Refreshed in " + secs + "s");
        window.setTimeout(() => updateStatusLine(), 2500);
      } else {
        updateStatusLine();
      }
      if (data.refresh && data.refresh.ok === false && data.refresh.error) {
        showError("Refresh warning: " + data.refresh.error, true);
      }
    } catch (e) {
      const aborted = e && (e.name === "AbortError" || /abort/i.test(String(e.message || "")));
      const msg = aborted
        ? "Refresh timed out (host busy or collector slow)."
        : "Fetch failed: " + (e.message || e);
      const offline = /Failed to fetch|NetworkError|Load failed/i.test(String(e.message || e));
      showError(offline ? "Offline / host down. " + msg : msg, true);
      statusEl.textContent = offline ? "Offline / host down" : (aborted ? "Timed out" : "Error");
      if (fetchChip) {
        fetchChip.hidden = false;
        fetchChip.className = "chip bad";
        fetchChip.textContent = offline ? "Offline" : "Error";
      }
    } finally {
      clearTimeout(timeoutId);
      fetching = false;
      if (manual) setRefreshBusy(false);
      if (!document.hidden && statusEl && !/Offline|Error|Timed out/.test(statusEl.textContent || "")) {
        updateStatusLine();
      }
    }
  }

  function clearTimer() {
    if (timer) { clearInterval(timer); timer = null; }
  }
  function startTimer() {
    clearTimer();
    if (document.hidden) {
      statusEl.textContent = "Paused (tab hidden)";
      return;
    }
    timer = setInterval(() => fetchSpend(false), POLL_MS);
    updateStatusLine();
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      clearTimer();
      statusEl.textContent = "Paused (tab hidden)";
    } else {
      fetchSpend(false);
      startTimer();
    }
  });

  refreshBtn.addEventListener("click", () => fetchSpend(true));
  privacyEl.addEventListener("change", () => {
    prefs.privacy = privacyEl.checked;
    savePrefs();
    render(lastData);
    syncViewportClass();
  });
  filterEl.addEventListener("change", () => {
    prefs.filter = filterEl.value;
    savePrefs();
    render(lastData);
  });
  if (themeEl) {
    themeEl.addEventListener("change", () => {
      prefs.theme = themeEl.value || "system";
      savePrefs();
      applyTheme();
    });
  }
  manageBtn.addEventListener("click", () => {
    rowPanel.hidden = !rowPanel.hidden;
    if (!rowPanel.hidden) renderRowPanel();
  });
  rowDone.addEventListener("click", () => { rowPanel.hidden = true; });

  // Drag title bar only in floating browser-card mode (not desk app window / mobile)
  let drag = null;
  titlebar.addEventListener("pointerdown", (e) => {
    if (document.documentElement.classList.contains("desk")) return;
    if (document.documentElement.classList.contains("mobile")) return;
    if (window.matchMedia("(max-width: 720px)").matches) return;
    if (e.target.closest("button, input, select, label, a, .brand")) return;
    drag = {
      x: e.clientX - modal.offsetLeft,
      y: e.clientY - modal.offsetTop,
      pid: e.pointerId,
    };
    titlebar.setPointerCapture(e.pointerId);
  });
  titlebar.addEventListener("pointermove", (e) => {
    if (!drag || e.pointerId !== drag.pid) return;
    modal.style.left = Math.max(0, e.clientX - drag.x) + "px";
    modal.style.top = Math.max(0, e.clientY - drag.y) + "px";
  });
  titlebar.addEventListener("pointerup", () => { drag = null; });
  titlebar.addEventListener("pointercancel", () => { drag = null; });

  privacyEl.checked = !!prefs.privacy;
  filterEl.value = prefs.filter || "all";
  document.body.classList.toggle("privacy", !!prefs.privacy);
  applyTheme();
  bindSystemThemeListener();
  startFetchedAgoTicker();
  fetchSpend(false).then(startTimer);
})();
