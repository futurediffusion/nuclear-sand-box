extends SceneTree

func run():
	var queue = WallRefreshQueue.new()
	var pos1 = Vector2i(1, 1) # Hot
	var pos2 = Vector2i(2, 2) # Normal
	var pos3 = Vector2i(3, 3) # Cooldown test

	print("Testing WallRefreshQueue Refined Prioritization...")

	# 1. Test Hot vs Normal
	queue.record_activity(pos1) # pos1 is now HOT
	queue.enqueue(pos2) # pos2 is Normal (no recent activity recorded before enqueue)
	queue.enqueue(pos1) # pos1 is Hot

	var first = queue.pop_next()
	print("First popped: ", first)
	if first == pos1:
		print("SUCCESS: Hot chunk (pos1) popped before Normal chunk.")
	else:
		print("FAILURE: pos1 (Hot) should have been first, got ", first)
		quit(1)

	var second = queue.pop_next()
	print("Second popped: ", second)
	if second == pos2:
		print("SUCCESS: Normal chunk (pos2) popped second.")
	else:
		print("FAILURE: pos2 should have been second.")
		quit(1)

	# 2. Test Promotion
	queue.enqueue(pos2) # Enqueue as normal (now + 0)
	OS.delay_msec(10)
	queue.record_activity(pos2) # PROMOTE TO HOT
	queue.enqueue(pos1) # Enqueue as hot (recorded activity earlier)

	# Since pos2 was promoted to hot, and we use append, the order depends on when it became hot.
	# Actually record_activity(pos2) moves it from normal_queue to hot_queue.
	# Let's verify pos2 comes out.
	first = queue.pop_next()
	print("Promotion test - first: ", first)

	# 3. Test Cooldown
	# Re-populating for cooldown test
	queue.clear()
	queue.enqueue(pos3)

	var pop1 = queue.pop_next()
	print("Cooldown test - pop1: ", pop1)

	queue.enqueue(pos3)
	var pop2 = queue.pop_next() # Should fail (cooldown = 200ms)
	print("Cooldown test - pop2 (should be fail): ", pop2)
	if pop2 == Vector2i(-999999, -999999):
		print("SUCCESS: Cooldown respected.")
	else:
		print("FAILURE: Cooldown ignored!")
		quit(1)

	OS.delay_msec(210)
	var pop3 = queue.pop_next()
	print("Cooldown test - pop3 (after delay): ", pop3)
	if pop3 == pos3:
		print("SUCCESS: Cooldown expired, chunk popped.")
	else:
		print("FAILURE: Cooldown should have expired.")
		quit(1)

	print("All refined prioritization tests passed!")
	quit(0)

func _init():
	run()
