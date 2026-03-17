extends SceneTree

func run():
	var queue = WallRefreshQueue.new()
	var pos1 = Vector2i(1, 1)
	var pos2 = Vector2i(2, 2)
	var pos3 = Vector2i(3, 3)

	print("Testing WallRefreshQueue prioritization...")

	# Enqueue 3 chunks
	queue.enqueue(pos1)
	queue.enqueue(pos2)
	queue.enqueue(pos3)

	# Record activity for pos2 (most recent)
	OS.delay_msec(10)
	queue.record_activity(pos2)
	OS.delay_msec(10)
	queue.record_activity(pos3) # pos3 is now most recent

	var first = queue.pop_next()
	print("First popped: ", first)
	if first == pos3:
		print("SUCCESS: pos3 was most recent and popped first.")
	else:
		print("FAILURE: pos3 should have been first.")
		quit(1)

	# Record activity for pos1
	OS.delay_msec(10)
	queue.record_activity(pos1)

	var second = queue.pop_next()
	print("Second popped: ", second)
	if second == pos1:
		print("SUCCESS: pos1 was most recent and popped second.")
	else:
		print("FAILURE: pos1 should have been second.")
		quit(1)

	var third = queue.pop_next()
	print("Third popped: ", third)
	if third == pos2:
		print("SUCCESS: pos2 was last.")
	else:
		print("FAILURE: pos2 should have been third.")
		quit(1)

	print("All prioritization tests passed!")
	quit(0)

func _init():
	run()
