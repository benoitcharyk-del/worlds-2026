#!/usr/bin/perl
# Recupere les matchs termines (depuis HORIZON) des ligues majeures via l'API publique lolesports.com.
# Lecture seule, une page a la fois, avec une courte pause entre deux requetes.
use strict; use warnings; use JSON::PP; use Time::HiRes qw(sleep);
my $KEY = '0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z';
my $HORIZON = '2025-10-01';
my %L = (
  worlds => '98767975604431411', msi => '98767991325878492', first_stand => '113464388705111224', ewc => '116838530616006090',
  lck => '98767991310872058', lpl => '98767991314006698', lec => '98767991302996019', lcs => '98767991299243165',
  lcp => '113476371197627891', cblol => '98767991332355509', lta_n => '113470291645289904', lta_s => '113475181634818701',
  lta_cross => '113475149040947852',
);
my $json = JSON::PP->new->utf8->canonical;
my @out; my $req = 0;
for my $name (sort keys %L) {
  my $token = ''; my $pages = 0; my $n = 0;
  while ($pages < 30) {
    my $url = "https://esports-api.lolesports.com/persisted/gw/getSchedule?hl=en-US&leagueId=$L{$name}" . ($token ? "&pageToken=$token" : '');
    my $raw = `curl -s -m 30 -H "x-api-key: $KEY" "$url"`;
    $req++; $pages++;
    my $j = eval { decode_json($raw) } or last;
    my $s = $j->{data}{schedule} or last;
    my $oldest = '9';
    for my $e (@{ $s->{events} }) {
      $oldest = $e->{startTime} if $e->{startTime} lt $oldest;
      next unless $e->{match} && $e->{state} eq 'completed' && $e->{startTime} ge $HORIZON;
      my @t = @{ $e->{match}{teams} };
      next unless @t == 2 && $t[0]{name} && $t[0]{name} ne 'TBD' && $t[1]{name} ne 'TBD';
      push @out, { lg => $name, t => $e->{startTime}, blk => $e->{blockName}, bo => $e->{match}{strategy}{count},
        a => $t[0]{name}, ac => $t[0]{code}, aw => $t[0]{result}{gameWins}, b => $t[1]{name}, bc => $t[1]{code}, bw => $t[1]{result}{gameWins} };
      $n++;
    }
    $token = $s->{pages}{older} or last;
    last if $oldest lt $HORIZON;
    sleep(0.4);
  }
  print "$name: $n matchs ($pages pages)\n";
}
open my $fh, '>:raw', 'matches.json' or die; print $fh $json->encode(\@out); close $fh;
print "total: " . scalar(@out) . " matchs, $req requetes\n";
