-- THE HUNT backend schema for a fresh Supabase project.
-- Run in Supabase Dashboard > SQL Editor. Review policies before production.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 3 and 24),
  player_id text not null unique,
  bio text not null default '' check (char_length(bio) <= 240),
  avatar_url text,
  streak integer not null default 0 check (streak >= 0),
  hunter_wins integer not null default 0 check (hunter_wins >= 0),
  runner_wins integer not null default 0 check (runner_wins >= 0),
  total_wins integer not null default 0 check (total_wins >= 0),
  games_played integer not null default 0 check (games_played >= 0),
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_lower_uidx on public.profiles(lower(username));

create or replace function public.new_player_id() returns text language plpgsql as $$
declare candidate text;
begin
  loop
    candidate := '#' || lpad((floor(random()*9000)+1000)::int::text,4,'0');
    exit when not exists(select 1 from public.profiles where player_id=candidate);
  end loop;
  return candidate;
end; $$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare uname text;
begin
  uname := coalesce(nullif(trim(new.raw_user_meta_data->>'username'),''), 'Player' || substr(new.id::text,1,8));
  insert into public.profiles(id,username,player_id) values(new.id,uname,public.new_player_id())
  on conflict(id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create table if not exists public.friendships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'accepted' check(status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  primary key(user_id,friend_id), check(user_id <> friend_id)
);
create table if not exists public.lobbies (
  id uuid primary key default gen_random_uuid(), name text not null check(char_length(name) between 1 and 40),
  code text not null unique check(char_length(code) between 3 and 12), host_id uuid not null references public.profiles(id),
  hunter_count integer not null default 1 check(hunter_count between 1 and 3),
  ping_interval integer not null default 3 check(ping_interval in (2,3,4,5)),
  ping_duration integer not null default 30 check(ping_duration between 5 and 300),
  status text not null default 'waiting' check(status in ('waiting','in_game','ended')),
  created_at timestamptz not null default now()
);
create table if not exists public.lobby_members (
  lobby_id uuid not null references public.lobbies(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text check(role in ('hunter','runner')),
  joined_at timestamptz not null default now(), primary key(lobby_id,user_id)
);
create table if not exists public.player_locations (
  lobby_id uuid not null references public.lobbies(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  lat double precision not null check(lat between -90 and 90),
  lng double precision not null check(lng between -180 and 180),
  updated_at timestamptz not null default now(), primary key(lobby_id,user_id)
);
create table if not exists public.match_results (
  id uuid primary key default gen_random_uuid(), lobby_id uuid not null references public.lobbies(id) on delete cascade,
  winner_role text not null check(winner_role in ('hunter','runner')), ended_at timestamptz not null default now()
);
create table if not exists public.chat_messages (
  id bigint generated always as identity primary key, lobby_id uuid not null references public.lobbies(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade, message text not null check(char_length(message) between 1 and 500),
  created_at timestamptz not null default now()
);
create table if not exists public.catch_reports (
  id uuid primary key default gen_random_uuid(), lobby_id uuid not null references public.lobbies(id) on delete cascade,
  hunter_id uuid not null references public.profiles(id), runner_id uuid not null references public.profiles(id),
  photo_path text not null, status text not null default 'pending' check(status in ('pending','confirmed','rejected')),
  created_at timestamptz not null default now(), check(hunter_id <> runner_id)
);

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.lobbies enable row level security;
alter table public.lobby_members enable row level security;
alter table public.player_locations enable row level security;
alter table public.match_results enable row level security;
alter table public.chat_messages enable row level security;
alter table public.catch_reports enable row level security;

-- SECURITY DEFINER helper avoids recursive RLS when checking lobby membership.
create or replace function public.is_lobby_member(p_lobby_id uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.lobby_members where lobby_id=p_lobby_id and user_id=auth.uid());
$$;
revoke all on function public.is_lobby_member(uuid) from public;
grant execute on function public.is_lobby_member(uuid) to authenticated;

drop policy if exists "profiles searchable by signed in users" on public.profiles;
create policy "profiles searchable by signed in users" on public.profiles for select to authenticated using(true);
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
drop policy if exists "friendships participants can read" on public.friendships;
create policy "friendships participants can read" on public.friendships for select to authenticated using(user_id=auth.uid() or friend_id=auth.uid());
drop policy if exists "friendships own insert" on public.friendships;
drop policy if exists "friendships participant delete" on public.friendships;
drop policy if exists "waiting lobbies searchable" on public.lobbies;
create policy "waiting lobbies searchable" on public.lobbies for select to authenticated using(status='waiting' or exists(select 1 from public.lobby_members m where m.lobby_id=id and m.user_id=auth.uid()));
drop policy if exists "members read lobby membership" on public.lobby_members;
create policy "members read lobby membership" on public.lobby_members for select to authenticated using(public.is_lobby_member(lobby_members.lobby_id));
-- No direct client inserts/updates/deletes to lobbies, members, or roles: use the RPC functions below.
drop policy if exists "location own insert" on public.player_locations;
create policy "location own insert" on public.player_locations for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.lobby_members m join public.lobbies l on l.id=m.lobby_id where m.lobby_id=player_locations.lobby_id and m.user_id=auth.uid() and l.status='in_game'));
drop policy if exists "location own update" on public.player_locations;
create policy "location own update" on public.player_locations for update to authenticated using(user_id=auth.uid() and exists(select 1 from public.lobby_members m join public.lobbies l on l.id=m.lobby_id where m.lobby_id=player_locations.lobby_id and m.user_id=auth.uid() and l.status='in_game')) with check(user_id=auth.uid() and exists(select 1 from public.lobby_members m join public.lobbies l on l.id=m.lobby_id where m.lobby_id=player_locations.lobby_id and m.user_id=auth.uid() and l.status='in_game'));
drop policy if exists "teammates see teammates locations only" on public.player_locations;
create policy "teammates see teammates locations only" on public.player_locations for select to authenticated using(exists(select 1 from public.lobby_members mine join public.lobby_members target on target.lobby_id=mine.lobby_id and target.role=mine.role where mine.lobby_id=player_locations.lobby_id and mine.user_id=auth.uid() and target.user_id=player_locations.user_id));
drop policy if exists "own location delete" on public.player_locations;
create policy "own location delete" on public.player_locations for delete to authenticated using(user_id=auth.uid());
drop policy if exists "members read results" on public.match_results;
create policy "members read results" on public.match_results for select to authenticated using(exists(select 1 from public.lobby_members m where m.lobby_id=match_results.lobby_id and m.user_id=auth.uid()));
drop policy if exists "runners read match chat" on public.chat_messages;
create policy "runners read match chat" on public.chat_messages for select to authenticated using(exists(select 1 from public.lobby_members m join public.lobbies l on l.id=m.lobby_id where m.lobby_id=chat_messages.lobby_id and m.user_id=auth.uid() and m.role='runner' and l.status='in_game'));
drop policy if exists "runners send match chat" on public.chat_messages;
create policy "runners send match chat" on public.chat_messages for insert to authenticated with check(user_id=auth.uid() and char_length(message) between 1 and 500 and exists(select 1 from public.lobby_members m join public.lobbies l on l.id=m.lobby_id where m.lobby_id=chat_messages.lobby_id and m.user_id=auth.uid() and m.role='runner' and l.status='in_game'));
drop policy if exists "participants read catch reports" on public.catch_reports;
create policy "participants read catch reports" on public.catch_reports for select to authenticated using(hunter_id=auth.uid() or exists(select 1 from public.lobbies l where l.id=lobby_id and l.host_id=auth.uid()));

-- Friend requests are stored as one row while pending (sender=user_id, recipient=friend_id).
-- When accepted, both directions become accepted rows so each user's friend list is easy to query.
create or replace function public.add_friend(p_friend_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare existing_status text;
begin
 if auth.uid() is null or p_friend_id=auth.uid() then raise exception 'Invalid friend'; end if;
 if not exists(select 1 from public.profiles where id=p_friend_id) then raise exception 'Player not found'; end if;
 if exists(select 1 from public.friendships where user_id=auth.uid() and friend_id=p_friend_id and status='accepted') then return; end if;
 if exists(select 1 from public.friendships where user_id=p_friend_id and friend_id=auth.uid() and status='pending') then
   update public.friendships set status='accepted' where user_id=p_friend_id and friend_id=auth.uid() and status='pending';
   insert into public.friendships(user_id,friend_id,status) values(auth.uid(),p_friend_id,'accepted') on conflict(user_id,friend_id) do update set status='accepted';
   return;
 end if;
 select status into existing_status from public.friendships where user_id=auth.uid() and friend_id=p_friend_id;
 if existing_status='pending' then raise exception 'Friend request already sent'; end if;
 insert into public.friendships(user_id,friend_id,status) values(auth.uid(),p_friend_id,'pending')
 on conflict(user_id,friend_id) do update set status='pending';
end; $$;
create or replace function public.accept_friend_request(p_sender_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or p_sender_id=auth.uid() then raise exception 'Invalid friend request'; end if;
 update public.friendships set status='accepted' where user_id=p_sender_id and friend_id=auth.uid() and status='pending';
 if not found then raise exception 'No pending request from this player'; end if;
 insert into public.friendships(user_id,friend_id,status) values(auth.uid(),p_sender_id,'accepted') on conflict(user_id,friend_id) do update set status='accepted';
end; $$;
create or replace function public.decline_friend_request(p_sender_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 delete from public.friendships where user_id=p_sender_id and friend_id=auth.uid() and status='pending';
end; $$;
create or replace function public.remove_friend(p_friend_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 delete from public.friendships where (user_id=auth.uid() and friend_id=p_friend_id) or (user_id=p_friend_id and friend_id=auth.uid());
end; $$;

create or replace function public.create_lobby(p_name text,p_code text,p_hunter_count integer,p_ping_interval integer,p_ping_duration integer) returns uuid language plpgsql security definer set search_path=public as $$
declare lid uuid;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if p_hunter_count not between 1 and 3 or p_ping_interval not in (2,3,4,5) or p_ping_duration not between 5 and 300 then raise exception 'Invalid game settings'; end if;
 insert into public.lobbies(name,code,host_id,hunter_count,ping_interval,ping_duration) values(trim(p_name),upper(trim(p_code)),auth.uid(),p_hunter_count,p_ping_interval,p_ping_duration) returning id into lid;
 insert into public.lobby_members(lobby_id,user_id) values(lid,auth.uid()); return lid;
end; $$;
create or replace function public.join_lobby(p_code text) returns uuid language plpgsql security definer set search_path=public as $$
declare lid uuid;
begin
 select id into lid from public.lobbies where upper(code)=upper(trim(p_code)) and status='waiting';
 if lid is null then raise exception 'No waiting lobby found for that code'; end if;
 insert into public.lobby_members(lobby_id,user_id) values(lid,auth.uid()) on conflict do nothing; return lid;
end; $$;
create or replace function public.invite_friend_to_lobby(p_lobby_id uuid,p_friend_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.lobbies where id=p_lobby_id and host_id=auth.uid() and status='waiting') then raise exception 'Only the host can invite players to a waiting lobby'; end if;
 if not exists(select 1 from public.friendships where user_id=auth.uid() and friend_id=p_friend_id and status='accepted') then raise exception 'You can only add accepted friends'; end if;
 insert into public.lobby_members(lobby_id,user_id) values(p_lobby_id,p_friend_id) on conflict do nothing;
end; $$;
create or replace function public.remove_lobby_player(p_lobby_id uuid,p_user_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.lobbies where id=p_lobby_id and host_id=auth.uid() and status='waiting') then raise exception 'Only the host can remove players from a waiting lobby'; end if;
 if p_user_id=auth.uid() then raise exception 'Host cannot remove themselves here'; end if;
 delete from public.lobby_members where lobby_id=p_lobby_id and user_id=p_user_id;
end; $$;
create or replace function public.leave_lobby(p_lobby_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin delete from public.player_locations where lobby_id=p_lobby_id and user_id=auth.uid(); delete from public.lobby_members where lobby_id=p_lobby_id and user_id=auth.uid(); end; $$;
create or replace function public.start_match(p_lobby_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare host uuid; hunters integer; total integer; ids uuid[];
begin
 select host_id,hunter_count into host,hunters from public.lobbies where id=p_lobby_id and status='waiting' for update;
 if host is null or host<>auth.uid() then raise exception 'Only the host can start this waiting match'; end if;
 select count(*) into total from public.lobby_members where lobby_id=p_lobby_id;
 if total<=hunters then raise exception 'Not enough players for that number of hunters'; end if;
 select array_agg(user_id order by random()) into ids from public.lobby_members where lobby_id=p_lobby_id;
 update public.lobby_members set role=case when user_id=any(ids[1:hunters]) then 'hunter' else 'runner' end where lobby_id=p_lobby_id;
 update public.lobbies set status='in_game' where id=p_lobby_id;
end; $$;

create or replace function public.submit_catch(p_lobby_id uuid,p_runner_id uuid,p_photo_path text) returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid;
begin
 if not exists(select 1 from public.lobbies where id=p_lobby_id and status='in_game') then raise exception 'Match is not active'; end if;
 if not exists(select 1 from public.lobby_members where lobby_id=p_lobby_id and user_id=auth.uid() and role='hunter') then raise exception 'Only hunters can submit a catch'; end if;
 if not exists(select 1 from public.lobby_members where lobby_id=p_lobby_id and user_id=p_runner_id and role='runner') then raise exception 'Target is not a runner in this match'; end if;
 if split_part(p_photo_path,'/',1) <> auth.uid()::text then raise exception 'Invalid photo path'; end if;
 insert into public.catch_reports(lobby_id,hunter_id,runner_id,photo_path) values(p_lobby_id,auth.uid(),p_runner_id,p_photo_path) returning id into rid;
 return rid;
end; $$;
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

revoke all on function public.add_friend(uuid) from public;
revoke all on function public.accept_friend_request(uuid) from public;
revoke all on function public.decline_friend_request(uuid) from public;
revoke all on function public.remove_friend(uuid) from public;
revoke all on function public.create_lobby(text,text,integer,integer,integer) from public;
revoke all on function public.join_lobby(text) from public;
revoke all on function public.invite_friend_to_lobby(uuid,uuid) from public;
revoke all on function public.remove_lobby_player(uuid,uuid) from public;
revoke all on function public.leave_lobby(uuid) from public;
revoke all on function public.start_match(uuid) from public;
revoke all on function public.submit_catch(uuid,uuid,text) from public;
revoke all on function public.finish_match(uuid,text) from public;
grant execute on function public.add_friend(uuid) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.decline_friend_request(uuid) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function public.create_lobby(text,text,integer,integer,integer) to authenticated;
grant execute on function public.join_lobby(text) to authenticated;
grant execute on function public.invite_friend_to_lobby(uuid,uuid) to authenticated;
grant execute on function public.remove_lobby_player(uuid,uuid) to authenticated;
grant execute on function public.leave_lobby(uuid) to authenticated;
grant execute on function public.start_match(uuid) to authenticated;
grant execute on function public.submit_catch(uuid,uuid,text) to authenticated;
grant execute on function public.finish_match(uuid,text) to authenticated;

grant select on public.profiles to authenticated;
grant update(bio,avatar_url) on public.profiles to authenticated;
revoke insert,update,delete on public.friendships from authenticated;
grant select on public.friendships to authenticated;
grant select on public.lobbies to authenticated;
grant select on public.lobby_members to authenticated;
grant select,insert,update,delete on public.player_locations to authenticated;
grant select on public.match_results to authenticated;
grant select,insert on public.chat_messages to authenticated;
grant select on public.catch_reports to authenticated;

create or replace function public.review_catch(p_report_id uuid,p_status text) returns void language plpgsql security definer set search_path=public as $$
begin
 if p_status not in ('confirmed','rejected') then raise exception 'Invalid review status'; end if;
 if not exists(select 1 from public.catch_reports r join public.lobbies l on l.id=r.lobby_id where r.id=p_report_id and l.host_id=auth.uid()) then raise exception 'Only the lobby host can review this report'; end if;
 update public.catch_reports set status=p_status where id=p_report_id;
end; $$;
revoke all on function public.review_catch(uuid,text) from public;
grant execute on function public.review_catch(uuid,text) to authenticated;

-- Avatar storage: public reads for profile photos; authenticated users can write only their own folder.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('avatars','avatars',true,2097152,array['image/jpeg','image/png','image/webp','image/gif']) on conflict(id) do nothing;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('catch-photos','catch-photos',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
drop policy if exists "avatar public read" on storage.objects;
create policy "avatar public read" on storage.objects for select using(bucket_id='avatars');
drop policy if exists "avatar owner upload" on storage.objects;
create policy "avatar owner upload" on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "avatar owner update" on storage.objects;
create policy "avatar owner update" on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "catch photo owner upload" on storage.objects;
create policy "catch photo owner upload" on storage.objects for insert to authenticated with check(bucket_id='catch-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "catch photo owner read" on storage.objects;
create policy "catch photo owner read" on storage.objects for select to authenticated using(bucket_id='catch-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "catch photo host review read" on storage.objects;
create policy "catch photo host review read" on storage.objects for select to authenticated using(bucket_id='catch-photos' and exists(select 1 from public.catch_reports r join public.lobbies l on l.id=r.lobby_id where r.photo_path=name and l.host_id=auth.uid()));

-- Enable Realtime for shared lobby and location updates if not already enabled.
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='lobby_members') then alter publication supabase_realtime add table public.lobby_members; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='lobbies') then alter publication supabase_realtime add table public.lobbies; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='player_locations') then alter publication supabase_realtime add table public.player_locations; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='friendships') then alter publication supabase_realtime add table public.friendships; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='chat_messages') then alter publication supabase_realtime add table public.chat_messages; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='catch_reports') then alter publication supabase_realtime add table public.catch_reports; end if;
end $$;
