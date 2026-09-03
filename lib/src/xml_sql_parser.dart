import 'package:xml/xml.dart';

import 'exceptions.dart';
import 'expression.dart';
import 'logger.dart';
import 'mybatis_config.dart';
import 'sql_comments.dart';

/// Parses mapper XML into statements and dynamic SQL elements.
class XmlSqlParser {
  /// Parses one mapper XML document.
  static MapperConfig parse(String xmlContent) {
    try {
      final document = XmlDocument.parse(xmlContent);
      final mapperElements = document.findElements('mapper');

      if (mapperElements.isEmpty) {
        throw XmlParseException('no <mapper> element found');
      }

      final mapper = mapperElements.first;
      final namespace = mapper.getAttribute('namespace') ?? '';

      if (namespace.isEmpty) {
        throw XmlParseException('the namespace attribute is required', element: 'mapper');
      }

      final statements = <String, SqlStatement>{};
      final fragments = <String, List<SqlElement>>{};

      // <sql> 조각을 먼저 등록 (statement보다 뒤에 선언돼도 참조 가능)
      for (final element in mapper.findElements('sql')) {
        final id = element.getAttribute('id');
        if (id == null || id.isEmpty) {
          throw XmlParseException('the id attribute is required', element: 'sql');
        }
        final key = '$namespace.$id';
        if (fragments.containsKey(key)) {
          throw XmlParseException('duplicate <sql> id: $key', element: 'sql');
        }
        fragments[key] = _parseElements(element.children);
      }

      // select, insert, update, delete 태그 처리
      for (final tagName in ['select', 'insert', 'update', 'delete']) {
        for (final element in mapper.findElements(tagName)) {
          final id = element.getAttribute('id');
          if (id == null || id.isEmpty) {
            throw XmlParseException('the id attribute is required', element: tagName);
          }

          final statement = SqlStatement(
            id: id,
            namespace: namespace,
            type: SqlStatementType.fromString(tagName),
            parameterType: element.getAttribute('parameterType'),
            resultType: element.getAttribute('resultType'),
            resultMap: element.getAttribute('resultMap'),
            databaseId: element.getAttribute('databaseId'),
            useGeneratedKeys: _boolAttr(element, 'useGeneratedKeys'),
            keyProperty: element.getAttribute('keyProperty'),
            keyColumn: element.getAttribute('keyColumn'),
            timeout: int.tryParse(element.getAttribute('timeout') ?? ''),
            flushCache: _boolAttr(element, 'flushCache'),
            useCache: _boolAttr(element, 'useCache'),
            selectKey: _parseSelectKey(element),
            elements: _parseElements(element.children),
          );

          final key = '$namespace.$id';
          if (statements.containsKey(key)) {
            throw XmlParseException('duplicate statement id: $key',
                element: tagName);
          }
          _warnInertAttributes(statement);
          statements[key] = statement;
        }
      }

      return MapperConfig(
        namespace: namespace,
        statements: statements,
        fragments: fragments,
      );
    } on XmlParseException {
      rethrow;
    } catch (e) {
      throw XmlParseException('failed to parse XML: $e');
    }
  }

  /// Warns about attributes that are parsed but have no effect yet.
  ///
  /// As of 1.0, `resultMap`, `flushCache`, `useCache` and `databaseId` are
  /// stored on [SqlStatement] but not applied at execution time.
  /// Ignoring them silently would invite people to rely on them.
  static void _warnInertAttributes(SqlStatement statement) {
    final inert = <String>[
      if (statement.resultMap != null) 'resultMap',
      if (statement.flushCache != null) 'flushCache',
      if (statement.useCache != null) 'useCache',
      if (statement.databaseId != null) 'databaseId',
    ];
    if (inert.isEmpty) return;

    MybatisLogger.configWarning(
      '${statement.fullId}: ${inert.join(", ")} has no effect yet '
      '(parsed only). See the README for the supported feature set.',
    );
  }

  /// Parses a boolean attribute; null when absent.
  static bool? _boolAttr(XmlElement element, String name) {
    final raw = element.getAttribute(name);
    if (raw == null) return null;
    final value = raw.toLowerCase();
    if (value != 'true' && value != 'false') {
      throw XmlParseException(
        '$name must be true or false, got "$raw"',
        element: name,
      );
    }
    return value == 'true';
  }

  /// Parses a `<selectKey>` child of an insert or update.
  static SelectKeyStatement? _parseSelectKey(XmlElement parent) {
    final elements = parent.findElements('selectKey');
    if (elements.isEmpty) return null;

    final element = elements.first;
    final keyProperty = element.getAttribute('keyProperty');
    if (keyProperty == null || keyProperty.isEmpty) {
      throw XmlParseException('the keyProperty attribute is required', element: 'selectKey');
    }

    // A typo such as order="BEFOR" silently became AFTER, which is exactly
    // the class of quiet mistake this parser is meant to catch.
    final rawOrder = element.getAttribute('order');
    final order = (rawOrder ?? 'AFTER').toUpperCase();
    if (order != 'BEFORE' && order != 'AFTER') {
      throw XmlParseException(
        'order must be BEFORE or AFTER, got "$rawOrder"',
        element: 'selectKey',
      );
    }

    return SelectKeyStatement(
      keyProperty: keyProperty,
      keyColumn: element.getAttribute('keyColumn'),
      resultType: element.getAttribute('resultType'),
      order: order == 'BEFORE' ? SelectKeyOrder.before : SelectKeyOrder.after,
      elements: _parseElements(element.children),
    );
  }

  /// Converts child nodes into SQL elements.
  static List<SqlElement> _parseElements(Iterable<XmlNode> nodes) {
    final elements = <SqlElement>[];

    for (final node in nodes) {
      if (node is XmlText) {
        // Comments must go before the trim: the trim removes the newline that
        // ends a `-- line comment`, after which it would swallow the following
        // sibling element.
        final text = stripSqlComments(node.value).trim();
        if (text.isNotEmpty) {
          elements.add(TextElement(text));
        }
      } else if (node is XmlCDATA) {
        final text = stripSqlComments(node.value).trim();
        if (text.isNotEmpty) {
          elements.add(TextElement(text));
        }
      } else if (node is XmlElement) {
        // selectKey는 SQL 본문이 아니라 별도 statement로 처리
        if (node.name.local == 'selectKey') continue;
        elements.add(_parseElement(node));
      }
    }

    return elements;
  }

  /// Converts a single XML element into a SQL element.
  static SqlElement _parseElement(XmlElement element) {
    switch (element.name.local) {
      case 'if':
        return IfElement(
          test: element.getAttribute('test') ?? '',
          children: _parseElements(element.children),
        );

      case 'choose':
        final whenElements = <WhenElement>[];
        OtherwiseElement? otherwiseElement;

        for (final child in element.children.whereType<XmlElement>()) {
          if (child.name.local == 'when') {
            whenElements.add(WhenElement(
              test: child.getAttribute('test') ?? '',
              children: _parseElements(child.children),
            ));
          } else if (child.name.local == 'otherwise') {
            if (otherwiseElement != null) {
              throw XmlParseException('<choose> has more than one <otherwise>',
                  element: 'choose');
            }
            otherwiseElement = OtherwiseElement(
              children: _parseElements(child.children),
            );
          } else {
            throw XmlParseException(
              '<choose> only accepts <when> and <otherwise>, '
              'found <${child.name.local}>',
              element: 'choose',
            );
          }
        }

        return ChooseElement(
          whenElements: whenElements,
          otherwiseElement: otherwiseElement,
        );

      case 'foreach':
        return ForeachElement(
          collection: element.getAttribute('collection') ?? '',
          item: element.getAttribute('item') ?? 'item',
          index: element.getAttribute('index'),
          open: element.getAttribute('open') ?? '',
          close: element.getAttribute('close') ?? '',
          separator: element.getAttribute('separator') ?? '',
          nullable: _boolAttr(element, 'nullable') ?? false,
          children: _parseElements(element.children),
        );

      case 'where':
        return WhereElement(children: _parseElements(element.children));

      case 'set':
        return SetElement(children: _parseElements(element.children));

      case 'trim':
        return TrimElement(
          prefix: element.getAttribute('prefix') ?? '',
          suffix: element.getAttribute('suffix') ?? '',
          prefixOverrides: element.getAttribute('prefixOverrides') ?? '',
          suffixOverrides: element.getAttribute('suffixOverrides') ?? '',
          children: _parseElements(element.children),
        );

      case 'bind':
        return BindElement(
          name: element.getAttribute('name') ?? '',
          value: element.getAttribute('value') ?? '',
        );

      case 'include':
        final properties = <String, String>{};
        for (final property in element.findElements('property')) {
          final name = property.getAttribute('name');
          final value = property.getAttribute('value');
          if (name != null && value != null) {
            properties[name] = value;
          }
        }
        return IncludeElement(
          refid: element.getAttribute('refid') ?? '',
          properties: properties,
        );

      default:
        // An unknown tag is almost always a typo (<whree>) or a MyBatis
        // element this port does not implement. Silently flattening it to text
        // would produce SQL that looks fine but is not what was written.
        throw XmlParseException(
          'unsupported element <${element.name.local}>',
          element: element.name.local,
        );
    }
  }
}

/// One parsed mapper file.
class MapperConfig {
  /// The `<mapper namespace="...">` value.
  final String namespace;

  /// Statements, keyed by `namespace.id`.
  final Map<String, SqlStatement> statements;

  /// `<sql>` fragments, keyed by `namespace.id`.
  final Map<String, List<SqlElement>> fragments;

  /// Creates a parsed mapper.
  MapperConfig({
    required this.namespace,
    required this.statements,
    Map<String, List<SqlElement>>? fragments,
  }) : fragments = fragments ?? const {};

  /// Whether [id] is present.
  bool hasStatement(String id) => statements.containsKey(id);

  /// Returns the statement for [id], or null.
  SqlStatement? getStatement(String id) => statements[id];

  /// Every statement id.
  List<String> get statementIds => statements.keys.toList();

  /// Every `<sql>` fragment id.
  List<String> get fragmentIds => fragments.keys.toList();
}

/// The kind of a mapped statement.
enum SqlStatementType {
  /// `<select>`
  select,

  /// `<insert>`
  insert,

  /// `<update>`
  update,

  /// `<delete>`
  delete;

  /// Maps a tag name to a kind, defaulting to [select].
  static SqlStatementType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'select':
        return SqlStatementType.select;
      case 'insert':
        return SqlStatementType.insert;
      case 'update':
        return SqlStatementType.update;
      case 'delete':
        return SqlStatementType.delete;
      default:
        return SqlStatementType.select;
    }
  }

  /// Whether this is a query.
  bool get isQuery => this == SqlStatementType.select;

  /// Whether this modifies data.
  bool get isModify => this != SqlStatementType.select;
}

/// When a `<selectKey>` runs.
enum SelectKeyOrder {
  /// Fetch the key **before** the main statement (`order="BEFORE"`).
  before,

  /// Fetch the key **after** the main statement (`order="AFTER"`, default).
  after,
}

/// A `<selectKey>` statement.
class SelectKeyStatement {
  /// Parameter key that receives the generated key.
  final String keyProperty;

  /// Result column; the first column when absent.
  final String? keyColumn;

  /// Declared result type (documentation only).
  final String? resultType;

  /// When it runs.
  final SelectKeyOrder order;

  /// The SQL that produces the key.
  final List<SqlElement> elements;

  /// Creates a `<selectKey>`.
  SelectKeyStatement({
    required this.keyProperty,
    this.keyColumn,
    this.resultType,
    required this.order,
    required this.elements,
  });
}

/// One mapped statement.
class SqlStatement {
  /// statement id (`<select id="...">`)
  final String id;

  /// The owning mapper's namespace.
  final String namespace;

  /// The statement kind.
  final SqlStatementType type;

  /// `parameterType` attribute (documentation only).
  final String? parameterType;

  /// `resultType` attribute (documentation only).
  final String? resultType;

  /// `resultMap` attribute. Parsed only; not applied yet.
  final String? resultMap;

  /// `databaseId` attribute. Parsed only; not applied yet.
  final String? databaseId;

  /// Whether `useGeneratedKeys="true"` was set.
  final bool? useGeneratedKeys;

  /// Parameter key that receives the generated key.
  final String? keyProperty;

  /// Column holding the generated key.
  final String? keyColumn;

  /// Timeout in seconds.
  final int? timeout;

  /// `flushCache` attribute. Parsed only; caching is not implemented.
  final bool? flushCache;

  /// `useCache` attribute. Parsed only; caching is not implemented.
  final bool? useCache;

  /// The `<selectKey>`, when present.
  final SelectKeyStatement? selectKey;

  /// The SQL elements that make up the body.
  final List<SqlElement> elements;

  /// Creates a statement.
  SqlStatement({
    required this.id,
    required this.namespace,
    required this.type,
    this.parameterType,
    this.resultType,
    this.resultMap,
    this.databaseId,
    this.useGeneratedKeys,
    this.keyProperty,
    this.keyColumn,
    this.timeout,
    this.flushCache,
    this.useCache,
    this.selectKey,
    required this.elements,
  });

  /// The fully qualified id, `namespace.id`.
  String get fullId => '$namespace.$id';

  /// Timeout for this statement, falling back to the global default.
  Duration? get timeoutDuration => timeout != null
      ? Duration(seconds: timeout!)
      : MybatisConfig.defaultStatementTimeout;

  /// Whether the generated key must be written back into the parameters.
  bool get writesGeneratedKey =>
      (useGeneratedKeys ?? false) && keyProperty != null && keyProperty!.isNotEmpty;

  /// Resolves every `<include>` against [fragments].
  ///
  /// Called by [SqlSessionFactory] once all mappers are loaded.
  void resolveIncludes(Map<String, List<SqlElement>> fragments) {
    for (final element in elements) {
      element.resolveIncludes(fragments, namespace, <String>{});
    }
    final key = selectKey;
    if (key != null) {
      for (final element in key.elements) {
        element.resolveIncludes(fragments, namespace, <String>{});
      }
    }
  }
}

/// Base class for SQL elements.
abstract class SqlElement {
  /// Renders this element to SQL text.
  String build(Map<String, dynamic> params);

  /// Child elements; container elements override this.
  List<SqlElement> get childElements => const [];

  /// Resolves `<include>` elements recursively.
  void resolveIncludes(
    Map<String, List<SqlElement>> fragments,
    String namespace,
    Set<String> stack,
  ) {
    for (final child in childElements) {
      child.resolveIncludes(fragments, namespace, stack);
    }
  }
}

/// Substitutes `${name}` placeholders.
///
/// In MyBatis `${}` is raw text substitution, not binding. The value goes
/// straight into the SQL, so never use it with user input.
String substituteDollar(String text, Map<String, dynamic> params) {
  if (!text.contains(r'${')) return text;

  return text.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (match) {
    final name = match.group(1)!.trim();
    final resolved = resolvePropertyPath(name, params);
    if (resolved == null && !params.containsKey(name)) {
      // Leaving the placeholder in place can only produce invalid SQL, so fail
      // with a message that names the missing property.
      throw SqlBuildException('no value for \${$name}', sql: text);
    }
    return resolved?.toString() ?? '';
  });
}

/// A literal chunk of SQL.
class TextElement extends SqlElement {
  /// The raw SQL text.
  final String text;

  /// Creates a text element.
  TextElement(this.text);

  @override
  String build(Map<String, dynamic> params) => substituteDollar(text, params);
}

/// An `<if>` element.
class IfElement extends SqlElement {
  /// The condition to evaluate.
  final String test;

  /// Included when the condition holds.
  final List<SqlElement> children;

  /// Creates an `<if>`.
  IfElement({required this.test, required this.children});

  @override
  List<SqlElement> get childElements => children;

  @override
  String build(Map<String, dynamic> params) {
    if (ConditionEvaluator.evaluate(test, params)) {
      return children.map((e) => e.build(params)).join(' ');
    }
    return '';
  }
}

/// A `<choose>` element.
class ChooseElement extends SqlElement {
  /// Branches, evaluated in order.
  final List<WhenElement> whenElements;

  /// Used when no branch matches.
  final OtherwiseElement? otherwiseElement;

  /// Creates a `<choose>`.
  ChooseElement({
    required this.whenElements,
    this.otherwiseElement,
  });

  @override
  String build(Map<String, dynamic> params) {
    for (final when in whenElements) {
      if (ConditionEvaluator.evaluate(when.test, params)) {
        return when.children.map((e) => e.build(params)).join(' ');
      }
    }
    if (otherwiseElement != null) {
      return otherwiseElement!.children.map((e) => e.build(params)).join(' ');
    }
    return '';
  }

  @override
  void resolveIncludes(
    Map<String, List<SqlElement>> fragments,
    String namespace,
    Set<String> stack,
  ) {
    for (final when in whenElements) {
      for (final child in when.children) {
        child.resolveIncludes(fragments, namespace, stack);
      }
    }
    for (final child in otherwiseElement?.children ?? const <SqlElement>[]) {
      child.resolveIncludes(fragments, namespace, stack);
    }
  }
}

/// A `<when>` branch.
class WhenElement {
  /// The condition to evaluate.
  final String test;

  /// Included when the condition holds.
  final List<SqlElement> children;

  /// Creates a `<when>`.
  WhenElement({required this.test, required this.children});
}

/// An `<otherwise>` branch.
class OtherwiseElement {
  /// Included when no `<when>` matches.
  final List<SqlElement> children;

  /// Creates an `<otherwise>`.
  OtherwiseElement({required this.children});
}

/// A `<foreach>` element.
class ForeachElement extends SqlElement {
  /// Name of the collection parameter.
  final String collection;

  /// Variable bound to each item.
  final String item;

  /// Variable bound to the index, or the key for a Map.
  final String? index;

  /// Text prepended to the result, e.g. `(`.
  final String open;

  /// Text appended to the result, e.g. `)`.
  final String close;

  /// Separator between items, e.g. `,`.
  final String separator;

  /// With `nullable="true"` a null collection yields empty text
  final bool nullable;

  /// Repeated for every item.
  final List<SqlElement> children;

  /// Creates a `<foreach>`.
  ForeachElement({
    required this.collection,
    required this.item,
    this.index,
    required this.open,
    required this.close,
    required this.separator,
    this.nullable = false,
    required this.children,
  });

  @override
  List<SqlElement> get childElements => children;

  @override
  String build(Map<String, dynamic> params) {
    // nullable 공개 필드는 promote되지 않으므로 지역 변수로 받는다
    final idx = index;
    final source = resolvePropertyPath(collection, params);

    if (source == null) {
      if (nullable) return '';
      throw SqlBuildException(
        'foreach collection is null: "$collection" '
        '(set nullable="true" to allow it)',
      );
    }

    // List / Set / Iterable / Map 지원
    final List<MapEntry<dynamic, dynamic>> entries;
    if (source is Map) {
      entries = source.entries.map((e) => MapEntry(e.key, e.value)).toList();
    } else if (source is Iterable) {
      final list = source.toList();
      entries = [
        for (var i = 0; i < list.length; i++) MapEntry(i, list[i]),
      ];
    } else {
      throw SqlBuildException(
        'foreach collection must be a List/Set/Map: "$collection" '
        '(actual: ${source.runtimeType})',
      );
    }

    // ${item} / ${index} 치환을 위해 반복 중에는 원래 이름으로도 바인딩한다.
    // (MyBatis에서 foreach 안의 ${key}는 현재 항목을 가리킨다)
    final hadItem = params.containsKey(item);
    final previousItem = params[item];
    final hadIndex = idx != null && params.containsKey(idx);
    final previousIndex = idx != null ? params[idx] : null;

    final results = <String>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];

      // 인덱스 기반 파라미터 이름으로 값 저장
      final indexedName = '__frch_${item}_$i';
      params[indexedName] = entry.value;
      params[item] = entry.value;

      if (idx != null) {
        final indexedIndexName = '__frch_${idx}_$i';
        params[indexedIndexName] = entry.key;
        params[idx] = entry.key;
      }

      // Rewrite #{item} and #{item.prop} / #{item[0]} to the indexed name, so
      // that a bulk insert such as (#{row.id}, #{row.nm}) binds each row.
      var itemSql = children.map((e) => e.build(params)).join(' ');
      itemSql = _rewriteItemRefs(itemSql, item, indexedName);
      if (idx != null) {
        itemSql = _rewriteItemRefs(itemSql, idx, '__frch_${idx}_$i');
      }

      results.add(itemSql);
    }

    // 반복 변수 정리 (바깥 스코프 파라미터를 오염시키지 않도록)
    if (hadItem) {
      params[item] = previousItem;
    } else {
      params.remove(item);
    }
    if (idx != null) {
      if (hadIndex) {
        params[idx] = previousIndex;
      } else {
        params.remove(idx);
      }
    }

    return '$open${results.join(separator)}$close';
  }
}

/// Rewrites `#{name}` and `#{name.path}` to `#{replacement...}`.
///
/// Used by `<foreach>` so that each iteration binds its own item.
String _rewriteItemRefs(String sql, String name, String replacement) {
  return sql.replaceAllMapped(RegExp(r'#\{([^}]*)\}'), (m) {
    final content = m.group(1)!;

    // A placeholder may carry MyBatis attributes: #{id,jdbcType=INTEGER}.
    // Only the property part is rewritten; the attributes are copied through.
    final comma = content.indexOf(',');
    final property = (comma == -1 ? content : content.substring(0, comma)).trim();
    final attributes = comma == -1 ? '' : content.substring(comma);

    final matchesItem = property == name ||
        property.startsWith('$name.') ||
        property.startsWith('$name[');
    if (!matchesItem) return m.group(0)!;

    final suffix = property.substring(name.length);
    return '#{$replacement$suffix$attributes}';
  });
}

/// A `<where>` element.
class WhereElement extends SqlElement {
  /// Conditions inside the WHERE clause.
  final List<SqlElement> children;

  /// Creates a `<where>`.
  WhereElement({required this.children});

  @override
  List<SqlElement> get childElements => children;

  @override
  String build(Map<String, dynamic> params) {
    final content = children.map((e) => e.build(params)).join(' ').trim();
    if (content.isEmpty) return '';

    var result = content;
    // 앞의 AND/OR 제거
    final upperResult = result.toUpperCase();
    if (upperResult.startsWith('AND ')) {
      result = result.substring(4);
    } else if (upperResult.startsWith('OR ')) {
      result = result.substring(3);
    }

    return 'WHERE $result';
  }
}

/// A `<set>` element.
class SetElement extends SqlElement {
  /// Assignments inside the SET clause.
  final List<SqlElement> children;

  /// Creates a `<set>`.
  SetElement({required this.children});

  @override
  List<SqlElement> get childElements => children;

  @override
  String build(Map<String, dynamic> params) {
    final content = children.map((e) => e.build(params)).join(' ').trim();
    if (content.isEmpty) return '';

    var result = content;
    // 뒤의 쉼표 제거
    if (result.endsWith(',')) {
      result = result.substring(0, result.length - 1);
    }

    return 'SET $result';
  }
}

/// A `<trim>` element.
class TrimElement extends SqlElement {
  /// Prepended when the body is non-empty.
  final String prefix;

  /// Appended when the body is non-empty.
  final String suffix;

  /// Leading tokens to strip, separated by `|`.
  final String prefixOverrides;

  /// Trailing tokens to strip, separated by `|`.
  final String suffixOverrides;

  /// The body.
  final List<SqlElement> children;

  /// Creates a `<trim>`.
  TrimElement({
    required this.prefix,
    required this.suffix,
    required this.prefixOverrides,
    required this.suffixOverrides,
    required this.children,
  });

  @override
  List<SqlElement> get childElements => children;

  @override
  String build(Map<String, dynamic> params) {
    var content = children.map((e) => e.build(params)).join(' ').trim();
    if (content.isEmpty) return '';

    // Whitespace inside an override is significant, as in MyBatis: "AND |OR "
    // must not match the "OR" that starts ORDER_ID. The match keeps the space,
    // the removal does not.
    if (prefixOverrides.isNotEmpty) {
      final upper = content.toUpperCase();
      for (final override in prefixOverrides.split('|')) {
        if (override.isEmpty) continue;
        if (upper.startsWith(override.toUpperCase())) {
          content = content.substring(override.trim().length).trim();
          break;
        }
      }
    }

    if (suffixOverrides.isNotEmpty) {
      final upper = content.toUpperCase();
      for (final override in suffixOverrides.split('|')) {
        if (override.isEmpty) continue;
        final bare = override.trim();
        if (upper.endsWith(override.toUpperCase()) ||
            upper.endsWith(bare.toUpperCase())) {
          content = content.substring(0, content.length - bare.length).trim();
          break;
        }
      }
    }

    if (content.isEmpty) return '';

    // A space between prefix/suffix and the body, or `prefix="WHERE"` would
    // produce WHEREID = ?.
    final head = prefix.isEmpty ? '' : '${prefix.trim()} ';
    final tail = suffix.isEmpty ? '' : ' ${suffix.trim()}';
    return '$head$content$tail';
  }
}

/// A `<bind>` element.
class BindElement extends SqlElement {
  /// Variable name to bind.
  final String name;

  /// Expression to bind, which may contain `#{param}`.
  final String value;

  /// Creates a `<bind>`.
  BindElement({required this.name, required this.value});

  @override
  String build(Map<String, dynamic> params) {
    // MyBatis evaluates the value with OGNL, e.g. value="'%' + name + '%'".
    // Use the same evaluator as <if test="..."> so both speak one language.
    try {
      params[name] = ExpressionEvaluator.evaluate(value, params);
      return '';
    } on ExpressionException {
      if (MybatisConfig.strictExpressions) {
        throw UnsupportedExpressionException(value);
      }
      // Legacy behaviour: substitute #{param} into the literal text.
      final paramMatch = RegExp(r'#\{([^}]+)\}').firstMatch(value);
      if (paramMatch != null) {
        final paramName = paramMatch.group(1)!.split(',').first.trim();
        final paramValue =
            resolvePropertyPath(paramName, params)?.toString() ?? '';
        params[name] = value
            .replaceAll('#{$paramName}', paramValue)
            .replaceAll("'", '');
      } else {
        params[name] = value;
      }
      return '';
    }
  }
}

/// An `<include>` element referencing a `<sql>` fragment.
///
/// ```xml
/// <sql id="columns">ID, NM, AGE</sql>
///
/// <select id="selectAll">
///   SELECT <include refid="columns"/> FROM PERSON
/// </select>
/// ```
///
/// Use `<property>` to pass values into the fragment.
///
/// ```xml
/// <sql id="softDelete">DEL_FL = '${flag}'</sql>
/// <select id="selectLive">
///   SELECT * FROM T WHERE
///   <include refid="softDelete"><property name="flag" value="N"/></include>
/// </select>
/// ```
class IncludeElement extends SqlElement {
  /// Fragment id, either `namespace.id` or a local id.
  final String refid;

  /// `<property>` name/value pairs.
  final Map<String, String> properties;

  List<SqlElement>? _resolved;

  /// Creates an `<include>`.
  IncludeElement({required this.refid, Map<String, String>? properties})
      : properties = properties ?? const {};

  /// The resolved fragment, or null before resolution.
  List<SqlElement>? get resolved => _resolved;

  @override
  void resolveIncludes(
    Map<String, List<SqlElement>> fragments,
    String namespace,
    Set<String> stack,
  ) {
    if (refid.isEmpty) {
      throw XmlParseException('the refid attribute is required', element: 'include');
    }

    // namespace가 이미 포함된 refid를 우선 조회, 없으면 현재 namespace 기준
    final qualified = fragments.containsKey(refid) ? refid : '$namespace.$refid';
    final fragment = fragments[qualified];

    if (fragment == null) {
      throw SqlFragmentNotFoundException(refid, namespace: namespace);
    }

    if (stack.contains(qualified)) {
      throw SqlBuildException(
        'circular <sql> reference: ${stack.join(" -> ")} -> $qualified',
      );
    }

    _resolved = fragment;

    // 조각 안의 include도 재귀 연결 (순환 감지 포함)
    final nextStack = {...stack, qualified};
    for (final element in fragment) {
      element.resolveIncludes(fragments, namespace, nextStack);
    }
  }

  @override
  String build(Map<String, dynamic> params) {
    final fragment = _resolved;
    if (fragment == null) {
      throw SqlFragmentNotFoundException(refid);
    }

    // property 값을 파라미터에 겹쳐 ${} 치환에 사용
    final effectiveParams = properties.isEmpty
        ? params
        : (Map<String, dynamic>.from(params)..addAll(properties));

    return fragment.map((e) => e.build(effectiveParams)).join(' ');
  }
}

/// Evaluates `test` conditions.
///
/// Delegates to [ExpressionEvaluator].
///
/// MyBatis uses OGNL; Dart has no `eval`, so only a subset is supported.
/// See "test expression support" in the README.
///
/// A failure throws by default. Set [MybatisConfig.strictExpressions] to
/// `false` to fall back to the 0.9.x behaviour of evaluating to `false` with
/// a warning.
class ConditionEvaluator {
  /// Evaluates [test] against [params].
  static bool evaluate(String test, Map<String, dynamic> params) {
    final trimmedTest = test.trim();
    if (trimmedTest.isEmpty) return false;

    try {
      return ExpressionEvaluator.evaluateBool(trimmedTest, params);
    } on ExpressionException catch (e) {
      if (MybatisConfig.strictExpressions) {
        throw UnsupportedExpressionException(trimmedTest);
      }
      MybatisLogger.configWarningOnce(
        'could not evaluate expression, treated as false: "$trimmedTest" (${e.message}) '
        '(set MybatisConfig.strictExpressions = true to throw instead)',
      );
      return false;
    }
  }
}
