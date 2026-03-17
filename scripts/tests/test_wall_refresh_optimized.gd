extends SceneTree

# Manual mock for OS.delay_msec since we want to control time if possible,
# but for now we'll use actual delays to be sure it works with real Time.get_ticks_msec()

func run():
	var queue = WallRefreshQueue.new()
	var pos1 = Vector2i(1, 1)
	var pos2 = Vector2i(2, 2)
	var pos3 = Vector2i(3, 3)

	print("--- Testing Optimized WallRefreshQueue Phase C ---")

	# 1. Test Priority (Hot vs Normal)
	print("Testing Priority (Hot vs Normal)...")
	queue.clear()
	queue.enqueue(pos1) # Normal
	queue.record_activity(pos2)
	queue.enqueue(pos2) # Hot

	var res = queue.try_pop_next()
	if res.ok and res.chunk_pos == pos2:
		print("  SUCCESS: Hot chunk pos2 popped before normal chunk pos1.")
	else:
		print("  FAILURE: Hot chunk should have priority. Result: ", res)
		quit(1)

	# 2. Test Promotion
	print("Testing Promotion...")
	queue.clear()
	queue.enqueue(pos1) # Normal
	queue.record_activity(pos1) # Promote to Hot
	queue.enqueue(pos2) # Normal

	res = queue.try_pop_next()
	if res.ok and res.chunk_pos == pos1:
		print("  SUCCESS: Promoted chunk pos1 popped before normal chunk pos2.")
	else:
		print("  FAILURE: Promoted chunk should have priority. Result: ", res)
		quit(1)

	# 3. Test Cooldown and NO SPIN
	print("Testing Cooldown and NO SPIN...")
	queue.clear()
	queue.record_activity(pos1)
	queue.enqueue(pos1)

	res = queue.try_pop_next() # Should work
	if not res.ok or res.chunk_pos != pos1:
		print("  FAILURE: Could not pop pos1.")
		quit(1)
	queue.confirm_rebuild(pos1, res.revision)

	# Enqueue again immediately
	queue.enqueue(pos1)
	res = queue.try_pop_next()
	if res.ok == false:
		print("  SUCCESS: pos1 is in cooldown, try_pop_next returned ok=false (NO SPIN).")
		if res.next_ready_in_ms > 0:
			print("  SUCCESS: Reported wait time: ", res.next_ready_in_ms, "ms")
		else:
			print("  FAILURE: Should report wait time > 0. Got: ", res.next_ready_in_ms)
			quit(1)
	else:
		print("  FAILURE: pos1 should be in cooldown. Result: ", res)
		quit(1)

	print("  Waiting 250ms for cooldown...")
	OS.delay_msec(250)

	res = queue.try_pop_next()
	if res.ok and res.chunk_pos == pos1:
		print("  SUCCESS: pos1 popped after cooldown.")
	else:
		print("  FAILURE: pos1 should be available after cooldown. Result: ", res)
		quit(1)

	# 4. Test Merge Anti-Spam (Revision System)
	print("Testing Merge Anti-Spam (Revision System)...")
	queue.clear()
	queue.enqueue(pos1) # Revision 1
	queue.enqueue(pos1) # Revision 2
	queue.enqueue(pos1) # Revision 3

	res = queue.try_pop_next()
	if res.ok and res.chunk_pos == pos1 and res.revision == 3:
		print("  SUCCESS: 3 enqueues merged into 1 pop with revision 3.")
	else:
		print("  FAILURE: Expected revision 3 for pos1. Result: ", res)
		quit(1)

	# More changes while in cooldown
	queue.confirm_rebuild(pos1, res.revision)
	queue.enqueue(pos1) # Revision 4
	queue.enqueue(pos1) # Revision 5

	res = queue.try_pop_next()
	if res.ok == false:
		print("  SUCCESS: In cooldown after revision 3 rebuild.")
	else:
		print("  FAILURE: Should be in cooldown.")
		quit(1)

	print("  Waiting 250ms...")
	OS.delay_msec(250)

	res = queue.try_pop_next()
	if res.ok and res.chunk_pos == pos1 and res.revision == 5:
		print("  SUCCESS: Popped revision 5 after cooldown.")
	else:
		print("  FAILURE: Expected revision 5. Result: ", res)
		quit(1)

	# 5. Test Purge
	print("Testing Purge...")
	queue.clear()
	queue.enqueue(pos1)
	queue.purge_chunk(pos1)
	if not queue.has_pending():
		print("  SUCCESS: Chunk purged correctly from pending.")
		res = queue.try_pop_next()
		if not res.ok:
			print("  SUCCESS: try_pop_next returned ok=false after purge.")
		else:
			print("  FAILURE: try_pop_next should be false after purge.")
			quit(1)
	else:
		print("  FAILURE: Queue should be empty after purge.")
		quit(1)

	# 6. Test Intra-Hot Priority (Most Recent First)
	print("Testing Intra-Hot Priority (Most Recent First)...")
	queue.clear()
	# pos1 activity, then pos2 activity
	queue.record_activity(pos1)
	queue.enqueue(pos1)
	OS.delay_msec(50)
	queue.record_activity(pos2)
	queue.enqueue(pos2)

	# pos2 should be first because it's more recent
	res = queue.try_pop_next()
	if res.ok and res.chunk_pos == pos2:
		print("  SUCCESS: Most recent hot chunk pos2 popped first.")
	else:
		print("  FAILURE: Most recent hot chunk should be first. Result: ", res)
		quit(1)

	# 7. Test Activity Refreshing Priority
	print("Testing Activity Refreshing Priority...")
	queue.clear()
	queue.record_activity(pos1)
	queue.enqueue(pos1)
	OS.delay_msec(50)
	queue.record_activity(pos2)
	queue.enqueue(pos2)
	OS.delay_msec(50)
	queue.record_activity(pos1) # pos1 becomes most recent again

	res = queue.try_pop_next()
	if res.ok and res.chunk_pos == pos1:
		print("  SUCCESS: Refreshed hot chunk pos1 popped first.")
	else:
		print("  FAILURE: Refreshed hot chunk should be first. Result: ", res)
		quit(1)

	# 8. Test Demotion (Hot -> Normal)
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
	res = queue.try_pop_next()
	if res.ok and res.chunk_pos == pos2:
		print("  SUCCESS: Hot chunk pos1 demoted, normal chunk pos2 popped first.")
	else:
		print("  FAILURE: pos1 should have been demoted and placed after pos2. Result: ", res)
		quit(1)

	# 9. Test Full State Reset after Purge
	print("Testing Full State Reset after Purge...")
	queue.clear()
	queue.enqueue(pos1) # Revision 1
	res = queue.try_pop_next()
	queue.confirm_rebuild(pos1, res.revision)

	# Trigger cooldown and higher revision
	queue.enqueue(pos1) # Revision 2
	res = queue.try_pop_next()
	if res.ok == false:
		print("  SUCCESS: pos1 in cooldown as expected.")
	else:
		print("  FAILURE: pos1 should be in cooldown.")
		quit(1)

	# Purge should clear everything
	queue.purge_chunk(pos1)

	if queue.has_pending():
		print("  FAILURE: Should not have pending after purge.")
		quit(1)

	res = queue.try_pop_next()
	if not res.ok:
		print("  SUCCESS: try_pop_next returned ok=false after purge.")
	else:
		print("  FAILURE: try_pop_next should be false after purge.")
		quit(1)

	# Enqueue again: should have NO cooldown and revision should START AT 1
	queue.enqueue(pos1)
	res = queue.try_pop_next()

	if res.ok and res.chunk_pos == pos1:
		print("  SUCCESS: No cooldown after purge.")
		if res.revision == 1:
			print("  SUCCESS: Revision reset to 1 after purge.")
		else:
			print("  FAILURE: Revision should be 1, got: ", res.revision)
			quit(1)
	else:
		print("  FAILURE: Should pop immediately after purge (cooldown reset). Result: ", res)
		quit(1)

	print("All Phase C WallRefreshQueue tests passed!")
	quit(0)

func _init():
	run()
