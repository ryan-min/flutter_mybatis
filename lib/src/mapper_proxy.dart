import 'sql_session.dart';

/// Base class for hand-written mappers.
///
/// Mirrors the MyBatis Mapper interface. Prefer the generated mappers
///
/// (`@MybatisMapper`) for new code. Example:
/// ```dart
/// class GrpF01Mapper extends Mapper {
///   GrpF01Mapper(super.session);
///
///   Future<List<Map<String, dynamic>>> search(Map<String, dynamic> p) => selectList('selectList', p);
///   Future<Map<String, dynamic>?> findById(Map<String, dynamic> p) => selectOne('selectById', p);
///   Future<int> add(Map<String, dynamic> p) => insert('insert', p);
///   Future<int> modify(Map<String, dynamic> p) => update('update', p);
///   Future<int> remove(Map<String, dynamic> p) => delete('delete', p);
/// }
/// ```
abstract class Mapper {
  final SqlSession _session;

  /// XML namespace; defaults to the class name.
  ///
  /// Override this if you build with `--obfuscate`, which mangles class names.
  String get namespace => runtimeType.toString();

  /// Creates a mapper bound to [session].
  Mapper(this._session);

  /// Runs a `<select>` and returns every row.
  Future<List<Map<String, dynamic>>> selectList(String id, Map<String, dynamic> p, {int? limit, int? offset}) =>
      _session.selectList('$namespace.$id', p, limit: limit, offset: offset);

  /// Runs a `<select>` and returns the first row, or null.
  Future<Map<String, dynamic>?> selectOne(String id, Map<String, dynamic> p) =>
      _session.selectOne('$namespace.$id', p);

  /// Runs a COUNT `<select>` and returns the number.
  Future<int> selectCount(String id, Map<String, dynamic> p, {String countColumn = 'CNT'}) =>
      _session.selectCount('$namespace.$id', p, countColumn: countColumn);

  /// Runs an `<insert>` and returns the new rowid.
  Future<int> insert(String id, Map<String, dynamic> p) =>
      _session.insert('$namespace.$id', p);

  /// Runs an `<update>` and returns the affected row count.
  Future<int> update(String id, Map<String, dynamic> p) =>
      _session.update('$namespace.$id', p);

  /// Runs a `<delete>` and returns the affected row count.
  Future<int> delete(String id, Map<String, dynamic> p) =>
      _session.delete('$namespace.$id', p);

  /// Runs [action] inside a transaction, rolling back on error.
  Future<T> transaction<T>(Future<T> Function(SqlSession txSession) action) =>
      _session.transaction(action);

  /// Inserts many rows in one transaction.
  Future<List<int>> batchInsert(String id, List<Map<String, dynamic>> paramsList) =>
      _session.batchInsert('$namespace.$id', paramsList);

  /// The underlying session.
  SqlSession get session => _session;
}

/// Legacy base class. Use [Mapper] instead.
@Deprecated('Use Mapper instead')
abstract class MapperProxy extends Mapper {
  final String _namespace;

  /// Creates a mapper with an explicit namespace.
  MapperProxy(super.session, this._namespace);

  @override
  String get namespace => _namespace;

  /// Deprecated alias for `selectList`.
  Future<List<Map<String, dynamic>>> selectListById(String id, Map<String, dynamic> params, {int? limit, int? offset}) =>
      selectList(id, params, limit: limit, offset: offset);

  /// Deprecated alias for `selectOne`.
  Future<Map<String, dynamic>?> selectOneById(String id, Map<String, dynamic> params) =>
      selectOne(id, params);

  /// Deprecated alias for `selectCount`.
  Future<int> selectCountById(String id, Map<String, dynamic> params, {String countColumn = 'CNT'}) =>
      selectCount(id, params, countColumn: countColumn);

  /// Deprecated alias for `insert`.
  Future<int> insertById(String id, Map<String, dynamic> params) =>
      insert(id, params);

  /// Deprecated alias for `update`.
  Future<int> updateById(String id, Map<String, dynamic> params) =>
      update(id, params);

  /// Deprecated alias for `delete`.
  Future<int> deleteById(String id, Map<String, dynamic> params) =>
      delete(id, params);

  /// Deprecated alias for `batchInsert`.
  Future<List<int>> batchInsertById(String id, List<Map<String, dynamic>> paramsList) =>
      batchInsert(id, paramsList);
}

/// Holds mapper instances for the whole app.
class MapperRegistry {
  final Map<Type, dynamic> _mappers = {};

  /// Registers [mapper] under its type.
  void register<T>(T mapper) {
    _mappers[T] = mapper;
  }

  /// Returns the mapper registered for [T].
  T getMapper<T>() {
    final mapper = _mappers[T];
    if (mapper == null) {
      throw StateError('no mapper registered for $T');
    }
    return mapper as T;
  }

  /// Whether a mapper is registered for [T].
  bool hasMapper<T>() => _mappers.containsKey(T);

  /// Removes every registered mapper.
  void clear() => _mappers.clear();

  /// The types that have a registered mapper.
  List<Type> get registeredTypes => _mappers.keys.toList();
}
