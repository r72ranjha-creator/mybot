/// Process-wide "stop now" flag.
///
/// The STOP button is a safety control, so it must reach a plan that is already
/// running. A `ManagerBot` is built with an immutable `AppSettings` snapshot, so
/// a stop tapped mid-plan would never be seen by it; this flag is read again
/// before every step instead.
///
/// The flag mirrors the persisted `stopRequested` setting: the setting survives
/// a restart, the flag is the in-process copy that a running plan polls.
class Halt {
  Halt._();

  static bool _requested = false;

  static bool get requested => _requested;

  static void request() => _requested = true;

  static void clear() => _requested = false;

  /// Used at startup to restore the persisted state.
  static void restore(bool stopped) => _requested = stopped;
}
