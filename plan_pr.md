### Plan to address PR Comments

**Goal:** Integrate `ItemDrop` with the `CarryComponent` so that when the player holds the secondary action (right-click) and approaches an item drop, the item is added to the carry stack instead of the inventory. If the player is not holding right-click, or if the carry stack is full/fails, it should fall back to the normal inventory pickup.

**Steps:**
1. **Add `CarryableComponent` to `ItemDrop`:**
   - Modify `scenes/items/item_drop.tscn` to include a `CarryableComponent` node.
   - Wait, `CarryableComponent` works by reparenting. Does `ItemDrop` support being reparented without breaking its internal state? Yes, it's just a RigidBody2D or Area2D. Let's check `scripts/items/item_drop.gd`.

2. **Modify `player.gd`:**
   - Add public methods to check carry intent:
     ```gdscript
     func wants_carry_pickup() -> bool:
         return Input.is_action_pressed("secondary_action") and carry_component != null

     func try_carry_pickup(node: Node2D) -> bool:
         if carry_component == null:
             return false
         return carry_component.try_pickup(node)
     ```
   - *Wait, the prompt says "is_secondary_action_pressed()", let's check player secondary action state.* The player has `secondary_action_state`.
     ```gdscript
     func wants_carry_pickup() -> bool:
         # Either scanning for carry or already carrying
         return secondary_action_state == SecondaryActionState.CARRY_SCAN or secondary_action_state == SecondaryActionState.CARRYING
     ```

3. **Modify `ItemDrop` (`scripts/items/item_drop.gd`):**
   - In `_try_pickup()`, check if the player wants to carry:
     ```gdscript
     if _player.has_method("wants_carry_pickup") and _player.wants_carry_pickup():
         if _player.has_method("try_carry_pickup") and _player.try_carry_pickup(self):
             # Successfully picked up by carry.
             # Disable magnet/legacy pickup
             _picked_up = true
             return
     ```
   - Make sure `_picked_up` prevents further magnet logic.
   - Also, `CarryableComponent` might disable collisions, which is good.

Let's inspect `scripts/items/item_drop.gd` and `scenes/items/item_drop.tscn` first.
