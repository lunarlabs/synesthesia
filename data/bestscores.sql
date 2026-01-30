SELECT 
	concat_ws(' ',s."title",s."sub_title") AS "song_title",
	s."difficulty_name",
	MAX(pr."status") AS "max_status",
	MAX(pr."timing_modifier") AS "max_timing",
	MAX(pr."rank") AS "max_rank",
	MAX(pr."score") AS "best_score",
	MAX(pr."percent_complete") AS "furthest_complete",
	MAX(pr."capture_accuracy") AS "best_accuracy",
	MAX(pr."max_streak") AS "best_streak"
FROM "player_records" pr
LEFT JOIN "library"."v_full_library" s ON pr."midi_hash" = s."midi_hash" AND pr."difficulty" = s."difficulty_offset"
GROUP BY pr.midi_hash, difficulty