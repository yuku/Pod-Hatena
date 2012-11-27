use strict;
use warnings;
use Test::More;
use Pod::Hatena;

my $parser = Pod::Hatena->new;

my $alt_text_for_urls = (Pod::ParseLink->VERSION >= 1.10);

my @tests = (
['external ftp',                 q<ftp://server>,       qq^[ftp://server]^],
['external http',                q<http://website>,     qq^[http://website]^],
['http, alt text (perl 5.12)',   q<web|http://website>, qq^[http://website:title=web]^],

['http',              q<http://www.perl.org/>,   qq^[http://www.perl.org/]^],
['text|http',         q<Perl.org|http://www.perl.org/>, qq^[http://www.perl.org/:title=Perl.org]^],

# is there something better to do?
['no url: empty',     q<>,             qq^L<>^],
['no url: pipe',      q<|>,            qq^L<|>^],
['no url: slash',     q</>,            qq^L</>^],
['no url: quotes',    q<"">,           qq^L<"">^],

['empty text: |url',  q<|http://foo>,  qq^[http://foo]^],
['false text: 0|url', q<0|http://foo>, qq^[http://foo:title=0]^],
);

plan tests => scalar @tests * 2;

foreach my $test ( @tests ){
  my ($desc, $pod, $mkdn) = @$test;

  SKIP: {
    skip 'alt text with schemes/absolute URLs not supported until perl 5.12 / Pod::ParseLink 1.10', 1
      if !$alt_text_for_urls && $pod =~ m/\|\w+:[^:\s]\S*\z/; # /alt text \| url (not perl module)/ (regexp from perlpodspec)

    # interior_sequence is what we specifically want to test
    is $parser->interior_sequence(L => $pod), $mkdn, $desc . ' (interior_sequence)';
    # but interpolate() tests the pod parsing as a whole (which can expose recursion bugs, etc)
    is $parser->interpolate("L<<< $pod >>>"), $mkdn, $desc . ' (interpolate)';
  }
}
