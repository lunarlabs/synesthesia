BEGIN TRANSACTION;

PRAGMA user_version = 1;

DROP TABLE IF EXISTS "sources";
CREATE TABLE "sources" (
    "source_id"    INTEGER PRIMARY KEY,
    "name"         TEXT NOT NULL UNIQUE COLLATE NOCASE
);

DROP TABLE IF EXISTS "difficulty_levels";
CREATE TABLE "difficulty_levels" (
    "offset"    INTEGER NOT NULL,
    "name"      TEXT NOT NULL UNIQUE,
    PRIMARY KEY("offset")
) WITHOUT ROWID;

DROP TABLE IF EXISTS "songs";
CREATE TABLE "songs" (
    "folder_id"     TEXT NOT NULL CHECK("folder_id" = TRIM("folder_id")),
    "title"         TEXT NOT NULL DEFAULT 'Unknown Song',
    "sub_title"     TEXT,
    "artist"        TEXT NOT NULL DEFAULT 'Unknown Artist',
    "genre"         TEXT NOT NULL DEFAULT 'Unknown Genre',
    "bpm"           REAL NOT NULL DEFAULT 120 CHECK("bpm" BETWEEN 30 AND 300),
    "source"        INTEGER,
    "desc"          TEXT,
    "inst_layout"   TEXT CHECK("inst_layout" = TRIM("inst_layout")
                    AND LENGTH("inst_layout") > 0
                    AND UPPER("inst_layout") GLOB '[DBGSVF]*'),
    "files_ok"      INTEGER NOT NULL DEFAULT 0 CHECK("files_ok" = 0 
                    OR ("resource_hash" IS NOT NULL AND "midi_hash" IS NOT NULL)),
    -- if hashes are null the files don't exist
    "resource_hash" TEXT CHECK("resource_hash" = TRIM("resource_hash") 
                    AND LENGTH("resource_hash") = 32
                    AND resource_hash GLOB '[0-9A-Fa-f]*'),
    "midi_hash"     TEXT CHECK("midi_hash" = TRIM("midi_hash") 
                    AND LENGTH("midi_hash") = 32
                    AND midi_hash GLOB '[0-9A-Fa-f]*'),
    "sort_key" TEXT GENERATED ALWAYS AS (
        CASE
            WHEN lower(concat_ws(' ', title, nullif(sub_title, ''))) LIKE 'the %'
                THEN substr(concat_ws(' ', title, nullif(sub_title, '')), 5)
            WHEN lower(concat_ws(' ', title, nullif(sub_title, ''))) LIKE 'an %'
                THEN substr(concat_ws(' ', title, nullif(sub_title, '')), 4)
            WHEN lower(concat_ws(' ', title, nullif(sub_title, ''))) LIKE 'a %'
                THEN substr(concat_ws(' ', title, nullif(sub_title, '')), 3)
            ELSE concat_ws(' ', title, nullif(sub_title, ''))
        END
    ) STORED,
    PRIMARY KEY("folder_id"),
    FOREIGN KEY("source") REFERENCES "sources"("source_id") ON DELETE SET NULL
);

DROP TABLE IF EXISTS "difficulties";
CREATE TABLE "difficulties" (
    "song_folder"       TEXT NOT NULL,
    "difficulty_offset" INTEGER NOT NULL,
    -- currently the highest rating is 10.7 but future songs may have higher ratings
    "difficulty_rating" REAL NOT NULL CHECK ("difficulty_rating" BETWEEN 0 AND 20),
    "details_json"      TEXT, -- Stores the DetailedDifficultyInfo serializer as JSON
    PRIMARY KEY("song_folder","difficulty_offset"),
    FOREIGN KEY("difficulty_offset") REFERENCES "difficulty_levels"("offset"),
    FOREIGN KEY("song_folder") REFERENCES "songs"("folder_id") ON DELETE CASCADE
);

-- pre-existing immutable data
-- the moggsong standard difficulty levels
INSERT INTO "difficulty_levels" ("offset","name") VALUES (96,'Beginner');
INSERT INTO "difficulty_levels" ("offset","name") VALUES (102,'Basic');
INSERT INTO "difficulty_levels" ("offset","name") VALUES (108,'Advanced');
INSERT INTO "difficulty_levels" ("offset","name") VALUES (114,'Expert');

-- common indices
CREATE INDEX "idx_title" ON "songs" ("sort_key");
CREATE INDEX "idx_songs_title_artist" ON "songs" ("title", "artist");
CREATE INDEX "idx_difficulties_rating" ON "difficulties" ("difficulty_rating");
CREATE INDEX "idx_songs_bpm" ON "songs" ("bpm");
CREATE INDEX "idx_difficulties_song" ON "difficulties" ("song_folder");
CREATE INDEX "idx_songs_source" ON "songs" ("source");


DROP VIEW IF EXISTS "v_full_library";
CREATE VIEW "v_full_library" AS
SELECT
    s."folder_id",
    s."title",
    s."sub_title",
    s."artist",
    s."genre",
    s."bpm",
    s."desc",
    s."sort_key",
    s."inst_layout",
    s."files_ok",
    s."resource_hash",
    s."midi_hash",
    d."difficulty_offset",
    d."difficulty_rating",
    d."details_json",
    dl."name" AS "difficulty_name",
    src."name" AS "source_name"
FROM "songs" s
LEFT JOIN "difficulties" d ON s."folder_id" = d."song_folder"
LEFT JOIN "difficulty_levels" dl ON d."difficulty_offset" = dl."offset"
LEFT JOIN "sources" src ON s."source" = src."source_id";

DROP VIEW IF EXISTS "v_song_upsert";
CREATE VIEW "v_song_upsert" AS
SELECT
    s."folder_id",
    s."title",
    s."sub_title",
    s."artist",
    s."genre",
    s."bpm",
    s."desc",
    s."inst_layout",
    s."files_ok",
    s."resource_hash",
    s."midi_hash",
    src."name" AS "source_name"
FROM "songs" s
LEFT JOIN "sources" src ON s."source" = src."source_id";

DROP TRIGGER IF EXISTS "trg_v_song_insert";
CREATE TRIGGER "trg_v_song_insert"
INSTEAD OF INSERT ON "v_song_upsert"
BEGIN
    INSERT OR IGNORE INTO "sources" ("name") 
    SELECT NEW."source_name"
    WHERE NEW."source_name" IS NOT NULL;

    INSERT INTO "songs" (
        "folder_id",
        "title",
        "sub_title",
        "artist",
        "genre",
        "bpm",
        "desc",
        "inst_layout",
        "files_ok",
        "resource_hash",
        "midi_hash",
        "source"
    ) VALUES (
        NEW."folder_id",
        NEW."title",
        NEW."sub_title",
        NEW."artist",
        NEW."genre",
        NEW."bpm",
        NEW."desc",
        NEW."inst_layout",
        NEW."files_ok",
        NEW."resource_hash",
        NEW."midi_hash",
        (SELECT "source_id" FROM "sources" WHERE "name" = NEW."source_name")
    )
    ON CONFLICT("folder_id") DO UPDATE SET
        title = excluded.title,
        sub_title = excluded.sub_title,
        artist = excluded.artist,
        genre = excluded.genre,
        bpm = excluded.bpm,
        desc = excluded.desc,
        inst_layout = excluded.inst_layout,
        files_ok = excluded.files_ok,
        resource_hash = excluded.resource_hash,
        midi_hash = excluded.midi_hash,
        source = excluded.source;
END;

COMMIT;