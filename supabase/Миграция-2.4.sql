-- ===========================================================================
--  Тнграм 2.4: вход в облако и подписанная отправка.
--  Вставь ВЕСЬ этот текст один раз в Supabase → SQL Editor → New query → Run.
--  Повторный запуск безопасен: всё создаётся «if not exists» / «or replace».
-- ===========================================================================
--
--  Что меняется:
--   * у ника появляется владелец (owner_id) — учётная запись облака;
--   * вошедший занимает свой ник через функцию tn_claim: облако само знает,
--     чья это учётная запись, и пароль по сети больше не сверяется;
--   * отправителя сообщения подставляет облако (tn_send), а не клиент:
--     подделать from_nick больше нельзя;
--   * у вошедших появляются свои правила доступа к messages, presence, profiles.
--
--  Это первый шаг. Правила для вошедших пока такие же мягкие, как были:
--  старые версии приложения (2.3 и ниже) продолжают работать по публичному
--  ключу. Второй шаг — закрыть доступ по публичному ключу, когда 2.4
--  установится у всех.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
--  1. ВЛАДЕЛЕЦ НИКА
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists owner_id uuid;
create index if not exists profiles_owner_idx on public.profiles (owner_id);

-- ---------------------------------------------------------------------------
--  2. ПРАВИЛА ДЛЯ ВОШЕДШИХ (пока такие же мягкие, как для публичного ключа)
-- ---------------------------------------------------------------------------
drop policy if exists "tn_read_auth" on public.messages;
create policy "tn_read_auth" on public.messages for select to authenticated using (true);

drop policy if exists "tn_insert_auth" on public.messages;
create policy "tn_insert_auth" on public.messages for insert to authenticated with check (true);

drop policy if exists "tn_delete_auth" on public.messages;
create policy "tn_delete_auth" on public.messages for delete to authenticated using (true);

drop policy if exists "presence read auth" on public.presence;
create policy "presence read auth" on public.presence for select to authenticated using (true);

drop policy if exists "presence insert auth" on public.presence;
create policy "presence insert auth" on public.presence for insert to authenticated with check (true);

drop policy if exists "presence update auth" on public.presence;
create policy "presence update auth" on public.presence for update to authenticated using (true) with check (true);

drop policy if exists "profiles read auth" on public.profiles;
create policy "profiles read auth" on public.profiles for select to authenticated using (true);

-- ---------------------------------------------------------------------------
--  3. ЗАНЯТЬ НИК
-- ---------------------------------------------------------------------------
--  Свободный ник (owner_id пустой) или уже свой — закрепляем за учётной записью.
--  Чужой ник не отдаём: пустая строка в ответе означает «занят».
-- ---------------------------------------------------------------------------
create or replace function public.tn_claim(p_nick text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_key text := lower(btrim(coalesce(p_nick, '')));
  v_nick text;
begin
  if v_uid is null or v_key = '' then return ''; end if;
  select nick into v_nick from public.profiles
   where nick_key = v_key and (owner_id is null or owner_id = v_uid) limit 1;
  if v_nick is null then return ''; end if;
  update public.profiles set owner_id = v_uid where nick_key = v_key and owner_id is null;
  return v_nick;
end $$;

-- Чей ник у вошедшего — для экранов, где нужно своё имя.
create or replace function public.tn_my_nick() returns text
language sql security definer set search_path = public as $$
  select nick from public.profiles where owner_id = auth.uid() limit 1
$$;

-- ---------------------------------------------------------------------------
--  4. ОТПРАВКА СООБЩЕНИЯ
-- ---------------------------------------------------------------------------
--  Отправителя берём из учётной записи, а не из тела запроса. Длины проверяем
--  здесь же: клиенту верить нельзя.
-- ---------------------------------------------------------------------------
create or replace function public.tn_send(p_to text, p_body text, p_ts bigint default 0) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_from text;
  v_to text := btrim(coalesce(p_to, ''));
  v_id bigint;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select nick into v_from from public.profiles where owner_id = v_uid limit 1;
  if v_from is null then raise exception 'nick not claimed' using errcode = '28000'; end if;
  if char_length(v_to) < 1 or char_length(v_to) > 24 then raise exception 'bad recipient'; end if;
  if char_length(coalesce(p_body, '')) < 1 or char_length(p_body) > 4000 then raise exception 'bad body'; end if;
  insert into public.messages (from_nick, to_nick, body, client_ts)
  values (v_from, v_to, p_body, coalesce(p_ts, 0))
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.tn_claim(text) from public;
revoke all on function public.tn_my_nick() from public;
revoke all on function public.tn_send(text, text, bigint) from public;
grant execute on function public.tn_claim(text) to authenticated;
grant execute on function public.tn_my_nick() to authenticated;
grant execute on function public.tn_send(text, text, bigint) to authenticated;

-- ---------------------------------------------------------------------------
--  5. ПОЛЕЗНЫЕ ОГРАНИЧЕНИЯ И ИНДЕКС ПОД ОЧИСТКУ
-- ---------------------------------------------------------------------------
alter table public.messages drop constraint if exists messages_body_len;
alter table public.messages add constraint messages_body_len
  check (char_length(body) <= 4000) not valid;
alter table public.profiles drop constraint if exists profiles_nick_len;
alter table public.profiles add constraint profiles_nick_len
  check (char_length(nick) between 2 and 24) not valid;
alter table public.survey_votes drop constraint if exists survey_text_len;
alter table public.survey_votes add constraint survey_text_len
  check (char_length(text) <= 500) not valid;
create index if not exists messages_created_at_idx on public.messages (created_at);

-- ---------------------------------------------------------------------------
--  6. НОВОСТИ СНОВА ЧИТАЮТСЯ
-- ---------------------------------------------------------------------------
drop policy if exists "news read" on public.news;
create policy "news read" on public.news for select using (published);

-- ---------------------------------------------------------------------------
--  7. ЛИШНИЕ ПРАВА
-- ---------------------------------------------------------------------------
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
revoke update, delete on public.profiles from anon, authenticated;
revoke insert, update, delete on public.news from anon, authenticated;
revoke insert, update, delete on public.version from anon, authenticated;
revoke update, delete on public.survey_votes from anon, authenticated;

-- ---------------------------------------------------------------------------
--  Проверка
-- ---------------------------------------------------------------------------
--  select nick, nick_key, owner_id from public.profiles order by nick;
--  select tablename, policyname, cmd, roles from pg_policies
--   where schemaname = 'public' order by tablename, cmd;
