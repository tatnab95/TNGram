-- ===========================================================================
--  Тнграм: настройка облака. Вставь ВЕСЬ этот текст один раз в
--  Supabase → SQL Editor → New query → Run.
-- ===========================================================================
--
--  Это безопасно запускать повторно: код ничего не ломает, если уже сделано.
--
-- ---------------------------------------------------------------------------
--  1. ЗАНЯТЫЕ НИКИ (таблица profiles)
-- ---------------------------------------------------------------------------
--  Зачем: чтобы один ник не могли занять двое. Пока ники не забронированы,
--  у двух людей с одинаковым ником сообщения путаются и «пропадают».
--
--  Как устроено:
--   * ник хранится в двух видах: как написал владелец (nick) и ключом
--     маленькими буквами (nick_key) — по нему и проверяется занятость,
--     поэтому «Админ» и «админ» считаются одним ником;
--   * правило «nick_key primary key» не даёт вставить ник дважды;
--   * читать и занимать ники может любой (иначе не проверить, свободен ли ник),
--     а менять и удалять — никто через публичный ключ.
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  nick_key   text primary key,
  nick       text not null,
  pass_hash  text not null default '',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles
  for select using (true);

drop policy if exists "profiles insert" on public.profiles;
create policy "profiles insert" on public.profiles
  for insert with check (true);

-- Изменять и удалять ники через публичный ключ нельзя: политик update/delete нет.

-- ---------------------------------------------------------------------------
--  2. ВЕРСИЯ ПРИЛОЖЕНИЯ (таблица version)
-- ---------------------------------------------------------------------------
--  Зачем: чтобы приложение могло сказать «вышла новая версия» — даже без сайта
--  на GitHub. Здесь лежит одна строка: последняя версия.
--
--  Как выпускать обновление:
--   1) подними номер версии в приложении (scripts/net/Protocol.gd, APP_VERSION);
--   2) в этой таблице поменяй значение version на новый номер:
--        update public.version set version = '1.3', notes = 'Что нового…',
--               updated_at = now() where id = 1;
--   3) разошли друзьям новый файл приложения.
--
--  Куда положить новый файл приложения (ссылка для друзей) — в поле url.
-- ---------------------------------------------------------------------------

create table if not exists public.version (
  id         integer primary key,
  version    text not null default '1.2',
  notes      text not null default '',
  url        text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.version enable row level security;

-- Читать версию может любой: это нужно каждому приложению при запуске.
drop policy if exists "version read" on public.version;
create policy "version read" on public.version
  for select using (true);

-- Менять версию через публичный ключ нельзя: политик insert/update/delete нет.
-- Значит, версию может поменять только ты — вручную здесь, в SQL Editor.

-- Строка с текущей версией. Если она уже есть, ничего не переписываем.
insert into public.version (id, version, notes, updated_at)
values (1, '1.2', '', now())
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
--  Проверка, что всё получилось (не обязательно, но полезно).
-- ---------------------------------------------------------------------------
--  select * from public.profiles;
--  select * from public.version;
