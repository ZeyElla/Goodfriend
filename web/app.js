// ── Config ─────────────────────────────────────────────
// Same Supabase project as the iOS app. The anon/publishable key is safe to
// ship in the browser — row-level security is what actually protects the data.
const SUPABASE_URL = "https://tdmqzjetxlxzxwzrmzyg.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_fyx-EWArHo_0-43HPY77WA_JvkNQWNa";

const client = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ── Elements ───────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const loginView = $("login");
const dashboardView = $("dashboard");
const accountBox = $("account");

// ── Auth ───────────────────────────────────────────────
$("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const email = $("email").value.trim();
  const status = $("login-status");
  status.className = "status";
  status.textContent = "Sending…";
  const { error } = await client.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: window.location.origin + window.location.pathname },
  });
  if (error) {
    status.className = "status err";
    status.textContent = error.message;
  } else {
    status.className = "status ok";
    status.textContent = "Check your email for the sign-in link.";
  }
});

$("signout").addEventListener("click", async () => {
  await client.auth.signOut();
});

client.auth.onAuthStateChange((_event, session) => {
  render(session);
});

async function render(session) {
  if (session) {
    loginView.classList.add("hidden");
    dashboardView.classList.remove("hidden");
    accountBox.classList.remove("hidden");
    $("account-email").textContent = session.user.email || "";
    await loadAll();
  } else {
    dashboardView.classList.add("hidden");
    accountBox.classList.add("hidden");
    loginView.classList.remove("hidden");
  }
}

// Initial check (also picks up the token from the magic-link redirect).
client.auth.getSession().then(({ data }) => render(data.session));

// ── Tabs ───────────────────────────────────────────────
document.querySelectorAll(".tab").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    const tab = btn.dataset.tab;
    $("tab-people").classList.toggle("hidden", tab !== "people");
    $("tab-reminders").classList.toggle("hidden", tab !== "reminders");
  });
});
$("refresh").addEventListener("click", loadAll);

// ── Data loading ───────────────────────────────────────
async function loadAll() {
  await Promise.all([loadPeople(), loadReminders()]);
}

async function loadPeople() {
  const { data, error } = await client
    .from("contacts")
    .select("*, bullet_points(content, kind, recorded_at)")
    .order("name");

  if (error) return renderError("people-grid", error.message);

  const rows = (data || []).map((c) => {
    const bullets = c.bullet_points || [];
    const keyFacts = bullets.filter((b) => b.kind === "key_fact").map((b) => b.content);
    const notes = bullets.filter((b) => b.kind === "note");
    const lastContact = bullets
      .map((b) => b.recorded_at)
      .filter(Boolean)
      .sort()
      .pop();
    return {
      Name: c.name || "",
      Context: c.context || "",
      Tags: c.tags || [],
      "Key facts": keyFacts,
      Notes: notes.length,
      "Last contact": lastContact ? new Date(lastContact) : null,
    };
  });

  renderSheet("people-grid", rows, {
    Tags: (v) => v.map((t) => `<span class="pill">${escapeHtml(t)}</span>`).join(""),
    "Key facts": (v) => v.map((t) => escapeHtml(t)).join("\n"),
    "Last contact": fmtDate,
  });
}

async function loadReminders() {
  const { data, error } = await client
    .from("reminders")
    .select("title, draft_message, due_date, contacts(name)")
    .eq("is_fired", false)
    .order("due_date");

  if (error) return renderError("reminders-grid", error.message);

  const rows = (data || []).map((r) => ({
    Person: r.contacts?.name || "",
    Nudge: r.title || "",
    Message: r.draft_message || "",
    Due: r.due_date ? new Date(r.due_date) : null,
  }));

  renderSheet("reminders-grid", rows, { Due: fmtDate });
}

// ── Rendering ──────────────────────────────────────────
// Keeps the current sort per grid so re-renders stay stable.
const sortState = {};

function renderSheet(gridId, rows, formatters = {}) {
  const grid = $(gridId);
  if (!rows.length) {
    grid.innerHTML = `<div class="empty">Nothing here yet.</div>`;
    return;
  }
  const columns = Object.keys(rows[0]);
  const state = sortState[gridId] || { col: null, dir: 1 };

  if (state.col) {
    rows = [...rows].sort((a, b) => compare(a[state.col], b[state.col]) * state.dir);
  }

  const thead = columns
    .map((col) => {
      const arrow = state.col === col ? (state.dir === 1 ? "▲" : "▼") : "";
      return `<th data-col="${escapeHtml(col)}">${escapeHtml(col)}<span class="arrow">${arrow}</span></th>`;
    })
    .join("");

  const tbody = rows
    .map((row) => {
      const cells = columns
        .map((col) => {
          const raw = row[col];
          const fmt = formatters[col];
          const html = fmt ? fmt(raw) : escapeHtml(raw == null ? "" : String(raw));
          return `<td>${html}</td>`;
        })
        .join("");
      return `<tr>${cells}</tr>`;
    })
    .join("");

  grid.innerHTML = `<table class="sheet"><thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table>`;

  grid.querySelectorAll("th").forEach((th) => {
    th.addEventListener("click", () => {
      const col = th.dataset.col;
      const cur = sortState[gridId] || { col: null, dir: 1 };
      sortState[gridId] = { col, dir: cur.col === col ? -cur.dir : 1 };
      // Re-render just this grid from the same data by reloading.
      loadAll();
    });
  });
}

function renderError(gridId, msg) {
  $(gridId).innerHTML = `<div class="empty">Couldn't load: ${escapeHtml(msg)}</div>`;
}

// ── Helpers ────────────────────────────────────────────
function compare(a, b) {
  if (a == null) return -1;
  if (b == null) return 1;
  if (a instanceof Date && b instanceof Date) return a - b;
  if (typeof a === "number" && typeof b === "number") return a - b;
  return String(a).localeCompare(String(b));
}

function fmtDate(d) {
  if (!d) return "";
  return d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
