import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mybatis/flutter_mybatis.dart';

/// XML SQL 파서 테스트
///
/// Java JUnit과 유사한 테스트 구조
void main() {
  group('XmlSqlParser 테스트', () {
    test('기본 SELECT 파싱', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <select id="selectList" parameterType="hashmap" resultType="hashmap">
    SELECT * FROM test_table WHERE id = #{id}
  </select>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);

      expect(config.namespace, equals('TestMapper'));
      expect(config.statements.length, equals(1));
      expect(config.hasStatement('TestMapper.selectList'), isTrue);

      final statement = config.getStatement('TestMapper.selectList')!;
      expect(statement.type, equals(SqlStatementType.select));
      expect(statement.id, equals('selectList'));
    });

    test('INSERT 파싱', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <insert id="insertData">
    INSERT INTO test_table (name, value) VALUES (#{name}, #{value})
  </insert>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.insertData')!;

      expect(statement.type, equals(SqlStatementType.insert));
    });

    test('UPDATE 파싱', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <update id="updateData">
    UPDATE test_table SET name = #{name} WHERE id = #{id}
  </update>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.updateData')!;

      expect(statement.type, equals(SqlStatementType.update));
    });

    test('DELETE 파싱', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <delete id="deleteData">
    DELETE FROM test_table WHERE id = #{id}
  </delete>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.deleteData')!;

      expect(statement.type, equals(SqlStatementType.delete));
    });

    test('다중 Statement 파싱', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="MultiMapper">
  <select id="selectOne">SELECT * FROM t1</select>
  <select id="selectTwo">SELECT * FROM t2</select>
  <insert id="insertOne">INSERT INTO t1 (a) VALUES (1)</insert>
  <update id="updateOne">UPDATE t1 SET a = 1</update>
  <delete id="deleteOne">DELETE FROM t1</delete>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);

      expect(config.statements.length, equals(5));
      expect(config.hasStatement('MultiMapper.selectOne'), isTrue);
      expect(config.hasStatement('MultiMapper.selectTwo'), isTrue);
      expect(config.hasStatement('MultiMapper.insertOne'), isTrue);
      expect(config.hasStatement('MultiMapper.updateOne'), isTrue);
      expect(config.hasStatement('MultiMapper.deleteOne'), isTrue);
    });
  });

  group('동적 SQL 테스트', () {
    test('<if> 태그 - 조건 참', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <select id="selectWithIf">
    SELECT * FROM test
    <if test="name != null">
      WHERE name = #{name}
    </if>
  </select>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.selectWithIf')!;

      final result = DynamicSqlBuilder.build(statement, {'name': '홍길동'});

      expect(result.sql, contains('WHERE name = ?'));
      expect(result.parameters, contains('홍길동'));
    });

    test('<if> 태그 - 조건 거짓', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <select id="selectWithIf">
    SELECT * FROM test
    <if test="name != null">
      WHERE name = #{name}
    </if>
  </select>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.selectWithIf')!;

      final result = DynamicSqlBuilder.build(statement, {});

      expect(result.sql, isNot(contains('WHERE')));
      expect(result.parameters, isEmpty);
    });

    test('<where> 태그 - AND 자동 제거', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <select id="selectWithWhere">
    SELECT * FROM test
    <where>
      <if test="name != null">
        AND name = #{name}
      </if>
      <if test="age != null">
        AND age = #{age}
      </if>
    </where>
  </select>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.selectWithWhere')!;

      final result = DynamicSqlBuilder.build(statement, {'name': '홍길동'});

      // WHERE 앞의 AND가 제거되어야 함
      expect(result.sql, contains('WHERE name = ?'));
      expect(result.sql, isNot(contains('WHERE AND')));
    });

    test('<set> 태그 - 쉼표 자동 제거', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <update id="updateWithSet">
    UPDATE test
    <set>
      <if test="name != null">
        name = #{name},
      </if>
      <if test="age != null">
        age = #{age},
      </if>
    </set>
    WHERE id = #{id}
  </update>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.updateWithSet')!;

      final result = DynamicSqlBuilder.build(statement, {'name': '홍길동', 'id': 1});

      // SET 마지막 쉼표가 제거되어야 함
      expect(result.sql, contains('SET name = ?'));
      expect(result.sql, isNot(contains(', WHERE')));
    });

    test('<choose> <when> <otherwise> 태그', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <select id="selectWithChoose">
    SELECT * FROM test WHERE 1=1
    <choose>
      <when test="type == 'A'">
        AND category = 'TypeA'
      </when>
      <when test="type == 'B'">
        AND category = 'TypeB'
      </when>
      <otherwise>
        AND category = 'Default'
      </otherwise>
    </choose>
  </select>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.selectWithChoose')!;

      // type = 'A' 테스트
      var result = DynamicSqlBuilder.build(statement, {'type': 'A'});
      expect(result.sql, contains("category = 'TypeA'"));

      // type = 'B' 테스트
      result = DynamicSqlBuilder.build(statement, {'type': 'B'});
      expect(result.sql, contains("category = 'TypeB'"));

      // otherwise 테스트
      result = DynamicSqlBuilder.build(statement, {'type': 'C'});
      expect(result.sql, contains("category = 'Default'"));
    });

    test('<foreach> 태그', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <select id="selectWithForeach">
    SELECT * FROM test WHERE id IN
    <foreach collection="ids" item="id" open="(" close=")" separator=",">
      #{id}
    </foreach>
  </select>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.selectWithForeach')!;

      final result = DynamicSqlBuilder.build(statement, {
        'ids': [1, 2, 3]
      });

      expect(result.sql, contains('('));
      expect(result.sql, contains(')'));
      expect(result.parameters, equals([1, 2, 3]));
    });
  });

  group('파라미터 바인딩 테스트', () {
    test('#{param} → ? 변환', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <select id="selectWithParams">
    SELECT * FROM test WHERE name = #{name} AND age = #{age}
  </select>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.selectWithParams')!;

      final result = DynamicSqlBuilder.build(statement, {
        'name': '홍길동',
        'age': 30,
      });

      expect(result.sql, contains('name = ?'));
      expect(result.sql, contains('age = ?'));
      expect(result.sql, isNot(contains('#{')));
      expect(result.parameters.length, equals(2));
      expect(result.parameters[0], equals('홍길동'));
      expect(result.parameters[1], equals(30));
    });

    test('NULL 파라미터 처리', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="TestMapper">
  <insert id="insertWithNull">
    INSERT INTO test (name, value) VALUES (#{name}, #{value})
  </insert>
</mapper>
''';

      final config = XmlSqlParser.parse(xml);
      final statement = config.getStatement('TestMapper.insertWithNull')!;

      final result = DynamicSqlBuilder.build(statement, {
        'name': '홍길동',
        'value': null,
      });

      expect(result.parameters[0], equals('홍길동'));
      expect(result.parameters[1], isNull);
    });
  });

  group('조건 평가 테스트', () {
    test('!= null 조건', () {
      expect(ConditionEvaluator.evaluate('name != null', {'name': '홍길동'}), isTrue);
      expect(ConditionEvaluator.evaluate('name != null', {}), isFalse);
      expect(ConditionEvaluator.evaluate('name != null', {'name': null}), isFalse);
    });

    test('== null 조건', () {
      expect(ConditionEvaluator.evaluate('name == null', {}), isTrue);
      expect(ConditionEvaluator.evaluate('name == null', {'name': null}), isTrue);
      expect(ConditionEvaluator.evaluate('name == null', {'name': '홍길동'}), isFalse);
    });

    test("!= '' 빈 문자열 조건", () {
      expect(ConditionEvaluator.evaluate("name != ''", {'name': '홍길동'}), isTrue);
      expect(ConditionEvaluator.evaluate("name != ''", {'name': ''}), isFalse);
    });

    test("== 'value' 문자열 비교", () {
      expect(ConditionEvaluator.evaluate("type == 'A'", {'type': 'A'}), isTrue);
      expect(ConditionEvaluator.evaluate("type == 'A'", {'type': 'B'}), isFalse);
    });

    test('AND 조건', () {
      expect(
        ConditionEvaluator.evaluate(
          'name != null and age != null',
          {'name': '홍길동', 'age': 30},
        ),
        isTrue,
      );
      expect(
        ConditionEvaluator.evaluate(
          'name != null and age != null',
          {'name': '홍길동'},
        ),
        isFalse,
      );
    });

    test('OR 조건', () {
      expect(
        ConditionEvaluator.evaluate(
          'name != null or age != null',
          {'name': '홍길동'},
        ),
        isTrue,
      );
      expect(
        ConditionEvaluator.evaluate(
          'name != null or age != null',
          {},
        ),
        isFalse,
      );
    });
  });
}
