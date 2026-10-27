-- Ligues avec un nom : creation et recherche par code.
-- A coller dans Supabase : SQL Editor > New query > coller > Run (apres supabase-setup.sql).

create table if not exists public.leagues (
  code text primary key check (code ~ '^[a-z0-9]{3,20}$'),
  name text not null check (char_length(name) between 2 and 30),
  created_at timestamptz not null default now()
);
alter table public.leagues enable row level security;
revoke all on public.leagues from anon, authenticated;

create or replace function public.create_league(p_code text, p_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from leagues where code = p_code) then raise exception 'code_pris'; end if;
  insert into leagues (code, name) values (p_code, p_name);
end $$;

create or replace function public.get_league(p_code text)
returns table (code text, name text)
language sql security definer set search_path = public as $$
  select code, name from leagues where code = p_code;
$$;

grant execute on function public.create_league(text, text) to anon;
grant execute on function public.get_league(text) to anon;
