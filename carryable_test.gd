extends SceneTree

func _init():
    print("Test CarryableComponent")

    var root = Node2D.new()
    var carrier = Node2D.new()
    carrier.name = "carrier"
    var item = CollisionObject2D.new()
    item.name = "item"
    var carry_comp = CarryableComponent.new()
    item.add_child(carry_comp)

    root.add_child(carrier)
    root.add_child(item)

    carry_comp._ready()

    print("Initial parent: ", item.get_parent().name)
    assert(carry_comp.can_pickup())

    carry_comp.pickup(carrier)
    print("Carried parent: ", item.get_parent().name)
    assert(not carry_comp.can_pickup())
    assert(item.get_parent() == carrier)

    carry_comp.drop()
    print("Dropped parent: ", item.get_parent().name)
    assert(carry_comp.can_pickup())
    assert(item.get_parent() == root)

    print("ALL TESTS PASSED")
    quit()
