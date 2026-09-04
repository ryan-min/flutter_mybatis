import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mybatis/flutter_mybatis.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Execution-layer failure semantics.
///
/// Until 1.0.1 a failed statement was logged and turned into an empty list,
/// `-1` or `0`. That made [SqlSession.transaction] unable to roll back: a
/// constraint violation inside a transaction left the earlier statements
/// committed. These tests pin the corrected behaviour.
void main() {
  sqfliteFfiInit();
  // The isolate-backed factory can keep the test runner alive after the last
  // test finishes; the no-isolate factory is the safe choice in tests.
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Database db;
  late SqlSession session;

  const mapperXml = '''
<mapper namespace="T">
  <insert id="ins">INSERT INTO P (ID, NM) VALUES (#{ID}, #{NM})</insert>
  <update id="upd">UPDATE P SET NM = #{NM} WHERE ID = #{ID}</update>
  <delete id="del">DELETE FROM P WHERE ID = #{ID}</delete>
  <select id="all">SELECT * FROM P ORDER BY ID</select>
  <select id="broken">SELECT * FROM NO_SUCH_TABLE</select>
  <update id="brokenUpdate">UPDATE NO_SUCH_TABLE SET A = 1</update>
  <delete id="brokenDelete">DELETE FROM NO_SUCH_TABLE</delete>
</mapper>
''';

  setUp(() async {
    MybatisConfig.reset();
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE P (ID INTEGER PRIMARY KEY, NM TEXT NOT NULL)',
    );
    session = (SqlSessionFactory(db)..loadMapperFromString(mapperXml))
        .openSession();
  });

  tearDown(() async {
    await db.close();
    MybatisConfig.reset();
  });

  group('errors reach the caller', () {
    test('a failing select throws', () {
      expect(session.selectList('T.broken', {}), throwsA(isA<Exception>()));
    });

    test('a failing insert throws', () {
      expect(
        session.insert('T.ins', {'ID': 1, 'NM': null}), // NM is NOT NULL
        throwsA(isA<Exception>()),
      );
    });

    test('a failing update throws', () {
      expect(session.update('T.brokenUpdate', {}), throwsA(isA<Exception>()));
    });

    test('a failing delete throws', () {
      expect(session.delete('T.brokenDelete', {}), throwsA(isA<Exception>()));
    });
  });

  group('transactions roll back', () {
    test('a constraint violation undoes the whole transaction', () async {
      await expectLater(
        session.transaction((tx) async {
          await tx.insert('T.ins', {'ID': 1, 'NM': 'first'});
          // duplicate primary key
          await tx.insert('T.ins', {'ID': 1, 'NM': 'dup'});
        }),
        throwsA(isA<Exception>()),
      );

      // The first insert must not survive.
      expect(await session.selectList('T.all', {}), isEmpty);
    });

    test('a malformed statement undoes the whole transaction', () async {
      await expectLater(
        session.transaction((tx) async {
          await tx.insert('T.ins', {'ID': 1, 'NM': 'first'});
          await tx.selectList('T.broken', {});
        }),
        throwsA(isA<Exception>()),
      );

      expect(await session.selectList('T.all', {}), isEmpty);
    });

    test('a successful transaction still commits', () async {
      await session.transaction((tx) async {
        await tx.insert('T.ins', {'ID': 1, 'NM': 'a'});
        await tx.insert('T.ins', {'ID': 2, 'NM': 'b'});
      });

      expect((await session.selectList('T.all', {})).length, 2);
    });
  });

  group('batchInsert', () {
    test('a bad row rolls back the whole batch', () async {
      await expectLater(
        session.batchInsert('T.ins', [
          {'ID': 1, 'NM': 'a'},
          {'ID': 1, 'NM': 'duplicate'},
        ]),
        throwsA(isA<Exception>()),
      );

      expect(await session.selectList('T.all', {}), isEmpty);
    });
  });

  group('suppressSqlErrors (legacy 0.9.x behaviour)', () {
    setUp(() => MybatisConfig.suppressSqlErrors = true);

    test('select returns an empty list instead of throwing', () async {
      expect(await session.selectList('T.broken', {}), isEmpty);
    });

    test('insert returns -1', () async {
      expect(await session.insert('T.ins', {'ID': 1, 'NM': null}), -1);
    });

    test('update and delete return 0', () async {
      expect(await session.update('T.brokenUpdate', {}), 0);
      expect(await session.delete('T.brokenDelete', {}), 0);
    });

    test('and that is exactly why a failed transaction could commit', () async {
      // Documents the old hazard: with errors suppressed the callback runs to
      // completion, so the earlier insert is committed.
      await session.transaction((tx) async {
        await tx.insert('T.ins', {'ID': 1, 'NM': 'first'});
        await tx.insert('T.ins', {'ID': 1, 'NM': 'dup'}); // swallowed
      });

      expect((await session.selectList('T.all', {})).length, 1);
    });
  });

  test('selectCount returns 0 when the aggregate is SQL NULL', () async {
    // SUM over an empty result set is NULL, not a missing column. That is a
    // count of zero; throwing here was a 1.1.0 regression.
    await db.execute('CREATE TABLE AGG (QTY INTEGER)');
    final s = (SqlSessionFactory(db)
          ..loadMapperFromString('''
<mapper namespace="Agg">
  <select id="sum">SELECT SUM(QTY) AS CNT FROM AGG WHERE QTY &gt; 100</select>
</mapper>
'''))
        .openSession();
    expect(await s.selectCount('Agg.sum', {}), 0);
  });

  test('selectCount still throws when no count column can be found', () async {
    final s = (SqlSessionFactory(db)
          ..loadMapperFromString('''
<mapper namespace="Agg2">
  <select id="two">SELECT 1 AS A, 2 AS B</select>
</mapper>
'''))
        .openSession();
    expect(() => s.selectCount('Agg2.two', {}),
        throwsA(isA<SqlBuildException>()));
  });

  test('a timed-out statement reports that it was not cancelled', () async {
    final f = SqlSessionFactory(db)
      ..loadMapperFromString('''
<mapper namespace="Slow">
  <select id="s" timeout="1">SELECT 1 AS V</select>
</mapper>
''');
    final s = f.openSession();
    // The statement itself is fast; what is pinned here is the exception type
    // and its message, which must not claim the statement was cancelled.
    expect(await s.selectList('Slow.s', {}), isNotEmpty);
    final e = SqlTimeoutException('Slow.s', const Duration(seconds: 1));
    expect(e, isA<TimeoutException>());
    expect(e.message, contains('NOT cancelled'));
  });
}
