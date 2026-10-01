class_name Skill
extends Node
## Base class for the pet's skills.
## Any `*_skill.gd` file in this folder that extends Skill is loaded automatically
## and shows up in the right-click menu. Skills are Nodes, so they can use _process.

## The running app (pet, bubble, chat, ...). Set before the skill enters the tree.
var app: Main
## Menu label. A skill with several actions gets a submenu with this name.
var title := "Skill"
## Menu position; lower comes first.
var order := 100


## Menu entries as [{"id": String, "title": String}, ...].
func get_actions() -> Array:
	return [{"id": "run", "title": title}]


## Called when an action is picked from the menu. May await.
func run_action(_id: String) -> void:
	pass
