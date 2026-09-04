import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mybatis/flutter_mybatis.dart';

/// 0.10.0 신규 기능 테스트
///
/// MyBatis 3.5.19 기준으로 이식한 항목들.
void main() {
  setUp(MybatisConfig.reset);
  tearDown(MybatisConfig.reset);

  /// XML 하나를 파싱하고 include까지 연결
  SqlStatement parseOne(String xml, String id) {
    final config = XmlSqlParser.parse(xml);
    for (final statement in config.statements.values) {
      statement.resolveIncludes(config.fragments);
    }
    return config.statements[id]!;
  }

  group('<sql> + <include>', () {
    const xml = '''
<mapper namespace="T">
  <sql id="cols">ID, NM, AGE</sql>
  <sql id="live">DEL_FL = 'N'</sql>

  <select id="selectAll">
    SELECT <include refid="cols"/> FROM PERSON WHERE <include refid="live"/>
  </select>
</mapper>
''';

    test('조각이 실제 SQL로 치환된다', () {
      final statement = parseOne(xml, 'T.selectAll');
      final built = DynamicSqlBuilder.build(statement, {});

      expect(built.sql, 'SELECT ID, NM, AGE FROM PERSON WHERE DEL_FL = \'N\'');
      // 0.9.0에서는 주석만 남았다: /* include: cols */
      expect(built.sql, isNot(contains('include:')));
    });

    test('statement보다 뒤에 선언된 조각도 참조된다', () {
      const backward = '''
<mapper namespace="T">
  <select id="s">SELECT <include refid="cols"/> FROM P</select>
  <sql id="cols">A, B</sql>
</mapper>
''';
      final statement = parseOne(backward, 'T.s');
      expect(DynamicSqlBuilder.build(statement, {}).sql, 'SELECT A, B FROM P');
    });

    test('<property>로 조각에 값을 넘긴다', () {
      const withProperty = '''
<mapper namespace="T">
  <sql id="flag">DEL_FL = '\${f}'</sql>
  <select id="s">SELECT * FROM P WHERE <include refid="flag"><property name="f" value="Y"/></include></select>
</mapper>
''';
      final statement = parseOne(withProperty, 'T.s');
      expect(
        DynamicSqlBuilder.build(statement, {}).sql,
        "SELECT * FROM P WHERE DEL_FL = 'Y'",
      );
    });

    test('조각 안의 조각도 재귀 연결된다', () {
      const nested = '''
<mapper namespace="T">
  <sql id="inner">A, B</sql>
  <sql id="outer"><include refid="inner"/>, C</sql>
  <select id="s">SELECT <include refid="outer"/> FROM P</select>
</mapper>
''';
      final statement = parseOne(nested, 'T.s');
      expect(DynamicSqlBuilder.build(statement, {}).sql, 'SELECT A, B, C FROM P');
    });

    test('없는 refid는 예외', () {
      const missing = '''
<mapper namespace="T">
  <select id="s">SELECT <include refid="nope"/> FROM P</select>
</mapper>
''';
      expect(
        () => parseOne(missing, 'T.s'),
        throwsA(isA<SqlFragmentNotFoundException>()),
      );
    });

    test('순환 참조는 예외', () {
      const cyclic = '''
<mapper namespace="T">
  <sql id="a"><include refid="b"/></sql>
  <sql id="b"><include refid="a"/></sql>
  <select id="s">SELECT <include refid="a"/> FROM P</select>
</mapper>
''';
      expect(
        () => parseOne(cyclic, 'T.s'),
        throwsA(isA<SqlBuildException>()),
      );
    });
  });

  group('\${} 치환', () {
    test('파라미터 값이 문자열 그대로 들어간다', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P ORDER BY \${sortCol} \${sortDir}</select>
</mapper>
''';
      final statement = parseOne(xml, 'T.s');
      final built = DynamicSqlBuilder.build(statement, {
        'sortCol': 'NM',
        'sortDir': 'DESC',
      });

      expect(built.sql, 'SELECT * FROM P ORDER BY NM DESC');
      // ${}는 바인딩이 아니므로 파라미터가 늘지 않는다
      expect(built.parameters, isEmpty);
    });

    test('#{}는 여전히 바인딩된다', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P WHERE NM = #{nm} ORDER BY \${col}</select>
</mapper>
''';
      final statement = parseOne(xml, 'T.s');
      final built = DynamicSqlBuilder.build(statement, {'nm': '홍', 'col': 'ID'});

      expect(built.sql, 'SELECT * FROM P WHERE NM = ? ORDER BY ID');
      expect(built.parameters, ['홍']);
    });

    test('값이 없으면 명확한 예외', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P ORDER BY \${nope}</select>
</mapper>
''';
      final statement = parseOne(xml, 'T.s');
      expect(
        () => DynamicSqlBuilder.build(statement, {}),
        throwsA(isA<SqlBuildException>()),
      );
    });
  });

  group('statement 속성', () {
    const xml = '''
<mapper namespace="T">
  <insert id="ins" useGeneratedKeys="true" keyProperty="ID" keyColumn="ID"
          timeout="7" flushCache="true" databaseId="sqlite">
    INSERT INTO P (NM) VALUES (#{nm})
  </insert>
  <select id="sel" resultMap="pMap" useCache="false" timeout="3">
    SELECT * FROM P
  </select>
</mapper>
''';

    test('useGeneratedKeys / keyProperty / keyColumn 파싱', () {
      final statement = parseOne(xml, 'T.ins');
      expect(statement.useGeneratedKeys, isTrue);
      expect(statement.keyProperty, 'ID');
      expect(statement.keyColumn, 'ID');
      expect(statement.writesGeneratedKey, isTrue);
    });

    test('timeout / flushCache / useCache / resultMap / databaseId 파싱', () {
      final ins = parseOne(xml, 'T.ins');
      final sel = parseOne(xml, 'T.sel');

      expect(ins.timeout, 7);
      expect(ins.timeoutDuration, const Duration(seconds: 7));
      expect(ins.flushCache, isTrue);
      expect(ins.databaseId, 'sqlite');

      expect(sel.resultMap, 'pMap');
      expect(sel.useCache, isFalse);
      expect(sel.timeout, 3);
    });

    test('timeout 미지정 시 전역 기본값을 따른다', () {
      const plain = '<mapper namespace="T"><select id="s">SELECT 1</select></mapper>';
      final statement = parseOne(plain, 'T.s');

      expect(statement.timeoutDuration, isNull);
      MybatisConfig.defaultStatementTimeout = const Duration(seconds: 30);
      expect(statement.timeoutDuration, const Duration(seconds: 30));
    });
  });

  group('<selectKey>', () {
    test('order="BEFORE" 파싱', () {
      const xml = '''
<mapper namespace="T">
  <insert id="ins">
    <selectKey keyProperty="ID" resultType="int" order="BEFORE">
      SELECT IFNULL(MAX(ID), 0) + 1 AS ID FROM P
    </selectKey>
    INSERT INTO P (ID, NM) VALUES (#{ID}, #{nm})
  </insert>
</mapper>
''';
      final statement = parseOne(xml, 'T.ins');

      expect(statement.selectKey, isNotNull);
      expect(statement.selectKey!.keyProperty, 'ID');
      expect(statement.selectKey!.order, SelectKeyOrder.before);
      expect(statement.selectKey!.resultType, 'int');

      // selectKey 본문은 INSERT SQL에 섞이면 안 된다
      final built = DynamicSqlBuilder.build(statement, {'ID': 1, 'nm': 'A'});
      expect(built.sql, 'INSERT INTO P (ID, NM) VALUES (?, ?)');
      expect(built.sql, isNot(contains('IFNULL')));
    });

    test('order 미지정 시 AFTER', () {
      const xml = '''
<mapper namespace="T">
  <insert id="ins">
    <selectKey keyProperty="ID">SELECT last_insert_rowid() AS ID</selectKey>
    INSERT INTO P (NM) VALUES (#{nm})
  </insert>
</mapper>
''';
      expect(parseOne(xml, 'T.ins').selectKey!.order, SelectKeyOrder.after);
    });

    test('keyProperty 없으면 예외', () {
      const xml = '''
<mapper namespace="T">
  <insert id="ins"><selectKey>SELECT 1</selectKey>INSERT INTO P VALUES (1)</insert>
</mapper>
''';
      expect(() => parseOne(xml, 'T.ins'), throwsA(isA<XmlParseException>()));
    });
  });

  group('<foreach>', () {
    const xml = '''
<mapper namespace="T">
  <select id="inList">
    SELECT * FROM P WHERE ID IN
    <foreach collection="ids" item="id" open="(" close=")" separator=",">#{id}</foreach>
  </select>
  <select id="nullable">
    SELECT * FROM P
    <foreach collection="ids" item="id" open="WHERE ID IN (" close=")" separator="," nullable="true">#{id}</foreach>
  </select>
  <select id="byMap">
    SELECT * FROM P WHERE
    <foreach collection="cond" index="k" item="v" separator=" AND ">\${k} = #{v}</foreach>
  </select>
</mapper>
''';

    test('List 순회', () {
      final built = DynamicSqlBuilder.build(
        parseOne(xml, 'T.inList'),
        {'ids': [1, 2, 3]},
      );
      expect(built.sql, 'SELECT * FROM P WHERE ID IN (?,?,?)');
      expect(built.parameters, [1, 2, 3]);
    });

    test('Map 순회 시 index=key, item=value', () {
      final built = DynamicSqlBuilder.build(
        parseOne(xml, 'T.byMap'),
        {
          'cond': {'NM': '홍', 'AGE': 20},
        },
      );
      expect(built.sql, 'SELECT * FROM P WHERE NM = ? AND AGE = ?');
      expect(built.parameters, ['홍', 20]);
    });

    test('collection이 null이면 예외 (MyBatis와 동일)', () {
      expect(
        () => DynamicSqlBuilder.build(parseOne(xml, 'T.inList'), {}),
        throwsA(isA<SqlBuildException>()),
      );
    });

    test('nullable="true"면 null이어도 통과', () {
      final built = DynamicSqlBuilder.build(parseOne(xml, 'T.nullable'), {});
      expect(built.sql, 'SELECT * FROM P');
    });

    test('collection 타입이 틀리면 예외', () {
      expect(
        () => DynamicSqlBuilder.build(parseOne(xml, 'T.inList'), {'ids': 3}),
        throwsA(isA<SqlBuildException>()),
      );
    });
  });

  group('strictExpressions', () {
    // OGNL 정적 메서드/필드 참조(@Class@member)는 Dart로 이식 불가
    const xml = '''
<mapper namespace="T">
  <select id="s">
    SELECT * FROM P
    <where><if test="@com.foo.Const@ACTIVE == STS">AND ID = #{id}</if></where>
  </select>
</mapper>
''';

    test('기본값(strict)에서는 예외', () {
      expect(
        () => DynamicSqlBuilder.build(parseOne(xml, 'T.s'), {'id': 1}),
        throwsA(isA<UnsupportedExpressionException>()),
      );
    });

    test('꺼두면 0.9.x 처럼 false 로 평가', () {
      MybatisConfig.strictExpressions = false;
      final built = DynamicSqlBuilder.build(parseOne(xml, 'T.s'), {'id': 1});
      expect(built.sql, 'SELECT * FROM P');
    });

    test('지원 범위 표현식은 strict에서도 정상 동작', () {
      const ok = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P<where><if test="nm != null and nm != ''">AND NM = #{nm}</if></where></select>
</mapper>
''';
      final built = DynamicSqlBuilder.build(parseOne(ok, 'T.s'), {'nm': '홍'});
      expect(built.sql, 'SELECT * FROM P WHERE NM = ?');
    });
  });

  group('mapUnderscoreToCamelCase', () {
    test('컬럼명 변환 규칙', () {
      expect(MybatisConfig.toCamelCase('USER_NM'), 'userNm');
      expect(MybatisConfig.toCamelCase('BRTH_YR_UM'), 'brthYrUm');
      expect(MybatisConfig.toCamelCase('user_nm'), 'userNm');
      expect(MybatisConfig.toCamelCase('id'), 'id');
      expect(MybatisConfig.toCamelCase('CNT'), 'cnt');
    });

    test('기본값 false면 행이 그대로 유지된다', () {
      final row = {'USER_NM': '홍', 'BRTH_YR': 1990};
      expect(MybatisConfig.mapRow(row), same(row));
    });

    test('켜면 키가 변환된다', () {
      MybatisConfig.mapUnderscoreToCamelCase = true;
      expect(
        MybatisConfig.mapRow({'USER_NM': '홍', 'BRTH_YR': 1990}),
        {'userNm': '홍', 'brthYr': 1990},
      );
    });
  });

  group('_parameter 내장 변수', () {
    test('파라미터 전체가 _parameter로 바인딩된다', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P<where><if test="_parameter != null">AND NM = #{nm}</if></where></select>
</mapper>
''';
      final built = DynamicSqlBuilder.build(parseOne(xml, 'T.s'), {'nm': '홍'});
      expect(built.sql, 'SELECT * FROM P WHERE NM = ?');
      expect(built.parameters, ['홍']);
    });
  });
}
