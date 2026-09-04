import 'package:sqflite_common/sqlite_api.dart';

import 'xml_sql_parser.dart';
import 'dynamic_sql_builder.dart';
import 'exceptions.dart';
import 'logger.dart';
import 'mybatis_config.dart';

/// A session for running mapped statements.
///
/// The equivalent of MyBatis `SqlSession`:
/// - selectList: every matching row
/// - selectOne: one row or null; throws [TooManyResultsException] for more
/// - insert: returns the new rowid
/// - update: returns the affected row count
/// - delete: returns the affected row count
///
/// Example:
/// ```dart
/// // statements are addressed as 'namespace.id'
/// final list = await session.selectList('PersonMapper.selectPersonList', {'name': 'Hong'});
/// final person = await session.selectOne('PersonMapper.selectPersonById', {'id': 1});
/// final count = await session.insert('PersonMapper.insertPerson', personData);
/// ```
class SqlSession {
  final Database _database;
  final Map<String, SqlStatement> _statements;

  /// Creates a session over [database] with the given statements.
  SqlSession(this._database, this._statements);

  /// Runs a `<select>` and returns every row.
  ///
  /// [statementId] is `namespace.id`, e.g. `PersonMapper.selectPersonList`.
  /// [params] are the statement parameters.
  /// [limit] and [offset] append LIMIT/OFFSET when given.
  Future<List<Map<String, dynamic>>> selectList(
    String statementId,
    Map<String, dynamic> params, {
    int? limit,
    int? offset,
  }) async {
    final statement = _getStatement(statementId);
    _validateStatementType(statementId, statement, SqlStatementType.select);

    final stopwatch = Stopwatch()..start();

    final result = DynamicSqlBuilder.buildSelect(
      statement,
      Map<String, dynamic>.from(params),
      limit: limit,
      offset: offset,
    );

    try {
      final rows = await _withTimeout(
        _database.rawQuery(result.sql, result.parameters),
        statement,
      );
      stopwatch.stop();

      MybatisLogger.logSql(
        statementId: statementId,
        sql: result.sql,
        parameters: result.parameters,
        executionTime: stopwatch.elapsed,
        resultCount: rows.length,
      );

      // mapUnderscoreToCamelCase (기본 false → 원본 컬럼명 유지)
      if (!MybatisConfig.mapUnderscoreToCamelCase) return rows;
      return rows.map(MybatisConfig.mapRow).toList();
    } catch (e, stackTrace) {
      MybatisLogger.logError(
        statementId: statementId,
        sql: result.sql,
        error: e,
        stackTrace: stackTrace,
      );
      // Rethrow so that transactions roll back. See
      // MybatisConfig.suppressSqlErrors for the legacy behaviour.
      if (!MybatisConfig.suppressSqlErrors) rethrow;
      return [];
    }
  }

  /// Runs a `<select>` and returns the first row.
  ///
  /// [statementId] is `namespace.id`.
  /// [params] are the statement parameters.
  /// Returns null when there is no match.
  Future<Map<String, dynamic>?> selectOne(
    String statementId,
    Map<String, dynamic> params,
  ) async {
    // Appending LIMIT would break a statement that already ends in one, so
    // the rows are counted instead.
    final list = await selectList(statementId, params);
    if (list.isEmpty) return null;
    if (list.length > 1) throw TooManyResultsException(statementId);
    return list.first;
  }

  /// Runs a COUNT `<select>` and returns the number.
  ///
  /// [statementId] is `namespace.id`.
  /// [params] are the statement parameters.
  /// [countColumn] is the column holding the count (default `CNT`).
  Future<int> selectCount(
    String statementId,
    Map<String, dynamic> params, {
    String countColumn = 'CNT',
  }) async {
    final result = await selectOne(statementId, params);
    if (result == null) return 0;

    // mapUnderscoreToCamelCase rewrites the row's keys, so CNT arrives as cnt.
    final key = MybatisConfig.mapUnderscoreToCamelCase
        ? MybatisConfig.toCamelCase(countColumn)
        : countColumn;

    // "SELECT COUNT(*) FROM T" with no alias yields a column literally named
    // "COUNT(*)". Falling back to the single column is friendlier than
    // silently returning 0.
    final hasColumn = result.containsKey(key) || result.length == 1;
    final value = result[key] ?? (result.length == 1 ? result.values.first : null);

    if (value is num) return value.toInt();
    // The column is there and holds SQL NULL: SUM/MAX over an empty result set.
    // That is a count of zero, not a misconfigured statement.
    if (value == null && hasColumn) return 0;
    throw SqlBuildException(
      'selectCount could not read a count from column "$key" '
      '(row keys: ${result.keys.join(", ")}). '
      'Alias the column, e.g. SELECT COUNT(*) AS $countColumn.',
    );
  }

  /// Runs an `<insert>`.
  ///
  /// [statementId] is `namespace.id`.
  /// [params] are the statement parameters.
  /// Returns the new rowid. With `useGeneratedKeys` or `<selectKey>` the key
  /// is also written back into [params].
  Future<int> insert(
    String statementId,
    Map<String, dynamic> params,
  ) async {
    final statement = _getStatement(statementId);
    _validateStatementType(statementId, statement, SqlStatementType.insert);

    // <selectKey order="BEFORE"> : INSERT 전에 키를 미리 조회
    final selectKey = statement.selectKey;
    if (selectKey != null && selectKey.order == SelectKeyOrder.before) {
      params[selectKey.keyProperty] = await _executeSelectKey(statement, selectKey, params);
    }

    final stopwatch = Stopwatch()..start();
    final result = DynamicSqlBuilder.build(statement, Map<String, dynamic>.from(params));

    try {
      final id = await _withTimeout(
        _database.rawInsert(result.sql, result.parameters),
        statement,
      );
      stopwatch.stop();

      MybatisLogger.logSql(
        statementId: statementId,
        sql: result.sql,
        parameters: result.parameters,
        executionTime: stopwatch.elapsed,
        resultCount: 1,
      );

      // useGeneratedKeys="true" keyProperty="ID" : 생성된 rowid를 파라미터에 기록
      if (statement.writesGeneratedKey) {
        params[statement.keyProperty!] = id;
      }

      // <selectKey order="AFTER"> : INSERT 후에 키를 조회
      if (selectKey != null && selectKey.order == SelectKeyOrder.after) {
        params[selectKey.keyProperty] = await _executeSelectKey(statement, selectKey, params);
      }

      return id;
    } catch (e, stackTrace) {
      MybatisLogger.logError(
        statementId: statementId,
        sql: result.sql,
        error: e,
        stackTrace: stackTrace,
      );
      if (!MybatisConfig.suppressSqlErrors) rethrow;
      return -1;
    }
  }

  /// Runs an `<update>`.
  ///
  /// [statementId] is `namespace.id`.
  /// [params] are the statement parameters.
  /// Returns the number of affected rows.
  Future<int> update(
    String statementId,
    Map<String, dynamic> params,
  ) async {
    final statement = _getStatement(statementId);
    _validateStatementType(statementId, statement, SqlStatementType.update);

    final stopwatch = Stopwatch()..start();
    final result = DynamicSqlBuilder.build(statement, Map<String, dynamic>.from(params));

    try {
      final count = await _withTimeout(
        _database.rawUpdate(result.sql, result.parameters),
        statement,
      );
      stopwatch.stop();

      MybatisLogger.logSql(
        statementId: statementId,
        sql: result.sql,
        parameters: result.parameters,
        executionTime: stopwatch.elapsed,
        resultCount: count,
      );

      return count;
    } catch (e, stackTrace) {
      MybatisLogger.logError(
        statementId: statementId,
        sql: result.sql,
        error: e,
        stackTrace: stackTrace,
      );
      if (!MybatisConfig.suppressSqlErrors) rethrow;
      return 0;
    }
  }

  /// Runs a `<delete>`.
  ///
  /// [statementId] is `namespace.id`.
  /// [params] are the statement parameters.
  /// Returns the number of affected rows.
  Future<int> delete(
    String statementId,
    Map<String, dynamic> params,
  ) async {
    final statement = _getStatement(statementId);
    _validateStatementType(statementId, statement, SqlStatementType.delete);

    final stopwatch = Stopwatch()..start();
    final result = DynamicSqlBuilder.build(statement, Map<String, dynamic>.from(params));

    try {
      final count = await _withTimeout(
        _database.rawDelete(result.sql, result.parameters),
        statement,
      );
      stopwatch.stop();

      MybatisLogger.logSql(
        statementId: statementId,
        sql: result.sql,
        parameters: result.parameters,
        executionTime: stopwatch.elapsed,
        resultCount: count,
      );

      return count;
    } catch (e, stackTrace) {
      MybatisLogger.logError(
        statementId: statementId,
        sql: result.sql,
        error: e,
        stackTrace: stackTrace,
      );
      if (!MybatisConfig.suppressSqlErrors) rethrow;
      return 0;
    }
  }

  /// Runs [action] inside a transaction.
  ///
  /// Everything is rolled back if [action] throws.
  Future<T> transaction<T>(Future<T> Function(SqlSession txSession) action) async {
    return await _database.transaction((txn) async {
      final txSession = SqlSession(_TransactionDatabase(txn), _statements);
      return await action(txSession);
    });
  }

  /// Inserts many rows in a single transaction.
  Future<List<int>> batchInsert(
    String statementId,
    List<Map<String, dynamic>> paramsList,
  ) async {
    final ids = <int>[];

    await transaction((txSession) async {
      for (final params in paramsList) {
        final id = await txSession.insert(statementId, params);
        ids.add(id);
      }
    });

    return ids;
  }

  /// Applies the statement's `timeout` attribute, in seconds.
  ///
  /// Falls back to [MybatisConfig.defaultStatementTimeout], then to no limit.
  /// Stops waiting for [future] after the statement's `timeout`.
  ///
  /// This does not cancel anything: sqflite offers no equivalent of JDBC's
  /// `Statement.cancel`, which is what MyBatis uses. See [SqlTimeoutException].
  Future<T> _withTimeout<T>(Future<T> future, SqlStatement statement) {
    final duration = statement.timeoutDuration;
    if (duration == null) return future;
    return future.timeout(
      duration,
      onTimeout: () => throw SqlTimeoutException(statement.fullId, duration),
    );
  }

  /// Runs a `<selectKey>` and returns the key it produced.
  Future<dynamic> _executeSelectKey(
    SqlStatement parent,
    SelectKeyStatement selectKey,
    Map<String, dynamic> params,
  ) async {
    final temp = SqlStatement(
      id: '${parent.id}!selectKey',
      namespace: parent.namespace,
      type: SqlStatementType.select,
      resultType: selectKey.resultType,
      elements: selectKey.elements,
    );

    final built = DynamicSqlBuilder.build(temp, Map<String, dynamic>.from(params));
    final rows = await _withTimeout(
      _database.rawQuery(built.sql, built.parameters),
      parent,
    );

    MybatisLogger.logSql(
      statementId: temp.fullId,
      sql: built.sql,
      parameters: built.parameters,
      executionTime: Duration.zero,
      resultCount: rows.length,
    );

    if (rows.isEmpty) return null;
    final row = rows.first;

    final column = selectKey.keyColumn;
    if (column != null && row.containsKey(column)) return row[column];
    return row.values.isEmpty ? null : row.values.first;
  }

  /// Looks up a statement, throwing if it is not registered.
  SqlStatement _getStatement(String statementId) {
    final statement = _statements[statementId];
    if (statement == null) {
      throw StatementNotFoundException(statementId);
    }
    return statement;
  }

  /// Verifies the statement is of the expected kind.
  void _validateStatementType(
    String statementId,
    SqlStatement statement,
    SqlStatementType expected,
  ) {
    if (statement.type != expected) {
      throw StatementTypeException(
        statementId: statementId,
        expected: expected.name,
        actual: statement.type.name,
      );
    }
  }

  /// Whether [statementId] is registered.
  bool hasStatement(String statementId) => _statements.containsKey(statementId);

  /// The underlying database.
  Database get database => _database;
}

/// Wraps a [Transaction] so it can be used as a [Database].
class _TransactionDatabase implements Database {
  final Transaction _txn;

  _TransactionDatabase(this._txn);

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) {
    return _txn.rawQuery(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    return _txn.rawInsert(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    return _txn.rawUpdate(sql, arguments);
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) {
    return _txn.rawDelete(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
        'not supported inside a transaction: ${invocation.memberName}');
  }
}
