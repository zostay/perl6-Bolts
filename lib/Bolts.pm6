unit module Bolts;

use v6;

role Blueprint {
    has $.clone;

    method build($c, Capture $args) { ... }

    method get($c, Capture $args) {
        my $o = self.build($c, $args);
        $o .= clone if $!clone;
        $o;
    }
}

class Blueprint::Built does Blueprint {
    has &.builder is required;

    submethod TWEAK {
        if &!builder ~~ WhateverCode {
            my &code = &!builder;
            &!builder = -> $c, |c { code(c) };
        }
        elsif &!builder !~~ Method {
            my &code = &!builder;
            &!builder = -> $c, |c { code(|c) };
        }
    }

    method build($c, Capture $args) {
        &!builder.($c, |$args)
    }
}

class Blueprint::MethodCall does Blueprint {
    has $.class is required;
    has $.method = "new";
    method build($c, Capture $args) { $!class."$!method"(|$args) }
}

role Locator { ... }
class Register { ... }

class Blueprint::Acquired does Blueprint {
    has @.path;
    method build($c, Capture $args) {
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

    method build($c, Capture $args) {
        if $!key.defined {
            $args{ $!key };
        }
        elsif $!slurp-keys {
            $args.hash.grep({ .key ∉ $!excluding-keys })
        }
        elsif $!at.defined {
            if $!slurp {
                $args[ $!at .. *-1 ];
            }
            else {
                $args[ $!at ];
            }
        }
        else {
            $args
        }
    }
}

class Blueprint::Literal does Blueprint {
    has $.value;
    method build($c, Capture $args) { $!value }
}

class Factory { ... }

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
#     trusts Factory;
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
    method put($c, $factory, $object) { ... }
    method get($c, $factory) { ... }
}

class Scope::Prototype does Scope {
    method put($c, $factory, $object) { }
    method get($c, $factory) { }
}

class Scope::Singleton does Scope does Rooted {
    method assure-singleton-scope($c) {
        my $root = self.bolts-root($c);
        $root does SingletonScope unless $root ~~ SingletonScope;
        $root;
    }

    method put($c, $factory, $object) {
        my $scope = self.assure-singleton-scope($c);
        $scope.bolts-singletons{ $factory.WHICH } = $object;
    }

    method get($c, $factory) {
        my $scope = self.assure-singleton-scope($c);
        $scope.bolts-singletons{ $factory.WHICH };
    }
}

class Scope::Dynamic does Scope does Rooted {
    has $.dynamic = "%*BOLTS-DYNAMIC";

    multi method new($dynamic) { self.new(:$dynamic) }

    method put($c, $factory, $object) {
        DYNAMIC::{ $!dynamic }{ $factory.WHICH } = $object
            if DYNAMIC::{ $!dynamic }.defined;
    }

    method get($c, $factory) {
        DYNAMIC::{ $!dynamic }{ $factory.WHICH }
            if DYNAMIC::{ $!dynamic }.defined;
    }
}

role Injector {
    has $.blueprint;

    method get-value($c, Capture $args) {
        $!blueprint.get($c, $args);
    }
}

role Parameter is Injector {
    method get($c, Capture $args) { ... }

    method append-capture($value, @list, %hash) { ... }
}

class Parameter::NamedSlip does Parameter {
    method get($c, Capture $args) {
        |self.get-value($c, $args);
    }

    method append-capture($value, @list, %hash) {
        push %hash, |$value;
    }
}

class Parameter::Slip does Parameter {
    method get($c, Capture $args) {
        |self.get-value($c, $args);
    }

    method append-capture($value, @list, %hash) {
        push @list ,|$value;
    }
}

class Parameter::Named does Parameter {
    has $.key;

    method get($c, Capture $args) {
        $!key => self.get-value($c, $args);
    }

    method append-capture($value, @list, %hash) {
        push %hash, $value;
    }
}

class Parameter::Positional does Parameter {
    method get($c, Capture $args) {
        self.get-value($c, $args);
    }

    method append-capture($value, @list, %hash) {
        push @list, $value;
    }
}

role Mutator is Injector {
    method mutate($c, $object, Capture $args) { ... }
}

class Mutator::Setter does Mutator {
    has $.attribute;

    method mutate($c, $object, Capture $args) {
        $object."$!attribute"() = self.get-value($c, $args);
    }
}

class Mutator::Call does Mutator {
    has $.method;

    method mutate($c, $object, Capture $args) {
        $object."$!method"(|self.get-value($c, $args));
    }
}

class Mutator::Store does Mutator {
    has $.key;
    has $.at;

    method mutate($c, $object, Capture $args) {
        given self.get-value($c, $args) -> $value {
            if $!key.defined {
                if $!key.elems > 1 {
                    $object{ @($!key) } = |$value;
                }
                else {
                    $object{ $!key } = $value;
                }
            }
            elsif $!at.defined {
                if $!at.elems > 1 {
                    $object[ @($!at) ] = |$value;
                }
                else {
                    $object[ $!at ] = $value;
                }
            }
        }
    }
}

class Factory {
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

    method mutate($c, $object, $args) {
        for @!injectors.grep(Mutator) {
            .mutate($c, $object, $args);
        }
    }

    method get($c, Capture $args) {
        my $obj = $!scope.get($c, self);
        return $obj with $obj;

        my $inject-args = self.build-capture($c, $args);

        $obj = $!blueprint.get($c, $inject-args);

        self.mutate($c, $obj, $args);

        $obj.bolts-parent //= $c if $obj ~~ Container;

        $!scope.put($c, self, $obj);

        $obj;
    }
}

###########################################################
###
### TODO This section of subs should be converted into the
### meta container used to build Bolts components.
###
###

multi build-blueprint(Blueprint:D $blueprint) {
    $blueprint;
}
multi build-blueprint(Whatever, :$clone) {
    Blueprint::Given.new(:$clone);
}
multi build-blueprint(:$key!, :$clone) {
    Blueprint::Given.new(:$key, :$clone);
}
multi build-blueprint(:$at!, :$slurp, :$clone) {
    Blueprint::Given.new(:$at, :$slurp, :$clone);
}
multi build-blueprint(:$slurp-keys!, :@excluding-keys, :$clone) {
    Blueprint::Given.new(:$slurp-keys, set(@excluding-keys), :$clone);
}
multi build-blueprint(:$class!, :$method = "new", :$clone) {
    Blueprint::MethodCall.new(:$class, :$method, :$clone);
}
multi build-blueprint(&builder, :$clone) {
    Blueprint::Built.new(:&builder, :$clone);
}
multi build-blueprint(:@path!, :$clone) {
    Blueprint::Acquired.new(:@path, :$clone);
}
multi build-blueprint(Str :$path!, :$clone) {
    Blueprint::Acquired.new(:path(($path,)), :$clone);
}
multi build-blueprint(Cool $value, :$clone) {
    Blueprint::Literal.new(:$value, :$clone);
}

multi build-parameters(Capture:D $cons) {
    gather {
        for $cons.list -> $blueprint is copy {
            $blueprint = build-blueprint(|$blueprint);
            take Parameter::Positional.new(
                blueprint => $blueprint,
            );
        }

        for $cons.hash.kv -> $key, $blueprint is copy {
            $blueprint = build-blueprint(|$blueprint);
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
            blueprint => Blueprint::Built.new(
                builder => *.list,
            ),
        ),
        Parameter::NamedSlip.new(
            blueprint => Blueprint::Built.new(
                builder => *.hash,
            ),
        ),
    )
}

multi build-mutators(@mutators) {
    gather for @mutators -> $mutator {
        if $mutator ~~ Mutator {
            take $mutator;
        }
        elsif $mutator ~~ Hash {
            my $to = $mutator<to>;
            $to = build-blueprint(|$to);

            if $mutator<set>.defined {
                take Mutator::Setter.new(
                    attribute => $mutator<set>,
                    blueprint => $to,
                );
            }
            elsif $mutator<at>.defined {
                take Mutator::Store.new(
                    at        => $mutator<at>,
                    blueprint => $to,
                );
            }
            elsif $mutator<key>.defined {
                take Mutator::Store.new(
                    key       => $mutator<key>,
                    blueprint => $to,
                );
            }
            elsif $mutator<call>.defined {
                take Mutator::Store.new(
                    method    => $mutator<call>,
                    blueprint => $to,
                );
            }
        }
    }
}
multi build-mutators(Any:U) { () }

sub build-injectors($parameters, $mutators) {
    flat(
        build-parameters($parameters),
        build-mutators($mutators),
    )
}

proto build-factory(|) { Factory.new(|{*}); }
multi build-factory(Whatever, Capture :$parameters, :$mutators, Scope :$scope = Scope::Prototype, :$clone) {
    my @injectors = build-injectors($parameters, $mutators);
    my $blueprint = build-blueprint(*, :$clone);
    \(:$blueprint, :@injectors, :$scope)
}
multi build-factory(:$class!, :$method = "new", Capture :$parameters, :$mutators, Scope :$scope = Scope::Prototype, :$clone) {
    my @injectors = build-injectors($parameters, $mutators);
    my $blueprint = build-blueprint(:$class, :$method, :$clone);
    \(:$blueprint, :@injectors, :$scope)
}
multi build-factory(&builder, Capture :$parameters, :$mutators, Scope :$scope = Scope::Prototype, :$clone) {
    my @injectors = build-injectors($parameters, $mutators);
    my $blueprint = build-blueprint(&builder, :$clone);
    \(:$blueprint, :@injectors, :$scope)
}
multi build-factory(:@path!, Capture :$parameters, :$mutators, Scope :$scope = Scope::Prototype, :$clone) {
    my @injectors = build-injectors($parameters, $mutators);
    my $blueprint = build-blueprint(:@path, :$clone);
    \(:$blueprint, :@injectors, :$scope)
}
multi build-factory(Str :$path!, Capture :$parameters, :$mutators, Scope :$scope = Scope::Prototype, :$clone) {
    my @injectors = build-injectors($parameters, $mutators);
    my $blueprint = build-blueprint(:path(($path,)), :$clone);
    \(:$blueprint, :@injectors, :$scope)
}
multi build-factory(Cool $value, :$clone) {
    my $blueprint = build-blueprint($value, :$clone);
    my $scope     = Scope::Prototype;
    \(:$blueprint, :$scope)
}

### END OF META
###########################################################

role Trait::Factory[Factory $factory, Method $orig] {
    method factory { $factory }

    method CALL-ME($self, |args) {
        my $args = $self.$orig(|args);
        $args = args if $args ~~ Whatever;

        Proxy.new(
            FETCH => method () { $factory.get($self, $args) },
            STORE => method ($v) { die 'storing to an factory is not permitted' },
        );
    }
}

multi trait_mod:<is> (Method $m, :$factory) is export {
    # Since $factory gets treated like a list, we have to fake it in like
    # it's a capture:
    my %c = $factory.list.classify({ $_ ~~ Pair ?? 'hash' !! 'list' });
    my %hash = %c<hash> // ();
    my @list = %c<list>:exists ?? |%c<list> !! ();
    my $factory-capture = Capture.new(:@list, :%hash);

    my $a = build-factory(|$factory-capture);
    my $orig = $m.clone;
    $m does Trait::Factory[$a, $orig];
}
