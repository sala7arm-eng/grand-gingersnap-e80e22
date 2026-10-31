-- The Hunt: open/private lobby visibility. Run once after zombies-mode-migration.sql.
alter table public.lobbies add column if not exists is_public boolean not null default false;

create or replace function public.create_lobby_mode_privacy(
 p_name text, p_code text, p_hunter_count integer, p_ping_interval integer,
 p_ping_duration integer, p_game_mode text, p_is_public boolean
) returns uuid language plpgsql security definer set search_path=public as $$
declare lid uuid;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if length(trim(coalesce(p_name,''))) not between 1 and 40 then raise exception 'Enter a lobby name'; end if;
 if length(trim(coalesce(p_code,''))) not between 3 and 12 then raise exception 'Lobby code must be 3–12 characters'; end if;
 if p_hunter_count not between 1 and 3 or p_ping_interval not in (2,3,4,5) or p_ping_duration not between 5 and 300 then raise exception 'Invalid game settings'; end if;
 if p_game_mode not in ('classic','zombies') then raise exception 'Invalid game mode'; end if;
 insert into public.lobbies(name,code,host_id,hunter_count,ping_interval,ping_duration,game_mode,is_public)
 values(trim(p_name),upper(trim(p_code)),auth.uid(),p_hunter_count,p_ping_interval,p_ping_duration,p_game_mode,p_is_public) returning id into lid;
 insert into public.lobby_members(lobby_id,user_id) values(lid,auth.uid());
 return lid;
end; $$;
-- Function is callable only by authenticated users.
revoke all on function public.create_lobby_mode_privacy(text,text,integer,integer,integer,text,boolean) from public;
grant execute on function public.create_lobby_mode_privacy(text,text,integer,integer,integer,text,boolean) to authenticated;
