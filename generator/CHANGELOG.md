# Changelog

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
