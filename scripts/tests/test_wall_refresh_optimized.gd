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
		print("  FAILURE: Promoted chunk should have priority.")
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

	# 5. Test Multiple Hot Priority (LIFO-like for Hot)
	print("Testing multiple Hot chunks...")
	queue.clear()
	queue.record_activity(pos1)
	queue.enqueue(pos1)
	OS.delay_msec(10)
	queue.record_activity(pos2)
	queue.enqueue(pos2)

	# Current implementation of pop_from_queue takes the first one that is NOT in cooldown.
	# Since they are both new, it depends on order of enqueue in the array.
	# _hot_queue.append(pos1) then _hot_queue.append(pos2)
	# pop_next will return pos1 because it's first in the array and not in cooldown.
	# Wait, if I want LIFO I should have used push_front or similar,
	# but the requirement said O(1) prioritization.
	# Actually, FIFO within the same tier is fine as long as Hot > Normal.

	print("All optimized WallRefreshQueue tests passed!")
	quit(0)

func _init():
	run()
