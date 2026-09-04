# JPetStore — flutter_mybatis example

[한국어](README-KR.md)

A port of [jpetstore-6](https://github.com/mybatis/jpetstore-6), the official
MyBatis sample application.

The XML mapper you would write in Java works here **almost unchanged**.

## Run it — 30 seconds

```bash
cd example/petstore
dart pub get
dart run
```

No emulator, no browser, no Android Studio. A plain Dart console app against
in-memory SQLite; it starts in about 3 seconds.

The Flutter SDK does have to be installed: `flutter_mybatis` depends on it for
asset loading, so use the `dart` that ships with Flutter.

To see the SQL being executed:

```bash
dart run bin/petstore.dart --sql
```

## Sample output

```
────────────────────────────────────────────────────────────────
3. Category filter (one <if> is added)
────────────────────────────────────────────────────────────────
  K9-BD-01   Bulldog
  K9-DL-01   Dalmation
  K9-PO-02   Poodle

────────────────────────────────────────────────────────────────
8. Order (transaction + <selectKey> + stock deduction)
────────────────────────────────────────────────────────────────
  order 1001 created (id allocated by selectKey)
  1. Bulldog (Male Adult) x 2 = $37.0
  2. Amazon Parrot (Adult Male) x 1 = $193.5
  EST-14 stock: 2 -> 1

────────────────────────────────────────────────────────────────
9. Not enough stock -> everything rolls back
────────────────────────────────────────────────────────────────
  EST-10 stock: 5
  order failed: not enough stock: EST-10 (requested 99)
  EST-1 stock unchanged: 10000 (rolled back)
  orders for jdoe: 1 (the failed one left nothing behind)
```

## Layout

```
petstore/
├── assets/petstore_mapper.xml   the mapper XML, as you would write it in Java
├── lib/
│   ├── petstore_mapper.dart     mapper declaration (no method bodies)
│   ├── petstore_mapper.g.dart   generated implementation (build_runner)
│   ├── petstore.dart            service layer
│   └── schema.dart              DDL and seed data
├── bin/petstore.dart            console demo
└── test/petstore_test.dart      26 tests
```

## What it demonstrates

### 1. SQL lives in XML, not in the code

```xml
<sql id="productColumns">
  P.PRODUCTID, P.NAME, P.DESCN, P.CATEGORY
</sql>

<select id="selectProductList">
  SELECT <include refid="productColumns"/>
  FROM PRODUCT P
  <where>
    <if test="CATID != null and CATID != ''">
      AND P.CATEGORY = #{CATID}
    </if>
    <if test="keyword != null and keyword != ''">
      AND (
        UPPER(P.NAME)  LIKE '%' || UPPER(#{keyword}) || '%'
        OR UPPER(P.DESCN) LIKE '%' || UPPER(#{keyword}) || '%'
      )
    </if>
    <if test="productIds != null and productIds.size() > 0">
      AND P.PRODUCTID IN
      <foreach collection="productIds" item="pid" open="(" close=")" separator=",">
        #{pid}
      </foreach>
    </if>
  </where>
  ORDER BY
  <choose>
    <when test="sortBy == 'name'">P.NAME</when>
    <when test="sortBy == 'category'">P.CATEGORY, P.NAME</when>
    <otherwise>P.PRODUCTID</otherwise>
  </choose>
  ${sortDir}
</select>
```

Conditions you do not pass are **dropped from the SQL entirely**, exactly as in
Java.

### 2. The mapper is only declared

```dart
@MybatisMapper('PetStoreMapper', xml: 'assets/petstore_mapper.xml')
abstract class PetStoreMapper {
  factory PetStoreMapper(SqlSession session) = _$PetStoreMapper;

  @Select('selectProductList')
  Future<List<Map<String, dynamic>>> products(
    Map<String, dynamic> params, {int? limit, int? offset});

  @Update('decreaseInventory')
  Future<int> decreaseInventory(
    @Param('ITEMID') String itemId, @Param('QTY') int qty);
}
```

No method bodies.

```bash
dart run build_runner build
```

Because `xml:` is given, **a typo in a statement id fails the build.** Java
MyBatis only reports that when the application starts.

### 3. Allocating an order id without sequences

JPetStore uses a sequence for order ids. SQLite has none, so `<selectKey>`
does the same job.

```xml
<insert id="insertOrder">
  <selectKey keyProperty="ORDERID" resultType="int" order="BEFORE">
    SELECT IFNULL(MAX(ORDERID), 1000) + 1 AS ORDERID FROM ORDERS
  </selectKey>
  INSERT INTO ORDERS (ORDERID, USERID, ORDERDATE, TOTALPRICE, STATUS)
  VALUES (#{ORDERID}, #{USERID}, #{ORDERDATE}, #{TOTALPRICE}, #{STATUS})
</insert>
```

### 4. Transactions and rollback

Stock deduction and order creation share one transaction. If stock runs short,
everything is undone.

```dart
return session.transaction((tx) async {
  final txMapper = PetStoreMapper(tx);

  await txMapper.createOrder(order);            // selectKey fills ORDERID
  final orderId = order['ORDERID'] as int;

  for (final line in cart) {
    // short stock updates no rows -> the order fails
    final affected = await txMapper.decreaseInventory(line.itemId, line.quantity);
    if (affected == 0) throw OrderFailure('not enough stock: ${line.itemId}');

    await txMapper.createOrderLine({...});
  }
  return orderId;
});
```

Deducting with `WHERE QTY >= #{QTY}` keeps it **concurrency-safe**, the same
approach the original JPetStore takes.

### 5. TypeHandler

sqflite only binds `num`, `String`, `Uint8List` and `null`. Passing a
`DateTime` would normally be a runtime error; a TypeHandler converts it.

```dart
'ORDERDATE': DateTime.now(),   // -> '2026-09-02T12:00:00.000'
```

## Tests

```bash
dart test
```

26 tests run against real SQLite: every dynamic SQL branch, id allocation,
stock deduction, rollback, the `${}` whitelist, paging and
`mapUnderscoreToCamelCase`.

## Differences from the original

| | jpetstore-6 (Java) | this example |
|---|---|---|
| Database | HSQLDB / MySQL | SQLite (in memory) |
| Order id | sequence | `<selectKey>` |
| Result mapping | `resultMap` to POJOs | `Map<String, dynamic>` |
| Mapper implementation | runtime dynamic proxy | build-time code generation |
| UI | JSP / Spring MVC | console (see `example/flutter_app` for a UI) |

Nested `resultMap` is not implemented yet, which is why results are maps.
See the [library README](../../README.md) for the full porting status.

## License and attribution

This example is modelled on [JPetStore 6](https://github.com/mybatis/jpetstore-6).
Its schema, table and column names and sample catalog data derive from that
project.

    Copyright 2010-2024 the original author or authors.
    Licensed under the Apache License, Version 2.0

Distributed under Apache-2.0, like flutter_mybatis itself. See
[NOTICE](../../NOTICE).
