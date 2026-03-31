-- Goodfriend: Initial Schema
-- Run this in the Supabase SQL editor (or via supabase db push)

-- ─────────────────────────────────────────────
-- PROFILES
-- ─────────────────────────────────────────────
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

-- Auto-create profile on sign-up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ─────────────────────────────────────────────
-- CONTACTS
-- ─────────────────────────────────────────────
create table if not exists public.contacts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  name        text not null,
  photo_url   text,
  tags        text[] not null default '{}',
  phone       text,
  email       text,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.contacts enable row level security;

create policy "Users manage own contacts"
  on public.contacts for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index contacts_user_id_idx on public.contacts(user_id);

-- ─────────────────────────────────────────────
-- BULLET POINTS
-- ─────────────────────────────────────────────
create table if not exists public.bullet_points (
  id          uuid primary key default gen_random_uuid(),
  contact_id  uuid not null references public.contacts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  content     text not null,
  source      text not null default 'voice', -- 'voice' | 'manual'
  recorded_at timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

alter table public.bullet_points enable row level security;

create policy "Users manage own bullet points"
  on public.bullet_points for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index bullet_points_contact_id_idx on public.bullet_points(contact_id);

-- ─────────────────────────────────────────────
-- CIRCLES
-- ─────────────────────────────────────────────
create table if not exists public.circles (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  name        text not null,
  color_hex   text not null default '#4F8EF7',
  view_mode   text not null default 'list' check (view_mode in ('list', 'tree')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.circles enable row level security;

create policy "Users manage own circles"
  on public.circles for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- CIRCLE MEMBERS
-- ─────────────────────────────────────────────
create table if not exists public.circle_members (
  circle_id   uuid not null references public.circles(id) on delete cascade,
  contact_id  uuid not null references public.contacts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  -- For tree view: optional parent contact within the circle
  parent_contact_id uuid references public.contacts(id) on delete set null,
  added_at    timestamptz not null default now(),
  primary key (circle_id, contact_id)
);

alter table public.circle_members enable row level security;

create policy "Users manage own circle members"
  on public.circle_members for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- REMINDERS
-- ─────────────────────────────────────────────
create table if not exists public.reminders (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  contact_id   uuid not null references public.contacts(id) on delete cascade,
  title        text not null,
  description  text,
  due_date     timestamptz not null,
  is_fired     boolean not null default false,
  draft_message text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table public.reminders enable row level security;

create policy "Users manage own reminders"
  on public.reminders for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index reminders_due_date_idx on public.reminders(due_date) where not is_fired;

-- ─────────────────────────────────────────────
-- GIFT IDEAS
-- ─────────────────────────────────────────────
create type gift_status as enum ('saved', 'purchased');

create table if not exists public.gift_ideas (
  id          uuid primary key default gen_random_uuid(),
  contact_id  uuid not null references public.contacts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  title       text not null,
  note        text,
  source      text not null default 'manual' check (source in ('manual', 'ai')),
  status      gift_status not null default 'saved',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.gift_ideas enable row level security;

create policy "Users manage own gift ideas"
  on public.gift_ideas for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index gift_ideas_contact_id_idx on public.gift_ideas(contact_id);

-- ─────────────────────────────────────────────
-- DEVICE TOKENS (APNs push)
-- ─────────────────────────────────────────────
create table if not exists public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  token       text not null unique,
  platform    text not null default 'ios',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.device_tokens enable row level security;

create policy "Users manage own device tokens"
  on public.device_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- UPDATED_AT TRIGGER
-- ─────────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_updated_at before update on public.profiles
  for each row execute procedure public.set_updated_at();
create trigger set_updated_at before update on public.contacts
  for each row execute procedure public.set_updated_at();
create trigger set_updated_at before update on public.circles
  for each row execute procedure public.set_updated_at();
create trigger set_updated_at before update on public.reminders
  for each row execute procedure public.set_updated_at();
create trigger set_updated_at before update on public.gift_ideas
  for each row execute procedure public.set_updated_at();
create trigger set_updated_at before update on public.device_tokens
  for each row execute procedure public.set_updated_at();
