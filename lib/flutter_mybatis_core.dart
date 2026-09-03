/// flutter_mybatis core — **pure Dart**.
///
/// No Flutter dependency, so it runs in console apps, server-side Dart and
/// tests. It takes a `Database` from `sqflite_common`, so you can plug in
/// `sqflite` (mobile), `sqflite_common_ffi` (desktop/CLI/tests) or
/// `sqflite_common_ffi_web` (web).
///
/// ```dart
/// import 'package:flutter_mybatis/flutter_mybatis_core.dart';
/// import 'package:sqflite_common_ffi/sqflite_ffi.dart';
///
/// void main() async {
///   sqfliteFfiInit();
///   final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
///
///   final factory = SqlSessionFactory(db)
///     ..loadMapperFromString(File('petstore_mapper.xml').readAsStringSync());
///
///   final session = factory.openSession();
/// }
/// ```
///
/// To load XML from Flutter assets, import `flutter_mybatis.dart` instead.
library;

// Core
export 'src/sql_session.dart' show SqlSession;
export 'src/sql_session_factory.dart' show SqlSessionFactory;

// Mapper
export 'src/mapper_proxy.dart' show Mapper, MapperProxy, MapperRegistry;

// 어노테이션 (flutter_mybatis_generator 용)
export 'src/annotations.dart'
    show
        MybatisMapper,
        Select,
        SelectOne,
        SelectCount,
        Insert,
        Update,
        Delete,
        Param;

// 표현식 평가기 (OGNL 서브셋)
export 'src/expression.dart' show ExpressionEvaluator, ExpressionException;

// TypeHandler
export 'src/type_handler.dart'
    show
        TypeHandler,
        TypeHandlerRegistry,
        DateTimeTypeHandler,
        DateTimeMillisTypeHandler,
        BoolTypeHandler,
        YnBoolTypeHandler,
        EnumTypeHandler,
        UriTypeHandler;

// 설정
export 'src/mybatis_config.dart' show MybatisConfig;

// Logging
export 'src/logger.dart' show MybatisLogger;
export 'src/log_adapter.dart' show MybatisLogLevel, MybatisLogHandler;

// Exceptions
export 'src/exceptions.dart';

// Advanced
export 'src/xml_sql_parser.dart'
    show
        XmlSqlParser,
        MapperConfig,
        SqlStatement,
        SqlStatementType,
        SelectKeyStatement,
        SelectKeyOrder,
        SqlElement,
        ConditionEvaluator,
        substituteDollar;
export 'src/dynamic_sql_builder.dart' show DynamicSqlBuilder, SqlBuildResult;
export 'src/result_map.dart';
