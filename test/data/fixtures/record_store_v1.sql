-- Frozen populated version 1. Synthetic data only; never rebuild from current schema.
CREATE TABLE dataset(generation TEXT PRIMARY KEY) STRICT;
CREATE TABLE person(id TEXT PRIMARY KEY, name TEXT NOT NULL) STRICT;
CREATE TABLE item(id TEXT PRIMARY KEY, person TEXT NOT NULL REFERENCES person(id), name TEXT NOT NULL, form TEXT NOT NULL, unit TEXT NOT NULL CHECK(unit IN ('mg','ml','count')), type TEXT NOT NULL, UNIQUE(id,person)) STRICT;
CREATE TABLE administration(id TEXT PRIMARY KEY, person TEXT NOT NULL, item TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), UNIQUE(id,person), FOREIGN KEY(item,person) REFERENCES item(id,person)) STRICT;
CREATE TABLE revision(record TEXT NOT NULL, person TEXT NOT NULL, revision INTEGER NOT NULL, name TEXT NOT NULL, form TEXT NOT NULL, unit TEXT NOT NULL CHECK(unit IN ('mg','ml','count')), type TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 9000000000000000), entered TEXT NOT NULL, actual INTEGER NOT NULL, entered_at INTEGER NOT NULL, voided INTEGER NOT NULL CHECK(voided IN (0,1)), PRIMARY KEY(record,revision), FOREIGN KEY(record,person) REFERENCES administration(id,person)) STRICT;
CREATE TABLE operation(id TEXT PRIMARY KEY, payload TEXT NOT NULL, result TEXT NOT NULL) STRICT;
CREATE INDEX administration_person ON administration(person,id);
CREATE INDEX revision_actual ON revision(actual,record);
INSERT INTO dataset VALUES ('fixture-generation');
INSERT INTO person VALUES ('me','Me'),('other','Synthetic other');
INSERT INTO item VALUES ('item','me','Current synthetic item','tablet','mg','medicine'),('other-item','other','Other item','liquid','ml','supplement');
INSERT INTO administration VALUES ('record','me','item',2),('other-record','other','other-item',1);
INSERT INTO revision VALUES ('record','me',1,'Original snapshot','tablet','mg','medicine',125000,'0.125000',1792368000000000,1792368000000010,0),('record','me',2,'Original snapshot','tablet','mg','medicine',500000,'0.5',1792368000000000,1792368000000020,1),('other-record','other',1,'Other snapshot','liquid','ml','supplement',1000000,'1',1792368000000000,1792368000000030,0);
INSERT INTO operation VALUES ('fixture-operation','["fixture-generation","record","me","item","0.125000",1792368000000000]','{"id":"record","person":"me","item":"item","name":"Original snapshot","form":"tablet","unit":"mg","type":"medicine","amount":125000,"entered":"0.125000","actual":1792368000000000,"entered_at":1792368000000010,"revision":1,"voided":0}');
PRAGMA user_version=1;
