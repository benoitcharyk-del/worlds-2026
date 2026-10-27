#!/usr/bin/perl
# Enregistre dans Supabase le vainqueur de chaque game, a partir de l'API publique de lolesports.com.
# Sans etat : pour chaque match, on compare les games deja enregistrees au score actuel.
# Un match 2-0 / 3-0 est toujours complet ; un match en 3 games ou plus est complete des que
# la derniere game est la seule manquante. Execute par GitHub Actions toutes les 5 minutes.
use strict; use warnings; use JSON::PP;
my $DRY = $ENV{DRY} ? 1 : 0;
my $json = JSON::PP->new->utf8->canonical;
sub slurp { my $f = shift; open my $fh, '<:raw', $f or die "$f: $!\n"; local $/; my $c = <$fh>; close $fh; $c }

my $cfg = slurp('config.js');
my ($URL) = $cfg =~ /url:\s*'([^']+)'/; my ($KEY) = $cfg =~ /key:\s*'([^']+)'/;
die "config.js incomplet\n" unless $URL && $KEY;
my $API = '0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z';   # cle publique utilisee par lolesports.com

my @TEAMS = ('Gen.G', "Anyone's Legend", 'Team Liquid Alienware', 'G2 Esports', 'Team Secret Whales', 'Los Grandes', 'Hanwha Life Esports',
  'Bilibili Gaming', 'LYON', 'Movistar KOI', 'T1', 'Top Esports', 'CTBC Flying Oyster', 'Invictus Gaming', 'Dplus KIA', 'Karmine Corp');
my %CANON = map { lc($_) => $_ } @TEAMS; $CANON{'gen.g esports'} = 'Gen.G'; $CANON{'los'} = 'Los Grandes';
sub canon { my $n = shift; return $CANON{lc $n} // $n; }

sub curl_json {
  my @args = @_;
  my $raw = `curl -s -m 30 @args`;
  return eval { decode_json($raw) };
}

my $sched = curl_json('-H', "'x-api-key: $API'", "'https://esports-api.lolesports.com/persisted/gw/getSchedule?hl=en-US&leagueId=98767975604431411'") or die "API indisponible\n";
my @ev = grep { $_->{match} && ($_->{startTime} // '') ge '2026-10-01' && $_->{state} ne 'unstarted' } @{ $sched->{data}{schedule}{events} };
my %m;
for my $e (@ev) {
  my @t = @{ $e->{match}{teams} }; next unless @t == 2 && $t[0]{name} ne 'TBD' && $t[1]{name} ne 'TBD';
  my @w = map { 0 + ($_->{result}{gameWins} // 0) } @t;
  $m{ $e->{match}{id} } = { names => [ canon($t[0]{name}), canon($t[1]{name}) ], wins => \@w } if $w[0] + $w[1] > 0;
}
exit 0 unless %m;

my $body = $json->encode({ p_matches => [ keys %m ] });
my $got = curl_json('-X', 'POST', "'$URL/rest/v1/rpc/get_games'", '-H', "'apikey: $KEY'", '-H', "'Content-Type: application/json'", '-d', "'$body'");
die "Supabase: lecture impossible\n" unless ref $got eq 'ARRAY';
my %rec; $rec{ $_->{match_id} }{ $_->{game_no} } = $_->{winner} for @$got;

my ($posted, $skipped) = (0, 0);
for my $mid (sort keys %m) {
  my ($n, $w) = ($m{$mid}{names}, $m{$mid}{wins}); my $tot = $w->[0] + $w->[1];
  my %have = %{ $rec{$mid} // {} };
  my @missing = grep { !$have{$_} } 1 .. $tot; next unless @missing;
  my @c = (0, 0);
  for my $g (keys %have) { $c[0]++ if $have{$g} eq $n->[0]; $c[1]++ if $have{$g} eq $n->[1]; }
  my @r = ($w->[0] - $c[0], $w->[1] - $c[1]);
  if ($r[0] < 0 || $r[1] < 0 || $r[0] + $r[1] != @missing) { $skipped++; next; }
  my $winner = $r[1] == 0 ? $n->[0] : $r[0] == 0 ? $n->[1] : undef;
  unless (defined $winner) { $skipped++; next; }
  for my $g (@missing) {
    print "game $g de $mid -> $winner\n";
    next if $DRY;
    my $b = $json->encode({ p_match => $mid, p_game => 0 + $g, p_winner => $winner });
    my $code = `curl -s -m 20 -o /dev/null -w "%{http_code}" -X POST '$URL/rest/v1/rpc/record_game' -H 'apikey: $KEY' -H 'Content-Type: application/json' -d '$b'`;
    $posted++ if $code =~ /^2/;
  }
}
print "matchs suivis: " . scalar(keys %m) . ", games envoyees: $posted, matchs ambigus: $skipped\n";
