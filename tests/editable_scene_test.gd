## Run with Godot 4.7: --headless --path PROJECT -s tests/editable_scene_test.gd
extends SceneTree

const FILES := [
    "res://main.tscn",
    "res://scenes/levels/PlanetAEnvironment.tscn",
    "res://scenes/levels/PlanetBEnvironment.tscn",
    "res://scenes/levels/WorkshopEnvironment.tscn",
    "res://scenes/levels/OrbitShipInterior.tscn",
    "res://scenes/levels/FlightEnvironment.tscn",
    "res://scenes/levels/FrontierArena.tscn",
    "res://scenes/prefabs/Kestrel.tscn",
    "res://scenes/prefabs/FlagMarker.tscn",
]

func _initialize() -> void:
    call_deferred("_check_scenes")

func _check_scenes() -> void:
    var failed := 0
    for path in FILES:
        var scene: PackedScene = load(path) as PackedScene
        if scene == null:
            push_error("FAILED to load scene: " + path)
            failed += 1
            continue
        var root: Node = scene.instantiate()
        if root == null:
            push_error("FAILED to instantiate scene: " + path)
            failed += 1
            continue
        if path.ends_with("PlanetAEnvironment.tscn") and not root.has_node("CollisionFootprints"):
            failed += 1
        if path.ends_with("WorkshopEnvironment.tscn") and not root.has_node("WorkshopBuilding/RobotArmPivot"):
            failed += 1
        if path.ends_with("OrbitShipInterior.tscn") and not root.has_node("Stations/cockpit"):
            failed += 1
        if path.ends_with("Kestrel.tscn") and not root.has_node("keel"):
            failed += 1
        root.free()
        print("PASS: ", path)
    print("Editable scene tests: %d failed" % failed)
    quit(1 if failed > 0 else 0)
