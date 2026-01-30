-- use on the player database after attaching the library database
-- this returns the campaign total score (based on accuracy and difficulty)
WITH aggregated AS (
    SELECT 
        pr.midi_hash,
        concat_ws(' ', s."title", s."sub_title") AS song_title,
        pr."difficulty",
        MAX(pr."status") AS max_status,
        MAX(pr."timing_modifier") AS max_timing,
        MAX(pr."rank") AS max_rank,
        MAX(pr."score") AS best_score,
        MAX(pr."percent_complete") AS furthest_complete,
        MAX(pr."capture_accuracy") AS best_accuracy,
        MAX(pr."max_streak") AS best_streak,
        s."difficulty_rating"
    FROM player_records pr
    LEFT JOIN library.v_full_library s
      ON pr.midi_hash = s.midi_hash
     AND pr.difficulty = s.difficulty_offset
    GROUP BY pr.midi_hash, pr.difficulty
),

ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY midi_hash
            ORDER BY 
                CASE WHEN furthest_complete = 100.0 THEN 1 ELSE 0 END DESC,
                furthest_complete DESC,
                difficulty DESC
        ) AS rn
    FROM aggregated
)

SELECT SUM(pow((best_accuracy / 100.0),3) * difficulty_rating) AS freq_score
FROM ranked
WHERE rn = 1;
