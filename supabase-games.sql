-- Paris "deroule game par game" : memoire commune des resultats de chaque game.
-- A coller dans Supabase : SQL Editor > New query > coller > Run (apres supabase-setup.sql).

create table if not exists public.game_results (
  match_id text not null check (char_length(match_id) between 5 and 40),
  game_no int not null check (game_no between 1 and 5),
  winner text not null check (char_length(winner) between 1 and 40),
  created_at timestamptz not null default now(),
  primary key (match_id, game_no)
);
alter table public.game_results enable row level security;
revoke all on public.game_results from anon, authenticated;

-- Le premier resultat enregistre pour une game fait foi.
create or replace function public.record_game(p_match text, p_game int, p_winner text)
returns void language sql security definer set search_path = public as $$
  insert into game_results (match_id, game_no, winner) values (p_match, p_game, p_winner)
  on conflict do nothing;
$$;

create or replace function public.get_games(p_matches text[])
returns table (match_id text, game_no int, winner text)
language sql security definer set search_path = public as $$
  select match_id, game_no, winner from game_results where match_id = any(p_matches);
$$;

grant execute on function public.record_game(text, int, text) to anon;
grant execute on function public.get_games(text[]) to anon;
