unit module Bolts;

use v6;

=begin pod

=NAME Bolts - an IoC framework for the Modern Perl

=begin SYNOPSIS

In F<myapp.yaml>:

    ---
    factories:
        logger:
            class: MyApp::Logger
            parameters:
                hash:
                    config: { path: [ log-config ] }
            scope: Singleton

        log-config:
            class: Hash
            mutators:
                - key: level
                  to: INFO

        start-request:
            class: MyApp::Request
            mutators:
                - set: logger
                  to: { path: [ logger ] }
                - call: run

and then in your app class, something like this:

    use Bolts;

    class MyApp is Container {
        has $.config-file = "myapp.yaml".IO;
        has $.config = Bolts::IO.load($!config-file);

        method logger { self.acquire(<config loggger>) }
        method start-request { self.acquire(<config start-request>) }
    }

    my $app = MyApp.new;
    $app.start-request;

=end SYNOPSIS

=head1 DESCRIPTION

B<Caution:> Experimental. This API is still being tested and may change.

Bolts defines an Inversion of Control (IOC) framework. Inversion of Control is an object-oriented software pattern. This pattern is designed to help you build classes that are independent of each other and assembled by an outside controller, called the dependency injector. (Because of this IOC frameworks are often referred to as Dependency Injection (DI) frameworks.)

When an IOC framework is present, classes are free to focus on executing their task without worrying about locating the external objects with which they need to exchange messages. This allows a large portion of your software be decoupled from other parts, which can make some aspects of reusability, development, and deployment simpler.

In simple terms, you can think of this as a way of programming your software from a configuration file. It provides a sometimes convenient notation for building objects, linking them together, and caching them.

This framework aims to provide a Perlish IOC framework, integrated into existing language features and provide some enhancements rather than forcing you down a development path that requires a full commitment to the framework.

Lets start by taking a look at a simple example and working out what it does. Afterward, we will introduce the major concepts of the Bolts IOC framework and then see how they all work together. Finally, we will document the details of each component provided by this framework.

=head2 Bolts Example

    use Bolts;

    class Point {
        has $.x;
        has $.y;
    }

    class Example does Bolts::Container {
        method origin(|) is factory(
            class      => Point,
            parameters => \(:x(0), :y(0)),
            scope      => Bolts::Scope::Singleton,
        ) { * }

        method point(|) is factory(
            path       => <origin>,
            clone      => True,
            mutators   => [
                { set => 'x', to => *.[0] },
                { set => 'y', to => *.[1] },
            ],
        ) { * }
    }

    my $ex = Example.new;
    my $origin = $ex.origin;
    my $point = $ex.point(3, 4);

    my $another-point = $ex.acquire(<point>, 7, 11);
    my $zero = $ex.acquire(<origin x>);

This is not a very interesting example, but it lets us examine the basics. Here we have defined a class named C<Point> and another named C<Example>.

C<Example> is specifically marked as a container by implementing the L<Bolts::Container> class. It then contains two methods defined using the C<is factory> trait. The example, is essentially the same as this without using the factory traits:

    class Example does Bolts::Container {
        method origin() {
            Point.new(:x(0), :y(0));
        }
        method point($x, $y) {
            my $p = self.origin;
            $p.x = $x;
            $p.y = $y;
            $p
        }
    }

Clearly, this latter version would be more straight-forward, but we could also migrate the C<Example> class to a configuration file, which might be saved to disk or located in a database or loaded from a service configuration tool:

    ---
    factories:
        origin:
            class: Point
            parameters:
                hash:
                    x: 0
                    y: 0
        point:
            path: [ origin ]
            mutators:
                - set: x
                  to: { at: 0 }
                - set: y
                  to: { at: 1 }

This can then be loaded with L<Bolts::IO> like so:

    my $example = Bolts::IO.load("config.yaml".IO.slurp);
    my $origin = $example.acquire(<origin>);
    my $point  = $example.acquire(<point>, 3, 5);

Now your glue code can become configuration that can be modified as needed, possibly even letting you tweak your application in production.

Aside from being configurable, the Bolts framework emphasizes designing objects that really don't know much about their environment. Each object configured by Bolts just needs to focus on its particular purpose.

Anyway, enough arguing for the idea and let's consider what's going on.

Each factory is represented by a L<Bolts::Factory> object. This object encapsulates a list of injectors, a blueprint, and a scope. The injectors determine what information is fed to the blueprint for construction and are able to modify the constructed object after construction. The blueprint knows how to construct the object. The scope knows how to cache the object.

In the C<origin> factory, we see that we are using what is called a method call blueprint. The blueprint calls a named method (or "new" by default) on a named class, so it will call C<Point.new> in the case of C<origin>. But what does it pass to C<Point.new>?

The C<parameters> setting to the C<origin> factory determines what is passed to the blueprint during construction. In this case, we see the L<Capture>, C<\(:x(0), :y(0))>. This gets processed into two parameter injectors that set the named argument C<x> to C<0> and the named argument C<y> also to C<0>.

Once constructed, the object is cached according to the scope. With C<origin>, we use the singleton scope, which means that exactly one object will be constructed using the blueprint for as long as the container object exists. Any further calls to C<origin> will return the first object constructed.

The C<point> factory uses a different blueprint. This one uses acquisition to acquire the value it uses from C<origin>. This is probably not the way you would choose to do this normally, but we do so here to demonstrate the feature. As we don't want to modify the singleton, we also tell blueprint, to clone whatever object it gets us, this way we have a fresh copy to work with.

From there, we use two mutator injectors to set the C<x> and C<y> values to the first and second arguments passed to the method (or passed to C<acquire>).

This factory does not set an explicit scope and relies on the default scope, which is L<Bolts::Scope::Prototype>. Prototype scope never caches the object, so a new object will be constructed on every call to C<point>.

The other piece we should explain is the C<acquire> method. This is the preferred entry point to getting values out of a container hierarchy. You don't have to use it, but as containers may be different kinds of objects whose API varies slightly (think L<Hash> versus L<Bolts::Container>), using acquire will allow you to change how the containers are constructed without having to change the code that depends on the values in them.

Basically, the first argument is a path, which is just a list of keys to look up in each container in the heirarchy. If we use C«<origin x>», for example, this is basically the same as calling C<$example.origin.x> (but smart enough to deal with whatever underlying API each container uses).

The remaining arguments are passed to the final method in the path to be used by the factory for construction.

Now that we have a basic notion of how this works, lets dig into the roles of each part of the system.

=head2 Factories

The primary component of the Bolts framework is the factory. A B<factory> is a method that encapsulates all aspects of configuring an individual value in the software. This defines a factory that knows to build a particular object, attach that object to other objects, and establish the lifecycle of the object.

Bolts provides the L<Bolts::Factory> class to capture the implementation of a factory. These objects are usually constructed and attached to a container using the C<is factory()> trait.

However, any method that returns something based on it's arguments may be treated as a factory by the Bolts framework.

=head2 Containers

A B<container> is an object that provides factory methods for constructing and retrieving objects. Containers may be any typical class, Maps, Lists, or special container objects provided by the framework, such as L<Bolts::Container> and L<Bolts::Register>.

A B<hierarchy of containers> is the object tree formed by a container pointing to other containers. A container may use a factory to construct or manage child containers.

=head2 Locators

A B<locator> is an object able to find things in a hierarchy of containers. The process of finding a factory in a hierarchy is called B<acquisition>. Once the desired factory is acquired via the locator, it will be resolved into an object. B<Resolution> is the process of turning the factory configuration into an actual object.

In Bolts, the C<acquire> method of B<Bolts::Locator> performs acquisition. Bolts uses a Proxy object to automatically resolve the actual object upon fetch, so resolution is seamless.

=head2 Blueprints

During resolution, a B<blueprint> defines how the object is retrieved or constructed. The Bolts framework provides L<Bolts::Blueprint> role for defining the contract blueprints adhere to and several built-in blueprint types.

=head2 Injectors

For blueprints to work, they need input. B<Injectors> find data to input to blueprints and injects them into the blueprints during resolution. Bolts provides two kinds of injectors: parameter injectors and mutator injectors.

B<Parameters> feed data into the blueprint itself during resolution.

B<Mutators> modify the object created by the blueprint immediately after it is produced.

=head2 Scope

The B<scope> determines how long an object will be cached in the container to be reused. The default scope does not cache the object, so it will be rebuilt from the blueprint every time. However, other scopes allow the value to be cached longer.

=head1 ROLES & CLASSES

=head2 role Bolts::Blueprint

This role defines the contract that all blueprints must follow.

=head3 method get

    method get($c, Capture $args)

Anything using a blueprint to do work will call this method to do that work.

The first argument, C<$c>, is the container in which the object is being created and the second argument is the C<Capture> containing the arguments the blueprint may use during construction, if applicable.

B<Important:> It is important to understand what C<$args> is when declaring your blueprints.

=item If the blueprint is used directly as part of a factory, these will be the arguments that have been constructed and injected by the configured L<Bolts::Parameter> injectors.

=item However, if the blueprint is being used in conjuction with an injector, this will be the actual arguments passed to the factory method by the caller.

=head3 method build

    method build($c, Capture $args)

This is the method any implementor of a blueprint must implement. This should return the constructed argument.

The first argument, C<$c>, is the container in which the object is being created and the second argument is the C<Capture> containing the arguments the blueprint may use during construction, if applicable.

=head2 class Bolts::Blueprint::Built

This blueprint calls the given L<Callable> and returns whatever it returns as the built object.

=head3 has &.builder

    has &.builder is required

This is the subroutine to run to get the object.It will be passed the same arguments given to the C<get> method of L<role Bolts::Blueprint>. There are a couple special cases:

=item C<WhateverCode> If given a C<WhateverCode>, the arguments will be passed as a C<Capture>. This way C<*.[$nth]> will grab the C<$nth> object or C<*.{$named}> will grab the argument named C<$named>.

=item C<Method> If given a C<Method>, C<self> will be set to the container on which this factory is being called. Any other code type will not have a reference to the container object.

=head2 class Bolts::Blueprint::MethodCall

This blueprint calls a method on a named class or object.

=head3 has $.class

    has $.class is required

This names the class or object on which to call a method. This is normally given as a type name, but really could be anything on which a method may be called.

=head3 has $.method

    has $.method = "new"

This names the method to be called. The method will be passed the arguments given to the blueprint during the call to C<get>.

=head2 class Bolts::Blueprint::Acquired

This blueprint will lookup a value within the current container.

=head3 has @.path

This is the path to use during acquisition. The basis for acquisition will be the container the factory method belongs to. If the first path in the lookup is "/", then the container's root will be used as the basis instead.

=head2 class Bolts::Blueprint::Given

This blueprint will return the arguments provided during injection.

If no attributes on the given object are set, the L<Capture> given as the second argument to the C<get> method is returned as-is by this blueprint. Attributes set on this blueprint will select individual parts of the arguments to return instead.

When setting attributes on this object, only one of C<$.key>, C<$.at>,adn C<$.slurp-keys> should be set. If more than one is defined, the behavior is not defined and may result in an exception.

=head3 has $.key

    has $.key

If the C<$.key> attribute is set, then the named argument named C<$.key> will be returned by the blueprint.

=head3 has $.at

    has Int $.at

If the $.at attribute is set, then the positional argument at the index C<$.at> will be returned by the blueprint.

=head3 has $.slurp

    has Bool $.slurp

This attribute only means something when C<$.at> is set. When combined with C<$.at>, all positional arguments pass from C<$.at> to the end of the positional arguments will be slurped up and returned as a list.

=head3 has $.slurp-keys

    has Bool $.slurp-keys

This attribute causes all named arguments to be slurped and returned as a list of pairs. Any key named in the C<$.excluding-keys> set will be excluded from the returned list.

=head3 has $.excluding-keys

    has Set $.excluding-keys

This attribute selects the named arguments to avoid slurping when using C<$.slurp-keys>.

=head2 class Bolts::Blueprint::Literal

This blueprint returns whatever value it is given.

=head3 has $.value

    has $.value

This is the literal value to return from this blueprint.

=head1 role Bolts::Locator

This class provides methods for performing acquisition.

=head2 method bolts-base

    method bolts-base()

This method should be overridden by any implementation that does not wish to use C<self> as the container to acquired from.

=head2 method acquire

    multi method acquire($path, |args)
    multi method acquire(@path is copy, |args)

The acquire method, when given a path and (optional) arguments, will locate the factory to resolve and resolve it with the arguments given.

Each element of the path is a value that describes the name of the factory (or method) to locate and resolve next in the container hierarchy. If the container being located within is L<Associative>, the current path element is used as the key to look up on the map. If the container being located within is L<Positional>, the path element is used as the index to lookup in the list. Otherwise, the current path element will be treated as the name of a method to call on the container, if the method provides method with that name. Beyond that is an error.

If, while descending the hierarchy, the container provides it's own C<acquire> method, that method will be called with the remaining path, allowing this service to be delegated to sub-containers.

If the first path element is a slash ("/") and the current container provides a C<bolts-root> method, the object return will be used as the starting point for acquisition instead of C<bolts-base>. If it lacks a C<bolts-root>, but has a C<bolts-parent>, the parent container returned by it will be searched for C<bolts-root> and then C<bolts-parent> in the same way until either C<bolts-parent> returns an undefined value or no C<bolts-parent> method is found.

Each path element may be given as a L<Pair>. If given as a pair, the key will be used as the lookup value and the value should be used as the arguments to pass to the factory, this allows for argument passing to locate on more complex container configurations in the middle of the hierarchy without requiring multiple calls to acquire.

=head2 role Bolts::Rooted

This is a helper role that provides a C<bolts-root> method to a container.

=head3 method bolts-root

    method bolts-root($base?)

The bolts-root method will attempt to find the root container of either the passed C<$base> value or the return value of C<bolts-base> or (failing both of these) of C<self>.

From here it will see if that object has a C<bolts-root> (aware of itself so it doesn't recurse) and use that value. If not avialable, it will look for a value from a C<bolts-parent> method and then repeat the process of locating a root from there. If that fails, this method will return the cotainer used as the original basis itself as the root (i.e., C<$base> or C<bolts-base> or C<self>).

=head2 role Bolts::Container

This role should be implemented by any object wishing to behave as a container. It also is a L<Bolts::Rooted> and L<Bolts::Locator>.

=head3 has $.bolts-parent

    has $.bolts-parent is rw

This is the parent object of the container. It may be undefined to use this container as the root container.

=head2 class Bolts::Register

This class provides a wrapper to provide a locator to another object that will act as the container. It is a L<Bolts::Locator>.

=head3 has $.bolts-base

    has $.bolts-base is required

This may be set to any Perl object that can be used to locate on.

=head2 role Bolts::SingletonScope

This is a role that will be applied to the object at the root of the container hierarchy the first time a L<Bolts::Scope::Singleton> scoped object is resolved.

=head3 has %.bolts-singletons

This stores references to all singletons cached in the container hierarchy.

=head2 role Bolts::Scope

This is the role that all scopes must implement.

=head3 method put

    method put($c, Bolts::Factory:D $factory, $object)

This method is called on a scope whenever a factory has generated one during resolution. The scope should cache the object as appropriate. The first argument is the container in which the object is associated, the second is the L<Bolts::Factory> object used to generate it, and the third is the object to cache.

=head3 method get

    method get($c, Bolts::Factory:D $factory)

This method is called on a scope whenever it is resolving an object. This method should check to see if an object for the given factory is cached and return it. If not, it should return an undefined value.

The first argument is the container the factory is associated with and the second is the L<Bolts::Factory> object that was or will be used to generate the object.

=head2 class Bolts::Scope::Prototype

This implements a L<Bolts::Scope> to perform no cachine whatsoever and is the default scope.

This scope is typically used as the type itself without calling the constructor.

=head2 class Bolts::Scope::Singleton

This implements a L<Bolts::Scope> to provide singleton objects, these are objects that exist as long as the root container in the container hierarchy exists.

This scope is typically used as the type itself without calling the constructor.

=head2 class Bolts::Scope::Dynamic

This implements a L<Bolts::Scope> that performs caching based upon the current dynamic scope.

    my $c = class :: does Bolts::Container {
        method counter(|) is factory({ $++ },
            scope => Bolts::Scope::Dynamic.new("%*BOLTS-DYNAMIC"),
        ) { * }
    }.new;

    say $c.counter; #> 1
    say $c.counter; #> 2

    {
        my %*BOLTS-DYNAMIC;
        say $c.counter; #> 3
        say $c.counter; #> 3
    }

    {
        my %*BOLTS-DYNAMIC;
        say $c.counter; #> 4
        say $c.counter; #> 4
    }

As you can see here, the C<counter> factory returns an incrementing number each time the builder is called. With the dynamic scope, the value will be cached in the variable named during construction (defaulting to C<%*BOLTS-DYNAMIC>), if it exists.

So the first two calls to C<counter> are not cached at all. The third call causes "3" to be cached and returned on the fourth, but the cache goes away when the dynamic variable goes out of scope. The same happens again for the fifth and sixth call and "4".

With careful use of dynamic scoping, many kinds of interesting scopes can be crafted without needing any other special scope objects.

=head1 GOALS

The goal of this project is to provide the basis for building an entire common objects library, which will provide tools for building applications, with these aspects being emphasize:

=head2 Separation of Concerns

The primary goal is to build applications out of small components that are laser-focused on doing one thing. These components should not depend on anything outside of themselves, inasmuch as possible given their task.

=head2 Layers of Opinionation

Each of the components in the system should allow a developer coming in to do the thing she wants without having to do it the way I would do it. The Perl community refers to this as TIMTOWTDI, but when a framework is implemented on top of Perl, it is very difficult to provide complete flexibility (a real-life scaffold that is completely flexible will certainly collapse).

I admit that this is the case, so the compromise is that the framework is built with "layers of opinionation". The developer applying the framework adopts the layers with opinions matching her own needs and preferences. The framework, then, provides places where the developer can insert a different implementation for layers when opinions differ. This requires that each piece of the framework be robust and not too dependent on the others (see Separation of Concerns).

=head2 Α to Ω Flexibility

The final aspect of this project is an emphasis on making sure that the application may be modified even after it has been "thrown of the wall." Often the deployment team or developer operations team needs tooling to be able to modify an application. However, if this requires issuing a change request and going through the whole development process, it can take a long time to fix and address problems.

To address this, I aim to provide tools to allow as much of an application as practicable can be adjusted through configuration. This is done by making it easy to adjust the layout and construction and lifecycle of objects and values. If done will, a deployed application can be made to react to the needs of deployment and operations without requiring any code changes even to the point of being reconfigured on the fly to address changing needs in the environment.

=head2 Unified through IOC

To achieve these ends, an Inversion of Control framework is an absolutely necessary foundation layer. With this in place, it becomes simpler to build each piece of the framework in its own niche and then glue all the pieces together to form a whole, but each piece can then be yanked out and replaced with a different implementation as needed or preferred.

=head1 HISTORY

I built an IOC framework for Perl 5 by the same name and this borrows many of the same concepts. However, there were some fundamental aspects of that framework I never liked, which also kept me from making effective use of it in my own work. This is an attempt to rebuild a similar system from the ground up, in Perl 6, and hopefully learn from the lessons I learned the first time around.

Many concepts are borrowed from Perl 5's C<Bread::Board> project and from the Spring Framework for Java, but I've gone in some different directions on my own in the process.

=end pod

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
    has $.bolts-base is required;
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
