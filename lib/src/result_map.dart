/// Maps result rows onto objects (the equivalent of MyBatis `ResultMap`).
class ResultMap<T> {
  /// Column name to field name.
  final Map<String, String> columns;

  /// Builds the object from the mapped row.
  final T Function(Map<String, dynamic>) factory;

  /// Per-column value converters.
  final Map<String, dynamic Function(dynamic)>? typeConverters;

  /// Creates a result map.
  ResultMap({
    required this.columns,
    required this.factory,
    this.typeConverters,
  });

  /// Maps a single row.
  T map(Map<String, dynamic> row) {
    final mappedRow = <String, dynamic>{};

    for (final entry in row.entries) {
      final fieldName = columns[entry.key] ?? entry.key;
      var value = entry.value;

      // 타입 변환기 적용
      if (typeConverters != null && typeConverters!.containsKey(entry.key)) {
        value = typeConverters![entry.key]!(value);
      }

      mappedRow[fieldName] = value;
    }

    return factory(mappedRow);
  }

  /// Maps every row.
  List<T> mapList(List<Map<String, dynamic>> rows) {
    return rows.map(map).toList();
  }

  /// Maps a row, or returns null when it is null.
  T? mapNullable(Map<String, dynamic>? row) {
    if (row == null) return null;
    return map(row);
  }
}

/// Ready-made value converters for [ResultMap.typeConverters].
class TypeConverters {
  /// Converts to `int`.
  static int? toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Converts to `double`.
  static double? toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Converts to `bool` (accepts 0/1, 'Y'/'N', true/false).
  static bool toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      return value.toUpperCase() == 'Y' || value.toLowerCase() == 'true' || value == '1';
    }
    return false;
  }

  /// Converts an ISO 8601 string to `DateTime`.
  static DateTime? toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Converts to `String`.
  static String? toStringValue(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }
}

/// Derives field names from column names automatically.
///
/// `SA101_PRSN_ID` -> `prsnId` (drop the prefix, then camelCase).
class AutoResultMapBuilder<T> {
  /// Prefix to strip from column names, e.g. `SA101_`.
  final String? removePrefix;

  /// Builds the object from the mapped row.
  final T Function(Map<String, dynamic>) factory;

  /// Per-column value converters.
  final Map<String, dynamic Function(dynamic)>? typeConverters;

  /// Creates an automatic result map builder.
  AutoResultMapBuilder({
    this.removePrefix,
    required this.factory,
    this.typeConverters,
  });

  /// Converts a column name to a camelCase field name.
  String _columnToField(String column) {
    var name = column;

    // 프리픽스 제거 (예: SA101_)
    if (removePrefix != null && name.startsWith(removePrefix!)) {
      name = name.substring(removePrefix!.length);
    }

    // 언더스코어 제거 및 camelCase 변환
    final parts = name.toLowerCase().split('_');
    final buffer = StringBuffer(parts.first);
    for (int i = 1; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        buffer.write(parts[i][0].toUpperCase());
        buffer.write(parts[i].substring(1));
      }
    }

    return buffer.toString();
  }

  /// Maps a single row.
  T map(Map<String, dynamic> row) {
    final mappedRow = <String, dynamic>{};

    for (final entry in row.entries) {
      final fieldName = _columnToField(entry.key);
      var value = entry.value;

      if (typeConverters != null && typeConverters!.containsKey(entry.key)) {
        value = typeConverters![entry.key]!(value);
      }

      mappedRow[fieldName] = value;
    }

    return factory(mappedRow);
  }

  /// Maps every row.
  List<T> mapList(List<Map<String, dynamic>> rows) {
    return rows.map(map).toList();
  }
}
