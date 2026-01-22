BEGIN TRANSACTION;

-- lookup tables
DROP TABLE IF EXISTS "ranks";
CREATE TABLE "ranks" (
    "rank_id"       INTEGER PRIMARY KEY,
    "rank_label"    TEXT NOT NULL UNIQUE
);

DROP TABLE IF EXISTS "clear_statuses";
CREATE TABLE "clear_statuses" (
    "status_id"     INTEGER PRIMARY KEY,
    "status_label"  TEXT NOT NULL UNIQUE
);

DROP TABLE IF EXISTS "energy_modifiers";
CREATE TABLE "energy_modifier" (
    "energy_id"     INTEGER PRIMARY KEY,
    "energy_name"   TEXT NOT NULL UNIQUE
);

DROP TABLE IF EXISTS "checkpoint_modifiers";
CREATE TABLE "checkpoint_modifiers" (
    "checkpoint_id"     INTEGER PRIMARY KEY,
    "checkpoint_name"   TEXT NOT NULL UNIQUE
);

DROP TABLE IF EXISTS "timing_modifiers";
CREATE TABLE "timing_modifiers" (
    "timing_id"     INTEGER PRIMARY KEY,
    "timing_name"   TEXT NOT NULL UNIQUE
);

DROP TABLE IF EXISTS "track_resets";
CREATE TABLE "track_resets" (
    "reset_len"     INTEGER NOT NULL UNIQUE,
    "reset_name"    TEXT NOT NULL UNIQUE,
    PRIMARY KEY("reset_len")
) WITHOUT ROWID;

-- primary table
DROP TABLE IF EXISTS "player_records";
CREATE TABLE "player_records" (
    "record_id"             INTEGER PRIMARY KEY,
    "midi_hash"             TEXT NOT NULL CHECK(LENGTH("midi_hash") = 32),
    "timestamp"             TEXT NOT NULL,
    "difficulty"            INTEGER NOT NULL CHECK("difficulty" IN (96, 102, 108, 114)),
    "score"                 INTEGER NOT NULL,
    "percent_complete"      REAL NOT NULL CHECK("percent_complete" BETWEEN 0.0 AND 100.0),
    "capture_accuracy"      REAL NOT NULL CHECK("capture_accuracy" BETWEEN 0.0 AND 100.0),
    "max_streak"            INTEGER NOT NULL,
    "status"                INTEGER NOT NULL,
    "rank"                  INTEGER,
    "streak_breaks"         INTEGER NOT NULL,
    "energy_modifier"       INTEGER NOT NULL,
    "checkpoint_modifier"   INTEGER NOT NULL,
    "timing_modifier"       INTEGER NOT NULL,
    "track_reset"           INTEGER NOT NULL,
    FOREIGN KEY("status") REFERENCES "clear_statuses"("status_id"),
    FOREIGN KEY("rank") REFERENCES "ranks"("rank_id"),
    FOREIGN KEY("energy_modifier") REFERENCES "energy_modifiers"("energy_id"),
    FOREIGN KEY("checkpoint_modifier") REFERENCES "checkpoint_modifiers"("checkpoint_id"),
    FOREIGN KEY("timing_modifier") REFERENCES "timing_modifiers"("timing_id"),
    FOREIGN KEY("track_reset") REFERENCES "track_resets"("reset_len")
);

INSERT INTO "ranks" ("rank_label")
VALUES ('F'), ('E'), ('D'), ('C'), ('B'), ('A'), ('AA'), ('AAA');

INSERT INTO "clear_statuses" ("status_label")
VALUES ('Failed'), ('Cleared'), ('Perfect');

INSERT INTO "energy_modifiers" ("energy_name")
VALUES ('Normal'), ('Drain'), ('No Recovery'), ('Sudden Death'), ('No Fail');

INSERT INTO "checkpoint_modifiers" ("checkpoint_name")
VALUES ('Normal'), ('Disabled'), ('Barrier 2x'), ('Barrier 3x'), ('Barrier 4x');

INSERT INTO "timing_modifiers" ("timing_name")
VALUES ('Normal'), ('Loose'), ('Strict');

INSERT INTO "track_resets" ("reset_len", "reset_name")
VALUES (12, 'Normal'), (10, 'Fast Reset 1'), (8, 'Fast Reset 2');

CREATE INDEX "idx_player_pb" ON "player_records" ("midi_hash", "difficulty", "score");

COMMIT;
