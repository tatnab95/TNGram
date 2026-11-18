-- ===========================================================================
--  Тнграм: очистка старых сообщений и предел скорости.
--  Вставь ВЕСЬ этот текст один раз в Supabase → SQL Editor → New query → Run.
--  Повторный запуск безопасен.
-- ===========================================================================
--
--  Зачем:
--   * «Сообщение удаляется с сервера после доставки» — если получатель так и
--     не зашёл, сообщение висело в облаке вечно. Теперь всё, что старше
--     90 дней, раз в сутки удаляется само (pg_cron, 03:17 UTC).
--   * Одна учётная запись может отправить не больше 30 сообщений в минуту:
--     иначе очередь получателя забивается за секунды.
-- ===========================================================================

-- ---------------------------------------------------------------------------
--  1. ОЧИСТКА
-- ---------------------------------------------------------------------------
create or replace function public.tn_purge_old(p_days integer default 90) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_deleted bigint;
begin
  delete from public.messages where created_at < now() - make_interval(days => greatest(p_days, 1));
  get diagnostics v_deleted = row_count;
  return v_deleted;
end $$;

revoke all on function public.tn_purge_old(integer) from public;

-- Расписание: нужен pg_cron (Dashboard → Database → Extensions → pg_cron).
create extension if not exists pg_cron;
select cron.schedule('tn-purge-old', '17 3 * * *', 'select public.tn_purge_old(90)');

-- ---------------------------------------------------------------------------
--  2. ПРЕДЕЛ СКОРОСТИ
-- ---------------------------------------------------------------------------
create index if not exists messages_from_idx on public.messages (from_nick, created_at);

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
  if (select count(*) from public.messages
       where from_nick = v_from and created_at > now() - interval '1 minute') >= 30 then
    raise exception 'too many messages' using errcode = '42901';
  end if;
  insert into public.messages (from_nick, to_nick, body, client_ts)
  values (v_from, v_to, p_body, coalesce(p_ts, 0))
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.tn_send(text, text, bigint) from public;
grant execute on function public.tn_send(text, text, bigint) to authenticated;

-- ---------------------------------------------------------------------------
--  Проверка
-- ---------------------------------------------------------------------------
--  select jobname, schedule, command from cron.job;
--  select public.tn_purge_old(90);   -- сколько удалилось сейчас
