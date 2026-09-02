import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mybatis/flutter_mybatis.dart';

/// 실사용 앱 매퍼 회귀 테스트
///
/// 모노레포의 실제 프로젝트(`projects/*/lib/dao/*.xml`)를 전부 파싱해
/// 생성 SQL을 스냅샷과 대조합니다.
///
/// - 스냅샷 파일: `<모노레포>/tool/flutter_mybatis_compat/app_sql_snapshot.json`
///   (앱의 실제 SQL이 담기므로 공개 패키지에 포함하지 않는다)
/// - 스냅샷이 없으면 현재 결과로 생성만 하고 통과합니다(최초 1회).
/// - 프로젝트 디렉터리가 없는 환경(패키지 단독 체크아웃)에서는 skip 합니다.
///
/// 목적: 라이브러리를 고쳐도 기존 앱이 만들어내는 SQL이 한 글자도
/// 바뀌지 않았음을 증명하는 것.
void main() {
  // 스냅샷에는 사내 앱의 실제 SQL이 들어가므로 공개 패키지 밖(모노레포)에 둔다
  const snapshotPath = '../../tool/flutter_mybatis_compat/app_sql_snapshot.json';

  /// statement 하나를 여러 파라미터 조합으로 빌드
  ///
  /// 동적 SQL의 모든 분기를 태우기 위해 3가지 조합을 사용합니다.
  /// - empty: 파라미터 없음 (모든 `<if>` false)
  /// - filled: 파일에 등장하는 모든 `#{key}`에 값 채움 (모든 `<if>` true)
  /// - blank: 모든 키를 빈 문자열로 (`!= ''` 분기 검증)
  ///
  /// 키 수집은 XML 원문 정규식으로 합니다. 구버전/신버전 양쪽에서
  /// 동일하게 동작해야 스냅샷 비교가 성립하기 때문입니다.
  List<Map<String, String>> buildVariants(
    SqlStatement statement,
    Set<String> keys,
  ) {
    final filled = <String, dynamic>{for (final k in keys) k: 'V_$k'};
    final blank = <String, dynamic>{for (final k in keys) k: ''};

    final variants = <Map<String, String>>[];
    for (final entry in <String, Map<String, dynamic>>{
      'empty': <String, dynamic>{},
      'filled': filled,
      'blank': blank,
    }.entries) {
      final built = DynamicSqlBuilder.build(statement, Map.of(entry.value));
      variants.add({
        'variant': entry.key,
        'sql': built.sql,
        'params': built.parameters.map((e) => '$e').join('|'),
      });
    }
    return variants;
  }

  test('실사용 앱 매퍼 17종의 생성 SQL이 스냅샷과 동일하다', () {
    // 패키지 기준 ../../projects
    final projectsDir = Directory('../../projects');
    if (!projectsDir.existsSync()) {
      markTestSkipped('projects 디렉터리 없음 (패키지 단독 체크아웃)');
      return;
    }

    final xmlFiles = projectsDir
        .listSync()
        .whereType<Directory>()
        .expand((project) {
          final dao = Directory('${project.path}/lib/dao');
          if (!dao.existsSync()) return const <File>[];
          return dao.listSync().whereType<File>().where(
                (f) => f.path.endsWith('.xml'),
              );
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(xmlFiles, isNotEmpty, reason: '앱 매퍼 XML을 찾지 못했습니다');

    // 실제 사용 형태와 동일하게: 전 매퍼 로드 → include 연결 → 빌드
    final current = <String, dynamic>{};
    final allFragments = <String, List<SqlElement>>{};
    final allStatements = <String, SqlStatement>{};

    final keysByStatement = <String, Set<String>>{};

    for (final file in xmlFiles) {
      final raw = file.readAsStringSync();
      final config = XmlSqlParser.parse(raw);

      // 파일 단위 파라미터 키 (구버전 하네스와 동일한 수집 방식)
      final fileKeys = RegExp(r'#\{(\w+)\}')
          .allMatches(raw)
          .map((m) => m.group(1)!)
          .toSet();

      allFragments.addAll(config.fragments);
      allStatements.addAll(config.statements);
      for (final id in config.statements.keys) {
        keysByStatement[id] = fileKeys;
      }
    }
    for (final statement in allStatements.values) {
      statement.resolveIncludes(allFragments);
    }

    for (final entry in allStatements.entries) {
      current[entry.key] =
          buildVariants(entry.value, keysByStatement[entry.key]!);
    }

    expect(
      allStatements.length,
      greaterThan(50),
      reason: 'statement 수집이 비정상적으로 적습니다',
    );

    final snapshotFile = File(snapshotPath);
    const encoder = JsonEncoder.withIndent('  ');

    if (!snapshotFile.existsSync()) {
      snapshotFile.parent.createSync(recursive: true);
      snapshotFile.writeAsStringSync(encoder.convert(current));
      // ignore: avoid_print
      print('스냅샷 생성: $snapshotPath (${allStatements.length} statements)');
      return;
    }

    final expected =
        jsonDecode(snapshotFile.readAsStringSync()) as Map<String, dynamic>;

    // statement 단위로 비교해야 실패 지점이 드러남
    expect(
      current.keys.toSet(),
      equals(expected.keys.toSet()),
      reason: 'statement 목록이 달라졌습니다',
    );

    for (final id in expected.keys) {
      expect(
        encoder.convert(current[id]),
        equals(encoder.convert(expected[id])),
        reason: '$id 의 생성 SQL이 달라졌습니다',
      );
    }
  });
}
