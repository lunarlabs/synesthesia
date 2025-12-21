extends Node3D

var gate_location: int
var _fadeout_started: bool = false
var _fadeout_tweener: Tween
@onready var particles = $GPUParticles3D as GPUParticles3D


	
