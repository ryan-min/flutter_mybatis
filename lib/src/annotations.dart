/// Annotations for generated mappers.
///
/// Declare a mapper the way you would a MyBatis `@Mapper` interface, and
/// `flutter_mybatis_generator` writes the implementation.
///
/// ```dart
/// @MybatisMapper('PersonMapper', xml: 'assets/person_mapper.xml')
/// abstract class PersonMapper {
///   factory PersonMapper(SqlSession session) = _$PersonMapper;
///
///   @Select('selectList')
///   Future<List<Map<String, dynamic>>> search(Map<String, dynamic> params);
///
///   @SelectOne('selectById')
///   Future<Map<String, dynamic>?> findById(@Param('ID') int id);
///
///   @Insert('insert')
///   Future<int> add(Map<String, dynamic> person);
/// }
/// ```
///
/// ```bash
/// dart run build_runner build
/// ```
library;

/// Marks an abstract class as a mapper.
///
/// When [xml] is given, the generator parses that file at build time and
/// **verifies every statement id you reference**, so a typo fails the build
/// instead of the running app. Java MyBatis only reports this at start-up.
class MybatisMapper {
  /// XML namespace (`<mapper namespace="...">`)
  final String namespace;

  /// Mapper XML used for validation, relative to the package root.
  ///
  /// For example `assets/person_mapper.xml`.
  final String? xml;

  /// Marks a class as a mapper for [namespace].
  const MybatisMapper(this.namespace, {this.xml});
}

/// Binds a method to `SqlSession.selectList`.
///
/// Omitting [id] uses the method name as the statement id.
class Select {
  /// Statement id; defaults to the method name.
  final String? id;

  /// Marks a list query.
  const Select([this.id]);
}

/// Binds a method to `SqlSession.selectOne`.
class SelectOne {
  /// Statement id; defaults to the method name.
  final String? id;

  /// Marks a single-row query.
  const SelectOne([this.id]);
}

/// Binds a method to `SqlSession.selectCount`.
class SelectCount {
  /// Statement id; defaults to the method name.
  final String? id;

  /// Column holding the count; defaults to `CNT`.
  final String column;

  /// Marks a count query.
  const SelectCount([this.id, this.column = 'CNT']);
}

/// Binds a method to `SqlSession.insert`.
class Insert {
  /// Statement id; defaults to the method name.
  final String? id;

  /// Marks an insert.
  const Insert([this.id]);
}

/// Binds a method to `SqlSession.update`.
class Update {
  /// Statement id; defaults to the method name.
  final String? id;

  /// Marks an update.
  const Update([this.id]);
}

/// Binds a method to `SqlSession.delete`.
class Delete {
  /// Statement id; defaults to the method name.
  final String? id;

  /// Marks a delete.
  const Delete([this.id]);
}

/// Names a parameter (the equivalent of MyBatis `@Param`).
///
/// Without it the Dart parameter name is used as the key. Use it when the
/// XML uses column-style names such as `#{NM}`.
///
/// ```dart
/// Future<Map<String, dynamic>?> findById(@Param('ID') int id);
/// ```
class Param {
  /// Key to use in the parameter map.
  final String name;

  /// Names a parameter [name].
  const Param(this.name);
}

/// Shorthand kept for 0.9.x compatibility.
///
/// New code should name the statement explicitly, e.g.
/// `@Select('selectList')`.
const select = Select();

/// Shorthand kept for 0.9.x compatibility.
const insert = Insert();

/// Shorthand kept for 0.9.x compatibility.
const update = Update();

/// Shorthand kept for 0.9.x compatibility.
const delete = Delete();
