/// Global settings (the equivalent of MyBatis `<settings>`).
///
/// Two defaults deliberately differ from 0.9.x, because the alternative fails
/// silently: [suppressSqlErrors] is `false` (a failed statement throws, so a
/// transaction can roll back) and [strictExpressions] is `true` (an unreadable
/// `test` throws instead of quietly dropping a `<where>` clause). Everything
/// else is off until you opt in.
///
/// ```dart
/// void main() {
///   MybatisConfig.mapUnderscoreToCamelCase = true; // USER_NM -> userNm
///   MybatisConfig.suppressSqlErrors = true;        // 0.9.x: swallow SQL errors
///   runApp(const MyApp());
/// }
/// ```
class MybatisConfig {
  MybatisConfig._();

  /// Map underscored column names to camelCase (MyBatis `mapUnderscoreToCamelCase`).
  ///
  /// `USER_NM` -> `userNm`, `user_nm` -> `userNm`
  ///
  /// Defaults to `false`: existing code reads raw column names such as
  /// `row['USER_NM']`, and turning this on changes those keys.
  static bool mapUnderscoreToCamelCase = false;

  /// Whether an unsupported `test` expression throws instead of being ignored.
  ///
  /// Defaults to `true`. An expression the parser cannot read used to become
  /// `false`, which silently removed a `<where>` clause — turning a guarded
  /// `<delete>` into one that deletes every row. Set to `false` only to
  /// restore the 0.9.x behaviour.
  ///
  /// Full OGNL cannot be ported because Dart has no `eval`, so the supported
  /// subset has a hard edge. Throwing is what makes that edge visible.
  static bool strictExpressions = true;

  /// Whether SQL execution errors are swallowed instead of thrown.
  ///
  /// Defaults to `false`: a failed statement throws, which is what makes
  /// [SqlSession.transaction] roll back. 0.9.x swallowed errors and returned
  /// an empty list / `-1` / `0` instead, which silently committed the rest of
  /// a failed transaction.
  ///
  /// Set this to `true` only as a temporary bridge for code written against
  /// that older behaviour.
  static bool suppressSqlErrors = false;

  /// Fallback timeout for statements without a `timeout` attribute.
  ///
  /// Defaults to `null` (no timeout), as in 0.9.x.
  static Duration? defaultStatementTimeout;

  /// Resets every setting to its default (useful in tests).
  static void reset() {
    mapUnderscoreToCamelCase = false;
    strictExpressions = true;
    suppressSqlErrors = false;
    defaultStatementTimeout = null;
  }

  /// Converts an underscored column name to camelCase.
  ///
  /// `USER_NM` -> `userNm`, `BRTH_YR` -> `brthYr`, `id` -> `id`
  static String toCamelCase(String column) {
    if (!column.contains('_')) {
      // 전부 대문자면 소문자화 (USERNM -> usernm), 그 외는 원본 유지
      return column == column.toUpperCase() && column != column.toLowerCase()
          ? column.toLowerCase()
          : column;
    }

    final parts = column.split('_').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return column;

    final buffer = StringBuffer(parts.first.toLowerCase());
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i].toLowerCase();
      buffer.write(p[0].toUpperCase());
      if (p.length > 1) buffer.write(p.substring(1));
    }
    return buffer.toString();
  }

  /// Rewrites a row's keys according to [mapUnderscoreToCamelCase].
  static Map<String, dynamic> mapRow(Map<String, dynamic> row) {
    if (!mapUnderscoreToCamelCase) return row;

    final mapped = <String, dynamic>{};
    for (final entry in row.entries) {
      mapped[toCamelCase(entry.key)] = entry.value;
    }
    return mapped;
  }
}
