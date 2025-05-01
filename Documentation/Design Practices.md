# Design Practices

## XPC Services

XPC services in Sparkle are all optional, so the code involved in the services needs to be usable directly from the framework as well. For this to work well, if the class used in the XPC service takes a delegate, it must not be weakly referenced, so the retain cycle will have to be broken explicitly (via an explicit added invalidate method). dealloc also must not be implemented (do cleanup in custom invalidate method). As one may tell, two of the services are simply proxies (InstallerConnection, InstallerStatus) -- we now recommend most developers to set up a temporary exception with their bundle ID rather than use these two services.

The protocols used in XPC services must also not adopt other protocols (i.e, one protocol inheriting from another protocol). This is because the XPC protocol decoder on older supported systems doesn't properly handle this case, and won't be able to find that methods exist on a class.

## Singletons

Singletons and other global mutable variables have been either removed entirely or completely avoided with an exception to backwards compatibility. They have no place in a well architectured framework.

`SPUUpdater` doesn't maintain singleton instances and can now be properly deconstructed. Note because a caller is not expected to explicitly invalidate an updater, this means that the updater needs to avoid getting into a retain cycle. Intermediate clasess were created for the update cycle and schedule timer to avoid just this.

One may argue that we shouldn't allow multiple live updaters running at the same bundle simultaneously, but I disagree and I think that is missing the point. It also does not account for updaters running external to the process. For example, it may be perfectly reasonable to start an update from `sparkle-cli` that defers the installation until quit, and have the application that is being updated be able to resume that installation and relaunch immediately.

The original `SUUpdater` may have also been created to assist plug-ins and other non-app bundles. My advice there is in order to be truly safe, you must not inject a framework like Sparkle into the host application anyway. An external tool that is bundled like `sparkle-cli` may be more appropriate to use here.

## Extensibility

Sparkle 2.0 does not support subclassing classes internal (not exported) to Sparkle anymore. Doing so would be almost impossible to maintain into the future. Subclassing in general has been banned. Composition is preferred everywhere, even amongst the internal update drivers which were rewritten to follow a protocol oriented approach. The reason why composition is preferred is because it's easier to follow the flow of logic.

I hope the user driver API gives enough extensibility without someone wanting to create another fork.

## Delegation

Newer classes, other than assisting backwards compatibility, that support delegation don't pass the delegator around anymore. Doing so has some [bad consequences](https://zgcoder.net/ramblings/avoid-passing-the-delegator) and makes code hard to maintain. 

Optional delegate methods that have return types need to be optional or have known default values for primitive types.

You may notice that the delegate and user driver are not accessible as properties from `SPUUpdater`. This is intentional. The methods that belong to these types aren't meaningful to any caller except from internal classes.

## Decoupling

Two software components should not directly know about each other. Preferably they wouldn't know about each other at all, but if they must, they can use the delegation pattern with a declared protocol.

See `Documentation/graph-of-sparkle.png` for a graph of how the code looks like currently. This was generated via [objc_dep](https://github.com/nst/objc_dep) (great tool). Note that there are no red edges which would mean that two nodes know of each other.

## Attributes & Code Size

Instance variables and instance variable access should be used for private members (declared in `@implementation` block) whenever possible over properties. Preferring instance variables over properties for internal usage can significantly reduce code size. Instance variables should also be ordered by having the larger sized data members declared first.

`SPU_OBJC_DIRECT_MEMBERS` should be used for any internal class in Sparkle and `SPU_OBJC_DIRECT` should be used for any other internal methods to Sparkle that doesn't need to utilize the Obj-C runtime to reduce code size. Note these attributes should not be used for *any* class or method that is exported to the developer (this includes private headers / APIs we carefully decided to expose too). For internal methods and classes that are also used by our Swift tools or unit tests, we may not expose them as direct specifically when building for those targets.

`nonatomic` should really be used wherever possible with regards to obj-c properties (`atomic` is a bad default). `readonly` should be used wherever possible as well, which also implies that only ivar access should be used in initializers. `NS_ASSUME_NONNULL_BEGIN` and `NS_ASSUME_NONNULL_END` should be used around new headers whenever possible. AppKit prevention guards should be used for any non-UI class whenever possible.

Sparkle has several feature flags in ConfigCommon.xcconfig (e.g. `SPARKLE_BUILD_LEGACY_SUUPDATER`, `SPARKLE_BUILD_LEGACY_DSA_SUPPORT`, `SPARKLE_BUILD_UI_BITS`, etc). This allows disabling any combination of these features and building Sparkle with a more minimal feature set. These flags (with the exception for stripping UI bits, localizations, or XPC Services) are for disabling features that are legacy or not recommended to use for most applications. Note when altering these flags, `OTHER_SWIFT_FLAGS_COMMON` may need to be updated appropriately too.
