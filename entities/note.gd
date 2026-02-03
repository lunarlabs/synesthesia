class_name SynRoadNote
extends Node3D

const PHRASE_MATERIAL:StandardMaterial3D = preload("uid://5nmgyh2a4s76")
@onready var capsule = $capsule
@onready var ghost = $ghost
@onready var particles = $GPUParticles3D
@onready var star = $Star

var suppressed: bool = false
var _blasted: bool = false
var blasted: bool:
	get: return _blasted

var capsule_material: BaseMaterial3D
var ghost_material: BaseMaterial3D

func _ready():
	_blasted = false
	ghost.material_override = ghost_material
	ghost.hide()
	capsule.material_override = capsule_material
	particles.material_override = ghost_material
	capsule.visible = !suppressed

func change_material(mat: BaseMaterial3D):
	capsule.material_override = mat

func blast(emit:bool = false):
	if _blasted:
		return
	_blasted = true
	if emit:
		particles.emitting = true
		star.emitting = true
	capsule.hide()
	ghost.show()

func set_phrase_note(is_phrase: bool):
	get_node("capsule").material_override = PHRASE_MATERIAL if is_phrase else capsule_material
	if not get_node("GPUParticles3D").emitting:
		get_node("GPUParticles3D").material_override = PHRASE_MATERIAL if is_phrase else ghost_material
