-- Classement entre amis, Worlds 2026 Live.
-- A coller dans Supabase : menu "SQL Editor" > "New query" > coller > "Run".
-- Rien de secret ici : les jetons sont fictifs.

create table if not exists public.players (
  id uuid primary key,
  token text not null,                      -- jeton prive du joueur, jamais renvoye au navigateur des autres
  league text not null check (league ~ '^[a-z0-9]{3,20}$'),
  pseudo text not null check (char_length(pseudo) between 2 and 20),
  balance int not null check (balance between 0 and 1000000),
  engaged int not null default 0 check (engaged between 0 and 1000000),
  won int not null default 0 check (won between 0 and 10000),
  lost int not null default 0 check (lost between 0 and 10000),
  updated_at timestamptz not null default now(),
  unique (league, pseudo)
);

-- Aucun acces direct a la table : tout passe par les deux fonctions ci-dessous.
alter table public.players enable row level security;
revoke all on public.players from anon, authenticated;

create or replace function public.upsert_player(
  p_id uuid, p_token text, p_league text, p_pseudo text,
  p_balance int, p_engaged int, p_won int, p_lost int
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from players where league = p_league and pseudo = p_pseudo and id <> p_id) then
    raise exception 'pseudo_pris';
  end if;
  insert into players (id, token, league, pseudo, balance, engaged, won, lost)
  values (p_id, p_token, p_league, p_pseudo, p_balance, p_engaged, p_won, p_lost)
  on conflict (id) do update
    set pseudo = excluded.pseudo, balance = excluded.balance, engaged = excluded.engaged,
        won = excluded.won, lost = excluded.lost, updated_at = now()
    where players.token = p_token;
end $$;

create or replace function public.get_leaderboard(p_league text)
returns table (id uuid, pseudo text, total int, balance int, engaged int, won int, lost int, updated_at timestamptz)
language sql security definer set search_path = public as $$
  select id, pseudo, balance + engaged as total, balance, engaged, won, lost, updated_at
  from players where league = p_league order by balance + engaged desc, pseudo limit 100;
$$;

grant execute on function public.upsert_player(uuid, text, text, text, int, int, int, int) to anon;
grant execute on function public.get_leaderboard(text) to anon;
