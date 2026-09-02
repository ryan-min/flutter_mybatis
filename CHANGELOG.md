# Changelog

## 1.0.0

First public release.

`0.9.0` was an internal preview. This is the first release intended for outside
use: the API surface below is stable, and everything on the roadmap is designed
to be additive rather than a replacement.

### XML mapping

- `<select>` `<insert>` `<update>` `<delete>`
- Dynamic SQL: `<if>` `<where>` `<set>` `<trim>`
  `<choose>`/`<when>`/`<otherwise>` `<foreach>` `<bind>`
- `<sql>` + `<include>` with `<property>`, forward references, cross-namespace
  references and cycle detection
- `#{param}` prepared-statement binding, `${param}` raw substitution
- `useGeneratedKeys` / `keyProperty` / `keyColumn` — the new rowid is written
  back into the parameter map
- `<selectKey>` with `order="BEFORE"` and `order="AFTER"`
- `timeout`, per statement and as a global default
- `_parameter` built-in variable

### `test` expressions

A dedicated parser covering an OGNL subset: literals, property and index
access, comparison, logic with parentheses, arithmetic, the ternary operator
and 13 methods (`size()`, `isEmpty()`, `startsWith()`, ...).

Full OGNL cannot be ported because Dart has no `eval`. Unsupported syntax
evaluates to `false` with a warning; set `MybatisConfig.strictExpressions` to
throw instead.

### Mapper code generation

`flutter_mybatis_generator` turns an abstract class annotated with
`@MybatisMapper` into an implementation — you write no method bodies.

Passing `xml:` makes the generator validate every statement id, statement kind
and namespace **at build time**. Java MyBatis only reports these at start-up.

### TypeHandler

sqflite binds only `num`, `String`, `Uint8List` and `null`. Handlers convert
`DateTime`, `bool`, `enum` and `Uri`, and you can register your own.

### Pure Dart core

`flutter_mybatis_core.dart` has no Flutter dependency, so the library runs in
console apps, server-side Dart and tests. It takes a `Database` from
`sqflite_common`, so `sqflite`, `sqflite_common_ffi` and
`sqflite_common_ffi_web` all work. `flutter_mybatis.dart` adds asset loading.

### Settings

`mapUnderscoreToCamelCase`, `strictExpressions` and
`defaultStatementTimeout` — all off by default.

### Examples

- `example/petstore` — a port of JPetStore 6, runnable with `dart run`
- `example/flutter_app` — the same library inside a Flutter app

### Not implemented yet

Nested `resultMap` (`<association>` `<collection>` `<discriminator>`), first and
second level cache, Interceptor plugins, annotation-inline SQL,
`ExecutorType.BATCH`/`REUSE`, `ResultHandler`/cursor streaming, and automatic
typed result decoding.

`resultMap`, `flushCache`, `useCache` and `databaseId` are parsed but have no
effect; using them logs a warning when the mapper is loaded.

### Cannot be ported

Full OGNL, runtime mapper proxies, lazy loading, stored procedures, multiple
result sets, connection pooling, and distributed second-level cache. The README
explains why.

## 0.9.0

Internal preview.

- XML-based SQL mapping
- Dynamic SQL: `<if>`, `<where>`, `<set>`, `<foreach>`, `<choose>`, `<trim>`
- `#{paramName}` binding
- SqlSession: selectList, selectOne, selectCount, insert, update, delete,
  transaction
- Mapper base class
- Log level configuration and a custom log handler
