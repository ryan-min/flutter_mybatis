import 'expression.dart';
import 'type_handler.dart';
import 'xml_sql_parser.dart';

/// Turns parsed SQL elements into an executable statement.
///
///
class DynamicSqlBuilder {
  /// Builds the final SQL and its bind parameters.
  ///
  /// `#{paramName}` becomes `?`, and the matching value is collected in
  /// order. `${paramName}` is substituted as raw text.
  static SqlBuildResult build(SqlStatement statement, Map<String, dynamic> params) {
    // 파라미터 복사 (bind 요소에서 수정될 수 있음)
    final workingParams = Map<String, dynamic>.from(params);

    // MyBatis 내장 변수: _parameter (파라미터 객체 전체)
    workingParams.putIfAbsent('_parameter', () => Map<String, dynamic>.from(params));

    // 1. 모든 요소를 빌드하여 SQL 문자열 생성
    final rawSql = statement.elements.map((e) => e.build(workingParams)).join(' ').trim();

    // 2. Tidy whitespace *outside* string literals. Normalising the whole
    //    statement would rewrite the literals themselves: 'hello   world'
    //    would silently become 'hello world'.
    var sql = _normalizeWhitespace(rawSql);

    // 3. #{paramName} → ? 변환 및 파라미터 추출
    final bindParams = <dynamic>[];
    // Allows nested paths such as #{user.id} and #{items[0].name}
    final paramPattern = RegExp(r'#\{([^}]+)\}');

    sql = sql.replaceAllMapped(paramPattern, (match) {
      // MyBatis allows attributes after the property:
      //   #{id, jdbcType=INTEGER, javaType=int}
      // Only the property itself is meaningful here; JDBC metadata has no
      // equivalent in sqflite and is ignored.
      final paramName = match.group(1)!.split(',').first.trim();
      final value = resolvePropertyPath(paramName, workingParams);
      // TypeHandler 적용 (DateTime/bool/enum 등 → sqflite 바인딩 가능 타입)
      bindParams.add(TypeHandlerRegistry.encode(value));
      return '?';
    });

    return SqlBuildResult(
      sql: sql,
      parameters: bindParams,
      statementId: statement.fullId,
    );
  }

  /// Same as [build], appending LIMIT/OFFSET when given.
  static SqlBuildResult buildSelect(
    SqlStatement statement,
    Map<String, dynamic> params, {
    int? limit,
    int? offset,
  }) {
    final result = build(statement, params);
    var sql = result.sql;
    final bindParams = List<dynamic>.from(result.parameters);

    // SQLite only accepts OFFSET as part of a LIMIT clause, so an offset
    // without a limit needs the "no limit" sentinel.
    if (limit != null) {
      sql += ' LIMIT ?';
      bindParams.add(limit);
    } else if (offset != null) {
      sql += ' LIMIT -1';
    }
    if (offset != null) {
      sql += ' OFFSET ?';
      bindParams.add(offset);
    }

    return SqlBuildResult(
      sql: sql,
      parameters: bindParams,
      statementId: result.statementId,
    );
  }
}

/// Collapses runs of whitespace outside string literals.
///
/// SQL text is tidied so that dropped `<if>` blocks do not leave gaps, but
/// anything inside `'...'` is copied verbatim — a literal's own spacing is
/// part of its value. SQLite escapes a quote by doubling it (`''`), which is
/// handled by simply toggling back into the literal.
String _normalizeWhitespace(String sql) {
  final out = StringBuffer();
  var inString = false;
  var pendingSpace = false;

  for (var i = 0; i < sql.length; i++) {
    final c = sql[i];

    if (inString) {
      out.write(c);
      if (c == "'") inString = false;
      continue;
    }

    if (c == "'") {
      if (pendingSpace) {
        out.write(' ');
        pendingSpace = false;
      }
      out.write(c);
      inString = true;
      continue;
    }

    if (c.trim().isEmpty) {
      pendingSpace = true;
      continue;
    }

    if (pendingSpace) {
      // Drop the space directly after "(" or before ")" and ",".
      final last = out.isEmpty ? '' : out.toString()[out.length - 1];
      if (last != '(' && c != ')' && c != ',') out.write(' ');
      pendingSpace = false;
    }
    out.write(c);
  }

  return out.toString().trim();
}

/// The result of building a statement.
class SqlBuildResult {
  /// The final SQL, with parameters replaced by `?`.
  final String sql;

  /// Bind parameters, in the order they appear in [sql].
  final List<dynamic> parameters;

  /// Statement ID
  final String statementId;

  /// Creates a build result.
  SqlBuildResult({
    required this.sql,
    required this.parameters,
    required this.statementId,
  });

  @override
  String toString() {
    return 'SqlBuildResult(\n  statementId: $statementId,\n  sql: $sql,\n  parameters: $parameters\n)';
  }
}
