# Changelog

## 1.1.5

First release on pub.dev, alongside `flutter_mybatis` 1.1.5. No change to the
generator's own API. Requires Dart 3.5, while the library it generates for
requires only Dart 3.0.

## 1.1.3

Version aligned with `flutter_mybatis` 1.1.3. No change to the generator's own
API. Note that this package requires Dart 3.5, while the library it generates
for requires only Dart 3.0.

## 1.1.2

Version aligned with `flutter_mybatis` 1.1.2, which fixes SQL comment handling
and `<trim>`. No change to the generator's own API.

## 1.1.1

### Fixed — const parameter map broke `useGeneratedKeys`

A mapper method with no parameters generated `const <String, dynamic>{}`. An
`insert` with `useGeneratedKeys` writes the generated key back into the
parameter map, and writing to a const map throws. The emitted map is now
mutable.

## 1.1.0

Version aligned with `flutter_mybatis` 1.1.0, which changes SQL generation
behaviour. No change to the generator's own API.

Note that the runtime parser is now stricter than the build-time one: it
rejects duplicate ids, unknown elements and malformed attributes that this
generator does not yet check. Sharing one parser is planned.

## 1.0.2

### Fixed

- `limit` and `offset` were treated as paging arguments on **every** method, so
  a mapper such as `@Update('updateQuota') Future<int> updateQuota(@Param('limit') int limit)`
  silently lost its parameter. Paging now applies only to list queries.
- A mapper XML containing more than one `<mapper>` element is rejected instead
  of validating only the first one.

## 1.0.1

- Aligned with `flutter_mybatis` 1.0.1.

## 1.0.0

First public release, aligned with `flutter_mybatis` 1.0.0.

### Code generation

Turns an abstract class annotated with `@MybatisMapper` into an
implementation — you write no method bodies.

- `@Select` `@SelectOne` `@SelectCount` `@Insert` `@Update` `@Delete`
- `@Param` names the key used in the parameter map
- Omitting the statement id uses the method name
- A single `Map<String, dynamic>` parameter is forwarded unchanged; otherwise a
  map is assembled from `@Param` names, falling back to Dart parameter names
- Parameters named `limit` and `offset` are forwarded as paging arguments and
  are not put into the parameter map

### Build-time XML validation

With `@MybatisMapper(..., xml: '...')` the generator parses the mapper XML at
build time and rejects:

- a statement id that does not exist (listing the ids that do)
- a statement kind mismatch, e.g. declaring a `<select>` as `@Insert`
- a namespace that does not match the XML
- a mapper XML that cannot be read or parsed

Java MyBatis only reports these when the application starts.

### Notes

- Results are `Map<String, dynamic>`; automatic typed mapping is not
  implemented yet.
- `source_gen` 2.0.0 still uses the legacy analyzer element model, so the
  generator suppresses `deprecated_member_use` internally.
