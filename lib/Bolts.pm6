unit module Bolts;

use v6;

role Blueprint {
    method get($c, Capture $args) { ... }
}

class Blueprint::Built does Blueprint {
    has &.builder;
    method get($c, Capture $args) { &!builder.(|$args) }
}

class Blueprint::Factory does Blueprint {
    has $.class;
    method get($c, Capture $args) { $!class.new(|$args) }
}

class Blueprint::Given does Blueprint {
    method get($c, Capture $args) { |$args }
}

class Blueprint::Literal does Blueprint {
    has $.value;
    method get($c, Capture $args) { $!value }
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
multi build-artifact(&builder) {
    \(
        blueprint => Blueprint::Built.new(:&builder),
    )
}
multi build-artifact(Cool $value) {
    \(
        blueprint => Blueprint::Literal.new(:$value),
    )
}

role Trait::Artifact[Artifact $artifact, Method $orig] {
    method artifact { $artifact }

    method CALL-ME($self, |args) {
        my $args = $self.$orig(|args);
        $args = args if $args ~~ Whatever;

        Proxy.new(
            FETCH => method () { $artifact.get($self, $args) },
            STORE => method ($v) { die 'storing to an artifact is not permitted' },
        );
    }
}

multi trait_mod:<is> (Method $m, :$artifact) is export {
    my $a = build-artifact(|$artifact);
    my $orig = $m.clone;
    $m does Trait::Artifact[$a, $orig];
}
