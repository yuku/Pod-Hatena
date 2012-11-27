use strict;
use warnings;
use Test::More;
use Pod::Hatena;

my $parser = Pod::Hatena->new;

my @tests = (
  [I => q<italic>,          q{<i>italic</i>}],
  [B => q<bold>,            q{<b>bold</b>}],
  [C => q<code>,            q{<code>code</code>}],

  [L => q<http://sample.com>, "[http://sample.com]"],

  [E => q<lt>,              q{&lt;}],
  [E => q<gt>,              q{&gt;}],
  [E => q<verbar>,          q{|}],
  [E => q<sol>,             q{/}],

  [E => q<eacute>,          q{&eacute;}],
  [E => q<0x201E>,          q{&#x201E;},  'E hex'],
  [E => q<075>,             q{&#61;},     'E octal'],
  [E => q<181>,             q{&#181;},    'E decimal'],

  # legacy charnames specifically mentioned by perlpodspec
  [E => q<lchevron>,        q{&laquo;}],
  [E => q<rchevron>,        q{&raquo;}],
  [E => q<zchevron>,        q{&zchevron;}],
  [E => q<rchevrony>,       q{&rchevrony;}],

  [F => q<file.ext>,        q{<code>file.ext</code>}],
  [S => q<$x ? $y : $z>,    q{<nobr>$x&nbsp;?&nbsp;$y&nbsp;:&nbsp;$z</nobr>}],
  [X => q<index>,           q{}],
  [Z => q<null>,            q{}],

  [Q => q<unknown>,         q{Q<unknown>}, 'uknown code (Q<>)' ],
);

plan tests => scalar @tests * 2;

foreach my $test ( @tests ){
  my ($code, $text, $exp, $desc) = @$test;
  $desc ||= "$code<$text>";

    # explicitly test interior_sequence (which is what we've defined)
    is $parser->interior_sequence($code => $text), $exp, $desc . ' (interior_sequence)';
    # also test parsing it as pod
    is $parser->interpolate("$code<<< $text >>>"), $exp, $desc . ' (interpolate)';
}
