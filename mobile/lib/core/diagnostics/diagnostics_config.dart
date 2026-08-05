import 'package:flutter/foundation.dart';

/// Compile-time gate for internal diagnostics.
///
/// Push builds enable this with `--dart-define=ENABLE_DIAGNOSTICS=true`.
/// Formal release builds omit the define and therefore keep diagnostics out of
/// the user-facing navigation.
const diagnosticsEnabled = bool.fromEnvironment(
  'ENABLE_DIAGNOSTICS',
  defaultValue: kDebugMode,
);
