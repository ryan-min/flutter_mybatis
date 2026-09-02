import 'package:flutter_mybatis/flutter_mybatis_core.dart';
import 'package:petstore/petstore.dart';
import 'package:test/test.dart';

/// JPetStore 예제 테스트
///
/// 순수 Dart라 `dart test` 로 바로 돕니다. Flutter도 에뮬레이터도 필요 없습니다.
void main() {
  late PetStore store;

  setUp(() async {
    MybatisConfig.reset();
    TypeHandlerRegistry.reset();
    // 예제 매퍼의 모든 test 표현식이 지원 범위인지 함께 검증
    MybatisConfig.strictExpressions = true;
    store = await PetStore.open();
  });

  tearDown(() async {
    await store.close();
    MybatisConfig.reset();
    TypeHandlerRegistry.reset();
  });

  group('카탈로그', () {
    test('카테고리 5종', () async {
      final categories = await store.categories();
      expect(categories.length, 5);
      expect(categories.map((c) => c['CATID']), contains('DOGS'));
    });

    test('조건이 없으면 WHERE 절 없이 전체 조회', () async {
      expect((await store.searchProducts()).length, 12);
    });

    test('<if> 카테고리 필터', () async {
      final dogs = await store.searchProducts(categoryId: 'DOGS');
      expect(dogs.length, 3);
      expect(dogs.every((p) => p['CATEGORY'] == 'DOGS'), isTrue);
    });

    test('<if> 키워드 검색 (이름/설명 OR)', () async {
      final found = await store.searchProducts(keyword: 'dog');
      final names = found.map((p) => p['NAME']).toSet();
      expect(names, containsAll(['Bulldog', 'Poodle']));
      // 설명에만 dog가 들어간 것도 잡힌다
      expect(names, contains('Rattlesnake'));
    });

    test('대소문자 무시 검색', () async {
      final upper = await store.searchProducts(keyword: 'DOG');
      final lower = await store.searchProducts(keyword: 'dog');
      expect(upper.length, lower.length);
    });

    test('<foreach> IN 절', () async {
      final some = await store.searchProducts(
        productIds: ['FI-SW-01', 'K9-BD-01'],
      );
      expect(some.length, 2);
    });

    test('빈 목록이면 IN 절이 붙지 않는다', () async {
      expect((await store.searchProducts(productIds: [])).length, 12);
    });

    test('조건 조합 — 카테고리 + 키워드', () async {
      final result = await store.searchProducts(
        categoryId: 'DOGS',
        keyword: 'Puppy',
      );
      expect(result, isEmpty); // 설명에 Puppy 없음
    });

    test('<choose> 정렬', () async {
      final byName = await store.searchProducts(sortBy: 'name');
      expect(byName.first['NAME'], 'Amazon Parrot');

      final desc = await store.searchProducts(sortBy: 'name', sortDir: 'DESC');
      expect(desc.first['NAME'], 'Tiger Shark');
    });

    test('\${} 정렬 방향은 화이트리스트로 막힌다', () async {
      // SQL injection 시도가 그대로 들어가지 않는다
      final result =
          await store.searchProducts(sortBy: 'name', sortDir: 'DESC; DROP TABLE PRODUCT');
      expect(result.length, 12);
      // 테이블이 살아 있다
      expect((await store.searchProducts()).length, 12);
    });

    test('페이징', () async {
      final page1 = await store.searchProducts(sortBy: 'name', limit: 5);
      final page2 =
          await store.searchProducts(sortBy: 'name', limit: 5, offset: 5);

      expect(page1.length, 5);
      expect(page2.length, 5);
      expect(page1.first['NAME'], isNot(page2.first['NAME']));
    });

    test('건수 조회', () async {
      expect(await store.mapper.productCount(null), 12);
      expect(await store.mapper.productCount('DOGS'), 3);
    });
  });

  group('재고 품목', () {
    test('상품의 품목 목록 (JOIN)', () async {
      final items = await store.itemsOf('K9-BD-01');
      expect(items.length, 2);
      expect(items.first['QTY'], isNotNull);
    });

    test('inStockOnly 조건부 필터', () async {
      // EST-10 은 재고 5
      expect((await store.itemsOf('RP-SN-01')).length, 1);
      expect((await store.itemsOf('RP-SN-01', inStockOnly: true)).length, 1);
    });

    test('단건 조회', () async {
      final item = await store.mapper.item('EST-14');
      expect(item!['ATTR1'], 'Adult Male');
      expect(item['QTY'], 2);
    });
  });

  group('주문', () {
    test('<selectKey>로 주문번호가 채번된다', () async {
      final orderId = await store.placeOrder('jdoe', [
        CartLine('EST-6', 2, 18.50),
      ]);
      expect(orderId, 1001);

      final second = await store.placeOrder('jdoe', [
        CartLine('EST-7', 1, 18.50),
      ]);
      expect(second, 1002);
    });

    test('주문 상세가 저장된다', () async {
      final orderId = await store.placeOrder('jdoe', [
        CartLine('EST-6', 2, 18.50),
        CartLine('EST-14', 1, 193.50),
      ]);

      final lines = await store.orderLines(orderId);
      expect(lines.length, 2);
      expect(lines.first['PRODUCTNAME'], 'Bulldog');
      expect(lines.last['QUANTITY'], 1);
    });

    test('재고가 차감된다', () async {
      await store.placeOrder('jdoe', [CartLine('EST-14', 1, 193.50)]);
      expect((await store.mapper.item('EST-14'))!['QTY'], 1);
    });

    test('총액이 계산된다', () async {
      final orderId = await store.placeOrder('jdoe', [
        CartLine('EST-6', 2, 18.50), // 37.0
        CartLine('EST-14', 1, 193.50), // 193.5
      ]);

      final order = await store.mapper.order(orderId);
      expect(order!['TOTALPRICE'], 230.5);
    });

    test('DateTime은 TypeHandler가 변환한다', () async {
      final orderId = await store.placeOrder('jdoe', [
        CartLine('EST-6', 1, 18.50),
      ]);

      final order = await store.mapper.order(orderId);
      expect(order!['ORDERDATE'], isA<String>());
      expect(DateTime.tryParse(order['ORDERDATE'] as String), isNotNull);
    });

    test('재고 부족이면 주문 전체가 롤백된다', () async {
      final before = await store.mapper.item('EST-1');

      await expectLater(
        store.placeOrder('jdoe', [
          CartLine('EST-1', 1, 16.50), // 성공했다가
          CartLine('EST-10', 99, 18.50), // 재고 5개뿐 -> 실패
        ]),
        throwsA(isA<OrderFailure>()),
      );

      // 앞 줄의 재고 차감도 되돌아간다
      expect((await store.mapper.item('EST-1'))!['QTY'], before!['QTY']);
      // 주문 자체가 남지 않는다
      expect(await store.ordersOf('jdoe'), isEmpty);
      expect((await store.mapper.item('EST-10'))!['QTY'], 5);
    });

    test('빈 장바구니는 거부된다', () async {
      await expectLater(
        store.placeOrder('jdoe', []),
        throwsA(isA<OrderFailure>()),
      );
    });

    test('주문 목록 조회 — 사용자/상태 필터', () async {
      await store.placeOrder('jdoe', [CartLine('EST-6', 1, 18.50)]);
      await store.placeOrder('ann', [CartLine('EST-7', 1, 18.50)]);

      expect((await store.ordersOf('jdoe')).length, 1);
      expect((await store.ordersOf('ann')).length, 1);
      expect((await store.ordersOf('jdoe', status: 'P')).length, 1);
      expect((await store.ordersOf('jdoe', status: 'X')), isEmpty);
    });
  });

  group('계정', () {
    test('useGeneratedKeys로 ID가 채워진다', () async {
      final account = <String, dynamic>{
        'USERID': 'jdoe',
        'EMAIL': 'jdoe@example.com',
        'FIRSTNAME': 'John',
        'LASTNAME': 'Doe',
        'STATUS': 'OK',
      };

      await store.mapper.createAccount(account);
      expect(account['ID'], 1);

      final saved = await store.mapper.account('jdoe');
      expect(saved!['EMAIL'], 'jdoe@example.com');
    });

    test('<set>은 넘어온 컬럼만 수정한다', () async {
      await store.mapper.createAccount({
        'USERID': 'jdoe',
        'EMAIL': 'old@example.com',
        'FIRSTNAME': 'John',
        'LASTNAME': 'Doe',
        'STATUS': 'OK',
      });

      await store.mapper.updateAccount({
        'USERID': 'jdoe',
        'EMAIL': 'new@example.com',
      });

      final saved = await store.mapper.account('jdoe');
      expect(saved!['EMAIL'], 'new@example.com');
      expect(saved['FIRSTNAME'], 'John'); // 그대로
    });
  });

  group('설정', () {
    test('mapUnderscoreToCamelCase', () async {
      final orderId = await store.placeOrder('jdoe', [
        CartLine('EST-6', 1, 18.50),
      ]);

      MybatisConfig.mapUnderscoreToCamelCase = true;
      final order = await store.mapper.order(orderId);

      expect(order!.containsKey('orderid'), isTrue);
      expect(order.containsKey('ORDERID'), isFalse);
    });
  });
}
