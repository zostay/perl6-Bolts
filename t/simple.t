use v6;

use Bolts;
use Test;

class Foo does Bolts::Container {
    has $.stuff;
}

class Simple does Bolts::Container {
    method literal(|) is artifact(42) { * }
    method given(|) is artifact(*) { * }
    method given-param(|) is artifact(*,
        parameters => \(43, opt => 4),
    ) { * }

    method foo(|) is artifact(:class(Foo)) { * }
    method foo-given(|) is artifact(
        class      => Foo,
        parameters => \(stuff => 'some stuff'),
    ) { * }

    method counter(|) is artifact({ ++$ }) { * }
}

my $simple = Simple.new;
is $simple.literal, 42, 'got a 42 from simple.literal';
is $simple.^methods.first(*.name eq 'literal').artifact.blueprint.value, 42, 'we can get at simple.literal the artifact itself';
is $simple.given('not very useful'), 'not very useful', 'got a not very useful from simple.given';
isa-ok $simple.^methods.first(*.name eq 'given').artifact.blueprint, Bolts::Blueprint::Given, 'we can get at simple.given the artifact itself';

is $simple.given-param, 43, 'got correct things from simple.given-param';
is $simple.given(43, opt => 4), 43, 'simple.given is the same as simple.given-param when given the same parameters';

my $foo = $simple.foo(stuff => 'ffuts');
isa-ok $foo, Foo;
is $foo.stuff, 'ffuts', 'got ffuts from foo.stuff';
is $simple.^methods.first(*.name eq 'foo').artifact.blueprint.class, Foo, 'we can get at simple.foo the artifact itself';

is $simple.counter, 1, 'first simple.counter is 1';
is $simple.counter, 2, 'first simple.counter is 2';
is $simple.counter, 3, 'first simple.counter is 3';
isa-ok $simple.^methods.first(*.name eq 'counter').artifact.blueprint, Bolts::Blueprint::Built, 'we can get at simple.counter the artifact itself';

is $simple.acquire(<foo-given stuff>), 'some stuff', 'acquisition works';
is $simple.acquire([ foo => \(stuff => 'other stuff'), 'stuff' ]), 'other stuff', 'acquisition with intermediate args works';
is $foo.acquire(<stuff>), 'ffuts', 'acquisition from foo works';
is $foo.acquire(</ foo-given stuff>), 'some stuff', 'acquisition back through root works';

done-testing;
