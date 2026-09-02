import 'package:flutter/services.dart';

import 'exceptions.dart';
import 'logger.dart';
import 'sql_session_factory.dart';

/// Loads mapper XML from Flutter assets.
///
/// The core (`flutter_mybatis_core.dart`) is pure Dart; only asset loading
/// depends on Flutter, and it lives here.
extension SqlSessionFactoryAssets on SqlSessionFactory {
  /// Loads one mapper XML from an asset path.
  ///
  /// The file must be declared under `flutter: assets:` in pubspec.yaml.
  ///
  /// For example:
  /// - 'lib/dao/person_mapper.xml'
  /// - 'assets/person_mapper.xml'
  Future<void> loadMapper(String assetPath) async {
    try {
      final xmlContent = await rootBundle.loadString(assetPath);
      loadMapperFromString(xmlContent, source: assetPath);
    } catch (e) {
      throw MapperLoadException('Failed to load mapper XML', path: assetPath, cause: e);
    }
  }

  /// Loads several mapper XML files.
  Future<void> loadMappers(List<String> assetPaths) async {
    for (final path in assetPaths) {
      await loadMapper(path);
    }

    MybatisLogger.logInit(registeredMappers.length, registeredStatements.length);
  }
}
