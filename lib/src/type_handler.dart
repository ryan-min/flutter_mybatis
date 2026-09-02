/// Type handlers (the equivalent of MyBatis `TypeHandler`).
///
/// sqflite only binds `num`, `String`, `Uint8List` and `null`. Passing a
/// `DateTime`, `bool` or `enum` directly would be a runtime error, so type
/// handlers convert them in one place.
///
/// SQLite has a thinner type system than JDBC, so this is needed more often
/// here than in Java MyBatis.
library;

import 'dart:typed_data';

/// Converts between a Dart value and a SQLite value.
abstract class TypeHandler<T> {
  /// Const constructor for subclasses.
  const TypeHandler();

  /// Whether this handler can convert [value].
  bool canHandle(Object? value) => value is T;

  /// Dart value -> a value sqflite can bind.
  Object? encode(T value);

  /// SQLite value -> Dart value.
  ///
  ///
  /// Only used where the target type is known, such as in a [ResultMap].
  T? decode(Object? value);
}

/// `DateTime` <-> ISO 8601 text.
///
/// Storing text keeps `BETWEEN`, `date()` and ORDER BY working naturally.
class DateTimeTypeHandler extends TypeHandler<DateTime> {
  /// Creates an ISO 8601 handler.
  const DateTimeTypeHandler();

  @override
  Object? encode(DateTime value) => value.toIso8601String();

  @override
  DateTime? decode(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse(value.toString());
  }
}

/// `DateTime` <-> epoch milliseconds.
///
/// [DateTimeTypeHandler] is the default; register this one to store integers.
///
/// ```dart
/// TypeHandlerRegistry.register(const DateTimeMillisTypeHandler());
/// ```
class DateTimeMillisTypeHandler extends TypeHandler<DateTime> {
  /// Creates an epoch-millis handler.
  const DateTimeMillisTypeHandler();

  @override
  Object? encode(DateTime value) => value.millisecondsSinceEpoch;

  @override
  DateTime? decode(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse(value.toString());
  }
}

/// `bool` <-> `1` / `0`.
class BoolTypeHandler extends TypeHandler<bool> {
  /// Creates a 1/0 handler.
  const BoolTypeHandler();

  @override
  Object? encode(bool value) => value ? 1 : 0;

  @override
  bool? decode(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().toUpperCase();
    return text == 'Y' || text == 'TRUE' || text == '1';
  }
}

/// `bool` <-> `'Y'` / `'N'`.
///
/// Common in enterprise schemas. [BoolTypeHandler] is the default, so
/// register this one to override it.
class YnBoolTypeHandler extends TypeHandler<bool> {
  /// Creates a 'Y'/'N' handler.
  const YnBoolTypeHandler();

  @override
  Object? encode(bool value) => value ? 'Y' : 'N';

  @override
  bool? decode(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value.toString().toUpperCase() == 'Y';
  }
}

/// `enum` <-> its name.
///
/// [decode] needs [values] because each enum has its own set of constants.
class EnumTypeHandler<T extends Enum> extends TypeHandler<T> {
  /// Every constant of the enum, e.g. `Status.values`.
  final List<T> values;

  /// Creates a handler for the enum described by [values].
  const EnumTypeHandler(this.values);

  @override
  Object? encode(T value) => value.name;

  @override
  T? decode(Object? value) {
    if (value == null) return null;
    final name = value.toString();
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// `Uri` <-> text.
class UriTypeHandler extends TypeHandler<Uri> {
  /// Creates a `Uri` handler.
  const UriTypeHandler();

  @override
  Object? encode(Uri value) => value.toString();

  @override
  Uri? decode(Object? value) =>
      value == null ? null : Uri.tryParse(value.toString());
}

/// Registry of [TypeHandler]s.
///
/// Registered handlers are applied automatically when binding parameters.
///
/// ```dart
/// void main() {
///   // DateTime, bool and Uri handlers are registered by default
///   TypeHandlerRegistry.register(const YnBoolTypeHandler()); // store 'Y'/'N'
///   TypeHandlerRegistry.register(EnumTypeHandler(Status.values));
///   runApp(const MyApp());
/// }
/// ```
class TypeHandlerRegistry {
  TypeHandlerRegistry._();

  static final List<TypeHandler<Object>> _handlers = [];
  static bool _initialized = false;

  static void _ensureDefaults() {
    if (_initialized) return;
    _initialized = true;
    _handlers.addAll(<TypeHandler<Object>>[
      const DateTimeTypeHandler(),
      const BoolTypeHandler(),
      const UriTypeHandler(),
    ]);
  }

  /// Registers [handler].
  ///
  /// It takes precedence over handlers registered earlier for the same type,
  /// so registering one is how you replace a default.
  static void register<T extends Object>(TypeHandler<T> handler) {
    _ensureDefaults();
    _handlers.insert(0, handler as TypeHandler<Object>);
  }

  /// How many handlers are registered.
  static int get count {
    _ensureDefaults();
    return _handlers.length;
  }

  /// Restores the default handlers (useful in tests).
  static void reset() {
    _handlers.clear();
    _initialized = false;
  }

  /// Returns the handler for [value], or null.
  static TypeHandler<Object>? handlerFor(Object? value) {
    if (value == null) return null;
    _ensureDefaults();
    for (final handler in _handlers) {
      if (handler.canHandle(value)) return handler;
    }
    return null;
  }

  /// Converts [value] into something sqflite can bind.
  ///
  /// Values that are already bindable are returned unchanged.
  static Object? encode(Object? value) {
    if (value == null) return null;
    if (value is num || value is String || value is Uint8List) return value;

    final handler = handlerFor(value);
    if (handler != null) return handler.encode(value);

    // 핸들러가 없는 미지원 타입은 문자열로 (sqflite 오류보다 낫다)
    if (value is Enum) return value.name;
    return value.toString();
  }
}
