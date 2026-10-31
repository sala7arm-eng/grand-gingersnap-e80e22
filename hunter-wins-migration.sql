-- Run this once in Supabase SQL Editor to add hunter-win stats to an existing The Hunt database.
alter table public.profiles add column if not exists hunter_wins integer not null default 0 check (hunter_wins >= 0);

create or replace function public.finish_match(p_lobby_id uuid,p_winner_role text) returns void language plpgsql security definer set search_path=public as $$
declare host uuid; uid uuid;
begin
 if p_winner_role not in ('hunter','runner') then raise exception 'Invalid winner'; end if;
 select host_id into host from public.lobbies where id=p_lobby_id and status='in_game' for update;
 if host is null or host<>auth.uid() then raise exception 'Only the host can finish this match'; end if;
 insert into public.match_results(lobby_id,winner_role) values(p_lobby_id,p_winner_role);
 for uid in select user_id from public.lobby_members where lobby_id=p_lobby_id loop
   update public.profiles p set games_played=p.games_played+1,
     total_wins=p.total_wins+case when exists(select 1 from public.lobby_members m where m.lobby_id=p_lobby_id and m.user_id=uid and m.role=p_winner_role) then 1 else 0 end,
     hunter_wins=p.hunter_wins+case when p_winner_role='hunter' and exists(select 1 from public.lobby_members m where m.lobby_id=p_lobby_id and m.user_id=uid and m.role='hunter') then 1 else 0 end,
     runner_wins=p.runner_wins+case when p_winner_role='runner' and exists(select 1 from public.lobby_members m where m.lobby_id=p_lobby_id and m.user_id=uid and m.role='runner') then 1 else 0 end,
     streak=case when exists(select 1 from public.lobby_members m where m.lobby_id=p_lobby_id and m.user_id=uid and m.role=p_winner_role) then p.streak+1 else 0 end
   where p.id=uid;
 end loop;
 update public.lobbies set status='ended' where id=p_lobby_id;
 delete from public.player_locations where lobby_id=p_lobby_id;
end; $$;
