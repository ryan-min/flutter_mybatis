/// flutter_mybatis — XML-based SQL mapping for Flutter/Dart.
///
/// A port of MyBatis: your Java XML mappers work here almost unchanged.
///
/// ## Features
/// - SQL lives in XML files, not in Dart code
/// - Dynamic SQL (`<if>`, `<where>`, `<foreach>`, ...)
/// - Parameter binding with `#{paramName}`
///
/// ## Quick start
/// ```dart
/// // Optional: log level
/// MybatisLogger.setLogLevel(MybatisLogLevel.debug);
///
/// // Create the factory and load mappers
/// final factory = SqlSessionFactory(database);
/// await factory.loadMapper('assets/person_mapper.xml');
///
/// // Run a query
/// final session = factory.openSession();
/// final list = await session.selectList('PersonMapper.selectList', {'NM': 'Hong'});
/// ```
library;

// 코어 전체 (순수 Dart)
export 'flutter_mybatis_core.dart';

// Flutter assets 로딩 (loadMapper / loadMappers)
export 'src/asset_loader.dart';
