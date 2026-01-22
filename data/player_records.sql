BEGIN TRANSACTION;

DROP TABLE IF EXISTS "ranks";
CREATE TABLE "ranks" (
    "rank_id"       INTEGER PRIMARY KEY,
    "rank_label"    TEXT NOT NULL UNIQUE
);

DROP TABLE IF EXISTS "clear_status";
CREATE TABLE "clear_status" (
    "status_id"     INTEGER PRIMARY KEY,
    "status_label"  TEXT NOT NULL UNIQUE
);

COMMIT;