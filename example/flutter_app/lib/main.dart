import 'package:flutter/material.dart';
import 'package:flutter_mybatis/flutter_mybatis.dart';
import 'package:sqflite/sqflite.dart';

import 'person_mapper.dart';

/// flutter_mybatis example app.
///
/// - SQL separated into an XML mapper
/// - dynamic SQL: `<if>` `<where>` `<foreach>` `<choose>` `<include>`
/// - retrieving the generated id with `useGeneratedKeys`
/// - automatic `DateTime` / `bool` conversion via TypeHandler
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 설정 (전부 선택 사항, 기본값은 0.9.x 동작과 동일)
  MybatisConfig.mapUnderscoreToCamelCase = false; // 예제는 원본 컬럼명 사용
  MybatisConfig.strictExpressions = true; // 오타난 test 표현식을 조용히 넘기지 않는다
  MybatisLogger.setDebugMode(true); // 실행 SQL을 콘솔에 출력

  // 2. bool을 'Y'/'N'이 아니라 1/0으로 저장 (기본값)
  //    필요하면 TypeHandlerRegistry.register(const YnBoolTypeHandler());

  // 3. DB 준비
  final database = await openDatabase(
    'flutter_mybatis_example.db',
    version: 1,
    onCreate: (db, _) => db.execute(createPersonTable),
  );

  // 4. Mapper 로드
  final factory = SqlSessionFactory(database);
  await factory.loadMappers(['assets/person_mapper.xml']);

  // PersonMapper(...) 는 생성된 구현체로 연결된다 (factory 리다이렉트)
  runApp(ExampleApp(mapper: PersonMapper(factory.openSession())));
}

/// Root of the example app.
class ExampleApp extends StatelessWidget {
  /// The generated mapper.
  final PersonMapper mapper;

  /// Creates the app root.
  const ExampleApp({super.key, required this.mapper});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_mybatis 예제',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: PersonListPage(mapper: mapper),
    );
  }
}

/// Person list screen: search, insert and delete.
class PersonListPage extends StatefulWidget {
  /// The generated mapper.
  final PersonMapper mapper;

  /// Creates the list screen.
  const PersonListPage({super.key, required this.mapper});

  @override
  State<PersonListPage> createState() => _PersonListPageState();
}

class _PersonListPageState extends State<PersonListPage> {
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _people = [];
  int _total = 0;
  int? _minAge;
  bool _activeOnly = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    // 값이 null이면 <if>가 false가 되어 해당 조건절이 SQL에서 통째로 빠진다
    final people = await widget.mapper.search({
      'NM': _searchController.text.isEmpty ? null : _searchController.text,
      'minAge': _minAge,
      'activeOnly': _activeOnly,
    });
    final total = await widget.mapper.countAll(_activeOnly);

    if (!mounted) return;
    setState(() {
      _people = people;
      _total = total;
    });
  }

  Future<void> _addSample() async {
    final person = <String, dynamic>{
      'NM': '홍길동 ${DateTime.now().millisecondsSinceEpoch % 1000}',
      'AGE': 20 + (_people.length % 30),
      'EMAIL': 'sample@example.com',
      // TypeHandler가 bool -> 1/0, DateTime -> ISO8601 문자열로 변환한다
      'ACTIVE_FL': true,
      'JOIN_DT': DateTime.now(),
    };

    // useGeneratedKeys 로 person['ID'] 가 채워진다
    await widget.mapper.add(person);
    final id = person['ID'];

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('등록 완료 — useGeneratedKeys로 받은 ID: $id')),
    );
    await _reload();
  }

  Future<void> _delete(int id) async {
    await widget.mapper.remove(id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_mybatis 예제'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => _reload(),
                  decoration: const InputDecoration(
                    hintText: '이름 검색 (<if> 조건절이 동적으로 붙습니다)',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('활성만'),
                      selected: _activeOnly,
                      onSelected: (v) {
                        setState(() => _activeOnly = v);
                        _reload();
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('30세 이상'),
                      selected: _minAge != null,
                      onSelected: (v) {
                        setState(() => _minAge = v ? 30 : null);
                        _reload();
                      },
                    ),
                    const Spacer(),
                    Text('전체 $_total명'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: _people.isEmpty
          ? const Center(child: Text('데이터가 없습니다. + 버튼으로 추가하십시오.'))
          : ListView.separated(
              itemCount: _people.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final person = _people[i];
                return ListTile(
                  leading: CircleAvatar(child: Text('${person['ID']}')),
                  title: Text('${person['NM']}'),
                  subtitle: Text(
                    '${person['AGE']}세 · ${person['EMAIL'] ?? '-'}'
                    '${person['ACTIVE_FL'] == 1 ? '' : ' · 비활성'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(person['ID'] as int),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSample,
        child: const Icon(Icons.add),
      ),
    );
  }
}
