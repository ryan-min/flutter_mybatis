# flutter_mybatis

[![pub package](https://img.shields.io/pub/v/flutter_mybatis.svg)](https://pub.dev/packages/flutter_mybatis)
[![pub points](https://img.shields.io/pub/points/flutter_mybatis)](https://pub.dev/packages/flutter_mybatis/score)
[![CI](https://github.com/ryan-min/flutter_mybatis/actions/workflows/ci.yml/badge.svg)](https://github.com/ryan-min/flutter_mybatis/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

[English](README.md)

Java MyBatis를 Flutter/Dart로 이식한 XML 기반 SQL 매핑 라이브러리입니다.

자바 개발자가 Flutter를 시작할 때, 최소한 **DB 계층만큼은 이미 아는 방식 그대로**
쓸 수 있게 하는 것이 목표입니다. 대부분의 MyBatis 매퍼 XML은 거의 그대로 옮겨오지만,
차이가 있는 부분은 [이식 현황](#mybatis-3519-대비-이식-현황)에 정리했습니다.

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
  flutter_mybatis: ^1.1.4

dev_dependencies:
  build_runner: ^2.4.0
  flutter_mybatis_generator: ^1.1.4
```

`flutter_mybatis_generator`는 Dart 3.5 이상이 필요합니다(라이브러리 자체는 3.0).
매퍼 코드 생성을 쓸 때만 필요하고, 없이도 `Mapper`를 직접 상속해 쓸 수 있습니다.

<details>
<summary>git으로 설치하려면</summary>

기본 브랜치를 따라가지 말고 태그를 고정하십시오. 저장소에 푸시가 들어와도
빌드가 바뀌지 않습니다.

```yaml
dependencies:
  flutter_mybatis:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      ref: v1.1.4

dev_dependencies:
  flutter_mybatis_generator:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      ref: v1.1.4
      path: generator
```

</details>

## 30초 만에 실행해 보기

[JPetStore 예제](example/petstore)는 MyBatis 공식 샘플의 이식판입니다.
순수 Dart 콘솔 앱이라 에뮬레이터도, 브라우저도, 안드로이드 스튜디오도 필요
없습니다. 다만 `flutter_mybatis` 가 에셋 로딩 때문에 Flutter SDK 에 의존하므로
SDK 자체는 설치되어 있어야 하고, 함께 딸려오는 `dart` 를 쓰면 됩니다.

```bash
git clone https://github.com/ryan-min/flutter_mybatis.git
cd flutter_mybatis/example/petstore
dart pub get
dart run                          # 약 3초
dart run bin/petstore.dart --sql  # 실행되는 SQL까지 출력
```

## 빠른 시작

### 1. Mapper XML 작성

`assets/person_mapper.xml`:

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
      <if test="minAge != null and minAge > 0">
        AND AGE &gt;= #{minAge}
      </if>
      <if test="ids != null and ids.size() > 0">
        AND ID IN
        <foreach collection="ids" item="id" open="(" close=")" separator=",">
          #{id}
        </foreach>
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
    - assets/person_mapper.xml
```

### 3. 사용

```dart
final factory = SqlSessionFactory(database);
await factory.loadMappers(['assets/person_mapper.xml']);

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

자바 MyBatis는 매퍼 XML을 앱이 뜰 때 읽고 해석하므로, 잘못된 statement id는
실행 시점에 드러납니다. `@MybatisMapper`에 `xml:`을 지정하면 제너레이터가 같은
파일을 빌드 중에 파싱해 그 오류를 미리 잡습니다.

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

| 예제 | 실행 | 무엇을 보여주는가 |
|---|---|---|
| [petstore](example/petstore) | `dart run` | JPetStore 이식판 — 동적 SQL 전 기능 |
| [flutter_app](example/flutter_app) | `flutter run` | Flutter 앱 안에서 쓰는 법 |

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

XML을 읽어들이는 방법만 다릅니다.

```dart
// Flutter: assets 에서
await factory.loadMapper('assets/person_mapper.xml');

// 콘솔 / 서버: 파일에서
factory.loadMapperFromString(File('assets/person_mapper.xml').readAsStringSync());
```

## 파라미터

`#{}`는 prepared statement로 바인딩하고, `${}`는 SQL에 문자열로 그대로 들어갑니다.
둘 다 `test` 표현식과 **같은 경로 규칙**을 씁니다.

```xml
WHERE ID = #{user.id} AND TAG = #{tags[0]} ORDER BY ${sort.column}
```

정확히 일치하는 키가 우선이라, `user.id`라는 이름의 파라미터도 그대로 동작합니다.
해석되지 않는 `#{}`는 `null`로 바인딩되고, `${}`는 예외를 던집니다 — 유효한 SQL이
될 수 없기 때문입니다.

파라미터 값은 [TypeHandler](#typehandler)가 변환합니다. 핸들러가 없는 타입은
`toString()`으로 뭉개지 않고 `UnsupportedTypeException`을 던집니다.

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

### `timeout` 은 statement 를 취소하지 않습니다

MyBatis 의 `timeout` 은 JDBC `Statement.setQueryTimeout` 으로 내려가 드라이버에
실행 중인 statement 취소를 요청합니다. sqflite 에는 대응물이 없어서, 여기서는
**기다리기를 멈출 뿐**입니다. DB 는 계속 실행 중일 수 있고 커밋될 수도 있습니다.

`select` 라면 무해합니다. 쓰기라면 결과가 불확정이라는 뜻이고 —
`SqlTimeoutException` 이 그 사실을 말해줍니다 — 재시도하면 두 번 적용될 수
있습니다.

```dart
try {
  await session.insert('Order.insert', order);
} on SqlTimeoutException catch (e) {
  // e.statementId 가 타임아웃. 행이 들어갔을 수도, 아닐 수도 있다.
  // 재시도 전에 확인하거나, statement 를 멱등으로 만들 것.
}
```

`SqlTimeoutException` 은 `TimeoutException` 을 구현하므로 기존
`on TimeoutException` 핸들러도 그대로 잡습니다.

## 설정 (MyBatis `<settings>` 대응)

`strictExpressions` 와 오류 전파는 기본으로 켜져 있습니다 — 반대쪽이 조용히
실패하기 때문입니다. 나머지는 꺼져 있습니다.

```dart
void main() {
  MybatisConfig.mapUnderscoreToCamelCase = true;  // USER_NM -> userNm (기본 false)
  MybatisConfig.strictExpressions = false;        // 0.9.x: 못 읽는 test 를 false 로
  MybatisConfig.defaultStatementTimeout = const Duration(seconds: 30); // 기본 null
  runApp(const MyApp());
}
```

## `test` 표현식 지원 범위

MyBatis는 OGNL로 `test`를 평가합니다. Dart에는 eval이 없어 **OGNL 전체 이식은
불가능**합니다. 전용 파서로 실무에서 쓰는 범위를 대부분 처리합니다.

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
**기본값은 예외를 던지는 것입니다.** `<delete>`에서 조건이 조용히 false가 되면
`<where>`가 통째로 사라져 전체 행이 삭제되기 때문입니다.
0.9.x 동작이 필요하면 `MybatisConfig.strictExpressions = false`로 내리십시오.

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
> 지정합니다. 결과 타입 자동 디코딩은 향후 버전에서 추가할 예정입니다.

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
| `#{param}` | prepared statement 바인딩, 중첩 경로(`#{user.id}`, `#{ids[0]}`) 및 `#{id, jdbcType=INTEGER}` 같은 MyBatis 속성(무시) |
| `${param}` | 문자열 직접 치환, 같은 경로 규칙. **사용자 입력 금지** |
| `useGeneratedKeys` / `keyProperty` / `keyColumn` | INSERT 후 rowid를 파라미터에 기록 |
| `<selectKey>` | `order="BEFORE"` / `"AFTER"` |
| `timeout` | statement 단위 + 전역 기본값. **기다리기를 멈출 뿐 취소하지 않는다** — 아래 참조 |
| `mapUnderscoreToCamelCase` | 기본 off |
| `test` 표현식 파서 | OGNL 서브셋 (비교·논리·괄호·산술·삼항·메서드·인덱스) |
| TypeHandler | DateTime · bool · enum · Uri + 사용자 정의 |
| 매퍼 코드 생성 | `@MybatisMapper` + build_runner, **빌드 시점 XML 검증** |
| `_parameter` 내장 변수 | |
| SqlSession | selectList / selectOne / insert / update / delete / transaction + `selectCount`·`batchInsert` (**확장**, MyBatis에 없음. `batchInsert`는 트랜잭션 일괄 삽입이지 SQLite `Batch` API가 아님) |
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

`1.1.4`는 위에 문서화된 공개 API가 안정적임을 뜻합니다. 로드맵 항목(중첩
`resultMap`, 캐시, 인터셉터, 타입 디코딩)은 전부 **기존 API를 대체하지 않고
추가되는** 방향으로 설계했습니다.

## 로깅

```dart
MybatisLogger.setLogLevel(MybatisLogLevel.debug);
MybatisLogger.setShowSql(true);
MybatisLogger.setShowParams(true);
```

## 라이선스

Apache License 2.0. [LICENSE](LICENSE)와 [NOTICE](NOTICE)를 보십시오.

이 라이브러리는 MyBatis의 XML 방언과 API 형태를 Dart로 재구현한 것이며,
MyBatis 소스 코드는 포함하지 않습니다. petstore 예제의 스키마와 샘플
데이터는 [JPetStore 6](https://github.com/mybatis/jpetstore-6)에서
파생됐고, 그 프로젝트 역시 Apache-2.0입니다.
