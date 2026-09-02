import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mybatis/flutter_mybatis.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQL generation edge cases found in review of 1.0.2.
///
/// Each group pins a behaviour that was demonstrably wrong before 1.1.0.
void main() {
  sqfliteFfiInit();
  // The isolate-backed factory can keep the test runner alive after the last
  // test finishes; the no-isolate factory is the safe choice in tests.
  databaseFactory = databaseFactoryFfiNoIsolate;

  setUp(() {
    MybatisConfig.reset();
    ExpressionEvaluator.clearCache();
  });
  tearDown(MybatisConfig.reset);

  SqlStatement parse(String xml, String id) {
    final config = XmlSqlParser.parse(xml);
    for (final s in config.statements.values) {
      s.resolveIncludes(config.fragments);
    }
    return config.statements[id]!;
  }

  group('string literals survive whitespace tidying', () {
    test('inner spacing is preserved', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">SELECT 'hello   world' AS V, '  padded  ' AS W</select>
</mapper>
''';
      final sql = DynamicSqlBuilder.build(parse(xml, 'T.s'), {}).sql;

      expect(sql, contains("'hello   world'"));
      expect(sql, contains("'  padded  '"));
    });

    test('a LIKE pattern keeps its spaces', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P WHERE NM LIKE '%a  b%'</select>
</mapper>
''';
      expect(
        DynamicSqlBuilder.build(parse(xml, 'T.s'), {}).sql,
        contains("'%a  b%'"),
      );
    });

    test('SQL outside literals is still tidied', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">
    SELECT   *
    FROM     P
  </select>
</mapper>
''';
      expect(
        DynamicSqlBuilder.build(parse(xml, 'T.s'), {}).sql,
        'SELECT * FROM P',
      );
    });
  });

  group('#{} with MyBatis attributes', () {
    const xml = '''
<mapper namespace="T">
  <select id="s">
    SELECT * FROM P
    WHERE ID = #{ID, jdbcType=INTEGER} AND NM = #{user.name, javaType=String}
  </select>
</mapper>
''';

    test('jdbcType and javaType are ignored, the property still binds', () {
      final built = DynamicSqlBuilder.build(parse(xml, 'T.s'), {
        'ID': 7,
        'user': {'name': 'Hong'},
      });

      expect(built.sql, 'SELECT * FROM P WHERE ID = ? AND NM = ?');
      expect(built.parameters, [7, 'Hong']);
    });
  });

  group('<foreach> item properties', () {
    test('#{item.prop} binds per row — the bulk insert pattern', () {
      const xml = '''
<mapper namespace="T">
  <insert id="bulk">
    INSERT INTO P (ID, NM) VALUES
    <foreach collection="rows" item="r" separator=",">(#{r.id}, #{r.nm})</foreach>
  </insert>
</mapper>
''';
      final built = DynamicSqlBuilder.build(parse(xml, 'T.bulk'), {
        'rows': [
          {'id': 10, 'nm': 'x'},
          {'id': 11, 'nm': 'y'},
        ],
      });

      expect(built.parameters, [10, 'x', 11, 'y']);
    });

    test('a scalar #{item} still binds', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">
    SELECT * FROM P WHERE ID IN
    <foreach collection="ids" item="i" open="(" close=")" separator=",">#{i}</foreach>
  </select>
</mapper>
''';
      final built = DynamicSqlBuilder.build(parse(xml, 'T.s'), {
        'ids': [1, 2, 3],
      });
      expect(built.parameters, [1, 2, 3]);
    });

    test('collection accepts a nested path', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">
    SELECT * FROM P WHERE ID IN
    <foreach collection="req.ids" item="i" open="(" close=")" separator=",">#{i}</foreach>
  </select>
</mapper>
''';
      final built = DynamicSqlBuilder.build(parse(xml, 'T.s'), {
        'req': {
          'ids': [4, 5]
        },
      });
      expect(built.parameters, [4, 5]);
    });
  });

  group('paging', () {
    const xml = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P</select>
</mapper>
''';

    test('offset without limit produces valid SQLite', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE P (ID INTEGER PRIMARY KEY)');
      for (var i = 1; i <= 5; i++) {
        await db.insert('P', {'ID': i});
      }

      final session =
          (SqlSessionFactory(db)..loadMapperFromString(xml)).openSession();

      // Would have been "SELECT * FROM P OFFSET ?", a syntax error.
      final rows = await session.selectList('T.s', {}, offset: 2);
      expect(rows.length, 3);

      await db.close();
    });
  });

  group('selectOne does not rewrite the statement', () {
    test('a statement that already ends in LIMIT still runs', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE P (ID INTEGER PRIMARY KEY)');
      await db.insert('P', {'ID': 1});
      await db.insert('P', {'ID': 2});

      const limited = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P ORDER BY ID LIMIT 1</select>
</mapper>
''';
      final session =
          (SqlSessionFactory(db)..loadMapperFromString(limited)).openSession();

      // Would have been "... LIMIT 1 LIMIT ?", a syntax error.
      expect((await session.selectOne('T.s', {}))!['ID'], 1);

      await db.close();
    });
  });

  group('selectCount with mapUnderscoreToCamelCase', () {
    test('finds the count even though CNT became cnt', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE P (ID INTEGER PRIMARY KEY)');
      await db.insert('P', {'ID': 1});
      await db.insert('P', {'ID': 2});

      const xml = '''
<mapper namespace="T">
  <select id="cnt">SELECT COUNT(*) AS CNT FROM P</select>
</mapper>
''';
      final session =
          (SqlSessionFactory(db)..loadMapperFromString(xml)).openSession();

      expect(await session.selectCount('T.cnt', {}), 2);

      MybatisConfig.mapUnderscoreToCamelCase = true;
      expect(await session.selectCount('T.cnt', {}), 2); // was 0

      await db.close();
    });
  });

  group('duplicate ids across mapper files', () {
    test('the same qualified statement id is rejected', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      final factory = SqlSessionFactory(db)
        ..loadMapperFromString(
            '<mapper namespace="D"><select id="x">SELECT 1</select></mapper>');

      expect(
        () => factory.loadMapperFromString(
            '<mapper namespace="D"><select id="x">SELECT 2</select></mapper>'),
        throwsA(isA<MapperLoadException>()),
      );

      await db.close();
    });

    test('the same qualified <sql> id is rejected', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      final factory = SqlSessionFactory(db)
        ..loadMapperFromString('<mapper namespace="D"><sql id="c">A</sql>'
            '<select id="a">SELECT 1</select></mapper>');

      expect(
        () => factory.loadMapperFromString(
            '<mapper namespace="D"><sql id="c">B</sql>'
            '<select id="b">SELECT 2</select></mapper>'),
        throwsA(isA<MapperLoadException>()),
      );

      await db.close();
    });
  });

  group('strictExpressions defaults to true', () {
    test('an unreadable condition throws instead of erasing the WHERE', () {
      // The dangerous shape: a guarded DELETE whose guard silently vanishes.
      const xml = '''
<mapper namespace="T">
  <delete id="d">
    DELETE FROM P
    <where><if test="@Const@ACTIVE == STS">ID = #{ID}</if></where>
  </delete>
</mapper>
''';
      expect(
        () => DynamicSqlBuilder.build(parse(xml, 'T.d'), {'ID': 1}),
        throwsA(isA<UnsupportedExpressionException>()),
      );
    });

    test('turning it off restores the old, dangerous behaviour', () {
      MybatisConfig.strictExpressions = false;
      const xml = '''
<mapper namespace="T">
  <delete id="d">
    DELETE FROM P
    <where><if test="@Const@ACTIVE == STS">ID = #{ID}</if></where>
  </delete>
</mapper>
''';
      // Documents why the default changed: the guard disappears entirely.
      expect(
        DynamicSqlBuilder.build(parse(xml, 'T.d'), {'ID': 1}).sql,
        'DELETE FROM P',
      );
    });
  });
}
