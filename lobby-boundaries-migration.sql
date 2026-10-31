-- The Hunt v1.4 migration: lobby settings and safe-zone boundaries.
-- Run once in Supabase SQL Editor on your existing project. This does not replace existing tables/data.

create table if not exists public.lobby_boundaries (
  id uuid primary key default gen_random_uuid(),
  lobby_id uuid not null references public.lobbies(id) on delete cascade,
  shape text not null check (shape in ('square','circle','triangle')),
  center_lat double precision not null check (center_lat between -90 and 90),
  center_lng double precision not null check (center_lng between -180 and 180),
  size_m double precision not null check (size_m between 50 and 10000),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.lobby_boundaries enable row level security;
drop policy if exists "members can view lobby boundaries" on public.lobby_boundaries;
create policy "members can view lobby boundaries" on public.lobby_boundaries for select to authenticated
using (exists(select 1 from public.lobby_members m where m.lobby_id=lobby_boundaries.lobby_id and m.user_id=auth.uid()));
drop policy if exists "host can add lobby boundaries" on public.lobby_boundaries;
create policy "host can add lobby boundaries" on public.lobby_boundaries for insert to authenticated
with check (created_by=auth.uid() and exists(select 1 from public.lobbies l where l.id=lobby_boundaries.lobby_id and l.host_id=auth.uid() and l.status='waiting'));
drop policy if exists "host can remove lobby boundaries" on public.lobby_boundaries;
create policy "host can remove lobby boundaries" on public.lobby_boundaries for delete to authenticated
using (exists(select 1 from public.lobbies l where l.id=lobby_boundaries.lobby_id and l.host_id=auth.uid() and l.status='waiting'));

create or replace function public.update_lobby_settings(p_lobby_id uuid,p_hunter_count integer,p_ping_interval integer,p_ping_duration integer) returns void
language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if p_hunter_count not between 1 and 3 or p_ping_interval not in (2,3,4,5) or p_ping_duration not between 5 and 300 then raise exception 'Invalid game settings'; end if;
 update public.lobbies set hunter_count=p_hunter_count,ping_interval=p_ping_interval,ping_duration=p_ping_duration
 where id=p_lobby_id and host_id=auth.uid() and status='waiting';
 if not found then raise exception 'Only the host can edit settings before the match starts'; end if;
end; $$;
revoke all on function public.update_lobby_settings(uuid,integer,integer,integer) from public;
grant execute on function public.update_lobby_settings(uuid,integer,integer,integer) to authenticated;
