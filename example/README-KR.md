# flutter_mybatis 예제

두 가지가 있습니다. **처음이라면 JPetStore부터 보십시오.**

| 예제 | 실행 | 무엇을 보여주나 |
|---|---|---|
| [**petstore/**](petstore) — JPetStore | `dart run` (약 3초) | MyBatis 공식 샘플 이식. 동적 SQL 전 기능 |
| [**flutter_app/**](flutter_app) — Flutter UI | `flutter run` | 실제 앱에서 쓰는 형태 |

## 가장 빠른 길

```bash
cd petstore
dart pub get
dart run
```

에뮬레이터도, 브라우저도, 안드로이드 스튜디오도 필요 없습니다. 순수 Dart
콘솔 앱이고 DB는 인메모리 SQLite입니다. 다만 `flutter_mybatis` 가 에셋 로딩
때문에 Flutter SDK에 의존하므로 SDK 자체는 설치되어 있어야 하고, 함께
딸려오는 `dart` 를 쓰면 됩니다.

실행되는 SQL까지 보려면:

```bash
dart run bin/petstore.dart --sql
```

## Flutter 앱 예제

```bash
cd flutter_app
flutter pub get
dart run build_runner build
flutter run
```

## 왜 콘솔 예제가 순수 Dart로 도는가

`flutter_mybatis` 코어는 Flutter에 의존하지 않습니다. 진입점이 둘입니다.

```dart
// 순수 Dart — 콘솔, 서버 사이드, 테스트
import 'package:flutter_mybatis/flutter_mybatis_core.dart';

// Flutter — 위 코어 전부 + assets 로딩(loadMapper / loadMappers)
import 'package:flutter_mybatis/flutter_mybatis.dart';
```

`sqflite_common` 의 `Database` 를 받으므로 아래 어느 드라이버와도 붙습니다.

| 환경 | 드라이버 |
|---|---|
| 모바일 (Android / iOS) | `sqflite` |
| 데스크톱 · CLI · 테스트 | `sqflite_common_ffi` |
| 웹 | `sqflite_common_ffi_web` (experimental) |

XML을 어디서 읽느냐만 다릅니다.

```dart
// Flutter: assets에서
await factory.loadMapper('assets/petstore_mapper.xml');

// 콘솔/서버: 파일에서
factory.loadMapperFromString(File('assets/petstore_mapper.xml').readAsStringSync());
```
