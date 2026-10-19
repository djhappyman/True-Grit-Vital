-- Frozen populated version 5. Synthetic data only; never rebuild from current schema.
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
