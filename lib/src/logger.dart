import 'log_adapter.dart';

export 'log_adapter.dart';

/// Whether this is a release build (pure-Dart stand-in for `kReleaseMode`).
const bool _kReleaseMode = bool.fromEnvironment('dart.vm.product');
/// Whether this is a debug build (the equivalent of `kDebugMode`).
const bool kDebugModeCompat = !_kReleaseMode;


/// Controls SQL logging.
///
/// ## Basic use
/// ```dart
/// // just set a level; output goes to the console
/// MybatisLogger.setLogLevel(MybatisLogLevel.debug);
/// ```
/// 
/// ## Routing to your own logger
/// ```dart
/// // e.g. the `logger` package
/// final logger = Logger();
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
class MybatisLogger {
  static MybatisLogLevel _logLevel = MybatisLogLevel.off;
  static MybatisLogHandler? _handler;
  
  // SQL 로그 옵션
  static bool _showSql = true;
  static bool _showParams = true;
  static bool _showTime = true;

  MybatisLogger._();

  // ============================================
  // 설정
  // ============================================

  /// Sets the minimum level that is logged.
  static void setLogLevel(MybatisLogLevel level) => _logLevel = level;

  /// The current log level.
  static MybatisLogLevel get logLevel => _logLevel;

  /// Routes log output to your own handler.
  /// 
  /// Pass null to go back to console output.
  static void setLogHandler(MybatisLogHandler? handler) => _handler = handler;

  /// Whether the SQL text is logged.
  static void setShowSql(bool show) => _showSql = show;

  /// Whether bind parameters are logged.
  static void setShowParams(bool show) => _showParams = show;

  /// Whether execution time is logged.
  static void setShowTime(bool show) => _showTime = show;

  /// Turns on debug-level logging with SQL and parameters.
  static void setDebugMode(bool debug) {
    _logLevel = debug ? MybatisLogLevel.debug : MybatisLogLevel.off;
  }

  /// Enables or disables logging entirely.
  static void setEnabled(bool enabled) {
    _logLevel = enabled ? MybatisLogLevel.debug : MybatisLogLevel.off;
  }

  // ============================================
  // 로그 출력
  // ============================================

  /// Whether [level] would be logged.
  ///
  /// Console output is limited to debug builds, but a custom handler set with
  /// [setLogHandler] also runs in release — that is how you forward SQL
  /// errors to a crash reporter. Remember that parameters can contain
  /// personal data; keep [setShowParams] off in release.
  static bool canLog(MybatisLogLevel level) {
    if (level.value < _logLevel.value) return false;
    return _handler != null || kDebugModeCompat;
  }

  /// Writes one line at [level].
  static void _log(MybatisLogLevel level, String message) {
    if (!canLog(level)) return;
    
    if (_handler != null) {
      _handler!(level, message);
    } else {
      // ignore: avoid_print
      print(message);
    }
  }

  /// Logs at debug level.
  static void log(String message) => _log(MybatisLogLevel.debug, message);
  
  /// Logs at debug level.
  static void debug(String message) => _log(MybatisLogLevel.debug, message);
  
  /// Logs at info level.
  static void info(String message) => _log(MybatisLogLevel.info, message);
  
  /// Logs at warning level.
  static void warn(String message) => _log(MybatisLogLevel.warn, message);

  /// Reports a mapper configuration mistake.
  ///
  /// Unlike [warn] this ignores the log level, which defaults to
  /// [MybatisLogLevel.off]. These are set-up errors — an attribute that has no
  /// effect, an expression that could not be read — and staying silent about
  /// them is how people come to rely on behaviour that does not exist.
  /// A handler set with [setLogHandler] still takes precedence over printing.
  static void configWarning(String message) {
    if (_handler != null) {
      _handler!(MybatisLogLevel.warn, message);
      return;
    }
    // ignore: avoid_print
    print('[flutter-mybatis] $message');
  }
  
  /// Logs at error level.
  static void error(String message) => _log(MybatisLogLevel.error, message);

  // ============================================
  // SQL 전용 로그
  // ============================================

  /// Logs a executed statement with its SQL, parameters and timing.
  static void logSql({
    required String statementId,
    required String sql,
    List<dynamic>? parameters,
    Duration? executionTime,
    int? resultCount,
  }) {
    if (!canLog(MybatisLogLevel.debug)) return;

    final buffer = StringBuffer();
    buffer.writeln('╔══════════════════════════════════════════════════════════════');
    buffer.writeln('║ [flutter-mybatis] $statementId');
    buffer.writeln('╠──────────────────────────────────────────────────────────────');

    if (_showSql) {
      buffer.writeln('║ SQL: $sql');
    }

    if (_showParams && parameters != null && parameters.isNotEmpty) {
      buffer.writeln('║ Params: $parameters');
    }

    if (_showTime && executionTime != null) {
      buffer.writeln('║ Time: ${executionTime.inMilliseconds}ms');
    }

    if (resultCount != null) {
      buffer.writeln('║ Result: $resultCount rows');
    }

    buffer.write('╚══════════════════════════════════════════════════════════════');

    _log(MybatisLogLevel.debug, buffer.toString());
  }

  /// Logs a failed statement.
  static void logError({
    required String statementId,
    required String sql,
    required Object error,
    StackTrace? stackTrace,
  }) {
    if (!canLog(MybatisLogLevel.error)) return;

    final buffer = StringBuffer();
    buffer.writeln('╔══════════════════════════════════════════════════════════════');
    buffer.writeln('║ [flutter-mybatis] ERROR - $statementId');
    buffer.writeln('╠──────────────────────────────────────────────────────────────');
    buffer.writeln('║ SQL: $sql');
    buffer.writeln('║ Error: $error');
    if (stackTrace != null) {
      buffer.writeln('║ StackTrace: $stackTrace');
    }
    buffer.write('╚══════════════════════════════════════════════════════════════');

    _log(MybatisLogLevel.error, buffer.toString());
  }

  /// Logs that a mapper was loaded.
  static void logMapperLoad(String namespace, int statementCount) {
    info('[flutter-mybatis] Loaded mapper: $namespace ($statementCount statements)');
  }

  /// Logs the totals after all mappers are loaded.
  static void logInit(int mapperCount, int totalStatements) {
    info('[flutter-mybatis] Initialized: $mapperCount mappers, $totalStatements statements');
  }
}
