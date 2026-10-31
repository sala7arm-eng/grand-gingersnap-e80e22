-- The Hunt v3.4: safe, repeatable friend-request setup.
-- Run this ONE file in Supabase SQL Editor if friend requests fail.
-- Requires the base supabase-schema.sql to have been run already.
begin;

alter table public.friendships enable row level security;
drop policy if exists "friendships participants can read" on public.friendships;
create policy "friendships participants can read" on public.friendships
  for select to authenticated
  using (user_id = auth.uid() or friend_id = auth.uid());

create or replace function public.add_friend(p_friend_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare existing_status text;
begin
  if auth.uid() is null then raise exception 'Please sign in first'; end if;
  if p_friend_id is null or p_friend_id = auth.uid() then raise exception 'Choose another player'; end if;
  if not exists (select 1 from public.profiles where id = p_friend_id) then raise exception 'Player not found'; end if;
  if exists (select 1 from public.friendships where user_id=auth.uid() and friend_id=p_friend_id and status='accepted') then return; end if;
  -- If the other player already requested you, accepting your request reciprocates it.
  if exists (select 1 from public.friendships where user_id=p_friend_id and friend_id=auth.uid() and status='pending') then
    update public.friendships set status='accepted' where user_id=p_friend_id and friend_id=auth.uid() and status='pending';
    insert into public.friendships(user_id,friend_id,status) values(auth.uid(),p_friend_id,'accepted')
      on conflict(user_id,friend_id) do update set status='accepted';
    return;
  end if;
  select status into existing_status from public.friendships where user_id=auth.uid() and friend_id=p_friend_id;
  if existing_status='pending' then raise exception 'Friend request already sent'; end if;
  insert into public.friendships(user_id,friend_id,status) values(auth.uid(),p_friend_id,'pending')
    on conflict(user_id,friend_id) do update set status='pending';
end; $$;

create or replace function public.accept_friend_request(p_sender_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Please sign in first'; end if;
  if p_sender_id is null or p_sender_id=auth.uid() then raise exception 'Invalid friend request'; end if;
  update public.friendships set status='accepted'
    where user_id=p_sender_id and friend_id=auth.uid() and status='pending';
  if not found then raise exception 'No pending request from this player'; end if;
  insert into public.friendships(user_id,friend_id,status) values(auth.uid(),p_sender_id,'accepted')
    on conflict(user_id,friend_id) do update set status='accepted';
end; $$;

create or replace function public.decline_friend_request(p_sender_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Please sign in first'; end if;
  delete from public.friendships where user_id=p_sender_id and friend_id=auth.uid() and status='pending';
  if not found then raise exception 'This request is no longer pending'; end if;
end; $$;

create or replace function public.remove_friend(p_friend_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Please sign in first'; end if;
  delete from public.friendships
   where (user_id=auth.uid() and friend_id=p_friend_id)
      or (user_id=p_friend_id and friend_id=auth.uid());
end; $$;

revoke all on function public.add_friend(uuid) from public, anon;
revoke all on function public.accept_friend_request(uuid) from public, anon;
revoke all on function public.decline_friend_request(uuid) from public, anon;
revoke all on function public.remove_friend(uuid) from public, anon;
grant execute on function public.add_friend(uuid) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.decline_friend_request(uuid) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant select on public.friendships to authenticated;

do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='friendships') then
    alter publication supabase_realtime add table public.friendships;
  end if;
end $$;
commit;
