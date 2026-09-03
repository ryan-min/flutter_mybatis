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

/// Thrown for `test` syntax outside the supported subset.
///
/// [MybatisConfig.strictExpressions] is `true` by default, so this throws.
/// Set it to `false` and the expression evaluates to `false` with a warning
/// instead, as in 0.9.x.
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

/// Thrown when `selectOne` matches more than one row.
///
/// MyBatis raises `TooManyResultsException` in the same situation.
class TooManyResultsException implements Exception {
  /// The statement that returned too many rows.
  final String statementId;

  /// Creates a too-many-results failure.
  TooManyResultsException(this.statementId);

  @override
  String toString() =>
      'TooManyResultsException: selectOne matched more than one row: '
      '$statementId';
}

/// Thrown when a parameter has no [TypeHandler] and cannot be bound.
///
/// sqflite binds only `num`, `String`, `Uint8List` and `null`. Register a
/// handler for the type rather than relying on `toString()`.
class UnsupportedTypeException implements Exception {
  /// The type that could not be bound.
  final Type type;

  /// Creates an unsupported-parameter-type failure.
  UnsupportedTypeException(this.type);

  @override
  String toString() =>
      'UnsupportedTypeException: no TypeHandler registered for $type. '
      'Register one with TypeHandlerRegistry.register().';
}
