use v6;

use Bolts;
use Test;

class Simple {
    method literal(|) is artifact(42) { * }
    method given(|) is artifact(*) { * }
}

my $simple = Simple.new;
is $simple.literal, 42, 'got a 42 from simple.literal';
is $simple.given('not very useful'), 'not very useful', 'got a not very useful from simple.given';

done-testing;
