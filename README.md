# Dio Event Signup

A generalised event signup system for Diocesan School for Girls. Configure any event with any number of sessions, dates, times, and seat caps. Staff sign in with Google and pick from the available sessions according to rules you set.

**Live:** [dio-event-signup.vercel.app](https://dio-event-signup.vercel.app)

Sister project to [dio-tod-signup](https://github.com/robmccrae1/dio-tod-signup), which was purpose-built for the May 2026 Teacher Only Day. This one is the configurable version, intended for any future signup (PD throughout the year, parents' evening slots, careers expo bookings, etc.).

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
| Event open / closed kill switch | `/admin-settings` |

## Stack

- **Frontend:** vanilla HTML + Supabase JS (CDN), no build step
- **Backend:** Supabase (Postgres + Auth + RPCs) — project `crdayyjrpytwfqsgmaxb`
- **Hosting:** Vercel (Hobby tier) — `dio-event-signup.vercel.app`
- **Auth:** Google OAuth via Supabase, domain-restricted via `email_domain` setting
- **Repo:** [github.com/robmccrae1/dio-event-signup](https://github.com/robmccrae1/dio-event-signup) — public
- **Keep-warm cron:** daily at 02:00 NZT via GitHub Actions

## Current status: live and ready

Initial setup is complete. To run an event:

1. Sign in to [dio-event-signup.vercel.app](https://dio-event-signup.vercel.app) as `rmccrae@diocesan.school.nz`
2. Navigate to `/admin` (you'll see the registrations dashboard, empty until you add sessions)
3. Click **Event settings** in the top nav → configure event name, max picks, cutoff, rules → save
4. Click **Sessions** → add your sessions one by one (or duplicate similar ones)
5. Send the homepage URL to your staff
6. Watch registrations come in on `/admin`
7. Print attendance sheets from `/print` when needed

## Day-to-day operations

See [`docs/OPERATIONS.md`](docs/OPERATIONS.md) for the full playbook.

Most operations now happen through the admin UI — SQL only needed for occasional manual fixes.

## Setup checklist (one-time, already done for this deployment)

Documented for future deployments / forks.

### 1. Supabase project

- [x] Created at [supabase.com](https://supabase.com) — region Sydney
- [x] Project URL: `https://crdayyjrpytwfqsgmaxb.supabase.co`
- [x] Schema loaded from `supabase/schema.sql`

### 2. Google Cloud OAuth

- [x] OAuth client created in existing `dio-tod-signup` GCP project, named "Supabase Auth — dio-event-signup"
- [x] Authorised redirect URI: `https://crdayyjrpytwfqsgmaxb.supabase.co/auth/v1/callback`
- [x] Credentials wired into Supabase → Authentication → Providers → Google

### 3. GitHub + Vercel

- [x] Repo at [github.com/robmccrae1/dio-event-signup](https://github.com/robmccrae1/dio-event-signup) — **public** (required to avoid Hobby-tier deploy blocks; codebase contains no secrets)
- [x] Vercel project — Framework: Other, Root Directory: `public`
- [x] Site URL + redirect URL configured in Supabase → Authentication → URL Configuration

### 4. Keep-warm cron

- [x] `SUPABASE_URL` + `SUPABASE_ANON_KEY` set as GitHub repo secrets
- [x] Workflow at `.github/workflows/keep-warm.yml` running green daily

### 5. Git author note

If you push new commits and Vercel blocks them with "commit author does not have contributing access", the per-repo git config is set to use `robmccrae1`'s noreply email. To inspect or change:

```bash
git config user.email  # should be 157330247+robmccrae1@users.noreply.github.com
git config user.name   # should be robmccrae1
```

This keeps Vercel happy on its Hobby tier.

## Project structure

```
dio-event-signup/
├── public/
│   ├── index.html              # signup grid (sessions grouped by date)
│   ├── admin.html              # registrations dashboard + CSV exports
│   ├── admin-sessions.html     # CRUD UI for sessions
│   ├── admin-settings.html     # event config form
│   ├── print.html              # attendance sheets (by session or by presenter)
│   └── config.js               # Supabase URL + publishable key
├── supabase/
│   ├── schema.sql              # full schema — run in SQL Editor
│   └── drop_all.sql            # nuke + pave (use with care)
├── .github/workflows/
│   └── keep-warm.yml           # daily Supabase ping
├── docs/
│   └── OPERATIONS.md           # day-to-day operations playbook
└── README.md
```

## Things to know

- **Cleaner URLs**: Vercel strips `.html` extensions. Use `/admin`, `/admin-sessions`, `/admin-settings`, `/print` — not `*.html`.
- **Admin nav**: the home page doesn't link to admin pages (intentional — staff shouldn't see them). Navigate to `/admin` directly, then use the in-page nav for the other admin pages.
- **Single event at a time**: this is built for one event configured at a time. To swap events, wipe registrations + delete old sessions, configure new ones. Multi-event support is a planned upgrade if needed.
- **No emails sent on registration**: deliberately skipped. Staff can print or download `.ics` of their picks from the home page.

## Pending / future enhancements

- [ ] Hide past sessions from the public signup grid (admin still sees them for reporting)
- [ ] Optional: per-session cutoffs (currently global)
- [ ] Optional: multi-event support (one app, multiple concurrent events)
- [ ] Optional: 24h-before reminder emails via Supabase Edge Functions
