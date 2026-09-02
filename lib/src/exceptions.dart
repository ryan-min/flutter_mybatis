/// Exceptions thrown by flutter_mybatis.
library;

/// Thrown when a mapper XML file cannot be loaded.
class MapperLoadException implements Exception {
  /// What went wrong.
  final String message;
  /// The XML path that was being loaded.
  final String? path;
  /// The underlying error.
  final Object? cause;

  /// Creates a mapper-load failure.
  MapperLoadException(this.message, {this.path, this.cause});

  @override
  String toString() {
    final buffer = StringBuffer('MapperLoadException: $message');
    if (path != null) buffer.write(' (path: $path)');
    if (cause != null) buffer.write('\nCause: $cause');
    return buffer.toString();
  }
}

/// Thrown when a statement id is not registered.
class StatementNotFoundException implements Exception {
  /// The statement id that was not found.
  final String statementId;

  /// Creates a statement-not-found failure.
  StatementNotFoundException(this.statementId);

  @override
  String toString() => 'StatementNotFoundException: statement not found: $statementId';
}

/// Thrown when a statement is used as the wrong kind.
class StatementTypeException implements Exception {
  /// The statement id involved.
  final String statementId;
  /// The kind that was expected.
  final String expected;
  /// The kind actually declared in XML.
  final String actual;

  /// Creates a statement-kind mismatch failure.
  StatementTypeException({
    required this.statementId,
    required this.expected,
    required this.actual,
  });

  @override
  String toString() =>
      'StatementTypeException: statement kind mismatch ($statementId): expected=$expected, actual=$actual';
}

/// Thrown when a statement cannot be built.
class SqlBuildException implements Exception {
  /// What went wrong.
  final String message;
  /// The SQL involved, when available.
  final String? sql;

  /// Creates a SQL build failure.
  SqlBuildException(this.message, {this.sql});

  @override
  String toString() {
    final buffer = StringBuffer('SqlBuildException: $message');
    if (sql != null) buffer.write('\nSQL: $sql');
    return buffer.toString();
  }
}

/// Thrown when mapper XML cannot be parsed.
class XmlParseException implements Exception {
  /// What went wrong.
  final String message;
  /// The XML element involved.
  final String? element;

  /// Creates an XML parse failure.
  XmlParseException(this.message, {this.element});

  @override
  String toString() {
    final buffer = StringBuffer('XmlParseException: $message');
    if (element != null) buffer.write(' (element: $element)');
    return buffer.toString();
  }
}

/// Thrown when a `test` condition cannot be evaluated.
class ConditionEvaluationException implements Exception {
  /// The condition that failed.
  final String condition;
  /// What went wrong.
  final String? reason;

  /// Creates a condition evaluation failure.
  ConditionEvaluationException(this.condition, {this.reason});

  @override
  String toString() {
    final buffer = StringBuffer('ConditionEvaluationException: failed to evaluate condition: $condition');
    if (reason != null) buffer.write(' ($reason)');
    return buffer.toString();
  }
}

/// Thrown for `test` syntax outside the supported subset.
///
/// Only thrown when [MybatisConfig.strictExpressions] is `true`; otherwise
/// the expression evaluates to `false` with a warning.
class UnsupportedExpressionException implements Exception {
  /// The unsupported expression.
  final String expression;
  /// The statement it appeared in.
  final String? statementId;

  /// Creates an unsupported-expression failure.
  UnsupportedExpressionException(this.expression, {this.statementId});

  @override
  String toString() {
    final buffer = StringBuffer(
        'UnsupportedExpressionException: unsupported test expression: "$expression"');
    if (statementId != null) buffer.write(' (statement: $statementId)');
    buffer.write('\nSee "test expression support" in the README for the supported syntax.');
    return buffer.toString();
  }
}

/// Thrown when `<include refid="...">` points at a missing `<sql>` fragment.
class SqlFragmentNotFoundException implements Exception {
  /// The fragment id that was not found.
  final String refid;
  /// The namespace that was searched.
  final String? namespace;

  /// Creates a fragment-not-found failure.
  SqlFragmentNotFoundException(this.refid, {this.namespace});

  @override
  String toString() {
    final buffer =
        StringBuffer('SqlFragmentNotFoundException: <sql> fragment not found: $refid');
    if (namespace != null) buffer.write(' (namespace: $namespace)');
    return buffer.toString();
  }
}
