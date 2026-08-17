-- One row per completed stretch on a given calendar day. Stretches are
-- daily (rest days included), so the key is the date itself.
create table public.stretch_completions (
  date date not null,
  stretch_index integer not null,
  completed_at timestamptz not null default now(),
  primary key (date, stretch_index)
);

alter table public.stretch_completions enable row level security;

create policy "anon full access" on public.stretch_completions
  for all to anon using (true) with check (true);
