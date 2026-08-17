create table public.workouts (
  id uuid primary key,
  date timestamptz not null default now(),
  name text not null,
  duration double precision not null,
  exercises jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.workouts enable row level security;

-- Single-user personal app with no auth flow yet: the anon key gets full
-- access. Tighten to authenticated-only when/if sign-in is added.
create policy "anon full access" on public.workouts
  for all to anon using (true) with check (true);
