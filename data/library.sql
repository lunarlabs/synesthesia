BEGIN TRANSACTION;

DROP TABLE IF EXISTS "sources";
CREATE TABLE "sources" (
    "source_id"    INTEGER PRIMARY KEY,
    "name"         TEXT NOT NULL
);

DROP TABLE IF EXISTS "difficulty_levels";
CREATE TABLE "difficulty_levels" (
    "offset"    INTEGER NOT NULL,
    "name"      TEXT NOT NULL UNIQUE,
    PRIMARY KEY("offset")
) WITHOUT ROWID;

DROP TABLE IF EXISTS "songs";
CREATE TABLE "songs" (
    "folder_id"     TEXT NOT NULL,
    "title"         TEXT NOT NULL,
    "sub_title"     TEXT,
    "artist"        TEXT NOT NULL,
    "genre"         TEXT NOT NULL DEFAULT 'Unknown Genre',
    "bpm"           INTEGER NOT NULL DEFAULT 120 CHECK("bpm" BETWEEN 30 AND 300),
    "source"        INTEGER,
    "desc"          TEXT,
    "inst_layout"   TEXT NOT NULL CHECK("inst_layout" = TRIM("inst_layout") AND UPPER("inst_layout") GLOB '[DBGSVF]*'),
    "files_ok"      INTEGER NOT NULL DEFAULT 0 CHECK("files_ok" IN (0, 1)),
    "resource_hash" TEXT,
    "midi_hash"     TEXT,
    PRIMARY KEY("folder_id"),
    FOREIGN KEY("source") REFERENCES "sources"("source_id") ON DELETE SET NULL
);

DROP TABLE IF EXISTS "difficulties";
CREATE TABLE "difficulties" (
    "song_folder"       TEXT NOT NULL,
    "difficulty_offset" INTEGER NOT NULL,
    "difficulty_rating" REAL NOT NULL CHECK ("difficulty_rating" BETWEEN 0 AND 15),
    PRIMARY KEY("song_folder","difficulty_offset"),
    FOREIGN KEY("difficulty_offset") REFERENCES "difficulty_levels"("offset"),
    FOREIGN KEY("song_folder") REFERENCES "songs"("folder_id") ON DELETE CASCADE
);

-- pre-existing immutable data
INSERT INTO "difficulty_levels" ("offset","name") VALUES (96,'Beginner');
INSERT INTO "difficulty_levels" ("offset","name") VALUES (102,'Basic');
INSERT INTO "difficulty_levels" ("offset","name") VALUES (108,'Advanced');
INSERT INTO "difficulty_levels" ("offset","name") VALUES (114,'Expert');

-- common indices
CREATE INDEX "idx_songs_title_artist" ON "songs" ("title", "artist");

COMMIT;