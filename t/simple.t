use v6;

use Bolts;
use Test;

class Foo {
    has $.stuff;
}

class Simple {
    method literal(|) is artifact(42) { * }
    method given(|) is artifact(*) { * }

    method foo(|) is artifact(:class(Foo)) { * }
}

my $simple = Simple.new;
is $simple.literal, 42, 'got a 42 from simple.literal';
is $simple.given('not very useful'), 'not very useful', 'got a not very useful from simple.given';

my $foo = $simple.foo(stuff => 'ffuts');
isa-ok $foo, Foo;
is $foo.stuff, 'ffuts', 'got ffuts from foo.stuff';

done-testing;
