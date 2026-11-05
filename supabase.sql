-- Run once in Supabase: SQL Editor > New query.
-- One shared row for the household; only emails on the allowlist can read/write it.

create table if not exists public.allowed_users (
  email text primary key
);
-- Replace with the real addresses (lowercase) before running:
insert into public.allowed_users(email) values
  ('you@example.com')
  -- , ('partner@example.com')
on conflict do nothing;

create table if not exists public.planner_state (
  id         text primary key default 'household',
  data       jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by text
);

alter table public.allowed_users enable row level security;   -- no policies: not readable from the browser
alter table public.planner_state enable row level security;

create or replace function public.is_allowed() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.allowed_users
                 where email = lower(auth.jwt() ->> 'email'));
$$;

drop policy if exists planner_select on public.planner_state;
drop policy if exists planner_insert on public.planner_state;
drop policy if exists planner_update on public.planner_state;
create policy planner_select on public.planner_state for select to authenticated using (public.is_allowed());
create policy planner_insert on public.planner_state for insert to authenticated with check (public.is_allowed() and id = 'household');
create policy planner_update on public.planner_state for update to authenticated using (public.is_allowed()) with check (public.is_allowed() and id = 'household');
-- No delete policy on purpose.

-- Keep updated_at honest regardless of what the client sends.
create or replace function public.touch_planner() returns trigger language plpgsql as $$
begin new.updated_at = now(); new.updated_by = lower(auth.jwt() ->> 'email'); return new; end $$;
drop trigger if exists planner_touch on public.planner_state;
create trigger planner_touch before insert or update on public.planner_state
  for each row execute function public.touch_planner();
