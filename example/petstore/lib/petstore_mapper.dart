import 'package:flutter_mybatis/flutter_mybatis_core.dart';

part 'petstore_mapper.g.dart';

/// The JPetStore mapper.
///
/// Declared like a MyBatis `@Mapper` interface: no method bodies.
/// `dart run build_runner build` writes the implementation into
/// `petstore_mapper.g.dart`.
///
/// Because `xml:` is given, statement id typos fail the build.
@MybatisMapper('PetStoreMapper', xml: 'assets/petstore_mapper.xml')
abstract class PetStoreMapper {
  /// Creates a mapper bound to [session].
  factory PetStoreMapper(SqlSession session) = _$PetStoreMapper;

  // ---------------- 카테고리 ----------------

  /// Every category, by name.
  @Select('selectCategoryList')
  Future<List<Map<String, dynamic>>> categories();

  /// One category.
  @SelectOne('selectCategory')
  Future<Map<String, dynamic>?> category(@Param('CATID') String catId);

  // ---------------- 상품 ----------------

  /// Searches products.
  ///
  /// Filters you omit make the matching `<if>` false, dropping the clause.
  /// Keys: `CATID`, `keyword`, `productIds`, `sortBy`, `sortDir`.
  @Select('selectProductList')
  Future<List<Map<String, dynamic>>> products(
    Map<String, dynamic> params, {
    int? limit,
    int? offset,
  });

  /// One product.
  @SelectOne('selectProduct')
  Future<Map<String, dynamic>?> product(@Param('PRODUCTID') String productId);

  /// Product count; pass null for every category.
  @SelectCount('selectProductCount')
  Future<int> productCount(@Param('CATID') String? catId);

  // ---------------- 재고 품목 ----------------

  /// Items belonging to a product.
  ///
  /// With [inStockOnly] only items still in stock are returned.
  @Select('selectItemListByProduct')
  Future<List<Map<String, dynamic>>> itemsOf(
    @Param('PRODUCTID') String productId,
    @Param('inStockOnly') bool inStockOnly,
  );

  /// One item, including its stock level.
  @SelectOne('selectItem')
  Future<Map<String, dynamic>?> item(@Param('ITEMID') String itemId);

  /// Deducts stock.
  ///
  /// Uses `WHERE QTY >= #{QTY}`, so a short stock level updates **no rows**.
  /// Treat a return value of 0 as insufficient stock.
  @Update('decreaseInventory')
  Future<int> decreaseInventory(
    @Param('ITEMID') String itemId,
    @Param('QTY') int qty,
  );

  // ---------------- 계정 ----------------

  /// Creates an account; `useGeneratedKeys` fills `ID` in [account].
  @Insert('insertAccount')
  Future<int> createAccount(Map<String, dynamic> account);

  /// Looks up an account.
  @SelectOne('selectAccount')
  Future<Map<String, dynamic>?> account(@Param('USERID') String userId);

  /// Updates an account; `<set>` touches only the columns you pass.
  @Update('updateAccount')
  Future<int> updateAccount(Map<String, dynamic> account);

  // ---------------- 주문 ----------------

  /// Creates an order.
  ///
  /// `<selectKey order="BEFORE">` fills `ORDERID` in [order].
  @Insert('insertOrder')
  Future<int> createOrder(Map<String, dynamic> order);

  /// Creates one order line.
  @Insert('insertOrderLine')
  Future<int> createOrderLine(Map<String, dynamic> line);

  /// Orders, optionally filtered by `USERID` and `STATUS`.
  @Select('selectOrderList')
  Future<List<Map<String, dynamic>>> orders(Map<String, dynamic> params);

  /// One order.
  @SelectOne('selectOrder')
  Future<Map<String, dynamic>?> order(@Param('ORDERID') int orderId);

  /// Order lines, joined with product name and option.
  @Select('selectOrderLineList')
  Future<List<Map<String, dynamic>>> orderLines(@Param('ORDERID') int orderId);

  /// Changes an order's status.
  @Update('updateOrderStatus')
  Future<int> updateOrderStatus(
    @Param('ORDERID') int orderId,
    @Param('STATUS') String status,
  );

  /// Deletes an order.
  @Delete('deleteOrder')
  Future<int> deleteOrder(@Param('ORDERID') int orderId);

  /// Deletes every line of an order.
  @Delete('deleteOrderLines')
  Future<int> deleteOrderLines(@Param('ORDERID') int orderId);
}
