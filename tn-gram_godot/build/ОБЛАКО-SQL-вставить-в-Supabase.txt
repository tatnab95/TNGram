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
--  3. КТО СЕЙЧАС В СЕТИ (таблица presence)
-- ---------------------------------------------------------------------------
--  Зачем: чтобы в списке чатов у человека была зелёная точка «в сети», а рядом
--  с именем — «был(а) 5 мин назад». Приложение каждые 25 секунд переписывает
--  здесь время «я здесь», и раз в 12 секунд спрашивает про остальных.
--
--  Одна строка на человека: ники — как и везде, ключом маленькими буквами.
--  Читать, писать и обновлять может любой (это открытые данные «я тут»),
--  а удалять нельзя: политики delete нет.
-- ---------------------------------------------------------------------------

create table if not exists public.presence (
  nick_key  text primary key,
  nick      text not null default '',
  last_seen timestamptz not null default now()
);

alter table public.presence enable row level security;

drop policy if exists "presence read" on public.presence;
create policy "presence read" on public.presence
  for select using (true);

drop policy if exists "presence insert" on public.presence;
create policy "presence insert" on public.presence
  for insert with check (true);

-- Приложение пишет себя «upsert»-ом: строка одна, время перезаписывается.
drop policy if exists "presence update" on public.presence;
create policy "presence update" on public.presence
  for update using (true) with check (true);

-- ---------------------------------------------------------------------------
--  4. НОВОСТИ ОТ РАЗРАБОТЧИКА (таблица news)
-- ---------------------------------------------------------------------------
--  Зачем: экран «Что нового» умеет показывать твои новости — их видно всем,
--  даже тем, у кого нет GitHub-сайта. Это просто лента записей.
--
--  Как добавить новость — руками здесь, в SQL Editor:
--    insert into public.news (title, body) values
--      ('Вышла версия 1.6', 'Группы, кто в сети, новые новости — обновитесь!');
--
--  published = false — черновик: приложение его не покажет.
-- ---------------------------------------------------------------------------

create table if not exists public.news (
  id         bigint generated by default as identity primary key,
  title      text not null default '',
  body       text not null default '',
  published  boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.news enable row level security;

-- Читать можно только опубликованное, писать через публичный ключ — нельзя.
drop policy if exists "news read" on public.news;
create policy "news read" on public.news
  for select using (published);

-- ---------------------------------------------------------------------------
--  Проверка, что всё получилось (не обязательно, но полезно).
-- ---------------------------------------------------------------------------
--  select * from public.profiles;
--  select * from public.version;
--  select * from public.presence;
--  select * from public.news;
