# Flutter UI example

[한국어](README-KR.md)

Using `flutter_mybatis` inside a real Flutter app. For dynamic SQL itself the
[petstore](../petstore) example covers more ground.

## Run

```bash
flutter pub get
dart run build_runner build   # generate the mapper implementation
flutter run
```

## Layout

| File | Contents |
|---|---|
| `assets/person_mapper.xml` | the mapper XML |
| `lib/person_mapper.dart` | mapper declaration (no method bodies) |
| `lib/person_mapper.g.dart` | generated implementation |
| `lib/main.dart` | search / insert / delete screen |

## What differs in Flutter

XML is read from assets:

```dart
final factory = SqlSessionFactory(database);
await factory.loadMappers(['assets/person_mapper.xml']);
```

```yaml
flutter:
  assets:
    - assets/person_mapper.xml
```

Everything else is the same as the console example.

## What to look at in the running app

- **type in the search box** — `<if>` clauses appear and disappear from the SQL
- **filter chips** — numeric comparison (`minAge > 0`) and an `<include>` fragment
- **the + button** — the id returned by `useGeneratedKeys` is shown in a snackbar
- **the console** — `MybatisLogger.setDebugMode(true)` prints the executed SQL

## Tests

```bash
flutter test
```

13 tests check that the generated mapper works against real SQLite.
