/// JPetStore schema and seed data.
///
/// The table structure of jpetstore-6, translated to SQLite.
library;

/// DDL for every table.
const createTables = <String>[
  '''
CREATE TABLE CATEGORY (
  CATID  TEXT PRIMARY KEY,
  NAME   TEXT,
  DESCN  TEXT
)''',
  '''
CREATE TABLE PRODUCT (
  PRODUCTID TEXT PRIMARY KEY,
  CATEGORY  TEXT NOT NULL,
  NAME      TEXT,
  DESCN     TEXT,
  FOREIGN KEY (CATEGORY) REFERENCES CATEGORY (CATID)
)''',
  '''
CREATE TABLE ITEM (
  ITEMID    TEXT PRIMARY KEY,
  PRODUCTID TEXT NOT NULL,
  LISTPRICE REAL,
  UNITCOST  REAL,
  ATTR1     TEXT,
  STATUS    TEXT,
  FOREIGN KEY (PRODUCTID) REFERENCES PRODUCT (PRODUCTID)
)''',
  '''
CREATE TABLE INVENTORY (
  ITEMID TEXT PRIMARY KEY,
  QTY    INTEGER NOT NULL
)''',
  '''
CREATE TABLE ACCOUNT (
  ID        INTEGER PRIMARY KEY AUTOINCREMENT,
  USERID    TEXT UNIQUE NOT NULL,
  EMAIL     TEXT,
  FIRSTNAME TEXT,
  LASTNAME  TEXT,
  STATUS    TEXT
)''',
  '''
CREATE TABLE ORDERS (
  ORDERID    INTEGER PRIMARY KEY,
  USERID     TEXT NOT NULL,
  ORDERDATE  TEXT,
  TOTALPRICE REAL,
  STATUS     TEXT
)''',
  '''
CREATE TABLE LINEITEM (
  ORDERID   INTEGER NOT NULL,
  LINENUM   INTEGER NOT NULL,
  ITEMID    TEXT NOT NULL,
  QUANTITY  INTEGER NOT NULL,
  UNITPRICE REAL,
  PRIMARY KEY (ORDERID, LINENUM)
)''',
];

/// Seed data, taken from the JPetStore catalog.
const seedData = <String>[
  """INSERT INTO CATEGORY VALUES
    ('FISH','Fish','물고기'),
    ('DOGS','Dogs','개'),
    ('REPTILES','Reptiles','파충류'),
    ('CATS','Cats','고양이'),
    ('BIRDS','Birds','새')""",
  """INSERT INTO PRODUCT VALUES
    ('FI-SW-01','FISH','Angelfish','Salt Water fish from Australia'),
    ('FI-SW-02','FISH','Tiger Shark','Salt Water fish from Australia'),
    ('FI-FW-01','FISH','Koi','Fresh Water fish from Japan'),
    ('K9-BD-01','DOGS','Bulldog','Friendly dog from England'),
    ('K9-PO-02','DOGS','Poodle','Cute dog from France'),
    ('K9-DL-01','DOGS','Dalmation','Great dog for a Fire Station'),
    ('RP-SN-01','REPTILES','Rattlesnake','Doubles as a watch dog'),
    ('RP-LI-02','REPTILES','Iguana','Friendly green friend'),
    ('FL-DSH-01','CATS','Manx','Great for reducing mouse populations'),
    ('FL-DLH-02','CATS','Persian','Friendly house cat, doubles as a princess'),
    ('AV-CB-01','BIRDS','Amazon Parrot','Great companion for up to 75 years'),
    ('AV-SB-02','BIRDS','Finch','Great stress reliever')""",
  """INSERT INTO ITEM VALUES
    ('EST-1','FI-SW-01',16.50,10.00,'Large','P'),
    ('EST-2','FI-SW-01',16.50,10.00,'Small','P'),
    ('EST-3','FI-SW-02',18.50,12.00,'Toothless','P'),
    ('EST-4','FI-FW-01',18.50,12.00,'Spotted','P'),
    ('EST-5','FI-FW-01',18.50,12.00,'Spotless','P'),
    ('EST-6','K9-BD-01',18.50,12.00,'Male Adult','P'),
    ('EST-7','K9-BD-01',18.50,12.00,'Female Puppy','P'),
    ('EST-8','K9-PO-02',18.50,12.00,'Male Puppy','P'),
    ('EST-9','K9-DL-01',18.50,12.00,'Spotless Male Puppy','P'),
    ('EST-10','RP-SN-01',18.50,12.00,'Venomless','P'),
    ('EST-11','RP-LI-02',18.50,12.00,'Green Adult','P'),
    ('EST-12','FL-DSH-01',58.50,12.00,'Tailless','P'),
    ('EST-13','FL-DLH-02',93.50,12.00,'Adult Female','P'),
    ('EST-14','AV-CB-01',193.50,92.00,'Adult Male','P'),
    ('EST-15','AV-SB-02',15.50,2.00,'Adult Male','P')""",
  """INSERT INTO INVENTORY VALUES
    ('EST-1',10000),('EST-2',10000),('EST-3',10000),('EST-4',10000),
    ('EST-5',10000),('EST-6',10000),('EST-7',10000),('EST-8',10000),
    ('EST-9',10000),('EST-10',5),('EST-11',10000),('EST-12',10000),
    ('EST-13',10000),('EST-14',2),('EST-15',10000)""",
];
