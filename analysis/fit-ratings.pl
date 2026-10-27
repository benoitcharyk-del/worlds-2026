#!/usr/bin/perl
# Estime la force de chaque equipe (modele logistique de Bradley-Terry sur les games) a partir de matches.json.
# Force d'une equipe = niveau de sa ligue (relie par les matchs internationaux) + ecart propre a l'equipe.
use strict; use warnings; use JSON::PP;
my $json = JSON::PP->new->utf8->canonical->pretty;
local $/; open my $fh, '<:raw', 'matches.json' or die; my $M = decode_json(<$fh>); close $fh;

my %ALIAS = ('gen.g esports' => 'Gen.G', 'los' => 'Los Grandes', 'cloud9 kia' => 'Cloud9 KIA', 'top esports' => 'Top Esports',
  'bilibili gaming' => 'Bilibili Gaming');
my @W26 = ('Gen.G', "Anyone's Legend", 'Team Liquid Alienware', 'G2 Esports', 'Team Secret Whales', 'Los Grandes', 'Hanwha Life Esports',
  'Bilibili Gaming', 'LYON', 'Movistar KOI', 'T1', 'Top Esports', 'CTBC Flying Oyster', 'Invictus Gaming', 'Dplus KIA', 'Karmine Corp');
my %CANON = map { lc($_) => $_ } @W26;
sub canon { my $n = shift; my $k = lc $n; return $ALIAS{$k} // $CANON{$k} // $n; }

my %REGIONAL = map { $_ => 1 } qw(lck lpl lec lcs lcp cblol);
my @g = gmtime(); my $now = sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $g[5]+1900, $g[4]+1, $g[3], $g[2], $g[1], $g[0]);
sub days_between { my ($a, $b) = @_; my @x = map { /(\d+)-(\d+)-(\d+)/; ($1 * 372 + $2 * 31 + $3) } ($a, $b); return $x[1] - $x[0]; }

# ligue d'une equipe = ligue regionale ou elle a le plus de matchs
my (%cnt, %games, %wins);
for my $m (@$M) {
  my ($a, $b) = (canon($m->{a}), canon($m->{b}));
  $cnt{$a}{ $m->{lg} }++ if $REGIONAL{ $m->{lg} }; $cnt{$b}{ $m->{lg} }++ if $REGIONAL{ $m->{lg} };
  $games{$a} += $m->{aw} + $m->{bw}; $games{$b} += $m->{aw} + $m->{bw};
  $wins{$a} += $m->{aw}; $wins{$b} += $m->{bw};
}
my %lg;
for my $t (keys %games) {
  my ($best) = sort { $cnt{$t}{$b} <=> $cnt{$t}{$a} } keys %{ $cnt{$t} // {} };
  $lg{$t} = $best // 'autre';
}

# observations ponderees par l'anciennete (demi-vie ~ 120 jours)
my @obs;
for my $m (@$M) {
  my $age = days_between(substr($m->{t}, 0, 10), substr($now, 0, 10));
  my $w = 0.5 ** ($age / 120);
  push @obs, [ canon($m->{a}), canon($m->{b}), $m->{aw}, $m->{bw}, $w ];
}
my @teams = sort keys %games; my @leagues = do { my %s = map { $_ => 1 } values %lg; sort keys %s };
my (%d, %L); $d{$_} = 0 for @teams; $L{$_} = 0 for @leagues;
my ($lamD, $lamL) = (1.5, 0.05);
sub r { my $t = shift; return $L{ $lg{$t} } + $d{$t}; }
for my $it (1 .. 400) {
  my (%gd, %hd, %gL, %hL);
  for my $o (@obs) {
    my ($a, $b, $aw, $bw, $w) = @$o; my $n = $aw + $bw; next unless $n;
    my $p = 1 / (1 + exp(-(r($a) - r($b))));
    my $g = $w * ($aw - $n * $p); my $h = $w * $n * $p * (1 - $p);
    $gd{$a} += $g; $gd{$b} -= $g; $hd{$a} += $h; $hd{$b} += $h;
    $gL{ $lg{$a} } += $g; $gL{ $lg{$b} } -= $g; $hL{ $lg{$a} } += $h; $hL{ $lg{$b} } += $h;
  }
  for my $t (@teams) { $d{$t} += ($gd{$t} // 0) / (($hd{$t} // 0) + $lamD + 1) - $lamD * $d{$t} / (($hd{$t} // 0) + $lamD + 1); }
  for my $l (@leagues) { $L{$l} += (($gL{$l} // 0) - $lamL * $L{$l}) / (($hL{$l} // 0) + $lamL + 1) * 0.5; }
}
# centre les forces (moyenne des 16 equipes des Worlds = 0)
my $mean = 0; $mean += r($_) for @W26; $mean /= @W26;
my %out;
for my $t (@teams) {
  next unless grep { $_ eq $t } @W26;
  $out{$t} = { r => sprintf('%.3f', r($t) - $mean) + 0, league => $lg{$t}, games => $games{$t}, winrate => sprintf('%.3f', $wins{$t} / $games{$t}) + 0 };
}
my %leag = map { $_ => sprintf('%.3f', $L{$_} - $mean) + 0 } @leagues;
my $res = { asOf => $now, teams => \%out, leagues => \%leag, note => 'Bradley-Terry sur les games depuis le 2025-10-01, demi-vie 120 jours' };
open my $o, '>:raw', 'ratings.json' or die; print $o $json->encode($res); close $o;
for my $t (sort { $out{$b}{r} <=> $out{$a}{r} } keys %out) {
  printf "%-24s r=%6.2f  %-6s games=%3d wr=%.0f%%\n", $t, $out{$t}{r}, $out{$t}{league}, $out{$t}{games}, $out{$t}{winrate} * 100;
}
print "ligues: " . join(', ', map { "$_=$leag{$_}" } sort keys %leag) . "\n";
