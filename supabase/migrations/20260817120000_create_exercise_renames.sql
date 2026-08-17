-- Custom display names for exercises. Keyed by the plan's original name so
-- one rename applies everywhere that exercise appears.
create table public.exercise_renames (
  original text primary key,
  custom text not null,
  updated_at timestamptz not null default now()
);

alter table public.exercise_renames enable row level security;

create policy "anon full access" on public.exercise_renames
  for all to anon using (true) with check (true);
