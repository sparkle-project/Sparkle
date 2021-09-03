# Sparkle 2 API Reference

These are the primary classes and protocols in Sparkle 2 you may be interested in:

- `SPUStandardUpdaterController` for creating a standard updater (encapsulates a `SPUUpdater` and `SPUStandardUserDriver`)
- `SPUUpdater` for invoking update checks and retrieving updater properties.
- `SPUUpdaterDelegate` for delegation methods to control the behavior of `SPUUpdater`.
- `SPUUserDriver` for making custom user interfaces.

If you are migrating from Sparkle 1, please refer to `SPUStandardUpdaterController` and `SPUUpdater`.

Please also visit the [Basic Setup](https://sparkle-project.org/documentation/) guide which shows how to instantiate an updater in a nib or how to create one programmatically.
