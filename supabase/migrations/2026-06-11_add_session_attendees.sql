-- =====================================================================
-- Migration: add get_session_attendees() RPC
-- Date: 2026-06-11
-- =====================================================================
-- Adds a "who's going" view to the signup grid. Returns (session_id,
-- user_name) for every registration so any signed-in staff member can
-- see who's attending a session. Names only — no email, no user_id.
--
-- Safe to run against the live DB on its own (it's create-or-replace).
-- Paste into Supabase → SQL Editor → New query → Run.
-- =====================================================================

create or replace function public.get_session_attendees()
returns table (
  session_id uuid,
  user_name  text
)
language sql
security definer
set search_path = public
as $$
  -- Names only. If a registration has no display name (or one that looks
  -- like an email, since register_for_session falls back to email when
  -- Google supplies no name), show a neutral placeholder rather than leak
  -- the address to everyone browsing the grid.
  select
    r.session_id,
    case
      when r.user_name is null or r.user_name = '' or r.user_name like '%@%'
        then 'Dio staff member'
      else r.user_name
    end as user_name
  from public.registrations r
  order by r.session_id,
           lower(case
                   when r.user_name is null or r.user_name = '' or r.user_name like '%@%'
                     then 'Dio staff member'
                   else r.user_name
                 end);
$$;

grant execute on function public.get_session_attendees() to authenticated;

-- Verify:
-- select * from public.get_session_attendees();
