-- ===========================================================================
--  Тнграм: ответы опроса с сайта.
--  Вставь ВЕСЬ этот текст один раз в Supabase → SQL Editor → New query → Run.
--  Повторный запуск безопасен: код ничего не ломает, если уже сделано.
-- ===========================================================================
--
--  Что происходит после запуска:
--   * сайт (кнопка «Отправить ответы») пишет строки в public.survey_votes;
--   * сводка public.survey_tally считает, сколько раз выбран каждый вариант;
--   * сайт читает сводку и рисует проценты.
--
--  Одна строка = один отмеченный вариант одного человека.
--  Для вопроса «до двух вариантов» один человек даёт две строки.
--
--  Настройки сайта лежат в index.html → CONFIG.survey:
--    url, key, table = 'survey_votes', tally = 'survey_tally'
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
--  1. ГОЛОСА
-- ---------------------------------------------------------------------------
create table if not exists public.survey_votes (
  id         bigserial primary key,
  q          text not null,                 -- id вопроса: messenger, instability, …
  answer     text not null,                 -- id варианта: telegram, whatsapp, other, …
  custom     boolean not null default false,-- true = свой вариант из поля ввода
  text       text not null default '',      -- текст своего варианта
  created_at timestamptz not null default now()
);

create index if not exists survey_votes_q_idx on public.survey_votes (q);

alter table public.survey_votes enable row level security;

-- Читать голоса может любой: иначе не построить проценты.
drop policy if exists "survey votes read" on public.survey_votes;
create policy "survey votes read" on public.survey_votes
  for select using (true);

-- Добавлять голос может любой посетитель сайта.
drop policy if exists "survey votes insert" on public.survey_votes;
create policy "survey votes insert" on public.survey_votes
  for insert with check (true);

-- Изменять и удалять голоса через публичный ключ нельзя:
-- политик update/delete нет.

grant usage on schema public to anon, authenticated;
grant select, insert on public.survey_votes to anon, authenticated;
grant usage, select on sequence public.survey_votes_id_seq to anon, authenticated;

-- ---------------------------------------------------------------------------
--  2. СВОДКА ДЛЯ ПРОЦЕНТОВ
-- ---------------------------------------------------------------------------
-- Что видит сайт: q, answer, custom, text, votes.
-- Проценты сайт считает сам: votes / сумма votes по этому вопросу.
-- ---------------------------------------------------------------------------
create or replace view public.survey_tally as
  select q,
         answer,
         custom,
         text,
         count(*)::int as votes
    from public.survey_votes
   group by q, answer, custom, text;

grant select on public.survey_tally to anon, authenticated;

-- ---------------------------------------------------------------------------
--  3. ПРОВЕРКА
-- ---------------------------------------------------------------------------
select * from public.survey_tally order by q, votes desc;
