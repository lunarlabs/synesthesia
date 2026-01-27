extends HBoxContainer

enum FinishMode {
	COMPLETE,
	FAILED,
	PRACTICE,
	AUTOBLAST,
}

@onready var anim = $AnimationPlayer as AnimationPlayer

func display(
	finish_type: FinishMode,
	result: SessionManager.SongResult,
	prev: SessionManager.SongResult,
):
	var lbl_clear_type_prev = %ClearTypeBox.get_node("Previous")
	var lbl_clear_type_new = %ClearTypeBox.get_node("New")
	var lbl_rank_prev = %RankBox.get_node("Previous")
	var lbl_rank_new = %RankBox.get_node("New")
	var lbl_completion = %CompletionBox.get_node("Value")
	var lbl_score_prev = %ScorePanel.get_node("%Previous")
	var lbl_score_new = %ScorePanel.get_node("%New")
	var lbl_score_diff = %ScorePanel.get_node("%Difference")
	var lbl_streak_prev = %StreakPanel.get_node("%Previous")
	var lbl_streak_new = %StreakPanel.get_node("%New")
	var lbl_streak_diff = %StreakPanel.get_node("%Difference")
	var lbl_acc_prev = %AccuracyPanel.get_node("%Previous")
	var lbl_acc_new = %AccuracyPanel.get_node("%New")
	var lbl_acc_diff = %AccuracyPanel.get_node("%Difference")
	if not prev:
		prev = SessionManager.SongResult.new()
	%SongTitleLabel.text = result.title
	%ArtistLabel.text = result.artist
	%DifficultyLabel.text = SynRoadSongManager.DIFFICULTY_NAMES[result.difficulty]
	lbl_clear_type_prev.text = prev.get_clear_string(true)
	lbl_clear_type_new.text = result.get_clear_string(true)
	lbl_rank_prev.text = prev.get_rank_string()
	lbl_rank_new.text = result.get_rank_string()
	%RankLabel.text = result.get_rank_string()
	lbl_completion.text = "%.2f%%" % result.percent_completed
	lbl_score_prev.text = str(prev.score)
	lbl_score_new.text = str(result.score)
	var score_difference = result.score - prev.score
	lbl_score_diff.text = "%+d" % score_difference
	lbl_streak_prev.text = str(prev.max_streak)
	lbl_streak_new.text = str(result.max_streak)
	var streak_difference = result.max_streak - prev.max_streak
	lbl_streak_diff.text = "%+d" % streak_difference
	lbl_acc_prev.text = "%.2f%%" % prev.accuracy
	lbl_acc_new.text = "%.2f%%" % result.accuracy
	var acc_difference = result.accuracy - prev.accuracy
	lbl_acc_diff.text = "%+.2f%%" % acc_difference
	%StreakBreaksLabel.text = str(result.streak_breaks)
	
	match finish_type:
		FinishMode.COMPLETE:
			%CompletionBox.hide()
			%RankPanel.show()
			%RankBox.show()
		FinishMode.FAILED:
			%CompletionBox.show()
			%RankPanel.hide()
			%RankBox.hide()
		FinishMode.PRACTICE:
			%RankPanel.hide()
			%RankBox.hide()
			%ClearTypeBox.hide()
			%RestartButton.hide()
		FinishMode.AUTOBLAST:
			$RightSide.hide()
			%RestartButton.hide()
	
	show()
	anim.play("BuildIn")
	await anim.animation_finished
	%RestartButton.disabled = false
	%ExitButton.disabled = false
