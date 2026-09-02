import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mybatis/flutter_mybatis.dart';

/// test 표현식 파서 (OGNL 서브셋) 테스트
void main() {
  setUp(() {
    MybatisConfig.reset();
    ExpressionEvaluator.clearCache();
  });
  tearDown(MybatisConfig.reset);

  bool ev(String expression, [Map<String, dynamic> params = const {}]) =>
      ConditionEvaluator.evaluate(expression, Map<String, dynamic>.from(params));

  group('0.9.x 호환 (기존 앱이 쓰는 4가지 형태)', () {
    test('X != null', () {
      expect(ev('NM != null', {'NM': '홍'}), isTrue);
      expect(ev('NM != null', {}), isFalse);
      expect(ev('NM != null', {'NM': null}), isFalse);
    });

    test('X == null', () {
      expect(ev('NM == null', {}), isTrue);
      expect(ev('NM == null', {'NM': '홍'}), isFalse);
    });

    test("X != null and X != ''", () {
      expect(ev("NM != null and NM != ''", {'NM': '홍'}), isTrue);
      expect(ev("NM != null and NM != ''", {'NM': ''}), isFalse);
      expect(ev("NM != null and NM != ''", {}), isFalse);
    });

    test("X != null and X == 'N'", () {
      expect(ev("HIDE_FL != null and HIDE_FL == 'N'", {'HIDE_FL': 'N'}), isTrue);
      expect(ev("HIDE_FL != null and HIDE_FL == 'N'", {'HIDE_FL': 'Y'}), isFalse);
      expect(ev("HIDE_FL != null and HIDE_FL == 'N'", {}), isFalse);
    });

    test('toString() 비교', () {
      expect(ev("ID.toString() != '1'.toString()", {'ID': 2}), isTrue);
      expect(ev("ID.toString() != '1'.toString()", {'ID': 1}), isFalse);
    });

    test('단독 파라미터 (truthiness)', () {
      expect(ev('NM', {'NM': '홍'}), isTrue);
      expect(ev('NM', {'NM': ''}), isFalse);
      expect(ev('NM', {}), isFalse);
      expect(ev('CNT', {'CNT': 0}), isFalse);
      expect(ev('CNT', {'CNT': 3}), isTrue);
    });
  });

  group('0.10에서 못 하던 것 (정규식 방식의 한계)', () {
    test('괄호 우선순위를 올바르게 해석한다', () {
      // 0.10: " and "를 먼저 잘라 a or (b and c)로 오해했다
      expect(
        ev('(A != null or B != null) and C != null', {'A': 1, 'C': 1}),
        isTrue,
      );
      expect(
        ev('(A != null or B != null) and C != null', {'A': 1}),
        isFalse,
      );
    });

    test('문자열 리터럴 안의 and/or를 구분자로 오인하지 않는다', () {
      // 0.10: 'salt and pepper' 의 " and " 에서 잘려나갔다
      expect(ev("NM == 'salt and pepper'", {'NM': 'salt and pepper'}), isTrue);
      expect(ev("NM == 'this or that'", {'NM': 'this or that'}), isTrue);
      expect(ev("NM == 'salt and pepper'", {'NM': '홍'}), isFalse);
    });

    test('숫자 비교', () {
      expect(ev('AGE > 20', {'AGE': 30}), isTrue);
      expect(ev('AGE > 20', {'AGE': 10}), isFalse);
      expect(ev('AGE >= 20 and AGE <= 40', {'AGE': 20}), isTrue);
      expect(ev('AGE < 20', {'AGE': 10}), isTrue);
      // null 비교는 false (예외 아님)
      expect(ev('AGE > 20', {}), isFalse);
    });

    test('컬렉션 size() / length / isEmpty()', () {
      expect(ev('ids.size() > 0', {'ids': [1, 2]}), isTrue);
      expect(ev('ids.size() > 0', {'ids': <int>[]}), isFalse);
      expect(ev('ids != null and ids.size() > 2', {'ids': [1, 2, 3]}), isTrue);
      expect(ev('NM.length > 2', {'NM': '홍길동'}), isTrue);
      expect(ev('ids.isEmpty()', {'ids': <int>[]}), isTrue);
      expect(ev('ids.isNotEmpty()', {'ids': [1]}), isTrue);
    });

    test('문자열 메서드', () {
      expect(ev("NM.startsWith('홍')", {'NM': '홍길동'}), isTrue);
      expect(ev("NM.endsWith('동')", {'NM': '홍길동'}), isTrue);
      expect(ev("NM.contains('길')", {'NM': '홍길동'}), isTrue);
      expect(ev("NM.trim() != ''", {'NM': '   '}), isFalse);
      expect(ev("NM.toUpperCase() == 'ABC'", {'NM': 'abc'}), isTrue);
      expect(ev("NM.equals('홍길동')", {'NM': '홍길동'}), isTrue);
    });

    test('중첩 프로퍼티 / 인덱스 접근', () {
      final params = {
        'user': {'name': '홍', 'tags': ['a', 'b']},
      };
      expect(ev('user.name != null', params), isTrue);
      expect(ev("user.name == '홍'", params), isTrue);
      expect(ev("user['name'] == '홍'", params), isTrue);
      expect(ev("user.tags[0] == 'a'", params), isTrue);
      expect(ev('user.tags.size() == 2', params), isTrue);
      // 없는 경로는 null (예외 아님)
      expect(ev('user.nope.deeper != null', params), isFalse);
    });

    test('not / && / || 표기', () {
      expect(ev('!(NM == null)', {'NM': '홍'}), isTrue);
      expect(ev('not (NM == null)', {'NM': '홍'}), isTrue);
      expect(ev('NM != null && AGE != null', {'NM': '홍', 'AGE': 1}), isTrue);
      expect(ev('NM != null || AGE != null', {'AGE': 1}), isTrue);
    });

    test('산술 / 삼항', () {
      expect(ev('AGE + 5 > 20', {'AGE': 20}), isTrue);
      expect(ev('AGE * 2 == 40', {'AGE': 20}), isTrue);
      expect(ev("(AGE > 20 ? 'Y' : 'N') == 'Y'", {'AGE': 30}), isTrue);
      expect(ev("(AGE > 20 ? 'Y' : 'N') == 'Y'", {'AGE': 10}), isFalse);
    });

    test('boolean 리터럴 / 값', () {
      expect(ev('true'), isTrue);
      expect(ev('false'), isFalse);
      expect(ev('FL == true', {'FL': true}), isTrue);
      expect(ev('FL', {'FL': true}), isTrue);
      expect(ev('FL', {'FL': false}), isFalse);
    });

    test('숫자/문자 느슨한 비교 (DB 타입 흔들림 대응)', () {
      expect(ev("STS == '1'", {'STS': 1}), isTrue);
      expect(ev('STS == 1', {'STS': '1'}), isTrue);
    });
  });

  group('미지원 문법 처리', () {
    const ognlStatic = '@com.foo.Const@ACTIVE == STS';

    test('기본값은 false + 경고 (0.9.x와 동일)', () {
      expect(ev(ognlStatic, {'STS': 'A'}), isFalse);
    });

    test('strictExpressions=true 면 예외', () {
      MybatisConfig.strictExpressions = true;
      expect(
        () => ev(ognlStatic, {'STS': 'A'}),
        throwsA(isA<UnsupportedExpressionException>()),
      );
    });

    test('문법 오류도 동일하게 처리', () {
      expect(ev('NM == '), isFalse);
      MybatisConfig.strictExpressions = true;
      expect(
        () => ev('NM == '),
        throwsA(isA<UnsupportedExpressionException>()),
      );
    });

    test('빈 표현식은 false', () {
      expect(ev(''), isFalse);
      expect(ev('   '), isFalse);
    });
  });

  group('파싱 캐시', () {
    test('같은 표현식을 반복 평가해도 결과가 일관된다', () {
      for (var i = 0; i < 100; i++) {
        expect(ev('AGE > 20', {'AGE': i}), i > 20);
      }
    });
  });
}
