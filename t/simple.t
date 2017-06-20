use v6;

use Bolts;
use Test;

class Foo does Bolts::Container {
    has $.stuff is rw;

    method root-acquired(|) is factory(path => </ literal>) { * }
}

class Simple does Bolts::Container {
    method literal(|) is factory(42) { * }
    method given(|) is factory(*) { * }
    method given-param(|) is factory(*,
        parameters => \(43, opt => 4),
    ) { * }

    method foo(|) is factory(:class(Foo)) { * }
    method foo-param(|) is factory(
        class      => Foo,
        parameters => \(stuff => 'some stuff'),
    ) { * }
    method foo-setter(|) is factory(
        class      => Foo,
        mutators   => (
            { set => 'stuff', to  => 14, },
        ),
    ) { * }

    method counter(|) is factory({ ++$ }) { * }

    method random(|) is factory({ rand }) { * }
    method random-singleton(|) is factory({ rand }, scope => Bolts::Scope::Singleton) { * }
    method random-dynamic(|) is factory({ rand }, scope => Bolts::Scope::Dynamic.new('%*my-rand')) { * }
}

my $simple = Simple.new;
is $simple.literal, 42, 'got a 42 from simple.literal';
is $simple.^methods.first(*.name eq 'literal').factory.blueprint.value, 42, 'we can get at simple.literal the factory itself';
is $simple.given('not very useful'), 'not very useful', 'got a not very useful from simple.given';
isa-ok $simple.^methods.first(*.name eq 'given').factory.blueprint, Bolts::Blueprint::Given, 'we can get at simple.given the factory itself';

is-deeply $simple.given-param, \(43, opt => 4), 'got correct things from simple.given-param';
is-deeply $simple.given(43, opt => 4), \(43, opt => 4), 'simple.given is the same as simple.given-param when given the same parameters';

my $foo = $simple.foo(stuff => 'ffuts');
isa-ok $foo, Foo;
is $foo.stuff, 'ffuts', 'got ffuts from foo.stuff';
is $simple.^methods.first(*.name eq 'foo').factory.blueprint.class, Foo, 'we can get at simple.foo the factory itself';

is $simple.foo-setter.stuff, 14, 'got 14 from simple.foo-setter.stuff';

is $simple.counter, 1, 'first simple.counter is 1';
is $simple.counter, 2, 'first simple.counter is 2';
is $simple.counter, 3, 'first simple.counter is 3';
isa-ok $simple.^methods.first(*.name eq 'counter').factory.blueprint, Bolts::Blueprint::Built, 'we can get at simple.counter the factory itself';

is $simple.acquire(<foo-param stuff>), 'some stuff', 'acquisition works';
is $simple.acquire([ foo => \(stuff => 'other stuff'), 'stuff' ]), 'other stuff', 'acquisition with intermediate args works';
is $foo.acquire(<stuff>), 'ffuts', 'acquisition from foo works';
is $foo.acquire(</ foo-param stuff>), 'some stuff', 'acquisition back through root works';

cmp-ok $foo.bolts-base, '===', $foo, 'foo.bolts-base === foo';
cmp-ok $foo.bolts-parent, '===', $simple, 'foo.bolts-parent === simple';
cmp-ok $foo.bolts-root, '===', $simple, 'foo.bolts-root === simple';
is $foo.root-acquired, 42, 'foo.root-acquired works';
is $simple.foo-param.root-acquired, 42, 'simple.foo-param.root-acquired works';

constant &isn't = &isnt; # sometimes it's the simple things

my $rp = $simple.random;
isn't $simple.random, $rp, 'random changes each time in default scope';
my $rs = $simple.random-singleton;
is $simple.random-singleton, $rs, 'random is the same in singleton scope';

my $rd;
{
    my %*my-rand;
    $rd = $simple.random-dynamic;
    is $simple.random-dynamic, $rd, 'random is the same within dynamic scope';
}
isn't $simple.random-dynamic, $rd, 'random is not the same outside dynamic scope';

done-testing;
