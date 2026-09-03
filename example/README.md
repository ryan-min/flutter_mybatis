# Examples

[한국어](README-KR.md)

Two of them. **Start with JPetStore.**

| Example | Run | What it shows |
|---|---|---|
| [**petstore/**](petstore) — JPetStore | `dart run` (~3s) | Port of the official MyBatis sample; every dynamic SQL feature |
| [**flutter_app/**](flutter_app) — Flutter UI | `flutter run` | Using the library inside a Flutter app |

## Fastest path

```bash
cd petstore
dart pub get
dart run
```

No emulator, no browser, no Android Studio. It is a plain Dart console app
against an in-memory SQLite database. The Flutter SDK does have to be
installed — `flutter_mybatis` depends on it for asset loading — so use the
`dart` that ships with Flutter.

To see the SQL as it runs:

```bash
dart run bin/petstore.dart --sql
```

## Flutter app example

```bash
cd flutter_app
flutter pub get
dart run build_runner build
flutter run
```

## Why the console example is plain Dart

The `flutter_mybatis` core does not depend on Flutter. There are two entry
points:

```dart
// Pure Dart — console, server-side, tests
import 'package:flutter_mybatis/flutter_mybatis_core.dart';

// Flutter — the core plus asset loading (loadMapper / loadMappers)
import 'package:flutter_mybatis/flutter_mybatis.dart';
```

The core takes a `Database` from `sqflite_common`, so any driver works:

| Environment | Driver |
|---|---|
| Mobile (Android / iOS) | `sqflite` |
| Desktop · CLI · tests | `sqflite_common_ffi` |
| Web | `sqflite_common_ffi_web` (experimental) |

Only XML loading differs:

```dart
// Flutter: from assets
await factory.loadMapper('assets/petstore_mapper.xml');

// Console / server: from a file
factory.loadMapperFromString(File('assets/petstore_mapper.xml').readAsStringSync());
```
