// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_mybatis/flutter_mybatis_core.dart';
import 'package:petstore/petstore.dart';

/// JPetStore console demo.
///
/// ```bash
/// dart run                          # or: dart run bin/petstore.dart
/// dart run bin/petstore.dart --sql   # also print the SQL being run
/// ```
///
/// No Flutter, no emulator, no browser.
/// Runs straight away against in-memory SQLite.
Future<void> main(List<String> args) async {
  // Keep box-drawing characters intact on Windows consoles
  stdout.encoding = SystemEncoding();

  final showSql = args.contains('--sql');
  if (showSql) {
    MybatisLogger.setDebugMode(true);
    MybatisLogger.setShowSql(true);
    MybatisLogger.setShowParams(true);
  }

  // Do not let a typo in a test expression pass silently
  MybatisConfig.strictExpressions = true;

  final store = await PetStore.open();

  try {
    await _section('1. Categories', () async {
      for (final c in await store.categories()) {
        print('  ${c['CATID']!.toString().padRight(10)} ${c['NAME']}');
      }
    });

    await _section('2. All products (no filters -> the SQL has no WHERE clause)', () async {
      final products = await store.searchProducts(sortBy: 'name');
      for (final p in products) {
        print('  ${p['PRODUCTID']!.toString().padRight(10)} '
            '${p['NAME']!.toString().padRight(16)} ${p['CATEGORY']}');
      }
      print('  ${products.length} rows');
    });

    await _section('3. Category filter (one <if> is added)', () async {
      final dogs = await store.searchProducts(categoryId: 'DOGS');
      for (final p in dogs) {
        print('  ${p['PRODUCTID']!.toString().padRight(10)} ${p['NAME']}');
      }
    });

    await _section('4. Keyword search (two <if>s and an OR)', () async {
      final found = await store.searchProducts(keyword: 'dog');
      for (final p in found) {
        print('  ${p['NAME']!.toString().padRight(16)} — ${p['DESCN']}');
      }
    });

    await _section('5. Combined filters and a <foreach> IN clause', () async {
      final some = await store.searchProducts(
        productIds: ['FI-SW-01', 'K9-BD-01', 'AV-CB-01'],
        sortBy: 'category',
      );
      for (final p in some) {
        print('  ${p['CATEGORY']!.toString().padRight(10)} ${p['NAME']}');
      }
    });

    await _section('6. Paging (limit / offset)', () async {
      final page1 = await store.searchProducts(sortBy: 'name', limit: 3);
      final page2 =
          await store.searchProducts(sortBy: 'name', limit: 3, offset: 3);
      print('  page 1: ${page1.map((p) => p['NAME']).join(', ')}');
      print('  page 2: ${page2.map((p) => p['NAME']).join(', ')}');
    });

    await _section('7. Items (JOIN plus an optional stock filter)', () async {
      for (final i in await store.itemsOf('K9-BD-01')) {
        print('  ${i['ITEMID']!.toString().padRight(8)} '
            '${i['ATTR1']!.toString().padRight(14)} '
            '\$${i['LISTPRICE']}  stock ${i['QTY']}');
      }
    });

    await _section('8. Order (transaction + <selectKey> + stock deduction)', () async {
      final orderId = await store.placeOrder('jdoe', [
        CartLine('EST-6', 2, 18.50),
        CartLine('EST-14', 1, 193.50),
      ]);
      print('  order $orderId created (id allocated by selectKey)');

      for (final line in await store.orderLines(orderId)) {
        print('  ${line['LINENUM']}. ${line['PRODUCTNAME']} '
            '(${line['ATTR1']}) × ${line['QUANTITY']} '
            '= \$${(line['UNITPRICE'] as num) * (line['QUANTITY'] as num)}');
      }

      final remaining = await store.mapper.item('EST-14');
      print('  EST-14 stock: 2 -> ${remaining!['QTY']}');
    });

    await _section('9. Not enough stock -> everything rolls back', () async {
      final before = await store.mapper.item('EST-10');
      print('  EST-10 stock: ${before!['QTY']}');

      try {
        await store.placeOrder('jdoe', [
          CartLine('EST-1', 1, 16.50), // 이건 성공
          CartLine('EST-10', 99, 18.50), // 재고 5개뿐 → 실패
        ]);
        print('  !! this order should not have succeeded');
      } on OrderFailure catch (e) {
        print('  order failed: ${e.message}');
      }

      final after = await store.mapper.item('EST-1');
      print('  EST-1 stock unchanged: ${after!['QTY']} (rolled back)');

      final orders = await store.ordersOf('jdoe');
      print('  orders for jdoe: ${orders.length} (the failed one left nothing behind)');
    });

    await _section('10. mapUnderscoreToCamelCase', () async {
      MybatisConfig.mapUnderscoreToCamelCase = true;
      final lines = await store.orderLines(1001);
      if (lines.isNotEmpty) {
        print('  keys: ${lines.first.keys.take(5).join(', ')} ...');
      }
      MybatisConfig.mapUnderscoreToCamelCase = false;
    });

    print('');
    print('Done. Pass --sql to see the SQL that was executed.');
  } finally {
    await store.close();
  }
}

Future<void> _section(String title, Future<void> Function() body) async {
  print('');
  print('─' * 64);
  print(title);
  print('─' * 64);
  await body();
}
