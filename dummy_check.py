with open('scripts/items/item_drop.gd', 'r') as f:
    text = f.read()

assert 'monitoring = false' in text
print("Valid checks")
