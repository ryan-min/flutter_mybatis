# Flutter UI 예제

`flutter_mybatis`를 실제 Flutter 앱에서 쓰는 형태입니다.
동적 SQL 자체를 보려면 [petstore](../petstore) 쪽이 더 촘촘합니다.

## 실행

```bash
flutter pub get
dart run build_runner build   # Mapper 구현 생성
flutter run
```

## 구성

| 파일 | 내용 |
|---|---|
| `assets/person_mapper.xml` | 매퍼 XML |
| `lib/person_mapper.dart` | Mapper 선언 (본문 없음) |
| `lib/person_mapper.g.dart` | 생성된 구현 |
| `lib/main.dart` | 검색 · 등록 · 삭제 화면 |

## Flutter에서 달라지는 부분

assets에서 XML을 읽습니다.

```dart
final factory = SqlSessionFactory(database);
await factory.loadMappers(['assets/person_mapper.xml']);
```

```yaml
flutter:
  assets:
    - assets/person_mapper.xml
```

나머지는 콘솔 예제와 같습니다.

## 화면에서 확인할 것

- **검색창에 입력** → `<if>` 조건절이 SQL에 붙고 빠지는 것
- **필터 칩** → 숫자 비교(`minAge > 0`)와 `<include>` 조각
- **+ 버튼** → `useGeneratedKeys`로 받은 ID가 스낵바에 표시됨
- **콘솔** → `MybatisLogger.setDebugMode(true)` 로 실행 SQL이 출력됨

## 테스트

```bash
flutter test
```

생성된 매퍼가 실제 SQLite에서 동작하는지 13개 테스트로 확인합니다.
