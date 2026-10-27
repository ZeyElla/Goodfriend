-- Goodfriend: Journal pivot
-- Adds a freeform "context" line to contacts and a "kind" to bullet points
-- so we can distinguish persistent key facts from dated journal entries.
-- Circles and gift_ideas tables are left in place but no longer surfaced in the app.

-- ─────────────────────────────────────────────
-- CONTACTS: context line (e.g. "Barista at Blue Bottle")
-- ─────────────────────────────────────────────
alter table public.contacts
  add column if not exists context text;

-- ─────────────────────────────────────────────
-- BULLET POINTS: key_fact vs note
--   'key_fact' → persistent fact ("Fiancé: Sean")
--   'note'     → dated journal entry
-- ─────────────────────────────────────────────
alter table public.bullet_points
  add column if not exists kind text not null default 'note'
  check (kind in ('key_fact', 'note'));

create index if not exists bullet_points_kind_idx
  on public.bullet_points(contact_id, kind);
