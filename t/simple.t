use v6;

use Bolts;
use Test;

class Simple {
    method literal is artifact(42) { * }
}

my $simple = Simple.new;
is $simple.literal, 42, 'got a 42 from simple.literal';

done-testing;
