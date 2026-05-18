-- Run this in Supabase SQL Editor ONLY if you need a clean slate.
-- It nukes everything this project created.

drop trigger  if exists enforce_email_domain_on_signup on auth.users;
drop trigger  if exists sessions_touch_updated_at on public.sessions;
drop function if exists public.touch_updated_at();
drop function if exists public.enforce_email_domain();
drop function if exists public.register_for_session(uuid);
drop function if exists public.unregister_from_session(uuid);
drop function if exists public.get_session_seats();
drop function if exists public.is_admin();
drop function if exists public.admin_get_all_registrations();
drop function if exists public.admin_upsert_session(uuid, text, text, text, date, time, time, text, smallint, int);
drop function if exists public.admin_delete_session(uuid, boolean);
drop function if exists public.admin_set_setting(text, text);
drop function if exists public.admin_cancel_registration(text, uuid);
drop table    if exists public.registrations cascade;
drop table    if exists public.sessions      cascade;
drop table    if exists public.admins        cascade;
drop table    if exists public.settings      cascade;
