import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mybatis/flutter_mybatis.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 예제 매퍼 End-to-End 테스트
///
/// `example/flutter_app/assets/person_mapper.xml` 을 **실제 SQLite(in-memory)** 에 붙여
/// 끝까지 실행합니다. SQL 문자열 생성만 검증하는 다른 테스트와 달리,
/// 여기서는 쿼리가 실제로 실행되고 결과가 맞는지까지 확인합니다.
///
/// 예제가 깨지면 이 테스트가 먼저 실패합니다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqlSession session;

  const createTable = '''
CREATE TABLE PERSON (
  ID        INTEGER PRIMARY KEY AUTOINCREMENT,
  NM        TEXT    NOT NULL,
  AGE       INTEGER,
  EMAIL     TEXT,
  ACTIVE_FL INTEGER NOT NULL DEFAULT 1,
  JOIN_DT   TEXT
)
''';

  setUp(() async {
    MybatisConfig.reset();
    TypeHandlerRegistry.reset();
    ExpressionEvaluator.clearCache();

    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(createTable);

    // 예제와 동일한 매퍼 XML을 그대로 사용
    final xml = File('example/flutter_app/assets/person_mapper.xml').readAsStringSync();
    final factory = SqlSessionFactory(db)..loadMapperFromString(xml);
    session = factory.openSession();
  });

  tearDown(() async {
    await db.close();
    MybatisConfig.reset();
    TypeHandlerRegistry.reset();
  });

  /// 샘플 데이터 3건
  Future<void> seed() async {
    await session.insert('PersonMapper.insert', {
      'NM': '홍길동',
      'AGE': 30,
      'EMAIL': 'hong@example.com',
      'ACTIVE_FL': true,
      'JOIN_DT': DateTime(2026, 1, 1),
    });
    await session.insert('PersonMapper.insert', {
      'NM': '김철수',
      'AGE': 20,
      'EMAIL': null,
      'ACTIVE_FL': true,
      'JOIN_DT': DateTime(2026, 2, 1),
    });
    await session.insert('PersonMapper.insert', {
      'NM': '이영희',
      'AGE': 40,
      'EMAIL': 'lee@example.com',
      'ACTIVE_FL': false,
      'JOIN_DT': DateTime(2026, 3, 1),
    });
  }

  group('INSERT', () {
    test('useGeneratedKeys로 생성 ID가 파라미터에 채워진다', () async {
      final person = <String, dynamic>{
        'NM': '홍길동',
        'AGE': 30,
        'EMAIL': 'hong@example.com',
        'ACTIVE_FL': true,
        'JOIN_DT': DateTime(2026, 1, 1),
      };

      await session.insert('PersonMapper.insert', person);

      expect(person['ID'], isNotNull);
      expect(person['ID'], 1);
    });

    test('TypeHandler가 bool과 DateTime을 변환해 저장한다', () async {
      await session.insert('PersonMapper.insert', {
        'NM': '홍길동',
        'AGE': 30,
        'EMAIL': null,
        'ACTIVE_FL': true, // bool -> 1
        'JOIN_DT': DateTime(2026, 1, 1), // DateTime -> ISO8601
      });

      final row = (await db.rawQuery('SELECT * FROM PERSON')).first;
      expect(row['ACTIVE_FL'], 1);
      expect(row['JOIN_DT'], '2026-01-01T00:00:00.000');
    });

    test('YnBoolTypeHandler로 교체하면 Y/N으로 저장된다', () async {
      TypeHandlerRegistry.register(const YnBoolTypeHandler());

      await session.insert('PersonMapper.insert', {
        'NM': '홍길동',
        'AGE': 30,
        'EMAIL': null,
        'ACTIVE_FL': true,
        'JOIN_DT': null,
      });

      final row = (await db.rawQuery('SELECT ACTIVE_FL FROM PERSON')).first;
      expect(row['ACTIVE_FL'], 'Y');
    });

    test('<selectKey order="BEFORE">로 ID를 직접 채번한다', () async {
      await seed();

      final person = <String, dynamic>{'NM': '박선영', 'AGE': 25};
      await session.insert('PersonMapper.insertWithSelectKey', person);

      // MAX(ID)=3 이므로 3 + 100 = 103
      expect(person['ID'], 103);

      final saved = await session.selectOne('PersonMapper.selectById', {'ID': 103});
      expect(saved, isNotNull);
      expect(saved!['NM'], '박선영');
    });
  });

  group('SELECT — 동적 SQL', () {
    setUp(seed);

    test('조건이 없으면 WHERE 절 자체가 사라진다', () async {
      final rows = await session.selectList('PersonMapper.selectList', {});
      expect(rows.length, 3);
      // ORDER BY ID DESC
      expect(rows.first['NM'], '이영희');
    });

    test('<if> 이름 부분일치', () async {
      final rows = await session.selectList('PersonMapper.selectList', {'NM': '홍'});
      expect(rows.length, 1);
      expect(rows.first['NM'], '홍길동');
    });

    test('<if> 숫자 비교 (0.11 표현식 파서)', () async {
      final rows =
          await session.selectList('PersonMapper.selectList', {'minAge': 30});
      expect(rows.map((r) => r['NM']), containsAll(['홍길동', '이영희']));
      expect(rows.length, 2);
    });

    test('minAge가 0이면 조건이 붙지 않는다 (minAge > 0)', () async {
      final rows =
          await session.selectList('PersonMapper.selectList', {'minAge': 0});
      expect(rows.length, 3);
    });

    test('<foreach> IN 절 — ids.size() > 0 조건 포함', () async {
      final rows = await session.selectList('PersonMapper.selectList', {
        'ids': [1, 3],
      });
      expect(rows.length, 2);
      expect(rows.map((r) => r['ID']), containsAll([1, 3]));
    });

    test('빈 목록이면 IN 절이 생성되지 않는다', () async {
      final rows = await session.selectList('PersonMapper.selectList', {
        'ids': <int>[],
      });
      expect(rows.length, 3);
    });

    test('<include> + <property>로 활성만 조회', () async {
      final rows = await session.selectList('PersonMapper.selectList', {
        'activeOnly': true,
      });
      expect(rows.length, 2);
      expect(rows.every((r) => r['ACTIVE_FL'] == 1), isTrue);
    });

    test('조건 여러 개 조합', () async {
      final rows = await session.selectList('PersonMapper.selectList', {
        'minAge': 25,
        'activeOnly': true,
      });
      expect(rows.length, 1);
      expect(rows.first['NM'], '홍길동');
    });

    test('selectOne / selectCount', () async {
      final one = await session.selectOne('PersonMapper.selectById', {'ID': 2});
      expect(one!['NM'], '김철수');

      expect(await session.selectCount('PersonMapper.selectCount', {}), 3);
      expect(
        await session.selectCount('PersonMapper.selectCount', {'activeOnly': true}),
        2,
      );
    });

    test('<choose> + \${} 동적 정렬', () async {
      final byAge = await session.selectList('PersonMapper.selectSorted', {
        'sortBy': 'age',
        'sortDir': 'ASC',
      });
      expect(byAge.map((r) => r['AGE']), [20, 30, 40]);

      final byName = await session.selectList('PersonMapper.selectSorted', {
        'sortBy': 'name',
        'sortDir': 'DESC',
      });
      expect(byName.first['NM'], '홍길동');
    });
  });

  group('UPDATE / DELETE', () {
    setUp(seed);

    test('<set>은 넘어온 컬럼만 수정한다', () async {
      final affected = await session.update('PersonMapper.update', {
        'ID': 1,
        'AGE': 31,
      });
      expect(affected, 1);

      final row = await session.selectOne('PersonMapper.selectById', {'ID': 1});
      expect(row!['AGE'], 31);
      expect(row['NM'], '홍길동'); // 건드리지 않은 컬럼은 그대로
      expect(row['EMAIL'], 'hong@example.com');
    });

    test('단건 삭제', () async {
      expect(await session.delete('PersonMapper.delete', {'ID': 1}), 1);
      expect(await session.selectCount('PersonMapper.selectCount', {}), 2);
    });

    test('<foreach>로 여러 건 삭제', () async {
      final affected = await session.delete('PersonMapper.deleteByIds', {
        'ids': [1, 2],
      });
      expect(affected, 2);
      expect(await session.selectCount('PersonMapper.selectCount', {}), 1);
    });
  });

  group('트랜잭션', () {
    test('예외가 나면 롤백된다', () async {
      await seed();

      try {
        await session.transaction((tx) async {
          await tx.delete('PersonMapper.delete', {'ID': 1});
          throw StateError('의도적 실패');
        });
      } catch (_) {
        // 무시
      }

      // 롤백되어 3건 그대로
      expect(await session.selectCount('PersonMapper.selectCount', {}), 3);
    });

    test('정상 종료되면 커밋된다', () async {
      await seed();

      await session.transaction((tx) async {
        await tx.delete('PersonMapper.delete', {'ID': 1});
        await tx.delete('PersonMapper.delete', {'ID': 2});
      });

      expect(await session.selectCount('PersonMapper.selectCount', {}), 1);
    });
  });

  group('mapUnderscoreToCamelCase', () {
    test('켜면 결과 키가 카멜케이스로 바뀐다', () async {
      await seed();

      MybatisConfig.mapUnderscoreToCamelCase = true;
      final rows = await session.selectList('PersonMapper.selectList', {});

      expect(rows.first.containsKey('activeFl'), isTrue);
      expect(rows.first.containsKey('joinDt'), isTrue);
      expect(rows.first.containsKey('ACTIVE_FL'), isFalse);
      expect(rows.first['nm'], '이영희');
    });
  });

  group('strictExpressions', () {
    test('예제 매퍼의 모든 test 표현식이 strict 모드를 통과한다', () async {
      MybatisConfig.strictExpressions = true;
      await seed();

      // 예제가 쓰는 모든 분기를 태운다
      await session.selectList('PersonMapper.selectList', {});
      await session.selectList('PersonMapper.selectList', {
        'NM': '홍',
        'minAge': 20,
        'ids': [1, 2],
        'activeOnly': true,
      });
      await session.selectList('PersonMapper.selectSorted', {'sortBy': 'age'});
      await session.selectCount('PersonMapper.selectCount', {'activeOnly': true});

      // 여기까지 예외 없이 도달하면 통과
      expect(true, isTrue);
    });
  });
}
