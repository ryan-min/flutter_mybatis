import 'dart:io';

import 'package:flutter_mybatis/flutter_mybatis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'petstore_mapper.dart';
import 'schema.dart';

export 'petstore_mapper.dart';
export 'schema.dart';

/// One line in the cart.
class CartLine {
  /// Item id (`ITEM.ITEMID`).
  final String itemId;

  /// Quantity ordered.
  final int quantity;

  /// Unit price at the time it was added.
  final double unitPrice;

  /// Creates a cart line.
  CartLine(this.itemId, this.quantity, this.unitPrice);

  /// Line total (unit price x quantity).
  double get subtotal => unitPrice * quantity;
}

/// Thrown when an order cannot be placed, e.g. not enough stock.
class OrderFailure implements Exception {
  /// Why the order failed.
  final String message;

  /// Creates an order failure.
  OrderFailure(this.message);

  @override
  String toString() => 'OrderFailure: $message';
}

/// The JPetStore service layer.
///
/// Uses the generated [PetStoreMapper].
class PetStore {
  /// The open SQLite database.
  final Database db;

  /// The session the mapper runs on.
  final SqlSession session;

  /// The generated mapper.
  final PetStoreMapper mapper;

  /// Creates a store from an existing database, session and mapper.
  PetStore(this.db, this.session, this.mapper);

  /// Opens an in-memory store for the demo and tests.
  ///
  /// [mapperXmlPath] points at `assets/petstore_mapper.xml`.
  static Future<PetStore> open({
    String mapperXmlPath = 'assets/petstore_mapper.xml',
    bool seed = true,
  }) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    for (final ddl in createTables) {
      await db.execute(ddl);
    }
    if (seed) {
      for (final sql in seedData) {
        await db.execute(sql);
      }
    }

    // Not Flutter, so read from a file rather than from assets.
    // (a Flutter app would use factory.loadMapper('assets/...'))
    final xml = File(mapperXmlPath).readAsStringSync();
    final factory = SqlSessionFactory(db)..loadMapperFromString(xml);
    final session = factory.openSession();

    return PetStore(db, session, PetStoreMapper(session));
  }

  /// Closes the database.
  Future<void> close() => db.close();

  /// Every category.
  Future<List<Map<String, dynamic>>> categories() => mapper.categories();

  /// Searches products.
  ///
  /// Every filter is optional; omitted ones are dropped from the SQL.
  Future<List<Map<String, dynamic>>> searchProducts({
    String? categoryId,
    String? keyword,
    List<String>? productIds,
    String sortBy = 'id',
    String sortDir = 'ASC',
    int? limit,
    int? offset,
  }) {
    return mapper.products(
      {
        'CATID': categoryId,
        'keyword': keyword,
        'productIds': productIds,
        'sortBy': sortBy,
        // ${} is raw substitution, so always whitelist it
        'sortDir': sortDir.toUpperCase() == 'DESC' ? 'DESC' : 'ASC',
      },
      limit: limit,
      offset: offset,
    );
  }

  /// Items belonging to a product.
  Future<List<Map<String, dynamic>>> itemsOf(
    String productId, {
    bool inStockOnly = false,
  }) =>
      mapper.itemsOf(productId, inStockOnly);

  /// Places an order.
  ///
  /// Stock deduction and order creation happen in **one transaction**.
  /// If stock runs short it throws [OrderFailure] and everything rolls back.
  Future<int> placeOrder(String userId, List<CartLine> cart) async {
    if (cart.isEmpty) {
      throw OrderFailure('the cart is empty');
    }

    final total = cart.fold<double>(0, (sum, line) => sum + line.subtotal);

    // Rebuild the mapper on the transaction session
    return session.transaction((tx) async {
      final txMapper = PetStoreMapper(tx);

      final order = <String, dynamic>{
        'USERID': userId,
        'ORDERDATE': DateTime.now(),
        'TOTALPRICE': total,
        'STATUS': 'P',
      };

      // <selectKey order="BEFORE"> fills ORDERID
      await txMapper.createOrder(order);
      final orderId = order['ORDERID'] as int;

      for (var i = 0; i < cart.length; i++) {
        final line = cart[i];

        // Short stock updates no rows -> the order fails
        final affected =
            await txMapper.decreaseInventory(line.itemId, line.quantity);
        if (affected == 0) {
          throw OrderFailure(
            'not enough stock: ${line.itemId} (requested ${line.quantity})',
          );
        }

        await txMapper.createOrderLine({
          'ORDERID': orderId,
          'LINENUM': i + 1,
          'ITEMID': line.itemId,
          'QUANTITY': line.quantity,
          'UNITPRICE': line.unitPrice,
        });
      }

      return orderId;
    });
  }

  /// Orders belonging to a user.
  Future<List<Map<String, dynamic>>> ordersOf(String userId, {String? status}) =>
      mapper.orders({'USERID': userId, 'STATUS': status});

  /// Line items of an order.
  Future<List<Map<String, dynamic>>> orderLines(int orderId) =>
      mapper.orderLines(orderId);
}
