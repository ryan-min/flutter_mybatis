# Changelog

## 1.1.0

SQL generation correctness. **Behaviour changes** — this is why it is a minor
release rather than another patch.

### Fixed — string literals were being rewritten

Whitespace was normalised across the whole statement, so

```sql
SELECT 'hello   world'
```

became `SELECT 'hello world'`. The literal's own spacing is part of its value;
LIKE patterns and JSON text were affected. Tidying now stops at the quotes.

### Fixed — `#{id, jdbcType=INTEGER}` bound null

Java mappers routinely annotate a parameter:

```xml
WHERE ID = #{id, jdbcType=INTEGER}
```

1.0.2 widened the placeholder pattern, so the whole `id, jdbcType=INTEGER`
string was treated as a property path, failed to resolve, and bound `null`.
Only the property is read now; `jdbcType` and `javaType` are ignored.

### Fixed — `selectCount` returned 0 under `mapUnderscoreToCamelCase`

`SELECT COUNT(*) AS CNT` arrives as `cnt` once the setting is on, but the
count was still read from `CNT`.

### Fixed — `selectOne` broke statements that already ended in LIMIT

It appended `LIMIT 2`, producing `... LIMIT 1 LIMIT ?`. The rows are counted
instead; the statement is no longer rewritten.

### Fixed — `offset` without `limit` produced invalid SQL

SQLite only accepts `OFFSET` as part of a `LIMIT` clause. `LIMIT -1 OFFSET ?`
is emitted now.

### Fixed — `<foreach>` could not bind item properties

The common bulk-insert shape did not work:

```xml
<foreach collection="rows" item="r" separator=",">(#{r.id}, #{r.nm})</foreach>
```

Only a bare `#{r}` was rewritten per iteration, so `#{r.id}` bound `null`.
`collection` now also accepts a nested path (`collection="req.ids"`).

### Fixed — duplicate ids across mapper files

Two files declaring the same `namespace.id` silently replaced each other.
Loading the second one now throws `MapperLoadException`.

### Fixed — XML attribute typos are caught

`order="BEFOR"` on a `<selectKey>` silently became `AFTER`, and a boolean
attribute that was not exactly `"true"` became `false`. Both are rejected now,
as is a `<choose>` with an unexpected child or a second `<otherwise>`.

### Changed — a custom log handler now runs in release builds

Logging was gated on debug builds entirely, so forwarding SQL errors to a
crash reporter was impossible in production. Console output is still
debug-only; a handler set with `setLogHandler` always runs. Keep
`setShowParams` off in release — parameters can contain personal data.

### Changed — `#{}` reports malformed paths like `<if>` does

`resolvePropertyPath` turned every failure into `null`, so a typo in a
placeholder was indistinguishable from a parameter that simply had no value —
even though `<if test="...">` already threw on the same text. Under
`strictExpressions` (now the default) a path that cannot be *read* throws;
a path that is readable but absent still binds `null`.

### Changed — `strictExpressions` defaults to `true`

An expression the parser cannot read used to evaluate to `false`. In a
`<delete>` that erased the `<where>` clause entirely, turning a guarded delete
into one that removes every row. Set it to `false` to restore 0.9.x behaviour.

## 1.0.2

MyBatis compatibility fixes. **Behaviour changes** in the last two items.

### Added — nested property paths

`#{}` and `${}` now accept the same paths as a `test` expression:

```xml
WHERE ID = #{user.id} AND TAG = #{tags[0]} ORDER BY ${sort.column}
```

Previously only a flat key matched (`#\{(\w+)\}`), so `#{user.id}` was left
in the SQL untouched while `<if test="user.id != null">` evaluated fine — a
confusing asymmetry. Both now share one resolver.

An exact key still wins, so a parameter literally named `user.id` keeps
working. An unresolvable `#{}` path binds `null`, as a missing key always did.

### Changed — `<bind>` uses the expression evaluator

`<bind name="pattern" value="'%' + name + '%'"/>` is now evaluated with the
same engine as `<if test="...">`, matching MyBatis. Values the evaluator does
not understand fall back to the previous literal substitution.

### Changed — unsupported parameter types throw

`TypeHandlerRegistry.encode` used to fall back to `toString()`, which quietly
stored `Instance of 'Customer'`. It now throws `UnsupportedTypeException`.
Register a `TypeHandler` for the type instead.

### Fixed — the generator no longer swallows a parameter named `limit`

`limit` and `offset` were treated as paging arguments on every method, so

```dart
@Update('updateQuota')
Future<int> updateQuota(@Param('limit') int limit);
```

lost its parameter. Paging is now applied only where it exists — list queries.

### Added

- `UnsupportedTypeException`
- `resolvePropertyPath` — the shared resolver behind `#{}`, `${}` and `test`
- Regression tests for nested paths, the old asymmetry, and the `limit`
  parameter case

## 1.0.1

Correctness fixes found in review right after 1.0.0. **Behaviour changes** —
read the first item before upgrading.

### Fixed — SQL errors are no longer swallowed

`selectList` / `insert` / `update` / `delete` used to log a failure and return
an empty list, `-1` or `0`. That made `transaction()` unable to roll back: a
constraint violation inside a transaction left the earlier statements
committed. Errors now propagate to the caller.

If you depend on the old behaviour, opt back in explicitly:

```dart
MybatisConfig.suppressSqlErrors = true; // 0.9.x behaviour
```

### Fixed — silent failures that hid mistakes

- A duplicate statement id or `<sql>` id used to overwrite the earlier one.
  It now throws `XmlParseException`.
- An unknown XML element (a typo such as `<whree>`, or a MyBatis element this
  port does not implement) used to be flattened into SQL text. It now throws.
- `${name}` with no matching value used to be left in the SQL as-is, producing
  a confusing SQLite syntax error downstream. It now throws
  `SqlBuildException` naming the property.
- `selectOne` returned the first of several rows. It now throws
  `TooManyResultsException`, matching MyBatis.
- The generator accepted an XML with several `<mapper>` elements and validated
  only the first. It now rejects the file.

### Fixed — documentation

- The library-level example used a different XML path and parameter names than
  the README.
- Duplicate and empty doc comments in `ResultMap`.

### Added

- `MybatisConfig.suppressSqlErrors` (default `false`).
- `TooManyResultsException`.
- Execution-layer regression tests: transaction rollback on constraint
  violation and on malformed SQL, batch rollback, and the legacy flag.
- GitHub Actions CI running analyze, tests and a publish dry-run for the
  library, the generator and both examples.

## 1.0.0

First public release.

`0.9.0` was an internal preview. This is the first release intended for outside
use.

> Superseded by 1.0.1, which corrects the execution-layer failure semantics.
> Use 1.0.1 or later.

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
