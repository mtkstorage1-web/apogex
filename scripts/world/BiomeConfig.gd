class_name BiomeConfig
extends Resource

@export var id: StringName
@export var display_name: String
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.WHITE
@export_range(0.0, 1.0) var roughness_base: float = 0.8
@export_range(0.0, 1.0) var metallic_base: float = 0.0
@export var elevation_bias: float = 0.0
@export_range(0.0, 1.0) var slope_steepness: float = 0.5
@export_range(0.0, 1.0) var volcanic_activity: float = 0.0
@export_range(0.0, 1.0) var dust_intensity: float = 0.5
