-- The Hunt v1.6: timed runner pings for hunters on the live map.
-- Run once in Supabase SQL Editor after previous schema/migrations.
alter table public.lobbies add column if not exists started_at timestamptz;

create or replace function public.start_match(p_lobby_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare host uuid; hunters integer; total integer; ids uuid[];
begin
 select host_id,hunter_count into host,hunters from public.lobbies where id=p_lobby_id and status='waiting' for update;
 if host is null or host<>auth.uid() then raise exception 'Only the host can start this waiting match'; end if;
 select count(*) into total from public.lobby_members where lobby_id=p_lobby_id;
 if total<=hunters then raise exception 'Not enough players for that number of hunters'; end if;
 select array_agg(user_id order by random()) into ids from public.lobby_members where lobby_id=p_lobby_id;
 update public.lobby_members set role=case when user_id=any(ids[1:hunters]) then 'hunter' else 'runner' end where lobby_id=p_lobby_id;
 update public.lobbies set status='in_game',started_at=now() where id=p_lobby_id;
end; $$;

-- Replace teammate-only read policy with teammate locations plus runner reveal only during configured hunter ping windows.
drop policy if exists "teammates see teammates locations only" on public.player_locations;
drop policy if exists "teammates and timed ping locations" on public.player_locations;
create policy "teammates and timed ping locations" on public.player_locations for select to authenticated using (
 exists (
  select 1 from public.lobby_members mine
  join public.lobby_members target on target.lobby_id=mine.lobby_id and target.user_id=player_locations.user_id
  join public.lobbies l on l.id=mine.lobby_id
  where mine.lobby_id=player_locations.lobby_id and mine.user_id=auth.uid() and l.status='in_game'
   and (target.role=mine.role or (mine.role='hunter' and target.role='runner' and
    mod(greatest(0,extract(epoch from (now()-coalesce(l.started_at,l.created_at))))::bigint, l.ping_interval*60) < l.ping_duration))
 );
