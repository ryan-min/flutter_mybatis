# JPetStore — flutter_mybatis 예제

MyBatis 공식 샘플 [jpetstore-6](https://github.com/mybatis/jpetstore-6)를
Flutter/Dart로 이식한 예제입니다.

자바에서 쓰던 XML 매퍼가 **거의 그대로** 동작합니다.

## 실행 — 30초

```bash
cd example/petstore
dart pub get
dart run
```

에뮬레이터도, 브라우저도, 안드로이드 스튜디오도 필요 없습니다. 순수 Dart
콘솔 앱이고 DB는 인메모리 SQLite라 **약 3초**에 뜹니다.

Flutter SDK 자체는 설치되어 있어야 합니다. `flutter_mybatis` 가 에셋 로딩
때문에 Flutter에 의존하므로, 함께 딸려오는 `dart` 를 쓰십시오.

실행되는 SQL을 보려면:

```bash
dart run bin/petstore.dart --sql
```

## 출력 예시

```
────────────────────────────────────────────────────────────────
3. 카테고리 필터 (<if> 하나가 붙는다)
────────────────────────────────────────────────────────────────
  K9-BD-01   Bulldog
  K9-DL-01   Dalmation
  K9-PO-02   Poodle

────────────────────────────────────────────────────────────────
8. 주문 (트랜잭션 + <selectKey> 채번 + 재고 차감)
────────────────────────────────────────────────────────────────
  주문번호 1001 생성 (selectKey로 채번)
  1. Bulldog (Male Adult) × 2 = $37.0
  2. Amazon Parrot (Adult Male) × 1 = $193.5
  EST-14 재고: 2 → 1

────────────────────────────────────────────────────────────────
9. 재고 부족 → 전체 롤백
────────────────────────────────────────────────────────────────
  EST-10 재고: 5개
  주문 실패: 재고 부족: EST-10 (요청 99개)
  EST-1 재고 그대로: 10000 (롤백됨)
  jdoe 주문 건수: 1건 (실패 주문은 남지 않음)
```

## 구성

```
petstore/
├── assets/petstore_mapper.xml   매퍼 XML (자바에서 쓰던 그대로)
├── lib/
│   ├── petstore_mapper.dart     Mapper 선언 (본문 없음)
│   ├── petstore_mapper.g.dart   생성된 구현 (build_runner)
│   ├── petstore.dart            서비스 계층
│   └── schema.dart              DDL + 시드 데이터
├── bin/petstore.dart            콘솔 데모
└── test/petstore_test.dart      26개 테스트
```

## 이 예제가 보여주는 것

### 1. SQL은 XML에, 코드에는 SQL이 없다

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

넘기지 않은 조건은 SQL에서 **통째로 빠집니다.** 자바에서와 똑같습니다.

### 2. Mapper는 선언만 한다

```dart
@MybatisMapper('PetStoreMapper', xml: 'assets/petstore_mapper.xml')
abstract class PetStoreMapper {
  factory PetStoreMapper(SqlSession session) = _$PetStoreMapper;

  @Select('selectProductList')
  Future<List<Map<String, dynamic>>> products(
    Map<String, dynamic> params, {int? limit, int? offset});

  @SelectOne('selectProduct')
  Future<Map<String, dynamic>?> product(@Param('PRODUCTID') String productId);

  @Update('decreaseInventory')
  Future<int> decreaseInventory(
    @Param('ITEMID') String itemId, @Param('QTY') int qty);
}
```

메서드 본문을 한 줄도 쓰지 않습니다.

```bash
dart run build_runner build
```

`xml:` 을 지정했으므로 **statement id 오타는 빌드 시점에 잡힙니다.**
자바 MyBatis는 앱 기동 시점에야 알 수 있는 오류입니다.

### 3. 시퀀스가 없는 SQLite에서 주문번호 채번

JPetStore는 시퀀스로 주문번호를 만듭니다. SQLite에는 시퀀스가 없으므로
`<selectKey>`로 같은 효과를 냅니다.

```xml
<insert id="insertOrder">
  <selectKey keyProperty="ORDERID" resultType="int" order="BEFORE">
    SELECT IFNULL(MAX(ORDERID), 1000) + 1 AS ORDERID FROM ORDERS
  </selectKey>
  INSERT INTO ORDERS (ORDERID, USERID, ORDERDATE, TOTALPRICE, STATUS)
  VALUES (#{ORDERID}, #{USERID}, #{ORDERDATE}, #{TOTALPRICE}, #{STATUS})
</insert>
```

### 4. 트랜잭션과 롤백

재고 차감과 주문 생성이 한 트랜잭션입니다. 재고가 모자라면 전부 되돌아갑니다.

```dart
return session.transaction((tx) async {
  final txMapper = PetStoreMapper(tx);

  await txMapper.createOrder(order);           // selectKey가 ORDERID를 채움
  final orderId = order['ORDERID'] as int;

  for (final line in cart) {
    // 재고가 모자라면 0건 갱신 -> 주문 실패
    final affected = await txMapper.decreaseInventory(line.itemId, line.quantity);
    if (affected == 0) throw OrderFailure('재고 부족: ${line.itemId}');

    await txMapper.createOrderLine({...});
  }
  return orderId;
});
```

재고 차감을 `WHERE QTY >= #{QTY}` 로 처리해 **동시성 안전**하게 만든 것도
원본 JPetStore와 같은 방식입니다.

### 5. TypeHandler

sqflite는 `num` `String` `Uint8List` `null` 만 바인딩합니다.
`DateTime`을 그대로 넘기면 원래는 런타임 오류인데, TypeHandler가 변환합니다.

```dart
'ORDERDATE': DateTime.now(),   // -> '2026-09-01T12:00:00.000'
```

## 테스트

```bash
dart test
```

26개 테스트가 실제 SQLite에서 돕니다 — 동적 SQL 전 분기, 채번, 재고 차감,
롤백, `${}` 화이트리스트, 페이징, `mapUnderscoreToCamelCase`.

## 원본과 다른 점

| 항목 | jpetstore-6 (Java) | 이 예제 |
|---|---|---|
| DB | HSQLDB / MySQL | SQLite (인메모리) |
| 주문번호 | 시퀀스 | `<selectKey>` |
| 결과 매핑 | `resultMap` → POJO | `Map<String, dynamic>` |
| 매퍼 구현 | 런타임 동적 프록시 | 빌드 시점 코드 생성 |
| 화면 | JSP / Spring MVC | 콘솔 (Flutter UI는 `example/` 참고) |

`resultMap` 중첩 매핑은 아직 미지원이라 결과가 `Map` 입니다.
자세한 이식 범위는 [라이브러리 README](../../README.md)를 보십시오.

## 라이선스와 출처

이 예제는 [JPetStore 6](https://github.com/mybatis/jpetstore-6)을 모델로 했습니다.
스키마, 테이블·컬럼명, 샘플 카탈로그 데이터가 그 프로젝트에서 파생됐습니다.

    Copyright 2010-2024 the original author or authors.
    Licensed under the Apache License, Version 2.0

flutter_mybatis 본체와 동일하게 Apache License 2.0 으로 배포됩니다.
자세한 내용은 저장소 루트의 [NOTICE](../../NOTICE) 를 보십시오.
