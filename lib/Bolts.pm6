unit module Bolts;

use v6;

role Blueprint {
    method get($c, Capture $args) { ... }
}

class Blueprint::Literal does Blueprint {
    has $.value;
    method get($c, Capture $args) { $!value }
}

class Blueprint::Factory does Blueprint {
    has $.class;
    method get($c, Capture $args) { $!class.new(|$args) }
}

class Blueprint::Given does Blueprint {
    method get($c, Capture $args) { |$args }
}

class Artifact {
    has $.blueprint is required;

    method get($c, Capture $args) {
        $!blueprint.get($c, $args);
    }
}

proto build-artifact(|) { Artifact.new(|{*}); }
multi build-artifact(Whatever) {
    \(
        blueprint => Blueprint::Given.new,
    )
}
multi build-artifact(:$class!) {
    \(
        blueprint => Blueprint::Factory.new(:$class),
    )
}
multi build-artifact(Cool $value) {
    \(
        blueprint => Blueprint::Literal.new(:$value),
    )
}

multi trait_mod:<is> (Method $m, :$artifact) is export {
    my $a = build-artifact(|$artifact);
    $m.wrap(-> $self, |a {
        my $args = callsame;
        $args = a if $args ~~ Whatever;

        Proxy.new(
            FETCH => method () { $a.get($self, $args) },
            STORE => method ($v) { die 'storing to an artifact is not permitted' },
        );
    });
}
