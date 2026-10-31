-- The Hunt v3.0: per-player match history and profile recap.
-- Run AFTER supabase-schema.sql and match-flow-migration.sql in Supabase SQL Editor.
create table if not exists public.match_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  lobby_id uuid not null references public.lobbies(id) on delete cascade,
  place text not null,
  location_label text not null default 'Location not recorded',
  role text not null check(role in ('hunter','runner')),
  won boolean not null,
  survival_seconds integer not null default 0 check(survival_seconds >= 0),
  placement text not null,
  ended_at timestamptz not null default now(),
  unique(user_id,lobby_id)
);
alter table public.match_history enable row level security;
drop policy if exists "players read own match history" on public.match_history;
create policy "players read own match history" on public.match_history for select to authenticated using(user_id=auth.uid());
grant select on public.match_history to authenticated;

create or replace function public.save_match_history_rows() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  lobby record;
  member record;
  loc record;
  caught_time timestamptz;
  survived integer;
  location_text text;
begin
  select id,name,started_at into lobby from public.lobbies where id=new.lobby_id;
  for member in select user_id,role from public.lobby_members where lobby_id=new.lobby_id loop
    select lat,lng into loc from public.player_locations where lobby_id=new.lobby_id and user_id=member.user_id;
    if found then
      location_text := 'Approx. ' || round(loc.lat::numeric,4)::text || ', ' || round(loc.lng::numeric,4)::text;
    else
      location_text := 'Location not recorded';
    end if;
    caught_time := null;
    if member.role='runner' then
      select rc.caught_at into caught_time from public.runner_catches rc where rc.lobby_id=new.lobby_id and rc.runner_id=member.user_id limit 1;
    end if;
    if member.role='runner' and caught_time is not null then
      survived := greatest(0,floor(extract(epoch from (caught_time-coalesce(lobby.started_at,new.ended_at))))::integer);
    else
      survived := greatest(0,floor(extract(epoch from (new.ended_at-coalesce(lobby.started_at,new.ended_at)))::integer));
    end if;
    insert into public.match_history(user_id,lobby_id,place,location_label,role,won,survival_seconds,placement,ended_at)
    values(member.user_id,new.lobby_id,coalesce(lobby.name,'The Hunt match'),location_text,member.role,member.role=new.winner_role,survived,upper(coalesce(member.role,'player')),new.ended_at)
    on conflict(user_id,lobby_id) do update set place=excluded.place,location_label=excluded.location_label,role=excluded.role,won=excluded.won,survival_seconds=excluded.survival_seconds,placement=excluded.placement,ended_at=excluded.ended_at;
  end loop;
  return new;
end; $$;
drop trigger if exists match_results_save_history on public.match_results;
create trigger match_results_save_history after insert on public.match_results for each row execute function public.save_match_history_rows();
