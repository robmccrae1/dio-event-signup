# Dio Event Signup

A generalised event signup system for Diocesan School for Girls. Configure any event with any number of sessions, dates, times, and seat caps. Staff sign in with Google and pick from the available sessions according to rules you set.

## What's configurable

| Thing | Where |
|---|---|
| Event name + subtitle | `/admin-settings` |
| Number of sessions | `/admin-sessions` (add as many as you want) |
| Date of each session | `/admin-sessions` (sessions can span multiple days) |
| Start + end time of each session | `/admin-sessions` |
| Title, presenter, room, description per session | `/admin-sessions` |
| Seat capacity per session | `/admin-sessions` (different per session is fine) |
| Max picks per staff member | `/admin-settings` |
| "Can't pick the same title twice" rule | `/admin-settings` (toggle on/off) |
| "Can't pick two sessions that overlap in time" rule | `/admin-settings` (toggle on/off) |
| Edit cutoff (when picks lock) | `/admin-settings` |
| Allowed email domain | `/admin-settings` (set to `*` to disable restriction) |

## Stack

- **Frontend:** vanilla HTML + Supabase JS (CDN), no build step
- **Backend:** Supabase (Postgres + Auth + RPCs)
- **Hosting:** Vercel (free Hobby tier)
- **Auth:** Google OAuth via Supabase, domain-restricted

Same architecture as `dio-tod-signup`. If you know that project, you know this one.

## Setup checklist (one-time)

### 1. Supabase project

- [ ] Create a new Supabase project at [supabase.com](https://supabase.com) — region: **Sydney** for latency.
- [ ] Once provisioned, copy the **Project URL** and the **publishable (anon) key** from Project Settings → API.
- [ ] Open SQL Editor → New query → paste `supabase/schema.sql` → Run.
- [ ] Verify with `select * from public.settings;` — should show 8 rows.

### 2. Google Cloud OAuth (new client, separate from any other project)

1. [console.cloud.google.com](https://console.cloud.google.com) — sign in as `rmccrae@diocesan.school.nz`.
2. New project: `dio-event-signup`. Confirm Organization = `diocesan.school.nz`.
3. APIs & Services → OAuth consent screen → **Internal** → fill app name, support email, dev contact.
4. Credentials → Create credentials → OAuth client ID → Web application:
   - **Authorised redirect URIs:** `https://<your-supabase-project>.supabase.co/auth/v1/callback`
5. Copy Client ID + Client Secret.
6. Supabase dashboard → Authentication → Providers → Google → enable, paste credentials, save.
7. Supabase → Authentication → URL Configuration → Site URL: `https://<your-vercel-url>.vercel.app` (set after Vercel deploy)

### 3. GitHub repo + Vercel

1. Create private GitHub repo: `dio-event-signup`.
2. Push this code: `git push -u origin main`.
3. Vercel → Add New Project → Import from GitHub → Framework: **Other**, Root Directory: **`public`**, Deploy.
4. Copy the Vercel URL → back to Supabase URL Configuration → set Site URL + add redirect URL `https://<vercel-url>/**`.

### 4. Edit `public/config.js`

Replace the placeholder Supabase URL and publishable key with your actual values, commit, push. Vercel auto-redeploys.

### 5. Keep-warm cron

GitHub repo → Settings → Secrets and variables → Actions → New repository secret:
- `SUPABASE_URL` = your project URL
- `SUPABASE_ANON_KEY` = your publishable key

The workflow at `.github/workflows/keep-warm.yml` runs daily to keep the project alive.

## First-time use

1. Sign in to your live site as the admin email seeded in the schema (default: `rmccrae@diocesan.school.nz` — change in `schema.sql` if it should be someone else).
2. Visit `/admin-settings` → configure event name, cutoff, pick rules.
3. Visit `/admin-sessions` → add your sessions.
4. Send the URL to your staff.

## Project structure

```
dio-event-signup/
├── public/
│   ├── index.html              # signup grid
│   ├── admin.html              # registrations dashboard
│   ├── admin-sessions.html     # CRUD UI for sessions
│   ├── admin-settings.html     # event config form
│   ├── print.html              # attendance sheets
│   └── config.js               # Supabase URL + publishable key
├── supabase/
│   ├── schema.sql              # full schema — run in SQL Editor
│   └── drop_all.sql            # nuke + pave
├── .github/workflows/
│   └── keep-warm.yml           # daily Supabase ping
├── docs/
│   └── OPERATIONS.md           # day-to-day operations (TBC)
└── README.md
```

## Day-to-day operations

See `docs/OPERATIONS.md` (to be written once first event is configured).

For now: everything you need to change is in `/admin-settings` or `/admin-sessions` — no SQL required for normal operations.
