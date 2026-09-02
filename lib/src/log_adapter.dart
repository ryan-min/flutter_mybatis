/// Log levels and the custom handler type.
///
///
library;

/// How much detail is logged.
enum MybatisLogLevel {
  /// Everything: SQL, parameters and timing.
  debug(0),
  
  /// Informational: mapper loading and start-up.
  info(1),
  
  /// Warnings only.
  warn(2),
  
  /// Errors only.
  error(3),
  
  /// Logging off.
  off(4);

  /// Ordering value; lower means more detail.
  final int value;

  const MybatisLogLevel(this.value);
}

/// Signature for a custom log handler.
///
///
/// 
/// ```dart
/// MybatisLogger.setLogHandler((level, message) {
///   switch (level) {
///     case MybatisLogLevel.debug: logger.d(message); break;
///     case MybatisLogLevel.info: logger.i(message); break;
///     case MybatisLogLevel.warn: logger.w(message); break;
///     case MybatisLogLevel.error: logger.e(message); break;
///     default: break;
///   }
/// });
/// ```
typedef MybatisLogHandler = void Function(MybatisLogLevel level, String message);
