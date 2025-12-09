extends Node3D

var mat: BaseMaterial3D
@onready var left = $left_rail
@onready var right = $right_rail

func _ready():
	left.material_override = mat
	right.material_override = mat
