-- Frozen populated v12 from ticket10 checkpoint, synthetic only.
-- Frozen populated schema11 pause migration fixture, synthetic only.
-- Frozen populated schema10 fixture, synthetic only.
-- Frozen schema9 reminder baseline before product migration. Synthetic data only.
-- Frozen schema8 populated stock/actual quantity; captured before reminder migration.
-- Frozen populated version 7. Synthetic data only; never rebuild from current schema.
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
CREATE TABLE setting(key TEXT PRIMARY KEY,value TEXT NOT NULL) STRICT;
INSERT INTO setting VALUES ('appearance','dark');
ALTER TABLE administration ADD COLUMN actual INTEGER NOT NULL DEFAULT 0;
UPDATE administration SET actual=(SELECT actual FROM revision WHERE record=administration.id AND person=administration.person AND revision=administration.revision);
CREATE INDEX administration_feed ON administration(person,actual DESC,id);
CREATE INDEX administration_item_feed ON administration(person,item,actual DESC,id);


ALTER TABLE person ADD COLUMN archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1));
ALTER TABLE person ADD COLUMN revision INTEGER NOT NULL DEFAULT 1 CHECK(revision > 0);
ALTER TABLE person ADD COLUMN adult_confirmed INTEGER NOT NULL DEFAULT 0 CHECK(adult_confirmed IN (0,1));
ALTER TABLE person ADD COLUMN report_name TEXT;
ALTER TABLE person ADD COLUMN relationship TEXT;
ALTER TABLE person ADD COLUMN notes TEXT;
ALTER TABLE person ADD COLUMN reminders_stopped INTEGER NOT NULL DEFAULT 0 CHECK(reminders_stopped IN (0,1));
CREATE INDEX person_active ON person(archived,id);
CREATE INDEX administration_everyone ON administration(actual DESC,id);
CREATE TABLE reminder_stop(person TEXT PRIMARY KEY, revision INTEGER NOT NULL) STRICT;
CREATE TABLE revision_source(record TEXT NOT NULL, revision INTEGER NOT NULL, source TEXT NOT NULL CHECK(source IN ('unspecified','selfReported','recordedOnBehalf')), PRIMARY KEY(record,revision), FOREIGN KEY(record,revision) REFERENCES revision(record,revision) ON DELETE CASCADE) STRICT;
UPDATE person SET revision=3,adult_confirmed=1,notes='Synthetic profile secret' WHERE id='other';
INSERT INTO revision_source VALUES ('other-record',1,'recordedOnBehalf');
CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT;
INSERT INTO ordinary_draft VALUES ('saved-draft','fixture-generation','draft-op','dose','other',3,'other-item',NULL,'{"fields":{"amount":"1.000","date":"2026-10-19","time":"12:00","instant":""},"submitted":false}');


CREATE TABLE daily_plan(id TEXT PRIMARY KEY,person TEXT NOT NULL,item TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),UNIQUE(id,person),UNIQUE(item,person),FOREIGN KEY(item,person) REFERENCES item(id,person)) STRICT;
CREATE TABLE daily_version(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,start TEXT NOT NULL,end TEXT,snapshot TEXT NOT NULL,UNIQUE(plan,start),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE,CHECK(end IS NULL OR end>start)) STRICT;
CREATE TABLE daily_version_audit(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,snapshot TEXT NOT NULL,FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT;
CREATE INDEX daily_version_bounds ON daily_version(plan,start,end);
CREATE TRIGGER daily_version_overlap BEFORE INSERT ON daily_version WHEN EXISTS(SELECT 1 FROM daily_version v WHERE v.plan=NEW.plan AND (NEW.end IS NULL OR v.start<NEW.end) AND (v.end IS NULL OR NEW.start<v.end)) BEGIN SELECT RAISE(ABORT,'daily_version_overlap'); END;
CREATE TABLE daily_expectation(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,date TEXT NOT NULL,snapshot TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),UNIQUE(id,person),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT;
CREATE INDEX daily_expectation_range ON daily_expectation(plan,date);
CREATE TABLE daily_action(id TEXT PRIMARY KEY,bucket TEXT NOT NULL,person TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('taken','skip')),record TEXT UNIQUE,revision INTEGER NOT NULL CHECK(revision>0),undone INTEGER NOT NULL CHECK(undone IN (0,1)),sequence INTEGER NOT NULL,recorded_at INTEGER NOT NULL,UNIQUE(bucket,sequence),CHECK((kind='taken')=(record IS NOT NULL)),FOREIGN KEY(bucket,person) REFERENCES daily_expectation(id,person) ON DELETE CASCADE,FOREIGN KEY(record,person) REFERENCES administration(id,person)) STRICT;
CREATE INDEX daily_action_bucket ON daily_action(bucket,id);
CREATE TABLE daily_clock(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,date TEXT NOT NULL,snapshot TEXT NOT NULL,FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT;
CREATE TABLE daily_reminder_intent(plan TEXT PRIMARY KEY,person TEXT NOT NULL,revision INTEGER NOT NULL,stopped INTEGER NOT NULL CHECK(stopped IN (0,1)),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT;
PRAGMA user_version=6;
INSERT INTO daily_plan VALUES ('plan','me','item',1);
INSERT INTO daily_version VALUES ('version','plan','me','2026-10-19',NULL,'{"person":"me","plan":"plan","item":"item","version":"version","start":"2026-10-19","end":null,"home":null,"timing":{"kind":"prn"}}');
-- Frozen schema 7 catalogue migration and populated type/provenance.
CREATE TABLE personal_item_type(id TEXT PRIMARY KEY,person TEXT NOT NULL REFERENCES person(id),name TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),UNIQUE(person,name),UNIQUE(id,person)) STRICT;
CREATE INDEX personal_item_type_owner ON personal_item_type(person,name,id);
ALTER TABLE item ADD COLUMN type_id TEXT REFERENCES personal_item_type(id);
ALTER TABLE item ADD COLUMN item_revision INTEGER NOT NULL DEFAULT 1 CHECK(item_revision>0);
ALTER TABLE item ADD COLUMN catalogue_snapshot TEXT;
INSERT INTO personal_item_type(id,person,name) VALUES ('medicine-type','me','medicine'),('supplement-type','other','supplement');
UPDATE item SET type_id=CASE WHEN person='me' THEN 'medicine-type' ELSE 'supplement-type' END;
CREATE TRIGGER item_type_insert BEFORE INSERT ON item WHEN NEW.type_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM personal_item_type t WHERE t.id=NEW.type_id AND t.person=NEW.person) BEGIN SELECT RAISE(ABORT,'item_type_owner'); END;
CREATE TRIGGER item_type_update BEFORE UPDATE OF type_id,person ON item WHEN NEW.type_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM personal_item_type t WHERE t.id=NEW.type_id AND t.person=NEW.person) BEGIN SELECT RAISE(ABORT,'item_type_owner'); END;
CREATE INDEX item_type_owner ON item(person,type_id,id);
CREATE TABLE revision_catalogue(record TEXT NOT NULL,revision INTEGER NOT NULL,catalogue_snapshot TEXT,PRIMARY KEY(record,revision),FOREIGN KEY(record,revision) REFERENCES revision(record,revision) ON DELETE CASCADE) STRICT;
ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v6;
CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','itemType')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT;
INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v6;
DROP TABLE ordinary_draft_v6;
PRAGMA user_version=7;

CREATE TABLE revision_quantity(record TEXT NOT NULL,revision INTEGER NOT NULL,numerator TEXT NOT NULL CHECK(length(numerator) BETWEEN 1 AND 20000 AND numerator NOT GLOB '*[^0-9]*' AND substr(numerator,1,1) BETWEEN '1' AND '9'),denominator TEXT NOT NULL CHECK(length(denominator) BETWEEN 1 AND 20000 AND denominator NOT GLOB '*[^0-9]*' AND substr(denominator,1,1) BETWEEN '1' AND '9'),unit TEXT NOT NULL CHECK(unit IN ('mg','ml','count')),entered TEXT NOT NULL,entered_unit TEXT NOT NULL CHECK(entered_unit IN ('mg','ml','count')),strength TEXT,replacement TEXT,PRIMARY KEY(record,revision),FOREIGN KEY(record,revision) REFERENCES revision(record,revision) ON DELETE CASCADE) STRICT;
CREATE TRIGGER revision_quantity_immutable BEFORE UPDATE ON revision_quantity BEGIN SELECT RAISE(ABORT,'immutable_actual_quantity'); END;
CREATE TABLE stock_container(id TEXT PRIMARY KEY CHECK(length(id)>0),person TEXT NOT NULL,item TEXT NOT NULL,label TEXT NOT NULL CHECK(length(label) BETWEEN 1 AND 500),unit TEXT NOT NULL CHECK(unit IN ('mg','ml','count')),strength TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),sequence INTEGER NOT NULL CHECK(sequence>=0),measurement_sequence INTEGER NOT NULL CHECK(measurement_sequence>=0 AND measurement_sequence<=sequence),balance_status TEXT NOT NULL CHECK(balance_status IN ('known','unknown','limit')),numerator TEXT,denominator TEXT,threshold_n TEXT,threshold_d TEXT,refill INTEGER NOT NULL CHECK(refill IN (0,1)),notice_eligible INTEGER NOT NULL DEFAULT 0 CHECK(notice_eligible IN (0,1)),notice_active INTEGER NOT NULL DEFAULT 1 CHECK(notice_active IN (0,1)),UNIQUE(id,person),UNIQUE(id,person,item),FOREIGN KEY(item,person) REFERENCES item(id,person),CHECK((numerator IS NULL)=(denominator IS NULL)),CHECK((balance_status='known')=(numerator IS NOT NULL)),CHECK((threshold_n IS NULL)=(threshold_d IS NULL)),CHECK(numerator IS NULL OR (length(numerator) BETWEEN 1 AND 20000 AND length(denominator) BETWEEN 1 AND 20000))) STRICT;
CREATE INDEX stock_container_owner ON stock_container(person,item,id);
CREATE INDEX stock_container_notices ON stock_container(notice_active,notice_eligible,person,item,id);
CREATE TABLE stock_movement(id TEXT PRIMARY KEY CHECK(length(id)>0),person TEXT NOT NULL,container TEXT NOT NULL,sequence INTEGER NOT NULL CHECK(sequence>0),kind TEXT NOT NULL CHECK(kind IN ('restock','actualUse','waste','reconciliation','correction')),numerator TEXT,denominator TEXT,strength TEXT NOT NULL,entered TEXT,entered_unit TEXT CHECK(entered_unit IN ('mg','ml','count')),record TEXT UNIQUE,reverses TEXT UNIQUE,physical_choice TEXT CHECK(physical_choice IN ('reverseRecordedEffect','retainPhysicalEffect')),replacement TEXT,reason TEXT CHECK(length(reason)<=4000),operation TEXT NOT NULL UNIQUE CHECK(length(operation)>0),generation TEXT NOT NULL CHECK(length(generation)>0),recorded_at INTEGER NOT NULL,UNIQUE(container,sequence),UNIQUE(id,person,container),FOREIGN KEY(container,person) REFERENCES stock_container(id,person) ON DELETE CASCADE,FOREIGN KEY(record,person) REFERENCES administration(id,person),FOREIGN KEY(reverses,person,container) REFERENCES stock_movement(id,person,container),CHECK((numerator IS NULL)=(denominator IS NULL)),CHECK((kind='actualUse')=(record IS NOT NULL)),CHECK((kind='correction')=(reverses IS NOT NULL)),CHECK((kind='correction')=(physical_choice IS NOT NULL)),CHECK((entered IS NULL)=(entered_unit IS NULL)),CHECK(numerator IS NULL OR (length(numerator) BETWEEN 1 AND 20000 AND length(denominator) BETWEEN 1 AND 20000))) STRICT;
CREATE INDEX stock_movement_owner ON stock_movement(person,container,sequence);
CREATE TRIGGER stock_movement_pair BEFORE INSERT ON stock_movement WHEN NEW.numerator IS NOT NULL AND (NEW.denominator GLOB '*[^0-9]*' OR substr(NEW.denominator,1,1) NOT BETWEEN '1' AND '9' OR NOT (NEW.numerator='0' OR (NEW.numerator NOT GLOB '*[^0-9]*' AND substr(NEW.numerator,1,1) BETWEEN '1' AND '9') OR (substr(NEW.numerator,1,1)='-' AND substr(NEW.numerator,2) NOT GLOB '*[^0-9]*' AND substr(NEW.numerator,2,1) BETWEEN '1' AND '9'))) BEGIN SELECT RAISE(ABORT,'stock_pair'); END;
CREATE TRIGGER stock_movement_semantics BEFORE INSERT ON stock_movement WHEN (NEW.kind='restock' AND (NEW.numerator IS NULL OR NEW.numerator='0' OR substr(NEW.numerator,1,1)='-')) OR (NEW.kind IN ('actualUse','waste') AND NEW.numerator IS NOT NULL AND substr(NEW.numerator,1,1)<>'-') OR (NEW.kind='waste' AND NEW.numerator IS NULL) OR (NEW.kind IN ('reconciliation','correction') AND substr(NEW.numerator,1,1)='-') OR NEW.sequence<>(SELECT sequence+1 FROM stock_container WHERE id=NEW.container AND person=NEW.person) OR NEW.strength<>(SELECT strength FROM stock_container WHERE id=NEW.container AND person=NEW.person) OR NEW.generation<>(SELECT generation FROM dataset) OR (NEW.record IS NOT NULL AND (SELECT item FROM administration WHERE id=NEW.record AND person=NEW.person)<>(SELECT item FROM stock_container WHERE id=NEW.container AND person=NEW.person)) BEGIN SELECT RAISE(ABORT,'stock_semantics'); END;
CREATE TRIGGER stock_correction_target BEFORE INSERT ON stock_movement WHEN NEW.kind='correction' AND NOT EXISTS(SELECT 1 FROM stock_movement old WHERE old.id=NEW.reverses AND old.person=NEW.person AND old.container=NEW.container AND old.kind IN ('actualUse','waste') AND ((NEW.physical_choice='retainPhysicalEffect' AND NEW.numerator='0' AND NEW.denominator='1') OR (NEW.physical_choice='reverseRecordedEffect' AND ((old.numerator IS NULL AND NEW.numerator IS NULL) OR (NEW.numerator=substr(old.numerator,2) AND NEW.denominator=old.denominator))))) BEGIN SELECT RAISE(ABORT,'stock_correction_target'); END;
CREATE TRIGGER stock_movement_immutable BEFORE UPDATE ON stock_movement BEGIN SELECT RAISE(ABORT,'immutable_stock_movement'); END;
CREATE TRIGGER stock_container_identity BEFORE UPDATE OF id,person,item,label,unit,strength ON stock_container BEGIN SELECT RAISE(ABORT,'immutable_stock_identity'); END;
ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v7;
CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','itemType','stockContainer','stockAdjustment')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT;
INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v7;
DROP TABLE ordinary_draft_v7;
INSERT INTO revision_quantity VALUES ('other-record',1,'1','3','ml','0.333333333333','ml','{"ingredient":"synthetic","label":"Synthetic exact metadata","pair":["50","1"]}',NULL);
PRAGMA user_version=8;

CREATE TABLE reminder_meta(id INTEGER PRIMARY KEY CHECK(id=1),namespace TEXT NOT NULL,sequence INTEGER NOT NULL DEFAULT 0,fingerprint TEXT NOT NULL DEFAULT '') STRICT;
CREATE TABLE reminder_config(plan TEXT PRIMARY KEY,person TEXT NOT NULL,enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),revision INTEGER NOT NULL CHECK(revision>0),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT;
CREATE TABLE reminder_state(bucket TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 0,snooze_revision INTEGER NOT NULL DEFAULT 0,ordinary_terminal INTEGER NOT NULL DEFAULT 0 CHECK(ordinary_terminal IN (0,1)),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT;
CREATE TABLE reminder_request(token TEXT PRIMARY KEY,bucket TEXT,plan TEXT,person TEXT,snapshot TEXT,intent_revision INTEGER NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)),state TEXT NOT NULL,reason TEXT,fingerprint TEXT,cancel_ack INTEGER NOT NULL DEFAULT 0 CHECK(cancel_ack IN (0,1))) STRICT;
CREATE INDEX reminder_request_current ON reminder_request(active,plan,bucket);
CREATE INDEX reminder_request_work ON reminder_request(token) WHERE active=1 AND snapshot IS NOT NULL AND state IN ('pending','prepared','failed','unknown','capacity');
CREATE INDEX reminder_request_attention ON reminder_request(state,token) WHERE active=1 AND snapshot IS NOT NULL;
CREATE INDEX reminder_request_due ON reminder_request(json_extract(snapshot,'$.deadline')) WHERE active=1 AND json_extract(snapshot,'$.kind')='ordinary' AND state IN ('pending','prepared','failed','unknown','capacity');
CREATE TABLE reminder_pending(envelope TEXT PRIMARY KEY,person TEXT,request TEXT,action_token TEXT,action TEXT NOT NULL,command TEXT NOT NULL UNIQUE,draft TEXT NOT NULL UNIQUE,snapshot TEXT,delay INTEGER,delay_text TEXT,observed_zone TEXT,sample TEXT,actual INTEGER,submitted INTEGER NOT NULL DEFAULT 0 CHECK(submitted IN (0,1)),consumed INTEGER NOT NULL DEFAULT 0 CHECK(consumed IN (0,1))) STRICT;
CREATE UNIQUE INDEX reminder_pending_token ON reminder_pending(action_token) WHERE action_token IS NOT NULL;
INSERT INTO reminder_meta VALUES (1,'synthetic-v9-namespace',7,'fixture');
INSERT INTO reminder_config VALUES ('plan','me',1,1);
PRAGMA user_version=9;

-- Frozen schema10 product SQL from the pre-interval calendar checkpoint.
CREATE TABLE product_label(item TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),snapshot TEXT NOT NULL CHECK(length(snapshot)<=32000 AND json_valid(snapshot) AND json_extract(snapshot,'$.personId') IS person AND json_extract(snapshot,'$.itemId') IS item AND json_extract(snapshot,'$.revision') IS revision AND json_array_length(snapshot,'$.components') BETWEEN 2 AND 32),PRIMARY KEY(item,revision),FOREIGN KEY(item,person) REFERENCES item(id,person) ON DELETE CASCADE) STRICT;
CREATE TRIGGER product_label_immutable BEFORE UPDATE ON product_label BEGIN SELECT RAISE(ABORT,'immutable_product_label'); END;
CREATE TABLE revision_product(record TEXT NOT NULL,revision INTEGER NOT NULL,snapshot TEXT NOT NULL CHECK(length(snapshot)<=70000 AND json_valid(snapshot)),PRIMARY KEY(record,revision),FOREIGN KEY(record,revision) REFERENCES revision(record,revision) ON DELETE CASCADE) STRICT;
CREATE TRIGGER revision_product_immutable BEFORE UPDATE ON revision_product BEGIN SELECT RAISE(ABORT,'immutable_product_actual'); END;
CREATE TRIGGER revision_product_context BEFORE INSERT ON revision_product WHEN json_extract(NEW.snapshot,'$.label.personId') IS NOT (SELECT person FROM administration WHERE id=NEW.record) OR json_extract(NEW.snapshot,'$.defaultLabel.personId') IS NOT (SELECT person FROM administration WHERE id=NEW.record) OR json_extract(NEW.snapshot,'$.label.itemId') IS NOT (SELECT item FROM administration WHERE id=NEW.record) OR json_extract(NEW.snapshot,'$.defaultLabel.itemId') IS NOT (SELECT item FROM administration WHERE id=NEW.record) OR json_extract(NEW.snapshot,'$.volume[0]') IS NOT (SELECT numerator FROM revision_quantity WHERE record=NEW.record AND revision=NEW.revision) OR json_extract(NEW.snapshot,'$.volume[1]') IS NOT (SELECT denominator FROM revision_quantity WHERE record=NEW.record AND revision=NEW.revision) OR (SELECT unit FROM revision_quantity WHERE record=NEW.record AND revision=NEW.revision) IS NOT 'ml' BEGIN SELECT RAISE(ABORT,'product_actual_context'); END;
ALTER TABLE stock_container ADD COLUMN product_label TEXT;
CREATE TRIGGER stock_product_immutable BEFORE UPDATE OF product_label ON stock_container BEGIN SELECT RAISE(ABORT,'immutable_product_source'); END;
CREATE TRIGGER stock_product_context BEFORE INSERT ON stock_container WHEN NEW.product_label IS NOT NULL AND (NOT json_valid(NEW.product_label) OR json_extract(NEW.product_label,'$.personId') IS NOT NEW.person OR json_extract(NEW.product_label,'$.itemId') IS NOT NEW.item OR NEW.unit<>'ml') BEGIN SELECT RAISE(ABORT,'product_source_context'); END;
ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v9;
CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','itemType','stockContainer','stockAdjustment','productLabel')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT;
INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v9;
DROP TABLE ordinary_draft_v9;
INSERT INTO product_label VALUES ('other-item','other',1,'{"personId":"other","itemId":"other-item","revision":1,"components":[{"ingredientId":"a","name":"Synthetic A","concentrationText":"2","massUnit":"mg","volumeUnit":"ml"},{"ingredientId":"b","name":"Synthetic B","concentrationText":"3","massUnit":"mg","volumeUnit":"ml"}]}');
INSERT INTO daily_plan VALUES ('calendar-plan','other','other-item',1);
INSERT INTO daily_version VALUES ('calendar-v1','calendar-plan','other','2026-10-19',NULL,'{"person":"other","plan":"calendar-plan","item":"other-item","version":"calendar-v1","start":"2026-10-19","end":null,"home":"Europe/London","calendar":{"version":1,"kind":"weekdays","days":[1,3]},"timing":{"kind":"count","count":1,"amount":{"entered":"1","unit":"ml"}}}');
INSERT INTO daily_version_audit VALUES ('calendar-v1','calendar-plan','other',1,'{"person":"other","plan":"calendar-plan","item":"other-item","version":"calendar-v1","start":"2026-10-19","end":null,"home":"Europe/London","calendar":{"version":1,"kind":"weekdays","days":[1,3]},"timing":{"kind":"count","count":1,"amount":{"entered":"1","unit":"ml"}}}');
INSERT INTO reminder_request VALUES ('frozen-cancelled',NULL,NULL,NULL,NULL,1,0,'pending','cancelled',NULL,0);
INSERT INTO administration(id,person,item,revision,actual) VALUES ('product-fixture','other','other-item',1,1792368000000000);
INSERT INTO revision VALUES ('product-fixture','other',1,'Frozen synthetic product','liquid','ml','supplement',500000,'0.500000',1792368000000000,1792368000000040,0);
INSERT INTO revision_source VALUES ('product-fixture',1,'recordedOnBehalf');
INSERT INTO revision_quantity VALUES ('product-fixture',1,'1','2','ml','0.500000','ml',NULL,NULL);
INSERT INTO revision_product VALUES ('product-fixture',1,'{"label":{"personId":"other","itemId":"other-item","revision":1,"components":[{"ingredientId":"a","name":"Synthetic A","concentrationText":"2","massUnit":"mg","volumeUnit":"ml"},{"ingredientId":"b","name":"Synthetic B","concentrationText":"3","massUnit":"mg","volumeUnit":"ml"}]},"defaultLabel":{"personId":"other","itemId":"other-item","revision":1,"components":[{"ingredientId":"a","name":"Synthetic A","concentrationText":"2","massUnit":"mg","volumeUnit":"ml"},{"ingredientId":"b","name":"Synthetic B","concentrationText":"3","massUnit":"mg","volumeUnit":"ml"}]},"volume":["1","2"],"amounts":[["1","1"],["3","2"]]}');


-- Frozen schema11 interval tables from independent interval checkpoint.
CREATE TABLE interval_recovery(plan TEXT PRIMARY KEY,person TEXT NOT NULL,cutoff TEXT NOT NULL,FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT;
CREATE TABLE interval_clock(plan TEXT NOT NULL,person TEXT NOT NULL,segment TEXT NOT NULL,boot TEXT NOT NULL,utc INTEGER NOT NULL,elapsed INTEGER NOT NULL CHECK(elapsed>=0),PRIMARY KEY(plan,segment),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT;
CREATE TABLE interval_qualification(plan TEXT NOT NULL,person TEXT NOT NULL,segment TEXT NOT NULL,record TEXT NOT NULL,qualifies INTEGER NOT NULL CHECK(qualifies IN (0,1)),revision INTEGER NOT NULL CHECK(revision>0),PRIMARY KEY(plan,segment,record),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE,FOREIGN KEY(record,person) REFERENCES administration(id,person)) STRICT;
INSERT INTO interval_qualification VALUES ('calendar-plan','other','frozen-segment','product-fixture',1,1);
INSERT INTO interval_clock VALUES ('calendar-plan','other','frozen-segment','frozen-boot',1792404000000,12345);
INSERT INTO interval_recovery VALUES ('calendar-plan','other','2026-10-19');
PRAGMA user_version=11;

DROP TRIGGER daily_version_overlap;
ALTER TABLE daily_version RENAME TO daily_version_v11;
CREATE TABLE daily_version(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,start TEXT NOT NULL,end TEXT,snapshot TEXT NOT NULL,FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE,CHECK(end IS NULL OR end>start)) STRICT;
INSERT INTO daily_version SELECT * FROM daily_version_v11;
DROP TABLE daily_version_v11;
CREATE INDEX daily_version_bounds ON daily_version(plan,start,end);
CREATE TRIGGER daily_version_overlap BEFORE INSERT ON daily_version WHEN EXISTS(SELECT 1 FROM daily_version v WHERE v.plan=NEW.plan AND (NEW.end IS NULL OR v.start<NEW.end) AND (v.end IS NULL OR NEW.start<v.end) AND NOT ((json_extract(v.snapshot,'$.effectiveUntil') IS NOT NULL AND json_extract(NEW.snapshot,'$.effectiveFrom') IS NOT NULL AND json_extract(v.snapshot,'$.effectiveUntil')<=json_extract(NEW.snapshot,'$.effectiveFrom')) OR (json_extract(NEW.snapshot,'$.effectiveUntil') IS NOT NULL AND json_extract(v.snapshot,'$.effectiveFrom') IS NOT NULL AND json_extract(NEW.snapshot,'$.effectiveUntil')<=json_extract(v.snapshot,'$.effectiveFrom')))) BEGIN SELECT RAISE(ABORT,'daily_version_overlap'); END;
ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v11;
CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','pausePlan','itemType','stockContainer','stockAdjustment','productLabel')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT;
INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v11;
DROP TABLE ordinary_draft_v11;
CREATE TABLE pause_change(id TEXT PRIMARY KEY,plan TEXT NOT NULL,person TEXT NOT NULL,revision INTEGER NOT NULL,before_snapshot TEXT NOT NULL,after_snapshot TEXT NOT NULL,recorded_at INTEGER NOT NULL,UNIQUE(plan,revision),FOREIGN KEY(plan,person) REFERENCES daily_plan(id,person) ON DELETE CASCADE) STRICT;
CREATE TRIGGER pause_change_immutable BEFORE UPDATE ON pause_change BEGIN SELECT RAISE(ABORT,'pause_history_immutable'); END;
INSERT INTO pause_change VALUES ('frozen-pause','calendar-plan','other',2,'{"person":"other","plan":"calendar-plan","item":"other-item","version":"calendar-v1","start":"2026-10-19","end":null,"home":"Europe/London","calendar":{"version":1,"kind":"weekdays","days":[1,3]},"timing":{"kind":"count","count":1,"amount":{"entered":"1","unit":"ml"}}}','{"person":"other","plan":"calendar-plan","item":"other-item","version":"calendar-v2","start":"2026-10-19","end":null,"home":"Europe/London","calendar":{"version":1,"kind":"weekdays","days":[1,3]},"timing":{"kind":"count","count":1,"amount":{"entered":"1","unit":"ml"}},"pauses":[{"start":1792404000000000,"resume":1792411200000000}],"effectiveUntil":1792411200000000}',1792404000000000);
UPDATE daily_version SET id='calendar-v2',snapshot='{"person":"other","plan":"calendar-plan","item":"other-item","version":"calendar-v2","start":"2026-10-19","end":null,"home":"Europe/London","calendar":{"version":1,"kind":"weekdays","days":[1,3]},"timing":{"kind":"count","count":1,"amount":{"entered":"1","unit":"ml"}},"pauses":[{"start":1792404000000000,"resume":1792411200000000}],"effectiveUntil":1792411200000000}' WHERE id='calendar-v1';
INSERT INTO daily_version_audit VALUES ('calendar-v2','calendar-plan','other',2,'{"person":"other","plan":"calendar-plan","item":"other-item","version":"calendar-v2","start":"2026-10-19","end":null,"home":"Europe/London","calendar":{"version":1,"kind":"weekdays","days":[1,3]},"timing":{"kind":"count","count":1,"amount":{"entered":"1","unit":"ml"}},"pauses":[{"start":1792404000000000,"resume":1792411200000000}],"effectiveUntil":1792411200000000}');
INSERT INTO daily_version VALUES ('calendar-v3','calendar-plan','other','2026-10-19',NULL,'{"person":"other","plan":"calendar-plan","item":"other-item","version":"calendar-v3","start":"2026-10-19","end":null,"home":"Europe/London","calendar":{"version":1,"kind":"weekdays","days":[1,3]},"timing":{"kind":"count","count":1,"amount":{"entered":"1","unit":"ml"}},"pauses":[{"start":1792404000000000,"resume":1792411200000000}],"effectiveFrom":1792411200000000}');
INSERT INTO daily_version_audit VALUES ('calendar-v3','calendar-plan','other',3,'{"person":"other","plan":"calendar-plan","item":"other-item","version":"calendar-v3","start":"2026-10-19","end":null,"home":"Europe/London","calendar":{"version":1,"kind":"weekdays","days":[1,3]},"timing":{"kind":"count","count":1,"amount":{"entered":"1","unit":"ml"}},"pauses":[{"start":1792404000000000,"resume":1792411200000000}],"effectiveFrom":1792411200000000}');
UPDATE daily_plan SET revision=3 WHERE id='calendar-plan';
INSERT INTO daily_reminder_intent VALUES ('calendar-plan','other',3,0);
INSERT INTO ordinary_draft VALUES ('frozen-pause-draft','fixture-generation','frozen-pause-op','pausePlan','other',1,'other-item',1,'{"fields":{"planId":"calendar-plan","versionId":"future-pause","pauseInstant":"1792404000000000"},"submitted":false}');
PRAGMA user_version=12;
