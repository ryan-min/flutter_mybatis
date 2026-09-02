# flutter_mybatis_generator

[flutter_mybatis](../) 용 코드 생성기입니다.

Java MyBatis의 `@Mapper` 인터페이스처럼 **선언만** 하면 구현이 생성됩니다.
Flutter에는 `dart:mirrors`가 없어 런타임 동적 프록시가 불가능하므로,
빌드 시점 코드 생성으로 같은 효과를 냅니다.

## 설치

```yaml
dependencies:
  flutter_mybatis:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      ref: master

dev_dependencies:
  build_runner: ^2.4.0
  flutter_mybatis_generator:
    git:
      url: https://github.com/ryan-min/flutter_mybatis.git
      path: generator
```

## 사용

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

메서드 본문을 한 줄도 쓰지 않습니다. `PersonMapper(session)` 은 생성된
`_$PersonMapper` 로 연결됩니다(factory 리다이렉트).

## 빌드 시점 XML 검증

`xml:` 을 지정하면 **statement id 오타를 빌드 시점에** 잡습니다.
Java MyBatis는 앱 기동 시점에야 알 수 있는 오류입니다.

```
[SEVERE] XML에 statement가 없습니다: "PersonMapper.selectLst"
사용 가능한 id: delete, deleteByIds, insert, insertWithSelectKey,
                selectById, selectCount, selectList, selectSorted, update

  package:flutter_mybatis_example/person_mapper.dart:36:33
     ╷
  36 │   Future<Map<String, dynamic>?> findById(@Param('ID') int id);
     │                                 ^^^^^^^^
```

다음도 함께 검증합니다.

- statement 종류 불일치 (`<select>` 를 `@Insert` 로 선언)
- `@MybatisMapper` namespace 와 XML `namespace` 불일치
- XML 파일 자체를 읽지 못하는 경우

## 어노테이션

| 어노테이션 | 생성되는 호출 |
|---|---|
| `@Select(id)` | `session.selectList(...)` |
| `@SelectOne(id)` | `session.selectOne(...)` |
| `@SelectCount(id, column)` | `session.selectCount(..., countColumn: column)` |
| `@Insert(id)` | `session.insert(...)` |
| `@Update(id)` | `session.update(...)` |
| `@Delete(id)` | `session.delete(...)` |
| `@Param(name)` | 파라미터 Map의 키 지정 |

- `id` 를 생략하면 **메서드명**을 statement id로 씁니다.
- 파라미터가 `Map<String, dynamic>` 하나면 그대로 전달합니다.
- 그 외에는 `@Param` 이름(없으면 파라미터명)으로 Map을 조립합니다.
- `limit` / `offset` 이름의 파라미터는 페이징 인자로 전달되며
  파라미터 Map에는 들어가지 않습니다.

## 제약

- 추상 메서드에만 적용됩니다 (`@MybatisMapper` 는 `abstract class` 전용).
- 결과값은 `Map<String, dynamic>` 입니다. 타입 객체 자동 매핑은 미지원입니다.
