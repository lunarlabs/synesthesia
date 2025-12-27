extends Node

func _ready():
	await get_tree().process_frame
	print("--- BEGIN SONG CATALOG FILE TESTS ---\n")
	SongCatalog.scan_for_songs()
	print("saving difficulty details\n")
	SongCatalog.save_difficulty_details_to_json()
	print("saving song entries\n")
	SongCatalog.save_entries_to_json()
	print("clearing catalog\n")
	SongCatalog.catalog.clear()
	print("loading difficulties before entry (you should see a lot of errors)\n")
	SongCatalog.load_difficulty_details_from_json()
	print("loading entries\n")
	SongCatalog.load_entries_from_json()
	print("loading difficulties properly\n")
	SongCatalog.load_difficulty_details_from_json()

	var lowest_rating_title: String
	var lowest_rating_diff: int
	var lowest_rating: float = INF
	var highest_rating_title: String
	var highest_rating_diff: int
	var highest_rating: float = 0.0
	var rating_histogram: Array[int] = []

	for song_entry in SongCatalog.catalog:
		for diff in song_entry.detailed_difficulty_info.keys():
			var rating = song_entry.detailed_difficulty_info[diff].avg_raw_difficulty
			var floored_rating = int(floor(rating))
			if floored_rating >= rating_histogram.size():
				rating_histogram.resize(floored_rating + 1)
			rating_histogram[floored_rating] += 1

			if rating < lowest_rating:
				lowest_rating = rating
				lowest_rating_title = song_entry.title
				lowest_rating_diff = diff

			if rating > highest_rating:
				highest_rating = rating
				highest_rating_title = song_entry.title
				highest_rating_diff = diff

	print("Lowest difficulty rating: %s (%s) - %f" % [lowest_rating_title, lowest_rating_diff, lowest_rating])
	print("Highest difficulty rating: %s (%s) - %f" % [highest_rating_title, highest_rating_diff, highest_rating])
	print("Difficulty rating histogram:")
	for i in range(rating_histogram.size()):
		print("  %d: %d" % [i, rating_histogram[i]])
	print("\n--- END SONG CATALOG FILE TESTS ---")
