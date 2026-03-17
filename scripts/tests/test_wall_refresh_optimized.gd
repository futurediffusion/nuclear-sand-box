extends SceneTree

# Manual mock for OS.delay_msec since we want to control time if possible,
# but for now we'll use actual delays to be sure it works with real Time.get_ticks_msec()

func run():
	var queue = WallRefreshQueue.new()
	var pos1 = Vector2i(1, 1)
	var pos2 = Vector2i(2, 2)
	var pos3 = Vector2i(3, 3)

	print("--- Testing Optimized WallRefreshQueue ---")

	# 1. Test Priority (Hot vs Normal)
	print("Testing Priority (Hot vs Normal)...")
	queue.clear()
	queue.enqueue(pos1) # Normal
	queue.record_activity(pos2)
	queue.enqueue(pos2) # Hot

	var first = queue.pop_next()
	if first == pos2:
		print("  SUCCESS: Hot chunk pos2 popped before normal chunk pos1.")
	else:
		print("  FAILURE: Hot chunk should have priority. Popped: ", first)
		quit(1)

	# 2. Test Promotion
	print("Testing Promotion...")
	queue.clear()
	queue.enqueue(pos1) # Normal
	queue.record_activity(pos1) # Promote to Hot
	queue.enqueue(pos2) # Normal

	first = queue.pop_next()
	if first == pos1:
		print("  SUCCESS: Promoted chunk pos1 popped before normal chunk pos2.")
	else:
		print("  FAILURE: Promoted chunk should have priority. Popped: ", first)
		quit(1)

	# 3. Test Cooldown
	print("Testing Cooldown (200ms)...")
	queue.clear()
	queue.record_activity(pos1)
	queue.enqueue(pos1)

	first = queue.pop_next() # Should work
	if first != pos1:
		print("  FAILURE: Could not pop pos1.")
		quit(1)

	# Enqueue again immediately
	queue.enqueue(pos1)
	var second = queue.pop_next()
	if second == Vector2i(-999999, -999999):
		print("  SUCCESS: pos1 is in cooldown and cannot be popped yet.")
	else:
		print("  FAILURE: pos1 should be in cooldown. Popped: ", second)
		quit(1)

	print("  Waiting 250ms for cooldown...")
	OS.delay_msec(250)

	second = queue.pop_next()
	if second == pos1:
		print("  SUCCESS: pos1 popped after cooldown.")
	else:
		print("  FAILURE: pos1 should be available after cooldown. Popped: ", second)
		quit(1)

	# 4. Test Purge
	print("Testing Purge...")
	queue.clear()
	queue.enqueue(pos1)
	queue.purge_chunk(pos1)
	if not queue.has_pending():
		print("  SUCCESS: Chunk purged correctly.")
	else:
		print("  FAILURE: Queue should be empty after purge.")
		quit(1)

	# 5. Test Intra-Hot Priority (Most Recent First)
	print("Testing Intra-Hot Priority (Most Recent First)...")
	queue.clear()
	# pos1 activity, then pos2 activity
	queue.record_activity(pos1)
	queue.enqueue(pos1)
	OS.delay_msec(50)
	queue.record_activity(pos2)
	queue.enqueue(pos2)

	# pos2 should be first because it's more recent
	first = queue.pop_next()
	if first == pos2:
		print("  SUCCESS: Most recent hot chunk pos2 popped first.")
	else:
		print("  FAILURE: Most recent hot chunk should be first. Popped: ", first)
		quit(1)

	# 6. Test Activity Refreshing Priority
	print("Testing Activity Refreshing Priority...")
	queue.clear()
	queue.record_activity(pos1)
	queue.enqueue(pos1)
	OS.delay_msec(50)
	queue.record_activity(pos2)
	queue.enqueue(pos2)
	OS.delay_msec(50)
	queue.record_activity(pos1) # pos1 becomes most recent again

	first = queue.pop_next()
	if first == pos1:
		print("  SUCCESS: Refreshed hot chunk pos1 popped first.")
	else:
		print("  FAILURE: Refreshed hot chunk should be first. Popped: ", first)
		quit(1)

	# 7. Test Demotion (Hot -> Normal)
	print("Testing Demotion (Hot -> Normal)...")
	queue.clear()
	queue.record_activity(pos1)
	queue.enqueue(pos1) # Hot
	queue.enqueue(pos2) # Normal

	print("  Waiting 2100ms for hot threshold (2000ms)...")
	OS.delay_msec(2100)

	# pos1 should have been demoted to Normal.
	# Since pos2 was already in Normal and didn't have activity,
	# the order in Normal depends on when they entered.
	# pos2 was first in Normal, then pos1 was demoted and appended.
	first = queue.pop_next()
	if first == pos2:
		print("  SUCCESS: Hot chunk pos1 demoted, normal chunk pos2 popped first.")
	else:
		print("  FAILURE: pos1 should have been demoted and placed after pos2. Popped: ", first)
		quit(1)

	print("All optimized WallRefreshQueue tests passed!")
	quit(0)

func _init():
	run()
