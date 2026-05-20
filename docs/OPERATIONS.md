# Operations playbook — dio-event-signup

Day-to-day usage of the configurable event signup system.

> **Golden rule:** before any `UPDATE` or `DELETE` in SQL Editor, swap the verb for `SELECT *` and run it first. If the SELECT returns the rows you expect, then run the real statement. The Supabase SQL Editor warns you about destructive operations but mistakes are still irreversible.

---

## Live URLs

- **Public signup:** [dio-event-signup.vercel.app](https://dio-event-signup.vercel.app)
- **Admin dashboard:** [dio-event-signup.vercel.app/admin](https://dio-event-signup.vercel.app/admin) (then use top nav for the other admin pages)
- **Supabase dashboard:** [supabase.com/dashboard](https://supabase.com/dashboard) → `dio-event-signup` project
- **GitHub repo:** [github.com/robmccrae1/dio-event-signup](https://github.com/robmccrae1/dio-event-signup)
- **Keep-warm cron:** [GitHub Actions tab](https://github.com/robmccrae1/dio-event-signup/actions)

## Where to do things

| Task | Where |
|---|---|
| Change event name, cutoff, pick rules, email domain | `/admin-settings` |
| Add / edit / delete sessions | `/admin-sessions` |
| Watch registrations + CSV export | `/admin` |
| Print attendance sheets | `/print` |
| Manual data fixes (cancel a registration, force a delete) | Supabase SQL Editor |
| Code / UI changes | Local repo → `git push` → Vercel auto-deploys |

---

## Setting up a new event

When you want to use the system for a new event (e.g. switching from PD to a parents' evening):

### 1. Wipe the old event's data

```sql
-- Wipe registrations
delete from public.registrations;

-- Optionally wipe sessions too (if it's a totally different event)
delete from public.sessions;
```

### 2. Update event settings

Visit `/admin-settings`:
- Change **Event name** + **Subtitle**
- Reset the **Edit cutoff** to the new date
- Adjust **Max picks** for the new event's shape
- Toggle rule flags as appropriate
- Save

### 3. Add the new sessions

Visit `/admin-sessions` and add each session via the form. Use the **Duplicate** button to copy a session and tweak just the date/time.

### 4. Send the URL to staff

Same URL as before: `https://dio-event-signup.vercel.app`. They sign in with their Dio Google account.

---

## Common operations via admin UI

### Adding / editing sessions

1. `/admin-sessions`
2. Fill in the form on the left → **Add session**
3. To edit: click **Edit** on a row → form populates → modify → **Save changes**
4. To duplicate: click **Duplicate** → form pre-fills with that session's details → adjust date/time → **Add session**
5. To delete: click **Delete** → confirm. If the session has registrations, you'll get a second confirm prompt warning that those registrations cascade-delete.

**Reducing capacity below current registrations** — allowed, but you'll get a confirm prompt. Existing registrations stay; no new ones can be made until people drop out.

### Changing rules mid-event

You can toggle pick rules in `/admin-settings` at any time. The change is live within ~10 seconds (next polling cycle on open browsers).

Existing registrations are **not retroactively checked** — if someone signed up for two conflicting sessions while the rule was off, turning it on doesn't cancel either. You'd need to manually cancel one.

### Closing registration early

Two options:

**Option A (kill switch):** `/admin-settings` → untick **Event is open for registration** → save. Grid goes read-only for everyone within 10 seconds.

**Option B (cutoff):** `/admin-settings` → change **Editing closes at** to right now → save. Same effect.

The difference: Option A leaves the future cutoff date intact for reference; Option B changes the cutoff.

### Extending the cutoff

`/admin-settings` → change **Editing closes at** to the new date → save. Open browser sessions pick up the new value within 10 seconds.

---

## Operations that still need SQL

### Manually cancel someone's registration

```sql
-- Preview their picks first
select s.title, s.session_date, s.start_time
from public.registrations r
join public.sessions s on s.id = r.session_id
where r.user_email = 'someone@diocesan.school.nz';

-- Cancel one
delete from public.registrations
where user_email = 'someone@diocesan.school.nz'
  and session_id = '<paste session id from query above>';

-- Cancel everything for them
delete from public.registrations where user_email = 'someone@diocesan.school.nz';
```

Or use the `admin_cancel_registration` RPC (which is what the future UI button will call):

```sql
select public.admin_cancel_registration('someone@diocesan.school.nz', '<session-id>');
```

### Manually register someone (last resort)

Cleanest path: ask them to sign in once. Then if needed:

```sql
-- 1. Find their auth.users id (only works if they've signed in at least once)
select id, email from auth.users where email = 'someone@diocesan.school.nz';

-- 2. Insert. NB: this bypasses cap + duplicate checks — verify manually first.
insert into public.registrations (user_id, session_id, user_email, user_name)
values (
  '<auth.users.id>',
  '<sessions.id>',
  'someone@diocesan.school.nz',
  'Their Name'
);
```

### Add or remove an admin

```sql
-- Add
insert into public.admins (email) values ('helper@diocesan.school.nz');

-- Remove
delete from public.admins where email = 'helper@diocesan.school.nz';
```

Admins see all the admin pages (`/admin`, `/admin-sessions`, `/admin-settings`, `/print`). They can edit anything an admin can edit.

---

## Code / UI changes

If you want to tweak wording, colours, or add a feature:

```bash
cd /Users/rmccrae/GitProjects/dio-event-signup
# edit files in public/ or supabase/
git add .
git commit -m "Tweak: <what changed>"
git push
```

Vercel auto-deploys within 30 seconds. Watch at [vercel.com/dashboard](https://vercel.com/dashboard).

**Important:** the per-repo git config is set to use `robmccrae1`'s noreply email. If you ever need to commit from a different machine, set it again:

```bash
cd /Users/rmccrae/GitProjects/dio-event-signup
git config user.email "157330247+robmccrae1@users.noreply.github.com"
git config user.name "robmccrae1"
```

To roll back a bad deploy: Vercel dashboard → Deployments → find the previous good one → **⋯ → Promote to Production**.

---

## Monitoring

A quick weekly check:

1. **Admin dashboard** ([/admin](https://dio-event-signup.vercel.app/admin)) — confirm registrations are coming in. Look at the summary tiles.
2. **GitHub Actions** — keep-warm should have green ticks. If red, the Supabase project may have paused; visit the dashboard to wake it.
3. **Spot-check the public site** in incognito — confirm the grid still loads.

For a numerical sanity check:

```sql
select count(distinct user_email) as registered_staff,
       count(*) as total_picks,
       round(count(*)::numeric / nullif(count(distinct user_email), 0), 2) as avg_picks_per_staff
from public.registrations;
```

---

## Troubleshooting

### Sign-in not working

**Symptoms:** "Sign in with Google" button doesn't trigger anything, or you bounce back with an error.

- Confirm Supabase → Authentication → Providers → Google → toggle ON, Client ID + Secret populated correctly.
- Confirm Supabase → Authentication → URL Configuration → Site URL = `https://dio-event-signup.vercel.app`, and **Redirect URLs** includes `https://dio-event-signup.vercel.app/**`.
- Confirm GCP → Credentials → "Supabase Auth — dio-event-signup" → Authorised redirect URIs includes `https://crdayyjrpytwfqsgmaxb.supabase.co/auth/v1/callback`.

### "Site is down" / blank page

- Check Supabase dashboard for project status. If **Paused**, click to resume (~30 seconds).
- Check Vercel for the latest deploy. If it's not "Ready", click into it for the error.

### Vercel "Blocked" deployment

Vercel Hobby plan blocks deploys where the commit author doesn't have project access. Two fixes (in order of preference):
1. Confirm the repo is **public** (Settings → Danger Zone). If private, make it public — codebase has no secrets.
2. Confirm git is committing as `157330247+robmccrae1@users.noreply.github.com` (see Code/UI changes section above).

### Keep-warm cron failing

Click into the failing run on GitHub Actions. Common causes:
- Secret got rotated — re-add `SUPABASE_URL` and `SUPABASE_ANON_KEY` in repo Settings → Secrets and variables → Actions.
- Supabase returned an unexpected status — paste the error here for me to diagnose.

### Session won't save

The admin UI validates: title required, date required, start+end times required, end > start, capacity > 0. If any of those fail you'll see a red toast at the bottom. Fix and save again.

---

## Things to NOT do

- **Don't truncate `auth.users`** — signs everyone out and orphans registrations.
- **Don't delete from `public.sessions` via SQL** when an event is live — use the admin UI's Delete button, which warns about cascading registrations.
- **Don't share the Supabase service-role key** — only the publishable key belongs in client code.
- **Don't `git push --force`** to main — Vercel will redeploy whatever you force-push, including bad states.

---

## When to ask Claude / a developer

DIY:
- Anything in `/admin-settings` or `/admin-sessions`
- Capacity adjustments, cutoff changes, adding admins
- Fixing typos in `public/index.html`

Ask first:
- Schema changes (new columns or tables)
- Anything touching the RPCs (`register_for_session`, etc.) or RLS
- New features
- "I tried X and got an unfamiliar error"

Better to ask than to wedge yourself out of access to your own data.
