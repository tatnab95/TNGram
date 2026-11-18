-- ===========================================================================
--  Тнграм 2.5: закрыть публичный ключ (ШАГ 2).
--  Черновик. НЕ запускать, пока приложение 2.4 не установилось у людей:
--  после этого шага версии 2.3 и ниже перестанут получать и отправлять
--  сообщения — у них нет пропуска облака.
-- ===========================================================================
--
--  Что станет:
--   * переписку читает и удаляет только адресат (по своей учётной записи);
--   * отправить сообщение можно только через tn_send — отправителя подписывает
--     облако, from_nick из запроса не берётся;
--   * presence пишет только сам человек;
--   * хеши паролей больше не отдаются никому: вместо таблицы — представление
--     без pass_hash, а проверка пароля уходит в Supabase Auth.
--
--  Порядок запуска:
--   1) все клиенты 2.4 у людей (проверить: в profiles есть owner_id у живых ников);
--   2) выполнить этот файл;
--   3) выпустить 2.5, где веб-клиент больше не читает pass_hash.
-- ===========================================================================

begin;

-- ---------------------------------------------------------------------------
--  1. ПЕРЕПИСКА
-- ---------------------------------------------------------------------------
-- Прямая вставка закрывается: единственный путь — tn_send.
drop policy if exists "tn_insert" on public.messages;
drop policy if exists "tn_insert_auth" on public.messages;
revoke insert on public.messages from anon, authenticated;

-- Читать и удалять — только своё. Сравниваем с ником, закреплённым за учётной записью.
drop policy if exists "tn_read" on public.messages;
drop policy if exists "tn_read_auth" on public.messages;
create policy "tn_read_own" on public.messages
  for select to authenticated
  using (to_nick = (select nick from public.profiles where owner_id = auth.uid() limit 1));

drop policy if exists "tn_delete" on public.messages;
drop policy if exists "tn_delete_auth" on public.messages;
create policy "tn_delete_own" on public.messages
  for delete to authenticated
  using (to_nick = (select nick from public.profiles where owner_id = auth.uid() limit 1));

revoke select, delete on public.messages from anon;

-- ---------------------------------------------------------------------------
--  2. КТО В СЕТИ
-- ---------------------------------------------------------------------------
drop policy if exists "presence insert" on public.presence;
drop policy if exists "presence update" on public.presence;
drop policy if exists "presence insert auth" on public.presence;
drop policy if exists "presence update auth" on public.presence;
drop policy if exists "presence read" on public.presence;
drop policy if exists "presence read auth" on public.presence;

create policy "presence read own net" on public.presence
  for select to authenticated using (true);

create policy "presence write own" on public.presence
  for insert to authenticated
  with check (nick_key = lower((select nick from public.profiles where owner_id = auth.uid() limit 1)));

create policy "presence update own" on public.presence
  for update to authenticated
  using (nick_key = lower((select nick from public.profiles where owner_id = auth.uid() limit 1)))
  with check (nick_key = lower((select nick from public.profiles where owner_id = auth.uid() limit 1)));

revoke select, insert, update on public.presence from anon;

-- ---------------------------------------------------------------------------
--  3. ПРОФИЛИ БЕЗ ХЕШЕЙ
-- ---------------------------------------------------------------------------
-- Наружу — только ник. Хеш остаётся в таблице до шага 3 и нужен лишь для
-- одноразового переноса старых аккаунтов в облако.
create or replace view public.profiles_public as
  select nick_key, nick from public.profiles;

grant select on public.profiles_public to anon, authenticated;

drop policy if exists "profiles read" on public.profiles;
drop policy if exists "profiles read auth" on public.profiles;
revoke select on public.profiles from anon, authenticated;

-- Занять ник по-прежнему можно только через tn_claim: прямой вставки нет.
drop policy if exists "profiles insert" on public.profiles;
revoke insert on public.profiles from anon, authenticated;

-- ---------------------------------------------------------------------------
--  4. ПРАВА ЛИШНЕГО НЕ НУЖНО
-- ---------------------------------------------------------------------------
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
revoke insert, update, delete on public.news from anon, authenticated;
revoke insert, update, delete on public.version from anon, authenticated;
revoke update, delete on public.survey_votes from anon, authenticated;

commit;

-- ---------------------------------------------------------------------------
--  Проверка
-- ---------------------------------------------------------------------------
--  select tablename, policyname, cmd, roles from pg_policies
--   where schemaname = 'public' order by tablename, cmd;
--  select * from public.profiles_public limit 5;
