-- The Hunt: Zombies game mode. Run once after the existing migrations.
alter table public.lobbies add column if not exists game_mode text not null default 'classic' check (game_mode in ('classic','zombies'));

create or replace function public.create_lobby_mode(p_name text,p_code text,p_hunter_count integer,p_ping_interval integer,p_ping_duration integer,p_game_mode text)
returns uuid language plpgsql security definer set search_path=public as $$
declare lid uuid;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if p_hunter_count not between 1 and 3 or p_ping_interval not in (2,3,4,5) or p_ping_duration not between 5 and 300 then raise exception 'Invalid game settings'; end if;
 if p_game_mode not in ('classic','zombies') then raise exception 'Invalid game mode'; end if;
 insert into public.lobbies(name,code,host_id,hunter_count,ping_interval,ping_duration,game_mode)
 values(trim(p_name),upper(trim(p_code)),auth.uid(),p_hunter_count,p_ping_interval,p_ping_duration,p_game_mode) returning id into lid;
 insert into public.lobby_members(lobby_id,user_id) values(lid,auth.uid());
 return lid;
end; $$;
revoke all on function public.create_lobby_mode(text,text,integer,integer,integer,text) from public;
grant execute on function public.create_lobby_mode(text,text,integer,integer,integer,text) to authenticated;

-- In Zombies mode, a valid runner code converts that runner to the hunter-side role
-- (displayed as ZOMBIE by the client) and creates a fresh code so they can infect others.
create or replace function public.catch_runner_by_code(p_lobby_id uuid,p_code text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare target uuid; mode text; candidate text; tries integer := 0;
begin
 if auth.uid() is null or p_code !~ '^[0-9]{5}$' then return jsonb_build_object('ok',false,'message','Enter a valid five-digit code.'); end if;
 select game_mode into mode from public.lobbies where id=p_lobby_id and status='in_game' for update;
 if mode is null then return jsonb_build_object('ok',false,'message','This match is not active.'); end if;
 if not exists(select 1 from public.lobby_members where lobby_id=p_lobby_id and user_id=auth.uid() and role='hunter') then raise exception 'Only hunters or zombies can confirm catches'; end if;
 select c.runner_id into target from public.runner_catch_codes c join public.lobby_members m on m.lobby_id=c.lobby_id and m.user_id=c.runner_id and m.role='runner' where c.lobby_id=p_lobby_id and c.code=p_code and not exists(select 1 from public.runner_catches rc where rc.lobby_id=c.lobby_id and rc.runner_id=c.runner_id) limit 1 for update of c;
 if target is null then return jsonb_build_object('ok',false,'message','Code not found, or this runner has already been caught.'); end if;
 if mode='zombies' then
   update public.lobby_members set role='hunter' where lobby_id=p_lobby_id and user_id=target and role='runner';
   delete from public.runner_catch_codes where lobby_id=p_lobby_id and runner_id=target;
   loop
     candidate := lpad(floor(random()*100000)::int::text,5,'0');
     exit when not exists(select 1 from public.runner_catch_codes where lobby_id=p_lobby_id and code=candidate);
     tries := tries+1; if tries>100 then raise exception 'Could not generate a new zombie code; try again'; end if;
   end loop;
   insert into public.runner_catch_codes(lobby_id,runner_id,code) values(p_lobby_id,target,candidate);
   return jsonb_build_object('ok',true,'message','Runner became a zombie.','converted',true);
 else
   insert into public.runner_catches(lobby_id,runner_id,caught_by) values(p_lobby_id,target,auth.uid()) on conflict do nothing;
   return jsonb_build_object('ok',true,'message','Runner caught.','converted',false);
 end if;
end; $$;
revoke all on function public.catch_runner_by_code(uuid,text) from public;
grant execute on function public.catch_runner_by_code(uuid,text) to authenticated;
