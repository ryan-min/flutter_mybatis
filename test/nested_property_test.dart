import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mybatis/flutter_mybatis.dart';

/// Nested property paths in `#{}` and `${}`.
///
/// Until 1.0.2 the binder matched `#\{(\w+)\}` only, so `#{user.id}` was left
/// untouched in the SQL while `<if test="user.id != null">` evaluated fine —
/// a confusing asymmetry. Both now go through the same resolver.
void main() {
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

  group('#{} nested paths', () {
    const xml = '''
<mapper namespace="T">
  <select id="byUser">
    SELECT * FROM P WHERE ID = #{user.id} AND NM = #{user.profile.name}
  </select>
  <select id="byIndex">
    SELECT * FROM P WHERE ID = #{ids[0]} AND NM = #{user['name']}
  </select>
  <select id="plain">SELECT * FROM P WHERE NM = #{NM}</select>
</mapper>
''';

    test('a.b resolves', () {
      final built = DynamicSqlBuilder.build(parse(xml, 'T.byUser'), {
        'user': {
          'id': 7,
          'profile': {'name': 'Hong'},
        },
      });

      expect(built.sql, 'SELECT * FROM P WHERE ID = ? AND NM = ?');
      expect(built.parameters, [7, 'Hong']);
    });

    test("a[0] and a['k'] resolve", () {
      final built = DynamicSqlBuilder.build(parse(xml, 'T.byIndex'), {
        'ids': [11, 22],
        'user': {'name': 'Kim'},
      });

      expect(built.parameters, [11, 'Kim']);
    });

    test('a plain key still binds exactly as before', () {
      final built =
          DynamicSqlBuilder.build(parse(xml, 'T.plain'), {'NM': 'Hong'});
      expect(built.parameters, ['Hong']);
    });

    test('an exact key wins over path interpretation', () {
      // A parameter literally named 'user.id' must still be usable.
      final built = DynamicSqlBuilder.build(parse(xml, 'T.byUser'), {
        'user.id': 'literal',
        'user.profile.name': 'also literal',
      });
      expect(built.parameters, ['literal', 'also literal']);
    });

    test('an unresolvable path binds null, as a missing key always did', () {
      final built = DynamicSqlBuilder.build(parse(xml, 'T.byUser'), {});
      expect(built.parameters, [null, null]);
    });
  });

  group('malformed vs missing', () {
    const xml = '''
<mapper namespace="T">
  <select id="bad">SELECT * FROM P WHERE ID = #{@Const@X}</select>
  <select id="missing">SELECT * FROM P WHERE ID = #{nope}</select>
</mapper>
''';

    test('a path that cannot be read throws under strict (the default)', () {
      // <if> already threw on this; #{} used to bind null instead.
      expect(
        () => DynamicSqlBuilder.build(parse(xml, 'T.bad'), {}),
        throwsA(isA<UnsupportedExpressionException>()),
      );
    });

    test('a readable path with no value still binds null', () {
      final built = DynamicSqlBuilder.build(parse(xml, 'T.missing'), {});
      expect(built.parameters, [null]);
    });

    test('turning strict off restores the lenient behaviour', () {
      MybatisConfig.strictExpressions = false;
      final built = DynamicSqlBuilder.build(parse(xml, 'T.bad'), {});
      expect(built.parameters, [null]);
    });
  });

  group('the asymmetry that used to exist', () {
    test('<if> and #{} now agree on the same path', () {
      const xml = '''
<mapper namespace="T">
  <select id="s">
    SELECT * FROM P
    <where>
      <if test="user.id != null">AND ID = #{user.id}</if>
    </where>
  </select>
</mapper>
''';
      final params = {
        'user': {'id': 42}
      };

      // the condition was already true before the fix
      expect(ConditionEvaluator.evaluate('user.id != null', params), isTrue);

      // and now the binding agrees
      final built = DynamicSqlBuilder.build(parse(xml, 'T.s'), params);
      expect(built.sql, 'SELECT * FROM P WHERE ID = ?');
      expect(built.parameters, [42]);
    });
  });

  group('\${} nested paths', () {
    const xml = '''
<mapper namespace="T">
  <select id="s">SELECT * FROM P ORDER BY \${sort.column} \${sort.dir}</select>
</mapper>
''';

    test('resolves through the same rules', () {
      final built = DynamicSqlBuilder.build(parse(xml, 'T.s'), {
        'sort': {'column': 'AGE', 'dir': 'DESC'},
      });

      expect(built.sql, 'SELECT * FROM P ORDER BY AGE DESC');
      expect(built.parameters, isEmpty);
    });

    test('a missing value still fails loudly', () {
      expect(
        () => DynamicSqlBuilder.build(parse(xml, 'T.s'), {}),
        throwsA(isA<SqlBuildException>()),
      );
    });
  });
}
