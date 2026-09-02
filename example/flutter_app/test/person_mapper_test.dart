import 'dart:io';

import 'package:flutter_mybatis/flutter_mybatis.dart';
import 'package:flutter_mybatis_example/person_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 생성된 Mapper 구현체 테스트
///
/// `person_mapper.g.dart` 는 build_runner가 만든 코드입니다.
/// 이 테스트는 그 생성 코드가 실제 SQLite에서 제대로 동작하는지 확인합니다.
///
/// ```bash
/// dart run build_runner build
/// flutter test
/// ```
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late PersonMapper mapper;

  setUp(() async {
    MybatisConfig.reset();
    TypeHandlerRegistry.reset();

    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(createPersonTable);

    final xml = File('assets/person_mapper.xml').readAsStringSync();
    final factory = SqlSessionFactory(db)..loadMapperFromString(xml);

    // 추상 클래스지만 factory 리다이렉트로 생성 구현체가 만들어진다
    mapper = PersonMapper(factory.openSession());
  });

  tearDown(() async {
    await db.close();
    MybatisConfig.reset();
    TypeHandlerRegistry.reset();
  });

  Future<void> seed() async {
    await mapper.add({
      'NM': '홍길동',
      'AGE': 30,
      'EMAIL': 'hong@example.com',
      'ACTIVE_FL': true,
      'JOIN_DT': DateTime(2026, 1, 1),
    });
    await mapper.add({
      'NM': '김철수',
      'AGE': 20,
      'EMAIL': null,
      'ACTIVE_FL': true,
      'JOIN_DT': DateTime(2026, 2, 1),
    });
    await mapper.add({
      'NM': '이영희',
      'AGE': 40,
      'EMAIL': 'lee@example.com',
      'ACTIVE_FL': false,
      'JOIN_DT': DateTime(2026, 3, 1),
    });
  }

  test('생성 구현체가 PersonMapper 타입이다', () {
    expect(mapper, isA<PersonMapper>());
    expect(mapper, isA<Mapper>());
    expect((mapper as Mapper).namespace, 'PersonMapper');
  });

  group('@Insert', () {
    test('add — useGeneratedKeys로 ID가 채워진다', () async {
      final person = <String, dynamic>{
        'NM': '홍길동',
        'AGE': 30,
        'EMAIL': null,
        'ACTIVE_FL': true,
        'JOIN_DT': null,
      };

      await mapper.add(person);
      expect(person['ID'], 1);
    });

    test('addWithSelectKey — <selectKey>로 직접 채번', () async {
      await seed();

      final person = <String, dynamic>{'NM': '박선영', 'AGE': 25};
      await mapper.addWithSelectKey(person);

      expect(person['ID'], 103); // MAX(ID)=3 + 100
      expect((await mapper.findById(103))!['NM'], '박선영');
    });
  });

  group('@Select / @SelectOne / @SelectCount', () {
    setUp(seed);

    test('search — 조건 없음', () async {
      final rows = await mapper.search({});
      expect(rows.length, 3);
      expect(rows.first['NM'], '이영희'); // ORDER BY ID DESC
    });

    test('search — 이름 부분일치', () async {
      expect((await mapper.search({'NM': '홍'})).length, 1);
    });

    test('search — 숫자 조건 + IN 절 조합', () async {
      final rows = await mapper.search({
        'minAge': 20,
        'ids': [1, 2],
      });
      expect(rows.length, 2);
    });

    test('searchPaged — limit / offset 전달', () async {
      final page1 = await mapper.searchPaged({}, limit: 2);
      expect(page1.length, 2);

      final page2 = await mapper.searchPaged({}, limit: 2, offset: 2);
      expect(page2.length, 1);
    });

    test('findById — @Param("ID")로 키가 매핑된다', () async {
      final row = await mapper.findById(2);
      expect(row, isNotNull);
      expect(row!['NM'], '김철수');

      expect(await mapper.findById(999), isNull);
    });

    test('countAll — @SelectCount', () async {
      expect(await mapper.countAll(false), 3);
      expect(await mapper.countAll(true), 2);
    });

    test('sorted — 여러 @Param', () async {
      final byAge = await mapper.sorted('age', 'ASC');
      expect(byAge.map((r) => r['AGE']), [20, 30, 40]);

      final byName = await mapper.sorted('name', 'DESC');
      expect(byName.first['NM'], '홍길동');
    });
  });

  group('@Update / @Delete', () {
    setUp(seed);

    test('modify — <set>이 넘어온 컬럼만 수정', () async {
      expect(await mapper.modify({'ID': 1, 'AGE': 31}), 1);

      final row = await mapper.findById(1);
      expect(row!['AGE'], 31);
      expect(row['NM'], '홍길동');
    });

    test('remove — 단건', () async {
      expect(await mapper.remove(1), 1);
      expect(await mapper.countAll(false), 2);
    });

    test('removeAll — @Param 리스트로 <foreach>', () async {
      expect(await mapper.removeAll([1, 2]), 2);
      expect(await mapper.countAll(false), 1);
    });
  });
}
