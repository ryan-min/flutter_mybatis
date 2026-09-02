/// Global settings (the equivalent of MyBatis `<settings>`).
///
/// **Every default preserves 0.9.x behaviour.**
/// Upgrading changes nothing until you opt in.
///
/// ```dart
/// void main() {
///   MybatisConfig.mapUnderscoreToCamelCase = true; // USER_NM -> userNm
///   MybatisConfig.strictExpressions = true;        // throw on unsupported test syntax
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
  /// Defaults to `false`: the expression evaluates to `false` with a warning,
  /// as in 0.9.x. Set to `true` to throw [UnsupportedExpressionException].
  ///
  /// Full OGNL cannot be ported because Dart has no `eval`. Turn this on to
  /// stop out-of-range expressions from silently becoming `false`.
  static bool strictExpressions = false;

  /// Fallback timeout for statements without a `timeout` attribute.
  ///
  /// Defaults to `null` (no timeout), as in 0.9.x.
  static Duration? defaultStatementTimeout;

  /// Resets every setting to its default (useful in tests).
  static void reset() {
    mapUnderscoreToCamelCase = false;
    strictExpressions = false;
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
