-- The Hunt v1.7: allow the lobby host to manage safe zones from the live map.
-- Run once in the existing Supabase SQL Editor. This preserves existing boundaries and other data.

drop policy if exists "host can add lobby boundaries" on public.lobby_boundaries;
create policy "host can add lobby boundaries" on public.lobby_boundaries
for insert to authenticated
with check (
  created_by = auth.uid()
  and exists (
    select 1 from public.lobbies l
    where l.id = lobby_boundaries.lobby_id
      and l.host_id = auth.uid()
      and l.status in ('waiting', 'in_game')
  )
);

drop policy if exists "host can remove lobby boundaries" on public.lobby_boundaries;
create policy "host can remove lobby boundaries" on public.lobby_boundaries
for delete to authenticated
using (
  exists (
    select 1 from public.lobbies l
    where l.id = lobby_boundaries.lobby_id
      and l.host_id = auth.uid()
      and l.status in ('waiting', 'in_game')
  )
);
