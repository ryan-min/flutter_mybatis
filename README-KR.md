# flutter_mybatis

[![pub package](https://img.shields.io/pub/v/flutter_mybatis.svg)](https://pub.dev/packages/flutter_mybatis)
[![pub points](https://img.shields.io/pub/points/flutter_mybatis)](https://pub.dev/packages/flutter_mybatis/score)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

[English](README.md)

Java MyBatis를 Flutter/Dart로 이식한 XML 기반 SQL 매핑 라이브러리입니다.

자바 개발자가 Flutter를 시작할 때, 최소한 **DB 계층만큼은 이미 아는 방식 그대로** 쓸 수 있게 하는 것이 목표입니다. 기준은 MyBatis 3.5.19입니다.

- **XML로 SQL 분리** — 코드와 SQL을 분리해 유지보수성 확보
- **동적 SQL** — `<if>` `<where>` `<set>` `<trim>` `<choose>` `<foreach>` `<bind>` `<sql>`/`<include>`
- **파라미터 바인딩** — `#{param}` (prepared statement), `${param}` (문자열 치환)
- **기존 sqflite DB 위에 그대로** — 스키마를 라이브러리가 소유하지 않습니다

## drift와 무엇이 다른가

[drift](https://pub.dev/packages/drift)는 Dart 진영의 성숙한 선택지이고, 다른
문제를 잘 풉니다. 아래가 중요할 때만 이 라이브러리를 고르십시오.

| | flutter_mybatis | drift |
|---|---|---|
| 스키마 소유 | **기존 sqflite 스키마 그대로** | drift가 스키마·마이그레이션을 소유 |
| SQL 작성 | XML 매퍼 (자바 MyBatis 그대로) | `.drift` 파일 또는 Dart DSL |
| 결과 타입 | `Map<String, dynamic>` | 생성된 타입 클래스 |
| 컴파일 타임 검사 | statement id | SQL 전체 검증 |
| 자바 개발자 학습 비용 | 거의 0 | 새 DSL 학습 |

기존 스키마가 없고 타입 안전성이 중요하면 drift가 낫습니다. **이미 있는
sqflite DB에 자바 매퍼를 그대로 가져오려는 경우**가 이 라이브러리의 자리입니다.

## 설치

```yaml
dependencies:
  flutter_mybatis: ^1.0.0

dev_dependencies:
  build_runner: ^2.4.0
  flutter_mybatis_generator: ^1.0.0
```

`flutter_mybatis_generator`는 코드 생성을 쓸 때만 필요합니다. 없으면 `Mapper`를
직접 상속해 쓰면 됩니다.

<details>
<summary>git에서 바로 설치하기</summary>

```yaml
dependencies:
  flutter_mybatis:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      ref: v1.0.1

dev_dependencies:
  flutter_mybatis_generator:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      ref: v1.0.1
      path: generator
```

</details>

## 30초 만에 실행해 보기

[JPetStore 예제](example/petstore)는 MyBatis 공식 샘플의 이식판입니다.
순수 Dart 콘솔 앱이라 Flutter도, 에뮬레이터도, 브라우저도 필요 없습니다.

```bash
git clone https://github.com/ryan-min/flutter_mybatis.git
cd flutter_mybatis/example/petstore
dart pub get
dart run                          # 약 3초
dart run bin/petstore.dart --sql  # 실행되는 SQL까지 출력
```

## 빠른 시작

### 1. Mapper XML 작성

`lib/dao/person_mapper.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mapper namespace="PersonMapper">

  <sql id="cols">ID, NM, AGE</sql>

  <select id="selectList">
    SELECT <include refid="cols"/> FROM PERSON
    <where>
      <if test="NM != null and NM != ''">
        AND NM LIKE '%' || #{NM} || '%'
      </if>
      <if test="AGE != null">
        AND AGE = #{AGE}
      </if>
    </where>
    ORDER BY ID DESC
  </select>

  <insert id="insert" useGeneratedKeys="true" keyProperty="ID">
    INSERT INTO PERSON (NM, AGE) VALUES (#{NM}, #{AGE})
  </insert>

</mapper>
```

### 2. assets 등록 (pubspec.yaml)

```yaml
flutter:
  assets:
    - lib/dao/person_mapper.xml
```

### 3. 사용

```dart
final factory = SqlSessionFactory(database);
await factory.loadMappers(['lib/dao/person_mapper.xml']);

final session = factory.openSession();

final list = await session.selectList('PersonMapper.selectList', {'NM': '홍'});

final params = {'NM': '홍길동', 'AGE': 30};
await session.insert('PersonMapper.insert', params);
print(params['ID']); // useGeneratedKeys로 채워진 rowid
```

### Mapper 클래스 — 코드 생성 (권장)

Java MyBatis의 `@Mapper` 인터페이스처럼 **선언만** 하면 구현이 생성됩니다.
메서드 본문을 한 줄도 쓰지 않습니다.

```dart
import 'package:flutter_mybatis/flutter_mybatis.dart';

part 'person_mapper.g.dart';

@MybatisMapper('PersonMapper', xml: 'assets/person_mapper.xml')
abstract class PersonMapper {
  factory PersonMapper(SqlSession session) = _$PersonMapper;

  @Select('selectList')
  Future<List<Map<String, dynamic>>> search(Map<String, dynamic> params);

  @SelectOne('selectById')
  Future<Map<String, dynamic>?> findById(@Param('ID') int id);

  @Insert('insert')
  Future<int> add(Map<String, dynamic> person);
}
```

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  flutter_mybatis_generator: ...
```

```bash
dart run build_runner build
```

**`xml:` 을 지정하면 statement id 오타를 빌드 시점에 잡습니다.**
Java MyBatis는 앱 기동 시점에야 알 수 있는 오류입니다.

```
[SEVERE] XML에 statement가 없습니다: "PersonMapper.selectLst"
사용 가능한 id: delete, insert, selectById, selectCount, selectList, update
```

자세한 내용은 [generator/](generator/README-KR.md) 를 보십시오.

### Mapper 클래스 — 직접 작성

코드 생성 없이 쓸 수도 있습니다.

```dart
class PersonMapper extends Mapper {
  PersonMapper(super.session);

  @override
  String get namespace => 'PersonMapper';

  Future<List<Map<String, dynamic>>> search(Map<String, dynamic> p) =>
      selectList('selectList', p);
}
```

> namespace는 기본적으로 클래스명(`runtimeType`)입니다. Flutter 릴리스 빌드에
> `--obfuscate`를 쓰면 클래스명이 뭉개져 statement를 찾지 못하므로, 위처럼
> namespace를 명시적으로 고정하십시오. (코드 생성 방식은 항상 고정됩니다)

## 빌드 시점 XML 검증

**이 이식판이 자바 MyBatis보다 나은 유일한 지점입니다.**

`@MybatisMapper`에 `xml:`을 지정하면, 제너레이터가 빌드 시점에 그 XML을 파싱해
참조한 statement id가 실제로 있는지 전부 검사합니다.

```
[SEVERE] Statement not found in XML: "PersonMapper.selectByIdd"
available ids: delete, deleteByIds, insert, insertWithSelectKey,
               selectById, selectCount, selectList, selectSorted, update

  package:example/person_mapper.dart:36:33
     ╷
  36 │   Future<Map<String, dynamic>?> findById(@Param('ID') int id);
     │                                 ^^^^^^^^
```

다음도 함께 잡습니다.

- statement 종류 불일치 (`<select>`를 `@Insert`로 선언)
- `@MybatisMapper` namespace와 XML `namespace` 불일치
- 매퍼 XML을 읽지 못하거나 파싱하지 못하는 경우

**자바 MyBatis는 이 오류들을 앱이 기동해야 압니다.**

## 예제

**가장 빠르게 보려면 JPetStore 콘솔 예제입니다.** MyBatis 공식 샘플
[jpetstore-6](https://github.com/mybatis/jpetstore-6) 이식판이고,
Flutter도 에뮬레이터도 없이 `dart run` 한 줄로 뜹니다.

```bash
cd example/petstore
dart pub get
dart run                          # 약 3초
dart run bin/petstore.dart --sql  # 실행 SQL까지 출력
```

Flutter UI 예제는 `example/flutter_app` 에 있습니다.
자세한 내용은 [example/README-KR.md](example/README-KR.md).

## 두 개의 진입점

코어는 **Flutter에 의존하지 않습니다.**

```dart
// 순수 Dart — 콘솔, 서버 사이드, 테스트
import 'package:flutter_mybatis/flutter_mybatis_core.dart';

// Flutter — 위 코어 전부 + assets 로딩(loadMapper / loadMappers)
import 'package:flutter_mybatis/flutter_mybatis.dart';
```

`sqflite_common` 의 `Database` 를 받으므로 드라이버를 골라 붙일 수 있습니다.

| 환경 | 드라이버 |
|---|---|
| 모바일 (Android / iOS) | `sqflite` |
| 데스크톱 · CLI · 테스트 | `sqflite_common_ffi` |
| 웹 | `sqflite_common_ffi_web` (experimental) |

## 오류 처리

실패한 statement는 예외를 던집니다. `transaction()`이 롤백되는 근거가 이것입니다.

```dart
await session.transaction((tx) async {
  await tx.insert('OrderMapper.insert', order);
  await tx.update('ItemMapper.decreaseStock', item); // 실패하면 전부 취소
});
```

```dart
// 0.9.x는 오류를 삼키고 [] / -1 / 0을 돌려줬습니다.
// 과거 동작이 필요하면 한시적으로만 켜세요.
MybatisConfig.suppressSqlErrors = true;
```

다른 실수도 조용히 넘어가지 않습니다.

| 상황 | 결과 |
|---|---|
| statement·`<sql>` id 중복 | `XmlParseException` |
| 모르는 태그(`<whree>` 같은 오타) | `XmlParseException` |
| 값 없는 `${name}` | `SqlBuildException` |
| `selectOne`이 여러 행과 매치 | `TooManyResultsException` |

## 설정 (MyBatis `<settings>` 대응)

모든 기본값은 **하위 호환**을 위해 0.9.x 동작과 동일합니다.

```dart
void main() {
  MybatisConfig.mapUnderscoreToCamelCase = true;  // USER_NM -> userNm (기본 false)
  MybatisConfig.strictExpressions = true;         // 미지원 test 문법을 예외로 (기본 false)
  MybatisConfig.defaultStatementTimeout = const Duration(seconds: 30); // 기본 null
  runApp(const MyApp());
}
```

## `test` 표현식 지원 범위

MyBatis는 OGNL로 `test`를 평가합니다. Dart에는 eval이 없어 **OGNL 전체 이식은
불가능**하지만, 0.11부터 전용 파서를 넣어 실무에서 쓰는 범위를 대부분 처리합니다.

| 분류 | 지원 |
|---|---|
| 리터럴 | 숫자, `'문자열'`, `"문자열"`, `true`, `false`, `null` |
| 프로퍼티 | `a`, `a.b.c`, `a['k']`, `a[0]` |
| 비교 | `==` `!=` `<` `<=` `>` `>=` (`eq` `neq` `lt` `lte` `gt` `gte`) |
| 논리 | `and` `or` `not` / `&&` `||` `!`, **괄호 그룹핑** |
| 산술 | `+` `-` `*` `/` `%` |
| 삼항 | `cond ? a : b` |
| 메서드 | `size()` `length()` `isEmpty()` `isNotEmpty()` `trim()` `toString()` `toUpperCase()` `toLowerCase()` `equals(x)` `contains(x)` `startsWith(x)` `endsWith(x)` `indexOf(x)` |

```xml
<if test="ids != null and ids.size() > 0">...</if>
<if test="(A != null or B != null) and C != null">...</if>
<if test="NM.startsWith('홍') and AGE >= 20">...</if>
<if test="user.tags[0] == 'vip'">...</if>
```

**미지원**: OGNL 정적 참조(`@Class@member`), 객체 생성(`new`), 람다 등.
미지원 문법이나 문법 오류는 기본적으로 `false`로 평가되고 경고 로그가 남습니다.
조용한 오판정을 막으려면 `MybatisConfig.strictExpressions = true`로 예외 전환하십시오.

**null 처리**: 비교 연산에서 한쪽이 `null`이면 예외 대신 `false`입니다.
`a.b.c`처럼 중간이 `null`인 경로도 `null`을 반환합니다.

## TypeHandler

sqflite는 `num` `String` `Uint8List` `null` 만 바인딩할 수 있어, `bool`이나
`DateTime`을 그대로 넘기면 런타임 오류가 납니다. TypeHandler가 자동 변환합니다.

```dart
await session.insert('PersonMapper.insert', {
  'ACTIVE_FL': true,          // -> 1
  'JOIN_DT': DateTime.now(),  // -> '2026-09-01T12:00:00.000'
  'STATUS': Status.active,    // -> 'active'
});
```

기본 등록: `DateTimeTypeHandler`(ISO8601) · `BoolTypeHandler`(1/0) · `UriTypeHandler`.
교체하거나 직접 만들 수 있습니다.

```dart
TypeHandlerRegistry.register(const YnBoolTypeHandler());        // true -> 'Y'
TypeHandlerRegistry.register(const DateTimeMillisTypeHandler()); // -> epoch millis
TypeHandlerRegistry.register(EnumTypeHandler(Status.values));

class MoneyTypeHandler extends TypeHandler<Money> {
  const MoneyTypeHandler();
  @override
  Object? encode(Money value) => value.cents;
  @override
  Money? decode(Object? value) => value == null ? null : Money(value as int);
}
```

> 결과값 디코딩은 대상 타입을 알아야 하므로 `ResultMap`의 `typeConverters`로
> 지정합니다. 자동 디코딩은 코드 생성이 들어가는 0.12 예정입니다.

## MyBatis 3.5.19 대비 이식 현황

### 지원

| 항목 | 비고 |
|---|---|
| `<select>` `<insert>` `<update>` `<delete>` | |
| `<if>` `<where>` `<set>` `<trim>` | |
| `<choose>` `<when>` `<otherwise>` | |
| `<foreach>` | `collection` `item` `index` `open` `close` `separator` `nullable` / List·Set·Map |
| `<bind>` | |
| `<sql>` + `<include>` | `<property>`, 전방 참조, 다른 namespace 참조, 순환 참조 감지 |
| `#{param}` | prepared statement 바인딩 |
| `${param}` | 문자열 직접 치환 |
| `useGeneratedKeys` / `keyProperty` / `keyColumn` | INSERT 후 rowid를 파라미터에 기록 |
| `<selectKey>` | `order="BEFORE"` / `"AFTER"` |
| `timeout` | statement 단위 + 전역 기본값 |
| `mapUnderscoreToCamelCase` | 기본 off |
| `test` 표현식 파서 | OGNL 서브셋 (비교·논리·괄호·산술·삼항·메서드·인덱스) |
| TypeHandler | DateTime · bool · enum · Uri + 사용자 정의 |
| 매퍼 코드 생성 | `@MybatisMapper` + build_runner, **빌드 시점 XML 검증** |
| `_parameter` 내장 변수 | |
| SqlSession | selectList/selectOne/selectCount/insert/update/delete/transaction/batchInsert |
| 로깅 | 레벨 설정, 사용자 로거 연결 |

### 미지원 (이식 예정)

`resultMap` 중첩 매핑(`<association>` `<collection>` `<discriminator>`) · 1차/2차 캐시(`<cache>` `<cache-ref>` `flushCache` `useCache`) · Interceptor(플러그인) · 어노테이션 인라인 SQL · `ExecutorType.BATCH`/`REUSE` · `ResultHandler`/Cursor 스트리밍 · 결과값 자동 디코딩

> `resultMap` `flushCache` `useCache` `databaseId`는 **파싱만 되고 아직 동작하지 않습니다.**

### 이식 불가 (구조적 제약)

| 항목 | 이유 |
|---|---|
| OGNL 전체 문법 | Dart에 eval이 없음 |
| 매퍼 인터페이스 **런타임** 동적 프록시 | Flutter에 `dart:mirrors`가 없음 → 빌드 시점 코드 생성으로 대체 |
| 지연 로딩(lazy loading) | 런타임 바이트코드 프록시 없음 |
| 저장 프로시저(`CALLABLE`) | SQLite에 없음 |
| 다중 ResultSet | SQLite에 없음 |
| 커넥션 풀 / JNDI | sqflite가 커넥션을 소유 |
| 분산·직렬화 2차 캐시 | 인메모리만 가능 |
| `<parameterMap>` | MyBatis 자체가 deprecated |

## API 안정성

`1.0.1`은 위에 문서화된 공개 API가 안정적임을 뜻합니다. 로드맵 항목(중첩
`resultMap`, 캐시, 인터셉터, 타입 디코딩)은 전부 **기존 API를 대체하지 않고
추가되는** 방향으로 설계했습니다.

## 로깅

```dart
MybatisLogger.setLogLevel(MybatisLogLevel.debug);
MybatisLogger.setShowSql(true);
MybatisLogger.setShowParams(true);
```

## 라이선스

Apache License 2.0
