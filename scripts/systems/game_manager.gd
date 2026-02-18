extends Node
class_name GameManager

signal player_died
signal player_healed(amount: int)
signal zone_entered(zone_name: String)

var current_wave: int = 0
var gold: int = 0
