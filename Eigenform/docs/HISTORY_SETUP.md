# Workout history setup

The app saves every finished set to a `workouts` table in the same Supabase
project used for auth. Until the table exists, saves queue locally on the
device (and upload once it does), and the History screen shows a pointer to
this file. One SQL script to run, no app changes.

## Create the table

Open the Supabase dashboard → **SQL Editor** and run:

```sql
create table public.workouts (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  exercise text not null,
  reps integer not null check (reps >= 0),
  duration_seconds double precision not null check (duration_seconds >= 0),
  faults jsonb not null default '[]',
  performed_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index workouts_user_performed_at
  on public.workouts (user_id, performed_at desc);

alter table public.workouts enable row level security;

create policy "Users read own workouts"
  on public.workouts for select
  using (auth.uid() = user_id);

create policy "Users insert own workouts"
  on public.workouts for insert
  with check (auth.uid() = user_id);
```

Notes on the shape:

- **`id` comes from the client** (a UUID minted at save time), not a database
  default. The offline queue retries inserts, and a stable id turns a retry of
  an already-landed row into a harmless duplicate-key error instead of a
  second copy.
- **`user_id` defaults to `auth.uid()`** so the app never sends it; the insert
  policy still checks it, so a client can't write rows as someone else.
- **`faults` is jsonb** — an array of `{ "text": "...", "count": n }` — because
  the cue strings are display text owned by the app, not data worth
  normalizing into a table.
- No update/delete policies yet: sets are immutable from the app today. Add a
  delete policy mirroring the select one when the UI grows a delete action.
- `on delete cascade` means account deletion (the `delete_user` RPC from
  docs/AUTH_SETUP.md) also removes the user's workout rows.

## Verify

1. Run the app, sign in, finish a set (curl a dumbbell at your desk).
2. The set appears under **History** (clock button on the home screen).
3. In the dashboard, **Table Editor → workouts** shows the row with your
   user's `user_id`.
4. RLS check: signing in as a different account shows an empty history.
