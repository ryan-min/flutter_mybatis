import 'package:sqflite_common/sqlite_api.dart';

import 'xml_sql_parser.dart';
import 'sql_session.dart';
import 'exceptions.dart';
import 'logger.dart';

/// Loads mapper XML and creates [SqlSession]s.
///
/// Example:
///
/// ```dart
/// final factory = SqlSessionFactory(database);
/// await factory.loadMapper('assets/person_mapper.xml');
/// final session = factory.openSession();
/// ```
class SqlSessionFactory {
  final Database _database;
  final Map<String, MapperConfig> _mapperConfigs = {};
  final Map<String, SqlStatement> _allStatements = {};

  /// Every `<sql>` fragment across all mappers, keyed by `namespace.id`.
  final Map<String, List<SqlElement>> _allFragments = {};

  /// Creates a factory bound to [database].
  SqlSessionFactory(this._database);

  /// Loads several mapper XML documents at once.
  ///
  /// To read from Flutter assets use the `loadMapper` / `loadMappers`
  /// extensions from `package:flutter_mybatis/flutter_mybatis.dart`.
  void loadMapperStrings(Iterable<String> xmlContents, {String? source}) {
    for (final xml in xmlContents) {
      _loadMapperFromString(xml, source ?? 'string');
    }
    MybatisLogger.logInit(_mapperConfigs.length, _allStatements.length);
  }

  /// Loads a mapper from an XML string.
  void loadMapperFromString(String xmlContent, {String? source}) {
    _loadMapperFromString(xmlContent, source ?? 'string');
  }

  void _loadMapperFromString(String xmlContent, String source) {
    final config = XmlSqlParser.parse(xmlContent);

    // Check everything before touching the factory. A rejected mapper must
    // leave no trace: half of its statements registered would be worse than
    // not loading it at all, and the caller may well catch and carry on.
    //
    // Registering the same qualified id twice would silently replace the
    // first mapper, which is a configuration mistake rather than an override.
    for (final key in config.statements.keys) {
      if (_allStatements.containsKey(key)) {
        throw MapperLoadException(
          'duplicate statement id across mappers: $key',
          path: source,
        );
      }
    }
    for (final key in config.fragments.keys) {
      if (_allFragments.containsKey(key)) {
        throw MapperLoadException(
          'duplicate <sql> id across mappers: $key',
          path: source,
        );
      }
    }

    _mapperConfigs[config.namespace] = config;
    _allStatements.addAll(config.statements);
    _allFragments.addAll(config.fragments);
    _includesResolved = false;

    MybatisLogger.logMapperLoad(config.namespace, config.statements.length);
  }

  /// Whether every `<include>` has been resolved.
  bool _includesResolved = true;

  /// Resolves every `<include>` against the loaded `<sql>` fragments.
  ///
  /// Runs automatically on the first [openSession] so that fragments from
  /// other mapper files can be referenced. Safe to call directly.
  void resolveIncludes() {
    for (final statement in _allStatements.values) {
      statement.resolveIncludes(_allFragments);
    }
    _includesResolved = true;
  }

  /// Opens a session, resolving `<include>`s if needed.
  SqlSession openSession() {
    if (!_includesResolved) {
      resolveIncludes();
    }
    return SqlSession(_database, _allStatements);
  }

  /// Namespaces of the loaded mappers.
  List<String> get registeredMappers => _mapperConfigs.keys.toList();

  /// Ids of every loaded statement.
  List<String> get registeredStatements => _allStatements.keys.toList();

  /// Whether [statementId] is registered.
  bool hasStatement(String statementId) {
    return _allStatements.containsKey(statementId);
  }

  /// Returns the parsed config for [namespace].
  MapperConfig? getMapperConfig(String namespace) {
    return _mapperConfigs[namespace];
  }

  /// Returns the statement registered as [statementId].
  SqlStatement? getStatement(String statementId) {
    return _allStatements[statementId];
  }

  /// The underlying database.
  Database get database => _database;

  /// Ids of every loaded `<sql>` fragment.
  List<String> get registeredFragments => _allFragments.keys.toList();

  /// Removes every loaded mapper.
  void clear() {
    _mapperConfigs.clear();
    _allStatements.clear();
    _allFragments.clear();
    _includesResolved = true;
  }
}
