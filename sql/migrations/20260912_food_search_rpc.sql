-- Run once on an existing OpenNutriTracker multi-source food backend.
-- Adapted from OpenNutriTracker-Backend/sql/schema.sql, section 6b:
-- https://github.com/simonoppowa/OpenNutriTracker-Backend/blob/main/sql/schema.sql
-- App upstream change: eb08e121 (#911). No user/profile data is changed.
-- New backends can use the current upstream schema instead.

begin;

create index if not exists idx_food_summary_name_fts
    on public.food_summary using gin (to_tsvector('english', name));

create or replace function public.search_food_summary(
    term text,
    sources text[] default null,
    max_rows int default 100
)
returns setof public.food_summary
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
    select fs.*
    from public.food_summary fs
    where to_tsvector('english', fs.name)
          @@ websearch_to_tsquery('english', term)
      and (sources is null or fs.source = any (sources))
    limit greatest(max_rows, 0)
$$;

create or replace function public.search_food_translation(
    term text,
    loc text,
    max_rows int default 100
)
returns table (food_id bigint, description text, source text)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
    select ft.food_id, ft.description, ft.source
    from public.food_translation ft
    where ft.locale = loc
      and to_tsvector('simple', ft.description)
          @@ websearch_to_tsquery('simple', term)
    limit greatest(max_rows, 0)
$$;

create or replace function public.food_summary_by_ids(
    ids bigint[],
    sources text[] default null
)
returns setof public.food_summary
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
    select fs.*
    from public.food_summary fs
    where fs.food_id = any (ids)
      and (sources is null or fs.source = any (sources))
$$;

revoke execute on function public.search_food_summary(text, text[], int) from public;
revoke execute on function public.search_food_translation(text, text, int) from public;
revoke execute on function public.food_summary_by_ids(bigint[], text[]) from public;
grant execute on function public.search_food_summary(text, text[], int) to anon, authenticated;
grant execute on function public.search_food_translation(text, text, int) to anon, authenticated;
grant execute on function public.food_summary_by_ids(bigint[], text[]) to anon, authenticated;

notify pgrst, 'reload schema';
commit;
