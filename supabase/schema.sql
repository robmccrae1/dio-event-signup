-- =====================================================================
-- Dio Event Signup — Database Schema
-- =====================================================================
-- A generalised event-signup system: each session is a flat unit with
-- its own date, time, room, and capacity. Pick rules are configurable
-- via the settings table — the registration RPC checks whichever are
-- turned on.
--
-- Run top-to-bottom in Supabase SQL Editor. Safe to re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. EXTENSIONS
-- ---------------------------------------------------------------------
create extension if not exists "pgcrypto";


-- ---------------------------------------------------------------------
-- 2. TABLES
-- ---------------------------------------------------------------------

-- Sessions: each session is a flat unit. No workshop/slot abstraction.
create table if not exists public.sessions (
  id            uuid     primary key default gen_random_uuid(),
  title         text     not null,
  presenter     text,
  description   text,
  session_date  date     not null,
  start_time    time     not null,
  end_time      time     not null,
  room          text,
  capacity      smallint not null default 25 check (capacity > 0),
  display_order int      not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (end_time > start_time)
);

create index if not exists sessions_date_time_idx on public.sessions(session_date, start_time);

-- Registrations
create table if not exists public.registrations (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  session_id uuid        not null references public.sessions(id) on delete cascade,
  user_email text        not null,
  user_name  text,
  created_at timestamptz not null default now(),
  primary key (user_id, session_id)
);

create index if not exists registrations_session_id_idx on public.registrations(session_id);
create index if not exists registrations_user_id_idx    on public.registrations(user_id);
create index if not exists registrations_user_email_idx on public.registrations(user_email);

-- Settings: event-level config + configurable pick rules
create table if not exists public.settings (
  key   text primary key,
  value text not null
);

-- Admins
create table if not exists public.admins (
  email text primary key
);


-- ---------------------------------------------------------------------
-- 3. SEED DATA — sensible defaults
-- ---------------------------------------------------------------------

insert into public.settings (key, value) values
  ('event_name',                  'Dio Event Signup'),
  ('event_subtitle',              ''),
  ('edit_cutoff_iso',             '2099-12-31T23:59:59+13:00'),
  ('email_domain',                'diocesan.school.nz'),
  ('max_picks',                   '4'),
  ('enforce_no_duplicate_titles', 'true'),
  ('enforce_no_time_conflicts',   'true'),
  ('event_open',                  'true')
on conflict (key) do nothing;

insert into public.admins (email) values
  ('rmccrae@diocesan.school.nz')
on conflict (email) do nothing;


-- ---------------------------------------------------------------------
-- 4. AUTO-UPDATE updated_at ON sessions
-- ---------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists sessions_touch_updated_at on public.sessions;
create trigger sessions_touch_updated_at
  before update on public.sessions
  for each row execute function public.touch_updated_at();


-- ---------------------------------------------------------------------
-- 5. AUTH DOMAIN RESTRICTION
-- ---------------------------------------------------------------------
create or replace function public.enforce_email_domain()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed_domain text;
begin
  select value into allowed_domain from public.settings where key = 'email_domain';
  if allowed_domain is null or allowed_domain = '' or allowed_domain = '*' then
    -- empty / '*' means no restriction
    return new;
  end if;
  if new.email is null or new.email not ilike '%@' || allowed_domain then
    raise exception 'Only @% accounts may register.', allowed_domain;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_email_domain_on_signup on auth.users;
create trigger enforce_email_domain_on_signup
  before insert on auth.users
  for each row execute function public.enforce_email_domain();


-- ---------------------------------------------------------------------
-- 6. REGISTRATION RPC
-- ---------------------------------------------------------------------
-- Atomic: locks the session row, checks capacity + configurable rules,
-- inserts on success. Returns JSON: { ok: true } or { ok: false, error: '...' }.
-- ---------------------------------------------------------------------
create or replace function public.register_for_session(p_session_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid    := auth.uid();
  v_user_email   text    := auth.jwt()->>'email';
  v_user_name    text;
  v_title        text;
  v_date         date;
  v_start        time;
  v_end          time;
  v_capacity     smallint;
  v_taken        int;
  v_user_total   int;
  v_max_picks    int;
  v_cutoff       timestamptz;
  v_domain       text;
  v_open         boolean;
  v_check_titles boolean;
  v_check_times  boolean;
begin
  if v_user_id is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- Domain check
  select value into v_domain from public.settings where key = 'email_domain';
  if v_domain is not null and v_domain != '' and v_domain != '*'
     and v_user_email !~* ('@' || v_domain || '$') then
    return json_build_object('ok', false, 'error', 'wrong_domain');
  end if;

  -- Verified email (defence in depth)
  if coalesce((auth.jwt()->>'email_verified')::boolean, false) is not true then
    return json_build_object('ok', false, 'error', 'email_not_verified');
  end if;

  -- Event open flag (kill switch)
  select (value)::boolean into v_open from public.settings where key = 'event_open';
  if v_open is not true then
    return json_build_object('ok', false, 'error', 'event_closed');
  end if;

  -- Edit cutoff
  select value::timestamptz into v_cutoff from public.settings where key = 'edit_cutoff_iso';
  if v_cutoff is not null and now() >= v_cutoff then
    return json_build_object('ok', false, 'error', 'editing_closed');
  end if;

  -- Pull user's display name from auth metadata (don't trust client input)
  select coalesce(
           raw_user_meta_data->>'full_name',
           raw_user_meta_data->>'name',
           email
         )
    into v_user_name
    from auth.users
   where id = v_user_id;

  -- Lock the session row
  select title, session_date, start_time, end_time, capacity
    into v_title, v_date, v_start, v_end, v_capacity
    from public.sessions
   where id = p_session_id
   for update;

  if v_title is null then
    return json_build_object('ok', false, 'error', 'session_not_found');
  end if;

  -- Capacity
  select count(*) into v_taken from public.registrations where session_id = p_session_id;
  if v_taken >= v_capacity then
    return json_build_object('ok', false, 'error', 'session_full');
  end if;

  -- Max picks (configurable, 0 or NULL = unlimited)
  select coalesce(nullif(value, '')::int, 0) into v_max_picks
    from public.settings where key = 'max_picks';
  if v_max_picks > 0 then
    select count(*) into v_user_total from public.registrations where user_id = v_user_id;
    if v_user_total >= v_max_picks then
      return json_build_object('ok', false, 'error', 'max_picks_reached');
    end if;
  end if;

  -- No-duplicate-titles (configurable)
  select (value)::boolean into v_check_titles
    from public.settings where key = 'enforce_no_duplicate_titles';
  if v_check_titles then
    if exists (
      select 1
        from public.registrations r
        join public.sessions s on s.id = r.session_id
       where r.user_id = v_user_id
         and lower(s.title) = lower(v_title)
    ) then
      return json_build_object('ok', false, 'error', 'duplicate_title');
    end if;
  end if;

  -- No-time-conflicts (configurable)
  -- Two sessions conflict iff same date AND start_time < other.end_time AND end_time > other.start_time
  select (value)::boolean into v_check_times
    from public.settings where key = 'enforce_no_time_conflicts';
  if v_check_times then
    if exists (
      select 1
        from public.registrations r
        join public.sessions s on s.id = r.session_id
       where r.user_id = v_user_id
         and s.session_date = v_date
         and s.start_time   < v_end
         and s.end_time     > v_start
    ) then
      return json_build_object('ok', false, 'error', 'time_conflict');
    end if;
  end if;

  insert into public.registrations (user_id, session_id, user_email, user_name)
    values (v_user_id, p_session_id, v_user_email, v_user_name);

  return json_build_object('ok', true);
end;
$$;

grant execute on function public.register_for_session(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 7. UNREGISTER RPC
-- ---------------------------------------------------------------------
create or replace function public.unregister_from_session(p_session_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_cutoff  timestamptz;
  v_deleted int;
begin
  if v_user_id is null then
    return json_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select value::timestamptz into v_cutoff from public.settings where key = 'edit_cutoff_iso';
  if v_cutoff is not null and now() >= v_cutoff then
    return json_build_object('ok', false, 'error', 'editing_closed');
  end if;

  delete from public.registrations
   where user_id = v_user_id and session_id = p_session_id;

  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    return json_build_object('ok', false, 'error', 'not_registered');
  end if;

  return json_build_object('ok', true);
end;
$$;

grant execute on function public.unregister_from_session(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 8. SEAT COUNTS RPC (no PII)
-- ---------------------------------------------------------------------
create or replace function public.get_session_seats()
returns table (
  session_id  uuid,
  capacity    smallint,
  taken       int,
  available   int
)
language sql
security definer
set search_path = public
as $$
  select
    s.id,
    s.capacity,
    coalesce(count(r.user_id), 0)::int                                 as taken,
    greatest(s.capacity - coalesce(count(r.user_id), 0)::int, 0)::int  as available
  from public.sessions s
  left join public.registrations r on r.session_id = s.id
  group by s.id;
$$;

grant execute on function public.get_session_seats() to authenticated;


-- ---------------------------------------------------------------------
-- 9. ADMIN RPCs
-- ---------------------------------------------------------------------

-- Check admin (used by other admin RPCs)
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select (auth.jwt()->>'email') is not null
     and (auth.jwt()->>'email') in (select email from public.admins);
$$;

grant execute on function public.is_admin() to authenticated;


-- Read all registrations
create or replace function public.admin_get_all_registrations()
returns table (
  user_email text,
  user_name  text,
  title      text,
  presenter  text,
  room       text,
  session_date date,
  start_time time,
  end_time   time,
  session_id uuid,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;

  return query
    select
      r.user_email,
      r.user_name,
      s.title,
      s.presenter,
      s.room,
      s.session_date,
      s.start_time,
      s.end_time,
      s.id,
      r.created_at
    from public.registrations r
    join public.sessions s on s.id = r.session_id
    order by s.session_date, s.start_time, s.display_order, r.user_email;
end;
$$;

grant execute on function public.admin_get_all_registrations() to authenticated;


-- Create or update a session
create or replace function public.admin_upsert_session(
  p_id            uuid,
  p_title         text,
  p_presenter     text,
  p_description   text,
  p_session_date  date,
  p_start_time    time,
  p_end_time      time,
  p_room          text,
  p_capacity      smallint,
  p_display_order int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;

  if p_end_time <= p_start_time then
    raise exception 'end_time must be after start_time';
  end if;

  if p_capacity <= 0 then
    raise exception 'capacity must be greater than 0';
  end if;

  if p_id is null then
    insert into public.sessions
      (title, presenter, description, session_date, start_time, end_time, room, capacity, display_order)
    values
      (p_title, p_presenter, p_description, p_session_date, p_start_time, p_end_time, p_room, p_capacity, p_display_order)
    returning id into v_id;
  else
    update public.sessions
       set title         = p_title,
           presenter     = p_presenter,
           description   = p_description,
           session_date  = p_session_date,
           start_time    = p_start_time,
           end_time      = p_end_time,
           room          = p_room,
           capacity      = p_capacity,
           display_order = p_display_order
     where id = p_id;
    v_id := p_id;
    if not found then raise exception 'session_not_found'; end if;

    -- If new capacity is below current registrations, that's allowed but no
    -- new registrations can be made until existing ones drop. We don't auto-bump.
  end if;

  return v_id;
end;
$$;

grant execute on function public.admin_upsert_session(uuid, text, text, text, date, time, time, text, smallint, int) to authenticated;


-- Delete a session (with registration check)
create or replace function public.admin_delete_session(p_session_id uuid, p_force boolean default false)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reg_count int;
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;

  select count(*) into v_reg_count from public.registrations where session_id = p_session_id;
  if v_reg_count > 0 and not p_force then
    return json_build_object('ok', false, 'error', 'has_registrations', 'count', v_reg_count);
  end if;

  -- registrations cascade-delete via FK
  delete from public.sessions where id = p_session_id;
  return json_build_object('ok', true);
end;
$$;

grant execute on function public.admin_delete_session(uuid, boolean) to authenticated;


-- Update a setting
create or replace function public.admin_set_setting(p_key text, p_value text)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;

  insert into public.settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;

  return json_build_object('ok', true);
end;
$$;

grant execute on function public.admin_set_setting(text, text) to authenticated;


-- Cancel a registration on behalf of a user (manual admin action)
create or replace function public.admin_cancel_registration(p_user_email text, p_session_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  if not public.is_admin() then
    raise exception 'forbidden';
  end if;

  delete from public.registrations
   where user_email = p_user_email and session_id = p_session_id;

  get diagnostics v_deleted = row_count;
  return json_build_object('ok', v_deleted > 0);
end;
$$;

grant execute on function public.admin_cancel_registration(text, uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 10. ROW-LEVEL SECURITY
-- ---------------------------------------------------------------------
alter table public.sessions      enable row level security;
alter table public.registrations enable row level security;
alter table public.admins        enable row level security;
alter table public.settings      enable row level security;

drop policy if exists "sessions readable" on public.sessions;
create policy "sessions readable" on public.sessions for select to authenticated using (true);

drop policy if exists "settings readable" on public.settings;
create policy "settings readable" on public.settings for select to authenticated using (true);

drop policy if exists "users see own regs" on public.registrations;
create policy "users see own regs" on public.registrations
  for select to authenticated
  using (user_id = auth.uid());

-- All writes go through RPCs (SECURITY DEFINER). No insert/update/delete policies.

-- Admins table: no client SELECT (the is_admin() function reads it as definer)
drop policy if exists "admins read admins" on public.admins;
create policy "admins read admins" on public.admins
  for select to authenticated
  using (false);


-- ---------------------------------------------------------------------
-- DONE
-- ---------------------------------------------------------------------
-- Sanity checks:
-- select * from public.settings;
-- select count(*) as session_count from public.sessions;
-- select email from public.admins;
