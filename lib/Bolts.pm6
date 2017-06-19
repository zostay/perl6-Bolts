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

role Locator { ... }
class Register { ... }

class Blueprint::Acquired does Blueprint {
    has @.path;
    method get($c, Capture $args) {
        my $locator = $c ~~ Locator ?? $c !! Register.new(:bolts-base($c));
        $locator.acquire(@!path, |$args);
    }
}

class Blueprint::Given does Blueprint {
    has $.key;

    has Int $.at;
    has Bool $.slurp;

    has Bool $.slurp-keys;
    has Set $.excluding-keys;

    method get($c, Capture $args) {
        if $!key.defined {
            $args{ $!key };
        }
        elsif $!slurp-keys {
            |$args.hash.grep({ .key ∉ $!excluding-keys })
        }
        elsif $!at.defined {
            if $!slurp {
                |$args[ $!at .. *-1 ];
            }
            else {
                $args[ $!at ];
            }
        }
        else {
            |$args
        }
    }
}

class Blueprint::Literal does Blueprint {
    has $.value;
    method get($c, Capture $args) { $!value }
}

class Artifact { ... }

role Locator {
    method bolts-base() { self }

    multi method acquire($path, |args) {
        self.acquire(($path,), |args);
    }

    multi method acquire(@path is copy, |args) {
        my $start = 0;
        my @so-far;
        my $c = self.bolts-base;
        if @path && @path[0] eq '/' {
            push @so-far, @path[0];
            $start++;

            if self.^can('bolts-root') {
                $c = self.bolts-root // self;
                return $c.acquire(@path[$start .. *-1], |args)
                    if $c !=== self.bolts-base and $c ~~ Locator;
            }
        }

        return $c unless @path;

        for @path[$start .. *-1].kv -> $i, $part {
            push @so-far, $part;

            my ($key, $args);
            if $part ~~ Pair {
                $key  = $part.key;
                $args = $part.value;
            }
            else {
                $key = $part;
                if $start+$i == @path.end {
                    $args = args;
                }
                else {
                    $args = \();
                }
            }

            given $c {
                when Associative { $c = $c{ $key } }
                when Positional  { $c = $c[ $key ] }
                default {
                    if $c.^can($key) {
                        $c = $c."$key"(|$args);
                    }
                    else {
                        pop @so-far;
                        die "Failed to lookup <@path[]>: No method named $key on container at <@so-far[]>";
                    }
                }

            }

            # Check for Nil, which is an error before the end
            without $c {
                return if $i+$start == @path.end;
                die "Failed to lookup <@path[]>: found Nil at <@so-far[]>";
            }

            # Switch to the container's acquire method, if possible
            return $c.acquire(@path[$start+$i+1 .. *-1], |args)
                if $c ~~ Locator && $i+$start < @path.end;
        }

        $c;
    }
}

role Rooted {
    method bolts-root($base? is copy) {
        $base //= do if self.^can('bolts-base') {
            self.bolts-base;
        }
        else {
            self;
        }

        loop {
            return $base.bolts-root
                if $base !=== self && $base.^can('bolts-root');

            last unless $base.^can('bolts-parent');

            my $parent = $base.bolts-parent;
            last without $parent;

            $base = $parent;
        }

        $base;
    }
}

role Container is Locator is Rooted {
#     # TODO Figure out how to make this work...
#     trusts Artifact;
#     has $.bolts-parent;
    has $.bolts-parent is rw;
}

class Register is Locator {
    has $.bolts-base;
    method bolts-base { $!bolts-base }
}

role SingletonScope {
    has %.bolts-singletons;
}

role Scope {
    method put($c, $artifact, $object) { ... }
    method get($c, $artifact) { ... }
}

class Scope::Prototype does Scope {
    method put($c, $artifact, $object) { }
    method get($c, $artifact) { }
}

class Scope::Singleton does Scope does Rooted {
    method assure-singleton-scope($c) {
        my $root = self.bolts-root($c);
        $root does SingletonScope unless $root ~~ SingletonScope;
        $root;
    }

    method put($c, $artifact, $object) {
        my $scope = self.assure-singleton-scope($c);
        $scope.bolts-singletons{ $artifact.WHICH } = $object;
    }

    method get($c, $artifact) {
        my $scope = self.assure-singleton-scope($c);
        $scope.bolts-singletons{ $artifact.WHICH };
    }
}

role Injector { }

role Parameter is Injector {
    method get($c, Capture $args) { ... }

    method append-capture($value, @list, %hash) { ... }
}

class Parameter::NamedSlip does Parameter {
    has $.blueprint;

    method get($c, Capture $args) {
        |$!blueprint.get($c, $args);
    }

    method append-capture($value, @list, %hash) {
        push %hash, |$value;
    }
}

class Parameter::Slip does Parameter {
    has $.blueprint;

    method get($c, Capture $args) {
        |$!blueprint.get($c, $args);
    }

    method append-capture($value, @list, %hash) {
        push @list ,|$value;
    }
}

class Parameter::Named does Parameter {
    has $.key;
    has $.blueprint;

    method get($c, Capture $args) {
        $!key => $!blueprint.get($c, $args);
    }

    method append-capture($value, @list, %hash) {
        push %hash, $value;
    }
}

class Parameter::Positional does Parameter {
    has $.blueprint;

    method get($c, Capture $args) {
        $!blueprint.get($c, $args);
    }

    method append-capture($value, @list, %hash) {
        push @list, $value;
    }
}

class Artifact {
    has Blueprint $.blueprint is required;
    has Scope $.scope is required;
    has Injector @.injectors;

    method build-capture($c, $args) {
        my (@list, %hash);
        for @!injectors.grep(Parameter) {
            my $value = .get($c, $args);
            .append-capture($value, @list, %hash);
        }

        Capture.new(:@list, :%hash);
    }

    method get($c, Capture $args) {
        my $obj = $!scope.get($c, self);
        return $obj with $obj;

        my $inject-args = self.build-capture($c, $args);

        $obj = $!blueprint.get($c, $inject-args);

        $obj.bolts-parent //= $c if $obj ~~ Container;

        $!scope.put($c, self, $obj);

        $obj;
    }
}

multi build-parameters(Capture:D $cons) {
    gather {
        for $cons.list -> $blueprint is copy {
            if $blueprint !~~ Blueprint {
                $blueprint = Blueprint::Literal.new(value => $blueprint);
            }

            take Parameter::Positional.new(
                blueprint => $blueprint,
            );
        }

        for $cons.hash.kv -> $key, $blueprint is copy {
            if $blueprint !~~ Blueprint {
                $blueprint = Blueprint::Literal.new(value => $blueprint);
            }

            take Parameter::Named.new(
                key       => $key,
                blueprint => $blueprint,
            );
        }
    }
}
multi build-parameters(Any:U) {
    (
        Parameter::Slip.new(
            blueprint => Blueprint::Given.new(:slurp),
        ),
        Parameter::NamedSlip.new(
            blueprint => Blueprint::Given.new(:slurp-keys),
        ),
    )
}

proto build-artifact(|) { Artifact.new(|{*}); }
multi build-artifact(Whatever, Capture :$parameters, Scope :$scope = Scope::Prototype) {
    my @injectors = build-parameters($parameters);
    \(
        blueprint => Blueprint::Given.new,
        :@injectors,
        :$scope,
    )
}
multi build-artifact(:$class!, Capture :$parameters, Scope :$scope = Scope::Prototype) {
    my @injectors = build-parameters($parameters);
    \(
        blueprint => Blueprint::Factory.new(:$class),
        :@injectors,
        :$scope,
    )
}
multi build-artifact(&builder, Capture :$parameters, Scope :$scope = Scope::Prototype) {
    my @injectors = build-parameters($parameters);
    \(
        blueprint => Blueprint::Built.new(:&builder),
        :@injectors,
        :$scope,
    )
}
multi build-artifact(:@path, Capture :$parameters, Scope :$scope = Scope::Prototype) {
    my @injectors = build-parameters($parameters);
    \(
        blueprint => Blueprint::Acquired.new(:@path),
        :@injectors,
        :$scope,
    )
}
multi build-artifact(Cool $value) {
    \(
        blueprint => Blueprint::Literal.new(:$value),
        scope     => Scope::Prototype,
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
    # Since $artifact gets treated like a list, we have to fake it in like
    # it's a capture:
    my %c = $artifact.list.classify({ $_ ~~ Pair ?? 'hash' !! 'list' });
    my %hash = %c<hash> // ();
    my @list = %c<list>:exists ?? |%c<list> !! ();
    my $artifact-capture = Capture.new(:@list, :%hash);

    my $a = build-artifact(|$artifact-capture);
    my $orig = $m.clone;
    $m does Trait::Artifact[$a, $orig];
}
