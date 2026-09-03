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

  /// Wraps [body] in a mapper, builds statement `T.s` and returns the result.
  SqlBuildResult buildResult(String body, Map<String, dynamic> params) =>
      DynamicSqlBuilder.build(
          parse('<mapper namespace="T">$body</mapper>', 'T.s'), params);

  String buildSql(String body, Map<String, dynamic> params) =>
      buildResult(body, params).sql;

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

  group('SQL comments', () {
    test('a line comment does not swallow the rest of the statement', () {
      // Newlines are collapsed, so "-- note" would comment out the WHERE and
      // an UPDATE would hit every row.
      const xml = '''
<mapper namespace="T">
  <update id="u">
    UPDATE ACCOUNT SET ACTIVE = 0
    -- deactivate stale accounts only
    WHERE LAST_SEEN &lt; #{cutoff}
  </update>
</mapper>
''';
      final sql = DynamicSqlBuilder.build(parse(xml, 'T.u'), {'cutoff': 'x'}).sql;

      expect(sql, contains('WHERE'));
      expect(sql, isNot(contains('--')));
      expect(sql, 'UPDATE ACCOUNT SET ACTIVE = 0 WHERE LAST_SEEN < ?');
    });

    test('a block comment is removed', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">SELECT ID /* the id */, NM FROM P</select>
</mapper>
''';
      expect(
        DynamicSqlBuilder.build(parse(xml, 'T.s'), {}).sql,
        'SELECT ID, NM FROM P',
      );
    });

    test('a double dash inside a literal is not a comment', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P WHERE NM = '--not a comment' AND ID = 1</select>
</mapper>
''';
      final sql = DynamicSqlBuilder.build(parse(xml, 'T.s'), {}).sql;
      expect(sql, contains("'--not a comment'"));
      expect(sql, contains('AND ID = 1'));
    });

    test('a quoted identifier keeps its spacing', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">SELECT "my  col" FROM P</select>
</mapper>
''';
      expect(
        DynamicSqlBuilder.build(parse(xml, 'T.s'), {}).sql,
        contains('"my  col"'),
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

    test('a scalar item with jdbcType still binds — #{i,jdbcType=...}', () {
      // The rewrite used to accept only "." or "[" after the item name, so an
      // attribute suffix left the placeholder pointing at a removed variable
      // and every value bound null.
      const xml = '''
<mapper namespace="T">
  <select id="s">
    SELECT * FROM P WHERE ID IN
    <foreach collection="ids" item="i" open="(" close=")" separator=",">
      #{i,jdbcType=INTEGER}
    </foreach>
  </select>
</mapper>
''';
      final built = DynamicSqlBuilder.build(parse(xml, 'T.s'), {
        'ids': [1, 2, 3],
      });
      expect(built.parameters, [1, 2, 3]);
    });

    test('an item property with jdbcType binds', () {
      const xml = '''
<mapper namespace="T">
  <insert id="b">
    INSERT INTO P (ID, NM) VALUES
    <foreach collection="rows" item="r" separator=",">(#{r.id,jdbcType=INTEGER}, #{r.nm})</foreach>
  </insert>
</mapper>
''';
      final built = DynamicSqlBuilder.build(parse(xml, 'T.b'), {
        'rows': [
          {'id': 7, 'nm': 'x'}
        ],
      });
      expect(built.parameters, [7, 'x']);
    });

    test('the index variable with jdbcType binds', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">
    SELECT * FROM P WHERE
    <foreach collection="cond" index="k" item="v" separator=" AND ">\${k} = #{v,jdbcType=VARCHAR}</foreach>
  </select>
</mapper>
''';
      final built = DynamicSqlBuilder.build(parse(xml, 'T.s'), {
        'cond': {'NM': 'Hong'},
      });
      expect(built.parameters, ['Hong']);
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

  // A comment used to be removed only after every element had been joined into
  // one line, so `-- note` swallowed whatever element followed it. These cases
  // put the comment and the victim in *different* nodes, which is the shape
  // that slipped through before.
  group('SQL comments across element boundaries', () {
    test('a line comment does not swallow the following <where>', () {
      final sql = buildSql('''
        <update id="s">
          UPDATE ACCOUNT SET ACTIVE = 0
          -- only accounts that went quiet
          <where><if test="d != null">LAST_SEEN &lt; #{d}</if></where>
        </update>
      ''', {'d': '2025-01-01'});
      expect(sql, 'UPDATE ACCOUNT SET ACTIVE = 0 WHERE LAST_SEEN < ?');
    });

    test('a line comment does not swallow a <foreach> separator', () {
      final result = buildResult('''
        <select id="s">
          SELECT * FROM P WHERE ID IN
          <foreach collection="ids" item="i" open="(" close=")" separator=",">
            #{i} -- one element
          </foreach>
        </select>
      ''', {'ids': [1, 2, 3]});
      expect(result.sql, 'SELECT * FROM P WHERE ID IN (?,?,?)');
      expect(result.parameters, [1, 2, 3]);
    });

    test('a block comment between elements is removed', () {
      final sql = buildSql('''
        <select id="s">
          SELECT * FROM P
          /* pick one */
          <where><if test="id != null">ID = #{id}</if></where>
        </select>
      ''', {'id': 1});
      expect(sql, 'SELECT * FROM P WHERE ID = ?');
    });
  });

  group('<trim>', () {
    test('prefix is separated from the body', () {
      final sql = buildSql('''
        <select id="s">
          SELECT * FROM P
          <trim prefix="WHERE" prefixOverrides="AND |OR ">
            AND ID = #{id}
          </trim>
        </select>
      ''', {'id': 1});
      expect(sql, 'SELECT * FROM P WHERE ID = ?');
    });

    test('whitespace in prefixOverrides is significant: ORDER_ID survives', () {
      final sql = buildSql('''
        <select id="s">
          SELECT * FROM P
          <trim prefix="WHERE" prefixOverrides="AND |OR ">
            ORDER_ID = #{id}
          </trim>
        </select>
      ''', {'id': 1});
      expect(sql, 'SELECT * FROM P WHERE ORDER_ID = ?');
    });

    test('suffixOverrides strips a trailing comma, suffix is spaced', () {
      final sql = buildSql('''
        <update id="s">
          UPDATE P
          <trim prefix="SET" suffixOverrides=",">
            NM = #{nm},
          </trim>
          WHERE ID = #{id}
        </update>
      ''', {'nm': 'x', 'id': 1});
      expect(sql, 'UPDATE P SET NM = ? WHERE ID = ?');
    });

    test('an empty body drops prefix and suffix', () {
      final sql = buildSql('''
        <select id="s">
          SELECT * FROM P
          <trim prefix="WHERE" prefixOverrides="AND |OR ">
            <if test="id != null">AND ID = #{id}</if>
          </trim>
        </select>
      ''', {});
      expect(sql, 'SELECT * FROM P');
    });
  });
}
