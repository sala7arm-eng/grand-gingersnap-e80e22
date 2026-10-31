-- The Hunt v1.8 match flow: start timestamp, private runner codes, separate team chats, catches.
-- Run once in Supabase SQL Editor after the earlier The Hunt migrations.
create extension if not exists pgcrypto;
alter table public.lobbies add column if not exists started_at timestamptz;

create table if not exists public.runner_catch_codes (
  lobby_id uuid not null references public.lobbies(id) on delete cascade,
  runner_id uuid not null references public.profiles(id) on delete cascade,
  code text not null check (code ~ '^[0-9]{5}$'),
  created_at timestamptz not null default now(),
  primary key(lobby_id, runner_id),
  unique(lobby_id, code)
);
create table if not exists public.runner_catches (
  lobby_id uuid not null references public.lobbies(id) on delete cascade,
  runner_id uuid not null references public.profiles(id) on delete cascade,
  caught_by uuid not null references public.profiles(id),
  caught_at timestamptz not null default now(),
  primary key(lobby_id, runner_id)
);
create table if not exists public.match_chat_messages (
  id bigint generated always as identity primary key,
  lobby_id uuid not null references public.lobbies(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  team text not null check(team in ('runner','hunter')),
  message text not null check(char_length(message) between 1 and 500),
  created_at timestamptz not null default now()
);

alter table public.runner_catch_codes enable row level security;
alter table public.runner_catches enable row level security;
alter table public.match_chat_messages enable row level security;
drop policy if exists "runner reads own catch code" on public.runner_catch_codes;
create policy "runner reads own catch code" on public.runner_catch_codes for select to authenticated
using(runner_id=auth.uid() and exists(select 1 from public.lobby_members m where m.lobby_id=runner_catch_codes.lobby_id and m.user_id=auth.uid()));
drop policy if exists "match members read catches" on public.runner_catches;
create policy "match members read catches" on public.runner_catches for select to authenticated
using(exists(select 1 from public.lobby_members m where m.lobby_id=runner_catches.lobby_id and m.user_id=auth.uid()));
drop policy if exists "team reads own chat" on public.match_chat_messages;
create policy "team reads own chat" on public.match_chat_messages for select to authenticated
using(exists(select 1 from public.lobby_members m join public.lobbies l on l.id=m.lobby_id where m.lobby_id=match_chat_messages.lobby_id and m.user_id=auth.uid() and m.role=match_chat_messages.team and l.status='in_game'));
drop policy if exists "team sends own chat" on public.match_chat_messages;
create policy "team sends own chat" on public.match_chat_messages for insert to authenticated
with check(user_id=auth.uid() and char_length(message) between 1 and 500 and exists(select 1 from public.lobby_members m join public.lobbies l on l.id=m.lobby_id where m.lobby_id=match_chat_messages.lobby_id and m.user_id=auth.uid() and m.role=match_chat_messages.team and l.status='in_game'));
grant select on public.runner_catch_codes, public.runner_catches, public.match_chat_messages to authenticated;
grant insert on public.match_chat_messages to authenticated;
grant usage, select on sequence public.match_chat_messages_id_seq to authenticated;

create or replace function public.start_match(p_lobby_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare host uuid; hunters integer; total integer; ids uuid[]; uid uuid; candidate text;
begin
 select host_id,hunter_count into host,hunters from public.lobbies where id=p_lobby_id and status='waiting' for update;
 if host is null or host<>auth.uid() then raise exception 'Only the host can start this waiting match'; end if;
 select count(*) into total from public.lobby_members where lobby_id=p_lobby_id;
 if total<=hunters then raise exception 'Not enough players for that number of hunters'; end if;
 select array_agg(user_id order by random()) into ids from public.lobby_members where lobby_id=p_lobby_id;
 update public.lobby_members set role=case when user_id=any(ids[1:hunters]) then 'hunter' else 'runner' end where lobby_id=p_lobby_id;
 update public.lobbies set status='in_game',started_at=now() where id=p_lobby_id;
 delete from public.runner_catch_codes where lobby_id=p_lobby_id;
 delete from public.runner_catches where lobby_id=p_lobby_id;
 for uid in select user_id from public.lobby_members where lobby_id=p_lobby_id and role='runner' loop
   loop
     candidate := lpad((floor(random()*100000))::int::text,5,'0');
     exit when not exists(select 1 from public.runner_catch_codes where lobby_id=p_lobby_id and code=candidate);
   end loop;
   insert into public.runner_catch_codes(lobby_id,runner_id,code) values(p_lobby_id,uid,candidate);
 end loop;
end; $$;

create or replace function public.catch_runner_by_code(p_lobby_id uuid,p_code text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare target uuid;
begin
 if auth.uid() is null or p_code !~ '^[0-9]{5}$' then return jsonb_build_object('ok',false,'message','Enter a valid five-digit code.'); end if;
 if not exists(select 1 from public.lobbies where id=p_lobby_id and status='in_game') then return jsonb_build_object('ok',false,'message','This match is not active.'); end if;
 if not exists(select 1 from public.lobby_members where lobby_id=p_lobby_id and user_id=auth.uid() and role='hunter') then raise exception 'Only hunters can confirm catches'; end if;
 select c.runner_id into target from public.runner_catch_codes c join public.lobby_members m on m.lobby_id=c.lobby_id and m.user_id=c.runner_id and m.role='runner' where c.lobby_id=p_lobby_id and c.code=p_code and not exists(select 1 from public.runner_catches rc where rc.lobby_id=c.lobby_id and rc.runner_id=c.runner_id) limit 1;
 if target is null then return jsonb_build_object('ok',false,'message','Code not found, or this runner has already been caught.'); end if;
 insert into public.runner_catches(lobby_id,runner_id,caught_by) values(p_lobby_id,target,auth.uid()) on conflict do nothing;
 return jsonb_build_object('ok',true,'message','Runner caught.');
end; $$;
revoke all on function public.catch_runner_by_code(uuid,text) from public;
grant execute on function public.catch_runner_by_code(uuid,text) to authenticated;
