# flutter_mybatis

[![pub package](https://img.shields.io/pub/v/flutter_mybatis.svg)](https://pub.dev/packages/flutter_mybatis)
[![pub points](https://img.shields.io/pub/points/flutter_mybatis)](https://pub.dev/packages/flutter_mybatis/score)
[![CI](https://github.com/ryan-min/flutter_mybatis/actions/workflows/ci.yml/badge.svg)](https://github.com/ryan-min/flutter_mybatis/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

[한국어](README-KR.md)

MyBatis for Flutter/Dart — XML-based SQL mapping, ported from
[MyBatis 3.5.19](https://github.com/mybatis/mybatis-3).

If you come from Java, the goal is simple: **the database layer should be
something you already know.** Most MyBatis mapper XML ports with little or no
change; see [Porting status](#porting-status-vs-mybatis-3519) for what differs.

- **SQL lives in XML**, not in your Dart code
- **Dynamic SQL** — `<if>` `<where>` `<set>` `<trim>` `<choose>` `<foreach>` `<bind>` `<sql>`/`<include>`
- **Parameter binding** — `#{param}` (prepared statement), `${param}` (string substitution)
- **Mapper code generation** — declare an abstract class, no method bodies
- **Build-time XML validation** — a typo in a statement id fails the build,
  not the app at startup
- **Works on your existing sqflite database** — this library does not own your schema

## How it compares

[drift](https://pub.dev/packages/drift) is the mature choice for Dart, and it
solves a different problem well. Pick this library only when these matter:

| | flutter_mybatis | drift |
|---|---|---|
| Schema ownership | **your existing sqflite schema**, untouched | drift owns the schema and migrations |
| SQL style | XML mappers, as in Java MyBatis | `.drift` files or a Dart DSL |
| Result type | `Map<String, dynamic>` | generated typed classes |
| Compile-time SQL check | statement ids only | full SQL verification |
| Learning cost for a Java dev | close to zero | a new DSL |

If you have no legacy schema and want type safety, use drift. If you are
bringing Java mappers to an sqflite database that already exists, this is
built for that.

## Install

```yaml
dependencies:
  flutter_mybatis: ^1.1.5

dev_dependencies:
  build_runner: ^2.4.0
  flutter_mybatis_generator: ^1.1.5
```

`flutter_mybatis_generator` needs Dart 3.5 or newer (the library itself needs
only 3.0). It is only needed if you want generated mappers. Without it you can
still extend `Mapper` by hand.

<details>
<summary>Installing from git instead</summary>

Pin a tag rather than tracking the default branch, so a push does not change
your build.

```yaml
dependencies:
  flutter_mybatis:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      ref: v1.1.5

dev_dependencies:
  flutter_mybatis_generator:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      ref: v1.1.5
      path: generator
```

</details>

## Try it in 30 seconds

The [JPetStore example](example/petstore) is a port of the official MyBatis
sample. It runs as a plain Dart console app — no emulator, no browser, no
Android Studio. You still need the Flutter SDK installed, because
`flutter_mybatis` depends on it for asset loading; use the `dart` that ships
with it.

```bash
git clone https://github.com/ryan-min/flutter_mybatis.git
cd flutter_mybatis/example/petstore
dart pub get
dart run                          # ~3 seconds
dart run bin/petstore.dart --sql  # show the SQL being executed
```

## Quick start

### 1. Write a mapper XML

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

### 2. Register it as an asset (pubspec.yaml)

```yaml
flutter:
  assets:
    - assets/person_mapper.xml
```

### 3. Use it

```dart
final factory = SqlSessionFactory(database);
await factory.loadMappers(['assets/person_mapper.xml']);

final session = factory.openSession();

// Conditions you don't pass are dropped from the SQL entirely
final list = await session.selectList('PersonMapper.selectList', {'NM': 'Hong'});

final params = {'NM': 'Hong Gildong', 'AGE': 30};
await session.insert('PersonMapper.insert', params);
print(params['ID']); // the rowid, filled in by useGeneratedKeys
```

### Mapper class — code generation (recommended)

Like a `@Mapper` interface in Java MyBatis, you **declare** it and the
implementation is generated. You never write a method body.

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

**Point `xml:` at the mapper file and a typo in a statement id fails the
build.** In Java MyBatis you only find out when the application starts.

```
[SEVERE] statement not found in XML: "PersonMapper.selectLst"
available ids: delete, insert, selectById, selectCount, selectList, update
```

See [generator/](generator/README.md) for details.

### Mapper class — by hand

Code generation is optional. You can extend `Mapper` directly:

```dart
class PersonMapper extends Mapper {
  PersonMapper(super.session);

  @override
  String get namespace => 'PersonMapper';

  Future<List<Map<String, dynamic>>> search(Map<String, dynamic> p) =>
      selectList('selectList', p);
}
```

> `namespace` defaults to the class name (`runtimeType`). If you build a Flutter
> release with `--obfuscate`, class names are mangled and statements will not be
> found — pin `namespace` explicitly as shown above. (Generated mappers always
> pin it.)

## Build-time XML validation

This is one thing this port does **better** than Java MyBatis.

When you pass `xml:` to `@MybatisMapper`, the generator parses that file at
build time and checks every statement id you reference:

```
[SEVERE] Statement not found in XML: "PersonMapper.selectByIdd"
available ids: delete, deleteByIds, insert, insertWithSelectKey,
               selectById, selectCount, selectList, selectSorted, update

  package:example/person_mapper.dart:36:33
     ╷
  36 │   Future<Map<String, dynamic>?> findById(@Param('ID') int id);
     │                                 ^^^^^^^^
```

It also catches:

- statement kind mismatch (declaring a `<select>` as `@Insert`)
- `@MybatisMapper` namespace not matching the XML `namespace`

Java MyBatis only reports these when the application starts.

## Examples

| Example | Run | What it shows |
|---|---|---|
| [petstore](example/petstore) | `dart run` | JPetStore port — every dynamic SQL feature |
| [flutter_app](example/flutter_app) | `flutter run` | using it inside a Flutter app |

See [example/README.md](example/README.md) for details.

## Two entry points

The core does **not** depend on Flutter.

```dart
// Pure Dart — console apps, server-side Dart, tests
import 'package:flutter_mybatis/flutter_mybatis_core.dart';

// Flutter — everything above, plus asset loading (loadMapper / loadMappers)
import 'package:flutter_mybatis/flutter_mybatis.dart';
```

It takes a `Database` from `sqflite_common`, so you can plug in any driver:

| Environment | Driver |
|---|---|
| Mobile (Android / iOS) | `sqflite` |
| Desktop · CLI · tests | `sqflite_common_ffi` |
| Web | `sqflite_common_ffi_web` (experimental) |

Only the way you load XML differs:

```dart
// Flutter: from assets
await factory.loadMapper('assets/person_mapper.xml');

// Console / server: from a file
factory.loadMapperFromString(File('assets/person_mapper.xml').readAsStringSync());
```

## Parameters

`#{}` binds through a prepared statement; `${}` is pasted into the SQL as text.
Both accept the same paths as a `test` expression:

```xml
WHERE ID = #{user.id} AND TAG = #{tags[0]} ORDER BY ${sort.column}
```

An exact key wins, so a parameter literally named `user.id` still works. An
unresolvable `#{}` path binds `null`; an unresolvable `${}` throws, because it
could only produce invalid SQL.

Parameter values are converted by [TypeHandler](#typehandler). A type with no
handler throws `UnsupportedTypeException` rather than being coerced with
`toString()`.

## Error handling

A failed statement throws. This is what makes `transaction()` roll back:

```dart
await session.transaction((tx) async {
  await tx.insert('OrderMapper.insert', order);
  await tx.update('ItemMapper.decreaseStock', item); // throws -> all undone
});
```

```dart
// 0.9.x swallowed errors and returned [] / -1 / 0 instead. Opt back in only
// as a temporary bridge:
MybatisConfig.suppressSqlErrors = true;
```

Other mistakes fail loudly rather than silently:

| Situation | Result |
|---|---|
| duplicate statement or `<sql>` id | `XmlParseException` |
| unknown element, e.g. a `<whree>` typo | `XmlParseException` |
| `${name}` with no value | `SqlBuildException` |
| `selectOne` matching several rows | `TooManyResultsException` |

### `timeout` does not cancel the statement

MyBatis maps `timeout` onto JDBC's `Statement.setQueryTimeout`, which asks the
driver to cancel a running statement. sqflite has no equivalent, so here it
only stops waiting: the database may still be running the statement, and it may
still commit.

For a `select` that is harmless. For a write it means the outcome is unknown —
`SqlTimeoutException` says so, and retrying can apply the write twice.

```dart
try {
  await session.insert('Order.insert', order);
} on SqlTimeoutException catch (e) {
  // e.statementId timed out. The row may or may not exist.
  // Check before retrying, or make the statement idempotent.
}
```

`SqlTimeoutException` implements `TimeoutException`, so an existing
`on TimeoutException` handler still catches it.

## Settings

Two defaults deliberately differ from 0.9.x, because the alternative fails
silently: SQL errors propagate, and an unreadable `test` expression throws.
Everything else is off until you opt in.

```dart
void main() {
  MybatisConfig.mapUnderscoreToCamelCase = true;   // USER_NM -> userNm (default false)
  MybatisConfig.strictExpressions = false;         // 0.9.x: an unreadable test becomes false
  MybatisConfig.defaultStatementTimeout = const Duration(seconds: 30);
  runApp(const MyApp());
}
```

## `test` expression support

MyBatis evaluates `test` with OGNL. Dart has no `eval`, so **full OGNL cannot
be ported.** This library ships a dedicated parser covering what real mappers
use.

| Category | Supported |
|---|---|
| Literals | numbers, `'string'`, `"string"`, `true`, `false`, `null` |
| Properties | `a`, `a.b.c`, `a['k']`, `a[0]` |
| Comparison | `==` `!=` `<` `<=` `>` `>=` (`eq` `neq` `lt` `lte` `gt` `gte`) |
| Logic | `and` `or` `not` / `&&` `\|\|` `!`, **parentheses** |
| Arithmetic | `+` `-` `*` `/` `%` |
| Ternary | `cond ? a : b` |
| Methods | `size()` `length()` `isEmpty()` `isNotEmpty()` `trim()` `toString()` `toUpperCase()` `toLowerCase()` `equals(x)` `contains(x)` `startsWith(x)` `endsWith(x)` `indexOf(x)` |

```xml
<if test="ids != null and ids.size() > 0">...</if>
<if test="(A != null or B != null) and C != null">...</if>
<if test="NM.startsWith('Hong') and AGE >= 20">...</if>
```

**Not supported**: OGNL static references (`@Class@member`), object creation
(`new`), lambdas. Unsupported syntax throws by default. In a `<delete>` a
silently-false condition would erase the `<where>` clause and remove every
row, which is why this is strict. Set `MybatisConfig.strictExpressions = false`
to fall back to the 0.9.x behaviour.

In comparisons, a `null` operand yields `false` rather than throwing, and a
`null` link in a property path (`a.b.c`) yields `null`.

## TypeHandler

sqflite only binds `num`, `String`, `Uint8List` and `null`. Passing a `bool` or
a `DateTime` would be a runtime error — TypeHandlers convert them.

```dart
await session.insert('PersonMapper.insert', {
  'ACTIVE_FL': true,          // -> 1
  'JOIN_DT': DateTime.now(),  // -> '2026-09-02T12:00:00.000'
  'STATUS': Status.active,    // -> 'active'
});
```

Registered by default: `DateTimeTypeHandler` (ISO8601), `BoolTypeHandler`
(1/0), `UriTypeHandler`. Replace or add your own:

```dart
TypeHandlerRegistry.register(const YnBoolTypeHandler());         // true -> 'Y'
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

> Decoding results needs a target type, so it is driven by `ResultMap`'s
> `typeConverters`. Automatic typed decoding is not implemented yet.

## Porting status vs MyBatis 3.5.19

### Supported

| Feature | Notes |
|---|---|
| `<select>` `<insert>` `<update>` `<delete>` | |
| `<if>` `<where>` `<set>` `<trim>` | |
| `<choose>` `<when>` `<otherwise>` | |
| `<foreach>` | `collection` `item` `index` `open` `close` `separator` `nullable`; List / Set / Map |
| `<bind>` | |
| `<sql>` + `<include>` | `<property>`, forward references, cross-namespace, cycle detection |
| `#{param}` | prepared statement binding, nested paths (`#{user.id}`, `#{ids[0]}`), and MyBatis attributes such as `#{id, jdbcType=INTEGER}` (ignored) |
| `${param}` | raw string substitution, same path rules. **Never pass user input** |
| `useGeneratedKeys` / `keyProperty` / `keyColumn` | writes the new rowid back into your parameter map |
| `<selectKey>` | `order="BEFORE"` / `"AFTER"` |
| `timeout` | per statement plus a global default. **Stops waiting; does not cancel** — see below |
| `mapUnderscoreToCamelCase` | off by default |
| `test` expressions | OGNL subset (see above) |
| TypeHandler | DateTime · bool · enum · Uri · custom |
| Mapper code generation | `@MybatisMapper` + build_runner, **build-time XML validation** |
| `_parameter` built-in variable | |
| SqlSession | selectList / selectOne / selectCount / insert / update / delete / transaction / batchInsert |
| Logging | level control, custom log handler |

### Not implemented yet

Nested `resultMap` (`<association>` `<collection>` `<discriminator>`) ·
first/second level cache (`<cache>` `<cache-ref>` `flushCache` `useCache`) ·
Interceptor plugins · annotation-inline SQL · `ExecutorType.BATCH` / `REUSE` ·
`ResultHandler` / cursor streaming · automatic typed result decoding

> `resultMap`, `flushCache`, `useCache` and `databaseId` are **parsed but have
> no effect**. Using them logs a warning at mapper load time so you never rely
> on them silently.

### Cannot be ported (structural limits of Dart)

| Feature | Reason |
|---|---|
| Full OGNL | Dart has no `eval` |
| **Runtime** mapper proxies | Flutter has no `dart:mirrors` — replaced by build-time code generation |
| Lazy loading | no runtime bytecode proxies |
| Stored procedures (`CALLABLE`) | not in SQLite |
| Multiple result sets | not in SQLite |
| Connection pooling / JNDI | sqflite owns the connection |
| Distributed / serialized second-level cache | in-memory only |
| `<parameterMap>` | deprecated in MyBatis itself |

## API stability

`1.1.5` means the public API above is stable. Everything on the roadmap
(nested `resultMap`, caching, interceptors, typed decoding) is designed to be
**additive** — new APIs alongside the current ones, not replacements.

## Logging

```dart
MybatisLogger.setLogLevel(MybatisLogLevel.debug);
MybatisLogger.setShowSql(true);
MybatisLogger.setShowParams(true);
```

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

This library reimplements the MyBatis XML dialect and API shape in Dart; no
MyBatis source code is included. The petstore example derives its schema and
sample data from [JPetStore 6](https://github.com/mybatis/jpetstore-6), also
Apache-2.0.
