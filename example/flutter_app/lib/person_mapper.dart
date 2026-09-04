import 'package:flutter_mybatis/flutter_mybatis.dart';

part 'person_mapper.g.dart';

/// PersonMapper — the equivalent of a MyBatis `@Mapper` interface.
///
/// No method bodies: `flutter_mybatis_generator` writes the implementation
/// into `person_mapper.g.dart`.
///
/// ```bash
/// dart run build_runner build
/// ```
///
/// Because `xml:` is given, statement id typos fail **the build**.
/// Java MyBatis only reports them at start-up.
@MybatisMapper('PersonMapper', xml: 'assets/person_mapper.xml')
abstract class PersonMapper {
  /// Creates a mapper bound to [session].
  factory PersonMapper(SqlSession session) = _$PersonMapper;

  /// Searches with optional filters.
  ///
  /// A null value makes the matching `<if>` false, dropping the clause.
  @Select('selectList')
  Future<List<Map<String, dynamic>>> search(Map<String, dynamic> params);

  /// Paged search; `limit` / `offset` are forwarded as-is.
  @Select('selectList')
  Future<List<Map<String, dynamic>>> searchPaged(
    Map<String, dynamic> params, {
    int? limit,
    int? offset,
  });

  /// Single row; `@Param` matches the XML's `#{ID}`.
  @SelectOne('selectById')
  Future<Map<String, dynamic>?> findById(@Param('ID') int id);

  /// Row count.
  @SelectCount('selectCount')
  Future<int> countAll(@Param('activeOnly') bool activeOnly);

  /// Sorted search.
  @Select('selectSorted')
  Future<List<Map<String, dynamic>>> sorted(
    @Param('sortBy') String sortBy,
    @Param('sortDir') String sortDir,
  );

  /// Insert; `useGeneratedKeys` fills the new id into [person].
  @Insert('insert')
  Future<int> add(Map<String, dynamic> person);

  /// Insert that allocates the id with `<selectKey>`.
  @Insert('insertWithSelectKey')
  Future<int> addWithSelectKey(Map<String, dynamic> person);

  /// Update; `<set>` touches only the columns you pass.
  @Update('update')
  Future<int> modify(Map<String, dynamic> person);

  /// Deletes one row.
  @Delete('delete')
  Future<int> remove(@Param('ID') int id);

  /// Deletes several rows.
  @Delete('deleteByIds')
  Future<int> removeAll(@Param('ids') List<int> ids);
}

/// Schema used by this example.
const createPersonTable = '''
CREATE TABLE PERSON (
  ID        INTEGER PRIMARY KEY AUTOINCREMENT,
  NM        TEXT    NOT NULL,
  AGE       INTEGER,
  EMAIL     TEXT,
  ACTIVE_FL INTEGER NOT NULL DEFAULT 1,
  JOIN_DT   TEXT
)
''';
