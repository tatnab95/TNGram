-- ===========================================================================
--  Тнграм: шаг 2 — закрыть публичный ключ.
--  Выполнять после того, как 2.4 установлена: версии 2.3 и ниже перестанут
--  получать и отправлять сообщения.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
--  1. ЗАНЯТЬ ИЛИ ЗАВЕСТИ НИК (теперь и регистрация)
-- ---------------------------------------------------------------------------
create or replace function public.tn_claim(p_nick text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_key text := lower(btrim(coalesce(p_nick, '')));
  v_nick text;
begin
  if v_uid is null or v_key = '' then return ''; end if;
  if char_length(v_key) < 2 or char_length(v_key) > 24 then return ''; end if;
  select nick into v_nick from public.profiles
   where nick_key = v_key and (owner_id is null or owner_id = v_uid) limit 1;
  if v_nick is not null then
    update public.profiles set owner_id = v_uid where nick_key = v_key and owner_id is null;
    return v_nick;
  end if;
  if exists (select 1 from public.profiles where nick_key = v_key) then
    return '';
  end if;
  insert into public.profiles (nick_key, nick, pass_hash, owner_id)
  values (v_key, btrim(p_nick), '', v_uid);
  return btrim(p_nick);
end $$;

-- Есть ли такой ник — без выдачи хешей и прочего
create or replace function public.tn_nick_exists(p_nick text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                  where nick_key = lower(btrim(coalesce(p_nick, ''))))
$$;

revoke all on function public.tn_claim(text) from public;
revoke all on function public.tn_nick_exists(text) from public;
grant execute on function public.tn_claim(text) to authenticated;
grant execute on function public.tn_nick_exists(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
--  2. ПРОФИЛИ: наружу только ники
-- ---------------------------------------------------------------------------
create or replace view public.profiles_public as
  select nick_key, nick from public.profiles;
grant select on public.profiles_public to anon, authenticated;

drop policy if exists "profiles read" on public.profiles;
drop policy if exists "profiles read auth" on public.profiles;
drop policy if exists "profiles insert" on public.profiles;
revoke select, insert, update, delete on public.profiles from anon, authenticated;

-- ---------------------------------------------------------------------------
--  3. ПЕРЕПИСКА: читать и удалять только своё
-- ---------------------------------------------------------------------------
drop policy if exists "tn_read" on public.messages;
drop policy if exists "tn_insert" on public.messages;
drop policy if exists "tn_delete" on public.messages;
drop policy if exists "tn_read_auth" on public.messages;
drop policy if exists "tn_insert_auth" on public.messages;
drop policy if exists "tn_delete_auth" on public.messages;

revoke select, insert, update, delete on public.messages from anon, authenticated;
grant select, delete on public.messages to authenticated;
grant select, insert, delete on public.messages to anon;

create policy "tn_read_own" on public.messages for select to authenticated
  using (lower(to_nick) = lower(public.tn_my_nick()));
create policy "tn_delete_own" on public.messages for delete to authenticated
  using (lower(to_nick) = lower(public.tn_my_nick()));

-- Демо-ники без пароля: они публичные, поэтому им оставляем общий путь.
create policy "tn_demo_read" on public.messages for select to anon
  using (lower(to_nick) in ('админ','админ2','admin','admin2'));
create policy "tn_demo_insert" on public.messages for insert to anon
  with check (lower(from_nick) in ('админ','админ2','admin','admin2'));
create policy "tn_demo_delete" on public.messages for delete to anon
  using (lower(to_nick) in ('админ','админ2','admin','admin2'));

-- ---------------------------------------------------------------------------
--  4. КТО В СЕТИ: только своя строка
-- ---------------------------------------------------------------------------
drop policy if exists "presence read" on public.presence;
drop policy if exists "presence insert" on public.presence;
drop policy if exists "presence update" on public.presence;
drop policy if exists "presence read auth" on public.presence;
drop policy if exists "presence insert auth" on public.presence;
drop policy if exists "presence update auth" on public.presence;

revoke select, insert, update, delete on public.presence from anon, authenticated;
grant select, insert, update on public.presence to authenticated;
grant select, insert, update on public.presence to anon;

create policy "presence read auth" on public.presence for select to authenticated using (true);
create policy "presence write own" on public.presence for insert to authenticated
  with check (lower(nick_key) = lower(public.tn_my_nick()));
create policy "presence update own" on public.presence for update to authenticated
  using (lower(nick_key) = lower(public.tn_my_nick()))
  with check (lower(nick_key) = lower(public.tn_my_nick()));

create policy "presence demo read" on public.presence for select to anon
  using (lower(nick_key) in ('админ','админ2','admin','admin2'));
create policy "presence demo write" on public.presence for insert to anon
  with check (lower(nick_key) in ('админ','админ2','admin','admin2'));
create policy "presence demo update" on public.presence for update to anon
  using (lower(nick_key) in ('админ','админ2','admin','admin2'))
  with check (lower(nick_key) in ('админ','админ2','admin','admin2'));

commit;
