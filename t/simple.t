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

    method counter(|) is artifact({ ++$ }) { * }
}

my $simple = Simple.new;
is $simple.literal, 42, 'got a 42 from simple.literal';
is $simple.^methods.first(*.name eq 'literal').artifact.blueprint.value, 42, 'we can get at simple.literal the artifact itself';
is $simple.given('not very useful'), 'not very useful', 'got a not very useful from simple.given';
isa-ok $simple.^methods.first(*.name eq 'given').artifact.blueprint, Bolts::Blueprint::Given, 'we can get at simple.given the artifact itself';

my $foo = $simple.foo(stuff => 'ffuts');
isa-ok $foo, Foo;
is $foo.stuff, 'ffuts', 'got ffuts from foo.stuff';
is $simple.^methods.first(*.name eq 'foo').artifact.blueprint.class, Foo, 'we can get at simple.foo the artifact itself';

is $simple.counter, 1, 'first simple.counter is 1';
is $simple.counter, 2, 'first simple.counter is 2';
is $simple.counter, 3, 'first simple.counter is 3';
isa-ok $simple.^methods.first(*.name eq 'counter').artifact.blueprint, Bolts::Blueprint::Built, 'we can get at simple.counter the artifact itself';

done-testing;
