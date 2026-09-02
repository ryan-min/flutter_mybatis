/// `test` expression parser (an OGNL subset).
///
/// MyBatis evaluates `test` with OGNL. Dart has no `eval`, so full OGNL
/// cannot be ported; this parser covers what real mappers use.
///
/// Supported syntax
/// - literals: numbers, `'text'`, `"text"`, `true`, `false`, `null`
/// - properties: `a`, `a.b.c`, `a['k']`, `a[0]`
/// - methods: `size()` `length()` `isEmpty()` `isNotEmpty()` `trim()`
///   `toString()` `toUpperCase()` `toLowerCase()` `equals(x)` `contains(x)`
///   `startsWith(x)` `endsWith(x)` `indexOf(x)`
/// - operators: `== != < <= > >=`, `and or not` (`&& || !`), `+ - * / %`, `?:`
/// - parentheses for grouping
library;

import 'exceptions.dart';
import 'mybatis_config.dart';

/// Thrown when an expression cannot be parsed or evaluated.
class ExpressionException implements Exception {
  /// What went wrong.
  final String message;

  /// The expression involved.
  final String expression;

  /// Creates an expression failure.
  ExpressionException(this.message, this.expression);

  @override
  String toString() => 'ExpressionException: $message  <<$expression>>';
}

// ---------------------------------------------------------------------------
// 토크나이저
// ---------------------------------------------------------------------------

enum _TokenType { number, string, identifier, operator, eof }

class _Token {
  final _TokenType type;
  final String text;
  final Object? value;

  _Token(this.type, this.text, [this.value]);

  @override
  String toString() => '${type.name}($text)';
}

class _Lexer {
  final String source;
  int _pos = 0;

  _Lexer(this.source);

  static const _operators = <String>[
    '>=', '<=', '==', '!=', '&&', '||',
    '>', '<', '+', '-', '*', '/', '%',
    '(', ')', '[', ']', '.', ',', '?', ':', '!',
  ];

  List<_Token> tokenize() {
    final tokens = <_Token>[];

    while (_pos < source.length) {
      final ch = source[_pos];

      if (ch.trim().isEmpty) {
        _pos++;
        continue;
      }

      // 문자열 리터럴
      if (ch == "'" || ch == '"') {
        tokens.add(_readString(ch));
        continue;
      }

      // 숫자
      if (_isDigit(ch)) {
        tokens.add(_readNumber());
        continue;
      }

      // 식별자 / 키워드
      if (_isIdentStart(ch)) {
        tokens.add(_readIdentifier());
        continue;
      }

      // 연산자
      final op = _operators.firstWhere(
        (o) => source.startsWith(o, _pos),
        orElse: () => '',
      );
      if (op.isEmpty) {
        throw ExpressionException('unexpected character: "$ch"', source);
      }
      _pos += op.length;
      tokens.add(_Token(_TokenType.operator, op));
    }

    tokens.add(_Token(_TokenType.eof, ''));
    return tokens;
  }

  _Token _readString(String quote) {
    _pos++; // 여는 따옴표
    final buffer = StringBuffer();

    while (_pos < source.length && source[_pos] != quote) {
      if (source[_pos] == r'\' && _pos + 1 < source.length) {
        _pos++;
        buffer.write(source[_pos]);
      } else {
        buffer.write(source[_pos]);
      }
      _pos++;
    }

    if (_pos >= source.length) {
      throw ExpressionException('unterminated string literal', source);
    }
    _pos++; // 닫는 따옴표

    return _Token(_TokenType.string, buffer.toString(), buffer.toString());
  }

  _Token _readNumber() {
    final start = _pos;
    while (_pos < source.length && (_isDigit(source[_pos]) || source[_pos] == '.')) {
      // 1.toString() 처럼 숫자 뒤 메서드 호출과 구분
      if (source[_pos] == '.' &&
          (_pos + 1 >= source.length || !_isDigit(source[_pos + 1]))) {
        break;
      }
      _pos++;
    }
    final text = source.substring(start, _pos);
    final value = text.contains('.') ? double.parse(text) : int.parse(text);
    return _Token(_TokenType.number, text, value);
  }

  _Token _readIdentifier() {
    final start = _pos;
    while (_pos < source.length && _isIdentPart(source[_pos])) {
      _pos++;
    }
    return _Token(_TokenType.identifier, source.substring(start, _pos));
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  static bool _isIdentStart(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        c == '_' ||
        c == r'$' ||
        code > 127; // 한글 등
  }

  static bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);
}

// ---------------------------------------------------------------------------
// 파서 + 평가기
// ---------------------------------------------------------------------------

/// Parses and evaluates `test` expressions.
///
/// Parsed expressions are cached, so repeated evaluation is cheap.
class ExpressionEvaluator {
  static final Map<String, _Node> _cache = {};

  /// Clears the parse cache (useful in tests).
  static void clearCache() => _cache.clear();

  /// Evaluates [expression] and coerces the result to `bool`.
  static bool evaluateBool(String expression, Map<String, dynamic> params) {
    return toBool(evaluate(expression, params));
  }

  /// Evaluates [expression] and returns the raw value.
  static Object? evaluate(String expression, Map<String, dynamic> params) {
    final node = _cache.putIfAbsent(expression, () {
      final tokens = _Lexer(expression).tokenize();
      final parser = _Parser(tokens, expression);
      final parsed = parser.parseExpression();
      parser.expectEof();
      return parsed;
    });

    return node.eval(params);
  }

  /// MyBatis/OGNL-like truthiness.
  ///
  /// - `bool` -> itself
  /// - `null` -> false
  /// - number -> true unless 0
  /// - string -> true unless empty
  /// - collection -> true unless empty
  static bool toBool(Object? value) {
    if (value is bool) return value;
    if (value == null) return false;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }
}

/// Resolves a property path against [params].
///
/// Uses the same rules as a `test` expression, so `#{user.id}` and
/// `<if test="user.id != null">` agree with each other.
///
/// An exact key match wins, so a parameter literally named `user.id` still
/// works. Otherwise `a.b.c`, `a['k']` and `a[0]` are walked.
///
/// A path that simply has no value yields `null`, as a missing parameter
/// always did. A path that cannot be *read* is a different thing — a typo in
/// the mapper — and is reported when [MybatisConfig.strictExpressions] is on,
/// so that `#{}` and `<if test="...">` agree about malformed syntax.
Object? resolvePropertyPath(String path, Map<String, dynamic> params) {
  if (params.containsKey(path)) return params[path];
  try {
    return ExpressionEvaluator.evaluate(path, params);
  } on ExpressionException {
    if (MybatisConfig.strictExpressions) {
      throw UnsupportedExpressionException(path);
    }
    return null;
  }
}

abstract class _Node {
  Object? eval(Map<String, dynamic> params);
}

class _Literal extends _Node {
  final Object? value;
  _Literal(this.value);

  @override
  Object? eval(Map<String, dynamic> params) => value;
}

class _Identifier extends _Node {
  final String name;
  _Identifier(this.name);

  @override
  Object? eval(Map<String, dynamic> params) => params[name];
}

/// Property access `a.b` and index access `a['k']`.
class _Access extends _Node {
  final _Node target;
  final _Node key;
  _Access(this.target, this.key);

  @override
  Object? eval(Map<String, dynamic> params) {
    final receiver = target.eval(params);
    if (receiver == null) return null;

    final k = key.eval(params);

    if (receiver is Map) return receiver[k];
    if (receiver is List && k is num) {
      final i = k.toInt();
      return (i >= 0 && i < receiver.length) ? receiver[i] : null;
    }
    if (receiver is String && k is num) {
      final i = k.toInt();
      return (i >= 0 && i < receiver.length) ? receiver[i] : null;
    }

    // length 프로퍼티
    if (k == 'length') {
      if (receiver is String) return receiver.length;
      if (receiver is Iterable) return receiver.length;
      if (receiver is Map) return receiver.length;
    }
    return null;
  }
}

/// A method call.
class _MethodCall extends _Node {
  final _Node target;
  final String method;
  final List<_Node> args;

  _MethodCall(this.target, this.method, this.args);

  @override
  Object? eval(Map<String, dynamic> params) {
    final receiver = target.eval(params);
    final values = args.map((a) => a.eval(params)).toList();

    switch (method) {
      case 'toString':
        return receiver?.toString();

      case 'size':
      case 'length':
        if (receiver is String) return receiver.length;
        if (receiver is Iterable) return receiver.length;
        if (receiver is Map) return receiver.length;
        return receiver == null ? 0 : null;

      case 'isEmpty':
        if (receiver == null) return true;
        if (receiver is String) return receiver.isEmpty;
        if (receiver is Iterable) return receiver.isEmpty;
        if (receiver is Map) return receiver.isEmpty;
        return false;

      case 'isNotEmpty':
        if (receiver == null) return false;
        if (receiver is String) return receiver.isNotEmpty;
        if (receiver is Iterable) return receiver.isNotEmpty;
        if (receiver is Map) return receiver.isNotEmpty;
        return true;

      case 'trim':
        return receiver?.toString().trim();

      case 'toUpperCase':
        return receiver?.toString().toUpperCase();

      case 'toLowerCase':
        return receiver?.toString().toLowerCase();

      case 'equals':
        if (receiver == null) return values.first == null;
        return _Binary.looseEquals(receiver, values.first);

      case 'contains':
        if (receiver is String) {
          return receiver.contains('${values.first}');
        }
        if (receiver is Iterable) return receiver.contains(values.first);
        if (receiver is Map) return receiver.containsKey(values.first);
        return false;

      case 'startsWith':
        return receiver is String && receiver.startsWith('${values.first}');

      case 'endsWith':
        return receiver is String && receiver.endsWith('${values.first}');

      case 'indexOf':
        if (receiver is String) return receiver.indexOf('${values.first}');
        if (receiver is List) return receiver.indexOf(values.first);
        return -1;

      default:
        throw ExpressionException('unsupported method: $method()', method);
    }
  }
}

class _Unary extends _Node {
  final String op;
  final _Node operand;
  _Unary(this.op, this.operand);

  @override
  Object? eval(Map<String, dynamic> params) {
    final value = operand.eval(params);
    switch (op) {
      case '!':
      case 'not':
        return !ExpressionEvaluator.toBool(value);
      case '-':
        return value is num ? -value : null;
      default:
        throw ExpressionException('unsupported unary operator: $op', op);
    }
  }
}

class _Binary extends _Node {
  final String op;
  final _Node left;
  final _Node right;

  _Binary(this.op, this.left, this.right);

  @override
  Object? eval(Map<String, dynamic> params) {
    // 단축 평가
    if (op == 'and') {
      return ExpressionEvaluator.toBool(left.eval(params)) &&
          ExpressionEvaluator.toBool(right.eval(params));
    }
    if (op == 'or') {
      return ExpressionEvaluator.toBool(left.eval(params)) ||
          ExpressionEvaluator.toBool(right.eval(params));
    }

    final l = left.eval(params);
    final r = right.eval(params);

    switch (op) {
      case '==':
        return looseEquals(l, r);
      case '!=':
        return !looseEquals(l, r);
      case '<':
      case '<=':
      case '>':
      case '>=':
        return _compare(op, l, r);
      case '+':
        if (l is num && r is num) return l + r;
        return '${l ?? ''}${r ?? ''}';
      case '-':
        return (l is num && r is num) ? l - r : null;
      case '*':
        return (l is num && r is num) ? l * r : null;
      case '/':
        return (l is num && r is num && r != 0) ? l / r : null;
      case '%':
        return (l is num && r is num && r != 0) ? l % r : null;
      default:
        throw ExpressionException('unsupported operator: $op', op);
    }
  }

  /// MyBatis-style loose equality.
  ///
  /// If either side is a string, both are compared as strings, so
  /// `STS == 'Y'` works even when the column type varies.
  static bool looseEquals(Object? a, Object? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a is num && b is num) return a == b;
    if (a is String || b is String) return a.toString() == b.toString();
    return a == b;
  }

  static bool _compare(String op, Object? l, Object? r) {
    if (l == null || r == null) return false;

    final int result;
    if (l is num && r is num) {
      result = l.compareTo(r);
    } else {
      result = l.toString().compareTo(r.toString());
    }

    switch (op) {
      case '<':
        return result < 0;
      case '<=':
        return result <= 0;
      case '>':
        return result > 0;
      default:
        return result >= 0;
    }
  }
}

class _Ternary extends _Node {
  final _Node condition;
  final _Node thenNode;
  final _Node elseNode;

  _Ternary(this.condition, this.thenNode, this.elseNode);

  @override
  Object? eval(Map<String, dynamic> params) {
    return ExpressionEvaluator.toBool(condition.eval(params))
        ? thenNode.eval(params)
        : elseNode.eval(params);
  }
}

class _Parser {
  final List<_Token> tokens;
  final String source;
  int _pos = 0;

  _Parser(this.tokens, this.source);

  _Token get _current => tokens[_pos];

  bool _matchOp(String op) {
    if (_current.type == _TokenType.operator && _current.text == op) {
      _pos++;
      return true;
    }
    return false;
  }

  bool _matchKeyword(String keyword) {
    if (_current.type == _TokenType.identifier &&
        _current.text.toLowerCase() == keyword) {
      _pos++;
      return true;
    }
    return false;
  }

  void expectEof() {
    if (_current.type != _TokenType.eof) {
      throw ExpressionException('unexpected token: ${_current.text}', source);
    }
  }

  void _expectOp(String op) {
    if (!_matchOp(op)) {
      throw ExpressionException('expected "$op" but found "${_current.text}"', source);
    }
  }

  _Node parseExpression() => _parseTernary();

  _Node _parseTernary() {
    final condition = _parseOr();
    if (_matchOp('?')) {
      final thenNode = _parseTernary();
      _expectOp(':');
      final elseNode = _parseTernary();
      return _Ternary(condition, thenNode, elseNode);
    }
    return condition;
  }

  _Node _parseOr() {
    var left = _parseAnd();
    while (true) {
      if (_matchOp('||') || _matchKeyword('or')) {
        left = _Binary('or', left, _parseAnd());
      } else {
        return left;
      }
    }
  }

  _Node _parseAnd() {
    var left = _parseEquality();
    while (true) {
      if (_matchOp('&&') || _matchKeyword('and')) {
        left = _Binary('and', left, _parseEquality());
      } else {
        return left;
      }
    }
  }

  _Node _parseEquality() {
    var left = _parseRelational();
    while (true) {
      if (_matchOp('==')) {
        left = _Binary('==', left, _parseRelational());
      } else if (_matchOp('!=')) {
        left = _Binary('!=', left, _parseRelational());
      } else if (_matchKeyword('eq')) {
        left = _Binary('==', left, _parseRelational());
      } else if (_matchKeyword('neq')) {
        left = _Binary('!=', left, _parseRelational());
      } else {
        return left;
      }
    }
  }

  _Node _parseRelational() {
    var left = _parseAdditive();
    while (true) {
      if (_matchOp('>=')) {
        left = _Binary('>=', left, _parseAdditive());
      } else if (_matchOp('<=')) {
        left = _Binary('<=', left, _parseAdditive());
      } else if (_matchOp('>')) {
        left = _Binary('>', left, _parseAdditive());
      } else if (_matchOp('<')) {
        left = _Binary('<', left, _parseAdditive());
      } else if (_matchKeyword('gt')) {
        left = _Binary('>', left, _parseAdditive());
      } else if (_matchKeyword('gte')) {
        left = _Binary('>=', left, _parseAdditive());
      } else if (_matchKeyword('lt')) {
        left = _Binary('<', left, _parseAdditive());
      } else if (_matchKeyword('lte')) {
        left = _Binary('<=', left, _parseAdditive());
      } else {
        return left;
      }
    }
  }

  _Node _parseAdditive() {
    var left = _parseMultiplicative();
    while (true) {
      if (_matchOp('+')) {
        left = _Binary('+', left, _parseMultiplicative());
      } else if (_matchOp('-')) {
        left = _Binary('-', left, _parseMultiplicative());
      } else {
        return left;
      }
    }
  }

  _Node _parseMultiplicative() {
    var left = _parseUnary();
    while (true) {
      if (_matchOp('*')) {
        left = _Binary('*', left, _parseUnary());
      } else if (_matchOp('/')) {
        left = _Binary('/', left, _parseUnary());
      } else if (_matchOp('%')) {
        left = _Binary('%', left, _parseUnary());
      } else {
        return left;
      }
    }
  }

  _Node _parseUnary() {
    if (_matchOp('!')) return _Unary('!', _parseUnary());
    if (_matchOp('-')) return _Unary('-', _parseUnary());
    if (_matchKeyword('not')) return _Unary('not', _parseUnary());
    return _parsePostfix();
  }

  _Node _parsePostfix() {
    var node = _parsePrimary();

    while (true) {
      if (_matchOp('.')) {
        if (_current.type != _TokenType.identifier) {
          throw ExpressionException('expected a name after "."', source);
        }
        final name = _current.text;
        _pos++;

        if (_matchOp('(')) {
          final args = <_Node>[];
          if (!_matchOp(')')) {
            do {
              args.add(parseExpression());
            } while (_matchOp(','));
            _expectOp(')');
          }
          node = _MethodCall(node, name, args);
        } else {
          node = _Access(node, _Literal(name));
        }
      } else if (_matchOp('[')) {
        final key = parseExpression();
        _expectOp(']');
        node = _Access(node, key);
      } else {
        return node;
      }
    }
  }

  _Node _parsePrimary() {
    final token = _current;

    if (token.type == _TokenType.number) {
      _pos++;
      return _Literal(token.value);
    }

    if (token.type == _TokenType.string) {
      _pos++;
      return _Literal(token.value);
    }

    if (token.type == _TokenType.identifier) {
      final lower = token.text.toLowerCase();
      if (lower == 'true') {
        _pos++;
        return _Literal(true);
      }
      if (lower == 'false') {
        _pos++;
        return _Literal(false);
      }
      if (lower == 'null') {
        _pos++;
        return _Literal(null);
      }
      _pos++;
      return _Identifier(token.text);
    }

    if (_matchOp('(')) {
      final node = parseExpression();
      _expectOp(')');
      return node;
    }

    throw ExpressionException('unexpected token: ${token.text}', source);
  }
}
