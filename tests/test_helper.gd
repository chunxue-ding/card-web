extends RefCounted
## headless 测试小工具：断言 + 汇总退出码（本项目不引入测试框架，见 spec §5）

var failures := 0
var passed := 0


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS %s" % label)
	else:
		failures += 1
		printerr("FAIL %s" % label)


func finish(tree: SceneTree) -> void:
	print("== %d passed, %d failed ==" % [passed, failures])
	tree.quit(1 if failures > 0 else 0)
