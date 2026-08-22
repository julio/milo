-- What was actually lifted, per plan entry: the weight used and reps done.
-- Same (day_id, entry_index) key as set_completions.
create table public.exercise_logs (
  day_id integer not null,
  entry_index integer not null,
  weight double precision,
  reps integer,
  updated_at timestamptz not null default now(),
  primary key (day_id, entry_index)
);

alter table public.exercise_logs enable row level security;

create policy "anon full access" on public.exercise_logs
  for all to anon using (true) with check (true);
