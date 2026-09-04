// source_gen 2.0.0의 Generator API는 아직 구 element 모델(Element/ClassElement)을
// 넘겨줍니다. analyzer 8.x가 이를 deprecated 처리했지만 source_gen이 새 모델
// (Element2)로 올라가기 전까지는 이쪽을 써야 합니다.
// ignore_for_file: deprecated_member_use

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:xml/xml.dart';

/// Reads a mapper XML and returns a `statement id -> tag name` map.
///
/// Used to catch statement id typos and kind mismatches at build time —
/// errors Java MyBatis only reports when the application starts.
Future<Map<String, String>> loadStatements(
  BuildStep buildStep,
  String xmlPath,
  String namespace,
  Element element,
) async {
  final assetId = AssetId(buildStep.inputId.package, xmlPath);

  if (!await buildStep.canRead(assetId)) {
    throw InvalidGenerationSourceError(
      'Cannot read mapper XML: $xmlPath\n'
      'The path is relative to the package root.',
      element: element,
    );
  }

  final content = await buildStep.readAsString(assetId);

  final XmlDocument document;
  try {
    document = XmlDocument.parse(content);
  } on XmlException catch (e) {
    throw InvalidGenerationSourceError(
      'Failed to parse mapper XML: $xmlPath\n$e',
      element: element,
    );
  }

  final mappers = document.findElements('mapper');
  if (mappers.isEmpty) {
    throw InvalidGenerationSourceError(
      'No <mapper> element found in $xmlPath',
      element: element,
    );
  }

  if (mappers.length > 1) {
    throw InvalidGenerationSourceError(
      'A mapper XML must contain exactly one <mapper> element, '
      'but $xmlPath has ${mappers.length}.',
      element: element,
    );
  }

  final mapper = mappers.first;
  final xmlNamespace = mapper.getAttribute('namespace');

  if (xmlNamespace != namespace) {
    throw InvalidGenerationSourceError(
      'Namespace mismatch.\n'
      '  @MybatisMapper: "$namespace"\n'
      '  $xmlPath: "${xmlNamespace ?? '(none)'}"',
      element: element,
    );
  }

  final statements = <String, String>{};
  for (final tag in ['select', 'insert', 'update', 'delete']) {
    for (final node in mapper.findElements(tag)) {
      final id = node.getAttribute('id');
      if (id != null && id.isNotEmpty) {
        statements[id] = tag;
      }
    }
  }

  return statements;
}
