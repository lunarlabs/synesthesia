SELECT 
    s."folder_id",
    s."difficulty_offset",
    coalesce(MAX(pr."status"), 0) AS "max_status"
FROM "library"."v_full_library" s
LEFT JOIN "player_records" pr 
    ON s."midi_hash" = pr."midi_hash" 
   AND s."difficulty_offset" = pr."difficulty"
GROUP BY 
    s."midi_hash", 
    s."difficulty_offset";