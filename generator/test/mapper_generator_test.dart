import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:flutter_mybatis_generator/flutter_mybatis_generator.dart';
import 'package:test/test.dart';

/// MapperGenerator 테스트
///
/// 실제 flutter_mybatis 패키지(= Flutter SDK 의존)를 끌어오지 않도록,
/// 어노테이션과 Mapper의 최소 스텁을 같은 경로
/// (`package:flutter_mybatis/src/annotations.dart`)로 제공합니다.
/// TypeChecker가 클래스를 URL로 식별하기 때문에 가능합니다.
void main() {
  final builder = mapperBuilder(BuilderOptions.empty);

  const annotationsStub = r'''
class MybatisMapper {
  final String namespace;
  final String? xml;
  const MybatisMapper(this.namespace, {this.xml});
}
class Select { final String? id; const Select([this.id]); }
class SelectOne { final String? id; const SelectOne([this.id]); }
class SelectCount {
  final String? id;
  final String column;
  const SelectCount([this.id, this.column = 'CNT']);
}
class Insert { final String? id; const Insert([this.id]); }
class Update { final String? id; const Update([this.id]); }
class Delete { final String? id; const Delete([this.id]); }
class Param { final String name; const Param(this.name); }
''';

  const mapperStub = r'''
class SqlSession {
  Future<List<Map<String, dynamic>>> selectList(
      String id, Map<String, dynamic> p, {int? limit, int? offset}) async => [];
  Future<Map<String, dynamic>?> selectOne(
      String id, Map<String, dynamic> p) async => null;
  Future<int> selectCount(
      String id, Map<String, dynamic> p, {String countColumn = 'CNT'}) async => 0;
  Future<int> insert(String id, Map<String, dynamic> p) async => 0;
  Future<int> update(String id, Map<String, dynamic> p) async => 0;
  Future<int> delete(String id, Map<String, dynamic> p) async => 0;
}

abstract class Mapper {
  Mapper(this.session);
  final SqlSession session;
  String get namespace => runtimeType.toString();
}
''';

  const barrelStub = r'''
export 'src/annotations.dart';
export 'src/mapper.dart';
''';

  final packageAssets = <String, String>{
    'flutter_mybatis|lib/src/annotations.dart': annotationsStub,
    'flutter_mybatis|lib/src/mapper.dart': mapperStub,
    'flutter_mybatis|lib/flutter_mybatis.dart': barrelStub,
  };

  const personXml = '''
<mapper namespace="PersonMapper">
  <select id="selectList">SELECT * FROM PERSON</select>
  <select id="selectById">SELECT * FROM PERSON WHERE ID = #{ID}</select>
  <select id="selectCount">SELECT COUNT(*) AS CNT FROM PERSON</select>
  <insert id="insert">INSERT INTO PERSON (NM) VALUES (#{NM})</insert>
  <update id="update">UPDATE PERSON SET NM = #{NM} WHERE ID = #{ID}</update>
  <delete id="delete">DELETE FROM PERSON WHERE ID = #{ID}</delete>
</mapper>
''';

  /// 공백 제거 — dart_style이 줄바꿈 위치를 바꿔도 검증이 깨지지 않게
  String squash(String value) => value.replaceAll(RegExp(r'\s+'), '');

  /// 공백을 무시하고 코드 조각 포함 여부 확인
  Matcher hasCode(String snippet) => contains(squash(snippet));

  /// 빌더 실행 결과
  ///
  /// 생성 실패는 예외가 아니라 로그로 보고되므로 [errors]로 받는다.
  Future<({String code, List<String> errors})> build(
    String source, {
    String? xml,
  }) async {
    final assets = <String, String>{
      ...packageAssets,
      'a|lib/person_mapper.dart': source,
      // build_test 리더는 lib/ 아래 자산만 읽는다 (실제 build_runner는 루트도 가능)
      if (xml != null) 'a|lib/person_mapper.xml': xml,
    };

    final errors = <String>[];
    final result = await testBuilder(
      builder,
      assets,
      generateFor: {'a|lib/person_mapper.dart'},
      onLog: (record) {
        if (record.level.name == 'SEVERE') {
          errors.add('${record.message} ${record.error ?? ''}');
        }
      },
    );

    final generated = result.readerWriter.testing.assets
        .where((a) => a.path.endsWith('.flutter_mybatis.g.part'));

    final code = generated.isEmpty
        ? ''
        : await result.readerWriter.readAsString(generated.first);

    return (code: squash(code), errors: errors);
  }

  /// 빌드가 실패하고 오류 메시지에 [expected] 조각이 담기는지 확인
  Future<void> expectBuildError(
    String source, {
    String? xml,
    required List<String> expected,
  }) async {
    final result = await build(source, xml: xml);

    expect(result.errors, isNotEmpty, reason: '오류 메시지가 없습니다');

    final joined = result.errors.join('\n');
    for (final fragment in expected) {
      expect(joined, contains(fragment));
    }
  }

  group('구현 생성', () {
    test('메서드 종류별로 알맞은 SqlSession 호출을 만든다', () async {
      final generated = (await build('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  factory PersonMapper(SqlSession session) = _\$PersonMapper;

  @Select('selectList')
  Future<List<Map<String, dynamic>>> search(Map<String, dynamic> params);

  @SelectOne('selectById')
  Future<Map<String, dynamic>?> findById(@Param('ID') int id);

  @SelectCount('selectCount')
  Future<int> countAll();

  @Insert('insert')
  Future<int> add(Map<String, dynamic> person);

  @Update('update')
  Future<int> modify(Map<String, dynamic> person);

  @Delete('delete')
  Future<int> remove(@Param('ID') int id);
}
''')).code;

      expect(
        generated,
        hasCode(r'class _$PersonMapper extends Mapper implements PersonMapper'),
      );
      expect(generated, hasCode("String get namespace => 'PersonMapper';"));
      expect(generated, hasCode("session.selectList('PersonMapper.selectList', params)"));
      expect(generated, hasCode("session.selectOne('PersonMapper.selectById'"));
      expect(generated, hasCode("session.selectCount('PersonMapper.selectCount'"));
      expect(generated, hasCode("countColumn: 'CNT'"));
      expect(generated, hasCode("session.insert('PersonMapper.insert', person)"));
      expect(generated, hasCode("session.update('PersonMapper.update', person)"));
      expect(generated, hasCode("session.delete('PersonMapper.delete'"));
    });

    test('@Param 이름으로 Map을 조립한다', () async {
      final generated = (await build('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  @SelectOne('selectById')
  Future<Map<String, dynamic>?> findById(@Param('ID') int id);
}
''')).code;

      expect(generated, hasCode("<String, dynamic>{'ID': id}"));
    });

    test('@Param이 없으면 파라미터명을 키로 쓴다', () async {
      final generated = (await build('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  @SelectOne('selectById')
  Future<Map<String, dynamic>?> findById(int ID);
}
''')).code;

      expect(generated, hasCode("<String, dynamic>{'ID': ID}"));
    });

    test('statement id를 생략하면 메서드명을 쓴다', () async {
      final generated = (await build('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  @Select()
  Future<List<Map<String, dynamic>>> selectList(Map<String, dynamic> params);
}
''')).code;

      expect(generated, hasCode("session.selectList('PersonMapper.selectList'"));
    });

    test('limit / offset은 그대로 전달한다', () async {
      final generated = (await build('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  @Select('selectList')
  Future<List<Map<String, dynamic>>> paged(
    Map<String, dynamic> params, {
    int? limit,
    int? offset,
  });
}
''')).code;

      expect(generated, hasCode('limit: limit'));
      expect(generated, hasCode('offset: offset'));
      // 페이징 인자는 파라미터 Map에 들어가면 안 된다
      expect(generated, isNot(hasCode("'limit': limit")));
    });

    test('@Update 에서 limit 은 일반 파라미터로 남는다', () async {
      // 예전에는 이름만 보고 페이징 인자로 가로채서 statement 에서 사라졌다.
      final generated = (await build('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  @Update('updateQuota')
  Future<int> updateQuota(@Param('limit') int limit);
}
''')).code;

      expect(generated, hasCode("<String, dynamic>{'limit': limit}"));
      expect(generated, isNot(hasCode('limit: limit')));
    });

    test('@SelectCount의 column 지정', () async {
      final generated = (await build('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  @SelectCount('selectCount', 'TOTAL')
  Future<int> countAll();
}
''')).code;

      expect(generated, hasCode("countColumn: 'TOTAL'"));
    });

    test('파라미터가 없으면 빈 Map을 넘긴다', () async {
      final generated = (await build('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  @Select('selectList')
  Future<List<Map<String, dynamic>>> all();
}
''')).code;

      expect(generated, hasCode('const <String, dynamic>{}'));
    });
  });

  group('XML 검증 (빌드 시점)', () {
    const valid = '''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper', xml: 'lib/person_mapper.xml')
abstract class PersonMapper {
  @Select('selectList')
  Future<List<Map<String, dynamic>>> search(Map<String, dynamic> params);
}
''';

    test('XML에 있는 statement면 통과', () async {
      final result = await build(valid, xml: personXml);
      expect(result.errors, isEmpty);
      expect(
        result.code,
        hasCode("session.selectList('PersonMapper.selectList'"),
      );
    });

    test('없는 statement id는 빌드 실패', () async {
      await expectBuildError('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper', xml: 'lib/person_mapper.xml')
abstract class PersonMapper {
  @Select('selectLst')
  Future<List<Map<String, dynamic>>> search(Map<String, dynamic> params);
}
''', xml: personXml, expected: [
        'Statement not found in XML',
        'PersonMapper.selectLst',
        // 사용 가능한 id 목록도 함께 보여준다
        'selectList',
      ]);
    });

    test('statement 종류가 다르면 빌드 실패', () async {
      await expectBuildError('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper', xml: 'lib/person_mapper.xml')
abstract class PersonMapper {
  @Insert('selectList')
  Future<int> add(Map<String, dynamic> person);
}
''', xml: personXml, expected: ['Statement kind mismatch', 'select', 'insert']);
    });

    test('namespace가 XML과 다르면 빌드 실패', () async {
      await expectBuildError('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('OtherMapper', xml: 'lib/person_mapper.xml')
abstract class OtherMapper {
  @Select('selectList')
  Future<List<Map<String, dynamic>>> search(Map<String, dynamic> params);
}
''', xml: personXml, expected: ['Namespace mismatch', 'OtherMapper']);
    });

    test('XML 파일이 없으면 빌드 실패', () async {
      await expectBuildError(valid, expected: ['Cannot read mapper XML']);
    });

    test('xml을 지정하지 않으면 검증을 건너뛴다', () async {
      final result = await build('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  @Select('anyIdWithoutXml')
  Future<List<Map<String, dynamic>>> search(Map<String, dynamic> params);
}
''');

      expect(result.errors, isEmpty);
      expect(result.code, hasCode("'PersonMapper.anyIdWithoutXml'"));
    });
  });

  group('잘못된 선언', () {
    test('statement 어노테이션이 없으면 빌드 실패', () async {
      await expectBuildError('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
abstract class PersonMapper {
  Future<int> mystery(Map<String, dynamic> params);
}
''', expected: ['@Select']);
    });

    test('abstract가 아니면 빌드 실패', () async {
      await expectBuildError('''
import 'package:flutter_mybatis/flutter_mybatis.dart';
part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper')
class PersonMapper {}
''', expected: ['abstract']);
    });
  });
}
