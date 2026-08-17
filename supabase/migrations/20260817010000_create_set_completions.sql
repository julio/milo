-- One row per completed set: a plan day (0-38) and the entry's position
-- within that day. Deleting the row un-marks the set.
create table public.set_completions (
  day_id integer not null,
  entry_index integer not null,
  completed_at timestamptz not null default now(),
  primary key (day_id, entry_index)
);

alter table public.set_completions enable row level security;

create policy "anon full access" on public.set_completions
  for all to anon using (true) with check (true);
