# Changelog

## 1.1.3

`<where>` parity with MyBatis, and honest `timeout` semantics.

### Fixed — `<where>` did not strip `AND` written on its own line

MyBatis strips a leading conjunction followed by *any* whitespace: its prefix
list carries a tab, newline and carriage-return variant of `AND` and `OR`. This
port matched only on a single space, so

```xml
<where>
  AND
  ID = #{id}
</where>
```

built `WHERE AND ID = ?` — a syntax error. Splitting a long condition across
lines is ordinary formatting, and it silently did not work. A column named
`ORDER_ID` or `ANDROID_ID` still keeps its name.

An explicit `<trim prefixOverrides="AND |OR ">` deliberately keeps matching the
override text verbatim, including its trailing space. That is what MyBatis does
with a user-supplied override, and it is now pinned by a test.

### Changed — a `timeout` now says it did not cancel anything

MyBatis maps `timeout` onto JDBC's `Statement.setQueryTimeout`, which asks the
driver to cancel the running statement. sqflite has no equivalent, so this
package could only ever stop waiting — the database may still be running the
statement, and it may still commit. On a write that means the outcome is
unknown and a retry can apply it twice.

A timeout now throws `SqlTimeoutException`, which names the statement and says
plainly that it was not cancelled. It implements `TimeoutException`, so an
existing `on TimeoutException` handler still catches it. The READMEs say the
same thing in the porting table and in a section of their own.

### Documentation

- The generator needs Dart 3.5; the library needs only 3.0. Both READMEs say so
  where the generator is introduced.

## 1.1.2

1.1.1 stripped SQL comments, but too late. This does it at the right point, and
fixes `<trim>`.

### Fixed — a comment swallowed the element that followed it

1.1.1 removed comments while flattening the finished statement onto one line.
By then the newline that ends a `--` comment was already gone, so the comment
ran on to the end of everything:

```xml
UPDATE ACCOUNT SET ACTIVE = 0
-- only accounts that went quiet
<where><if test="d != null">LAST_SEEN &lt; #{d}</if></where>
```

built as `UPDATE ACCOUNT SET ACTIVE = 0` — valid SQL that updates every row.
1.1.0's version of this bug produced a syntax error, so the database rejected
it; 1.1.1's produced a statement that runs. The same shape truncated a
`<foreach>` at its first element (`... IN (?` with one parameter instead of
three).

Comments are now removed per XML text node while parsing, before the node is
trimmed and before siblings are joined. The newline is still there at that
point, so the comment ends where it should. Quoted strings and quoted
identifiers are still left alone.

The 1.1.1 tests missed this because the comment and its victim were in the same
text node. The new tests put them in different nodes.

### Fixed — `<trim prefix="WHERE" prefixOverrides="AND |OR ">`

Two defects in the canonical MyBatis example.

`prefix` was concatenated straight onto the body, so `prefix="WHERE"` gave
`WHEREID = ?`. Prefix and suffix are now separated by a space, as MyBatis does.

Whitespace inside an override is significant, and it was being trimmed away, so
`prefixOverrides="AND |OR "` matched the `OR` that starts `ORDER_ID` and built
`WHERE DER_ID = ?`. The match now keeps the space; only the removal drops it.

`<where>` and `<set>` were never affected — they already matched on `'AND '`
and `'OR '` with the space, and inserted their own.

### Fixed — `selectCount` threw on a NULL aggregate

`SELECT SUM(QTY) AS CNT FROM T WHERE ...` returns one row holding NULL when
nothing matches. 1.1.0 made that throw. It is a count of zero, not a
misconfigured statement, and it returns 0 again. A row with no usable count
column still throws.

### Changed — an unreadable `test` warns once, not once per query

With `strictExpressions = false` the warning was emitted on every build of the
statement. It is now emitted once per distinct message.

## 1.1.1

Follow-up to 1.1.0: two more SQL-generation defects, one dependency the package
never used, and documentation that did not match the code.

### Fixed — SQL comments swallowed the rest of the statement

Whitespace normalisation collapsed a statement onto one line without
understanding comments, so a `--` comment ate everything after it:

```sql
SELECT ID, NM
-- active only
FROM PERSON WHERE DEL_FL = 'N'
```

produced `SELECT ID, NM -- active only FROM PERSON WHERE DEL_FL = 'N'`, which
is `SELECT ID, NM`. `/* ... */` had the same shape of problem. Comments are now
stripped, and quoted identifiers (`"my  col"`, `` `col` ``, `[col]`) keep their
spacing the way string literals already did.

### Fixed — `<foreach>` with `#{item, jdbcType=...}` bound null

1.1.0 fixed the jdbcType suffix for plain parameters; inside `<foreach>` the
item rewrite still matched on the whole `#{...}` body, so `#{i,jdbcType=INTEGER}`
was not recognised as a reference to `item="i"` and every element bound null.

### Changed — `sqflite` is no longer a dependency

The package only ever imported `sqflite_common`, the pure-Dart API. Depending
on `sqflite` as well pinned the package to that driver and to its platforms for
no benefit. Applications keep choosing their own driver (`sqflite`,
`sqflite_common_ffi`, `sqflite_common_ffi_web`); nothing in the public API
changes. `platforms:` now declares `web` as well.

If your app used `sqflite` without declaring it, add it to your own
`pubspec.yaml` — it was reaching you transitively.

### Fixed — generated mappers emitted a const parameter map

A mapper method with no parameters generated `const <String, dynamic>{}`. An
`insert` with `useGeneratedKeys` writes the generated key back into that map,
which throws on a const map. The generated map is now mutable.

### Documentation

- `ConditionEvaluator`'s dartdoc described the pre-1.1.0 default (evaluate to
  `false` with a warning). The default has been "throw" since 1.1.0.
- The English README claimed all defaults preserve 0.9.x behaviour. Two
  deliberately do not; that is what the migration section is for.
- The petstore example said it needs no Flutter. It needs no emulator or
  browser, but the Flutter SDK does have to be installed.
- `MapperProxy` and `MapperRegistry` are exported again from
  `flutter_mybatis_core.dart`; they are part of the 0.9.x-compatible path.
- Removed the unused `ConditionEvaluationException`.
- `MybatisConfig`'s own dartdoc still claimed every default preserves 0.9.x
  behaviour, and `UnsupportedExpressionException` described the old default
  too.
- The English and Korean READMEs are now section-for-section equivalent. Both
  install from git and pin a tag: the package is not on pub.dev, so the
  `flutter_mybatis: ^1.0.0` snippet and the pub badges did not work.

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
