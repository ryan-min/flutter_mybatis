# flutter_mybatis_generator

[한국어](README-KR.md)

Code generator for [flutter_mybatis](../).

Declare a mapper the way you would a MyBatis `@Mapper` interface, and the
implementation is generated. Flutter has no `dart:mirrors`, so runtime dynamic
proxies are impossible; build-time code generation achieves the same result.

## Install

```yaml
dependencies:
  flutter_mybatis:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      ref: v1.0.0

dev_dependencies:
  build_runner: ^2.4.0
  flutter_mybatis_generator:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      ref: v1.0.0
      path: generator
```

## Use

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

  @SelectCount('selectCount')
  Future<int> countAll(@Param('activeOnly') bool activeOnly);

  @Insert('insert')
  Future<int> add(Map<String, dynamic> person);

  @Update('update')
  Future<int> modify(Map<String, dynamic> person);

  @Delete('delete')
  Future<int> remove(@Param('ID') int id);
}
```

```bash
dart run build_runner build
```

You write no method bodies. `PersonMapper(session)` resolves to the generated
`_$PersonMapper` through the redirecting factory constructor.

## Build-time XML validation

Passing `xml:` makes the generator **catch statement id typos at build time.**
Java MyBatis only reports these when the application starts.

```
[SEVERE] Statement not found in XML: "PersonMapper.selectLst"
available ids: delete, deleteByIds, insert, insertWithSelectKey,
               selectById, selectCount, selectList, selectSorted, update

  package:example/person_mapper.dart:36:33
     ╷
  36 │   Future<Map<String, dynamic>?> findById(@Param('ID') int id);
     │                                 ^^^^^^^^
```

It also rejects:

- a statement kind mismatch, e.g. declaring a `<select>` as `@Insert`
- a `@MybatisMapper` namespace that does not match the XML `namespace`
- a mapper XML that cannot be read or parsed

## Annotations

| Annotation | Generated call |
|---|---|
| `@Select(id)` | `session.selectList(...)` |
| `@SelectOne(id)` | `session.selectOne(...)` |
| `@SelectCount(id, column)` | `session.selectCount(..., countColumn: column)` |
| `@Insert(id)` | `session.insert(...)` |
| `@Update(id)` | `session.update(...)` |
| `@Delete(id)` | `session.delete(...)` |
| `@Param(name)` | key in the parameter map |

- Omitting `id` uses the **method name** as the statement id.
- A single `Map<String, dynamic>` parameter is forwarded unchanged.
- Otherwise a map is assembled from `@Param` names, falling back to the Dart
  parameter names.
- Parameters named `limit` and `offset` are forwarded as paging arguments and
  are not put into the parameter map.

## Limitations

- Only abstract classes; `@MybatisMapper` requires `abstract class`.
- Results are `Map<String, dynamic>`. Automatic typed mapping is not
  implemented yet.
