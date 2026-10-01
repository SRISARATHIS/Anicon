class_name SkillRegistry
extends Node
## Loads every `*_skill.gd` script in res://scripts/skills/.

const SKILLS_DIR := "res://scripts/skills/"

var skills: Array[Skill] = []


func load_all(app: Main) -> void:
	for file in ResourceLoader.list_directory(SKILLS_DIR):
		if not file.ends_with("_skill.gd"):
			continue
		var skill := (load(SKILLS_DIR + file) as Script).new() as Skill
		if skill == null:
			push_warning("%s does not extend Skill; skipping it." % file)
			continue
		skill.app = app
		skill.name = file.get_basename()
		add_child(skill)
		skills.append(skill)
	skills.sort_custom(func(a: Skill, b: Skill): return a.order < b.order)
