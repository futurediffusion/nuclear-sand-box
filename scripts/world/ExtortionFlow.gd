class_name ExtortionFlow
extends Node

## Orquestación completa del ciclo de extorsión:
## abort logic, phase machine, retaliation, movement, payment resolution.
## Sin dependencias de UI — se comunica con ExtortionUIAdapter via callables.

const BanditTuningScript := preload("res://scripts/world/BanditTuning.gd")

## Frases de acercamiento — se muestran cuando el grupo ya está cerca del jugador.
const TAUNT_PHRASES: Array[String] = [
	"Mira quién cree que puede pasar por aquí.",
	"Paga y quizá sigas respirando.",
	"No pongas esa cara. Esto es solo negocios.",
	"Qué conveniente encontrarte aquí.",
	"Para. Tenemos que hablar de tu cuenta pendiente.",
	"No te muevas. Esto será rápido.",
	"Sabíamos que aparecerías. Siempre apareces.",
	"Hoy tienes cara de que me vas a pagar.",
	"Elige bien lo que dices ahora.",
	"Cuánto tiempo. Aunque no tanto como para olvidar que nos debes.",
]

## Frases cuando el jugador no puede pagar.
const POVERTY_TAUNT_PHRASES: Array[String] = [
	"¿Esto es todo lo que tienes? ¡Qué miseria!",
	"Tan pobre que ni para el peaje. Da asco.",
	"Acuérdate de esta paliza. La próxima te va a costar el doble... si es que sobrevives.",
	"Sin dinero. Qué decepción. Vamos a tener que cobrarnos de otra forma.",
	"¿De verdad? ¿Ni un perro? Entonces vas a aprender lo que cuesta no tener.",
	"No hay plata. Vale. Hay otras monedas.",
]

## Frases cuando el jugador paga — se muestran mientras se retiran.
const PAY_ACK_PHRASES: Array[String] = [
	"Buen movimiento.",
	"Siempre supe que eras razonable.",
	"Nos vemos pronto. Ya sabes cómo va esto.",
	"Smart. Muy smart.",
	"Te va a durar poco eso que te queda. Volveremos.",
	"Hasta la próxima. Que será pronto.",
	"Gracias por los negocios.",
]

## Reacciones al rechazo (opción 2) — antes del warning strike.
const REFUSE_REACTION_PHRASES: Array[String] = [
	"Error que vas a lamentar.",
	"Bien. Que sea la última vez que dices no.",
	"Decidiste el camino difícil. Respeto eso. Pero te va a doler.",
	"No. Mira lo que pasa cuando dices no.",
	"Como quieras. Pero esto no queda así.",
	"Qué valiente. Veremos cuánto te dura.",
	"Bonita decisión. Equivocada, pero bonita.",
]

## Reacciones al insulto (opción 3) — antes del aggro completo.
const INSULT_REACTION_PHRASES: Array[String] = [
	"¿Eso acabas de decir? Último error.",
	"Genial. Ahora vas a aprender modales.",
	"Que te guste el dolor. Te va a hacer falta.",
	"Palabras muy grandes para alguien tan solo.",
	"Ya no hay negociación. Solo consecuencias.",
	"No sé qué te pasa por la cabeza. Pero sí sé lo que te va a pasar ahora.",
]

## Frases cuando alguien del grupo vio caer al líder.
const LEADER_KILLED_PHRASES: Array[String] = [
	"¡Mató al jefe! ¡Recuerda su cara!",
	"Esto no se olvida. No se olvida nunca.",
	"¡Al jefe! ¡Le mató al jefe! ¡Vais a pagar por esto!",
	"Te vamos a encontrar. No importa dónde vayas.",
	"Eso fue un error muy grande.",
]

## Frases cuando el jugador huyó durante la extorsión.
const PLAYER_RAN_PHRASES: Array[String] = [
	"La próxima no se escapa.",
	"Corre. Disfrútalo. No va a durar.",
	"Muy listo. Por ahora.",
	"La deuda sigue ahí. Nosotros también.",
	"Vuelve cuando tengas agallas. Y dinero.",
]

var _npc_simulator:           NpcSimulator              = null
var _player:                  Node2D                    = null
var _bubble_manager:          WorldSpeechBubbleManager  = null
var _get_behavior_for_enemy:  Callable                  = Callable()
var _show_choice_ui:          Callable                  = Callable()  # (gid: String, pay_amount: int, is_minimum: bool) -> void
var _close_choice_ui:         Callable                  = Callable()  # (gid: String) -> void

var _active_extortions: Dictionary = {}  # gid -> ExtortionJob  (runtime-only)
var _post_pay_groups:   Dictionary = {}  # gid -> Array[String] de ids suprimidos
# Runtime-only deferred jobs owned by this flow.
# Criterio actual: mantenerlos locales mientras sean callbacks efímeros,
# cancelables por destrucción del flow/chunk y usados solo por ExtortionFlow.
# Extraer a un scheduler world-owned recién cuando:
#   1) haya 2+ flows de dominio usando el mismo patrón,
#   2) necesitemos introspección/cancelación compartida entre sistemas, o
#   3) el job deba sobrevivir reload/rebuild del mundo.
# Hoy no hace falta: un servicio genérico agregaría más abstracción que claridad.
var _scheduled_callbacks: Array[Dictionary] = []


func setup(ctx: Dictionary) -> void:
	_npc_simulator          = ctx.get("npc_simulator")
	_player                 = ctx.get("player")
	_bubble_manager         = ctx.get("speech_bubble_manager")
	_get_behavior_for_enemy = ctx.get("get_behavior_for_enemy", Callable())
	_show_choice_ui         = ctx.get("show_choice_ui",         Callable())
	_close_choice_ui        = ctx.get("close_choice_ui",        Callable())


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------

func process_flow(delta: float) -> void:
	_tick_scheduled_callbacks(delta)
	_abort_invalid_jobs()
	_check_retaliation()
	_consume_extortion_queue()


func apply_movement(friction_compensation: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var player_pos: Vector2 = _player.global_position
	for gid in _active_extortions:
		var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
		if job == null or job.is_finished():
			continue

		if job.is_aggressive():
			var dc := _player.get_node_or_null("DownedComponent")
			if dc != null and (dc as DownedComponent).is_downed:
				job.mark_resolved()
				for aid: String in job.assigned_ids:
					var behavior: BanditWorldBehavior = _behavior_for_enemy(aid)
					if behavior != null:
						behavior.force_return_home()
				Debug.log("extortion", "[EXTORT] aggro resolved (player downed) group=%s" % gid)
			continue

		if job.needs_warning_strike():
			_tick_warning_strike(job, player_pos, friction_compensation)
			continue

		if job.is_collecting():
			continue

		for eid in job.assigned_ids:
			var enode := _npc_simulator.get_enemy_node(eid)
			if enode == null:
				continue
			_set_enemy_scripted_control(enode, true)
			_drive_enemy_toward_point(enode, player_pos,
				BanditTuningScript.extort_group_approach_speed(job.group_id) + friction_compensation)


## Llamado por ExtortionUIAdapter.choice_resolved (signal). option 0 = descarte externo → warn.
func on_choice_resolved(option: int, gid: String) -> void:
	if not _active_extortions.has(gid):
		return
	var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
	if job == null:
		return
	var faction: String = _get_job_faction_id(job)
	match option:
		0:
			_resolve_extortion_warn(job)
		1:
			var inv := _player.get_node_or_null("InventoryComponent") as InventoryComponent
			var pay_amount: int = BanditTuningScript.extort_pay_amount(inv.gold if inv != null else 0, gid)
			if inv != null and inv.gold >= pay_amount:
				inv.spend_gold(pay_amount)
				FactionHostilityManager.add_hostility(faction, 0.0, "extortion_paid",
					{"group_id": gid, "amount": pay_amount})
				Debug.log("extortion", "[EXTORT] paid %d gold group=%s" % [pay_amount, gid])
				_show_reaction_bubble(job, PAY_ACK_PHRASES)
				BanditGroupMemory.push_social_cooldown(gid, 10.0)
				_resolve_extortion_idle(job)
			else:
				# El jugador quiso pagar pero no tiene oro: misma gravedad que negarse
				FactionHostilityManager.add_hostility(faction, 0.0, "extortion_refused",
					{"group_id": gid, "reason": "cant_pay"})
				Debug.log("extortion", "[EXTORT] can't pay, forced refuse group=%s" % gid)
				_show_poverty_taunts(job)
				BanditGroupMemory.push_social_cooldown(gid, 6.0)
				_resolve_extortion_warn(job)
		2:
			FactionHostilityManager.add_hostility(faction, 0.0, "extortion_refused",
				{"group_id": gid})
			_show_reaction_bubble(job, REFUSE_REACTION_PHRASES)
			BanditGroupMemory.push_social_cooldown(gid, 6.0)
			_resolve_extortion_warn(job)
		3:
			FactionHostilityManager.add_hostility(faction, 0.0, "extortion_insulted",
				{"group_id": gid})
			_show_reaction_bubble(job, INSULT_REACTION_PHRASES)
			BanditGroupMemory.push_social_cooldown(gid, 12.0)
			_resolve_extortion_aggro(job)



func _tick_scheduled_callbacks(delta: float) -> void:
	if _scheduled_callbacks.is_empty():
		return
	var i: int = 0
	while i < _scheduled_callbacks.size():
		var entry: Dictionary = _scheduled_callbacks[i]
		entry["remaining"] = float(entry.get("remaining", 0.0)) - delta
		if float(entry.get("remaining", 0.0)) > 0.0:
			_scheduled_callbacks[i] = entry
			i += 1
			continue
		var callback: Callable = entry.get("callback", Callable())
		_scheduled_callbacks.remove_at(i)
		if callback.is_valid():
			callback.call()


func _schedule_callback(delay: float, callback: Callable) -> void:
	if not callback.is_valid():
		return
	_scheduled_callbacks.append({
		"remaining": maxf(0.0, delay),
		"callback": callback,
	})


# ---------------------------------------------------------------------------
# Abort
# ---------------------------------------------------------------------------

func _abort_invalid_jobs() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var player_pos: Vector2 = _player.global_position
	for gid in _active_extortions.keys():
		var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
		if job == null or job.is_finished():
			continue
		var reason: String = _get_abort_reason(job.group_id, job, player_pos)
		if reason != "":
			_abort_job(job.group_id, job, reason)


func _get_abort_reason(gid: String, job: ExtortionJob, player_pos: Vector2) -> String:
	var group_data: Dictionary = BanditGroupMemory.get_group(gid)
	if group_data.is_empty():
		return "group_missing"

	var leader_id: String = String(group_data.get("leader_id", ""))
	if leader_id == "":
		return "leader_dead"
	var leader_node := _npc_simulator.get_enemy_node(leader_id)
	if leader_node == null or not is_instance_valid(leader_node):
		return "leader_dead"

	var current_intent: String = String(group_data.get("current_group_intent", "idle"))
	if _intent_strength(current_intent) > _intent_strength("extorting"):
		return "stronger_group_intent:%s" % current_intent

	var member_ids: Array = group_data.get("member_ids", [])
	for aid: String in job.assigned_ids:
		if not member_ids.has(aid):
			return "group_composition_broken"
		var anode := _npc_simulator.get_enemy_node(aid)
		if anode == null or not is_instance_valid(anode):
			return "group_composition_broken"

	if job.assigned_ids.size() <= 0:
		return "group_composition_broken"

	if (leader_node as Node2D).global_position.distance_squared_to(player_pos) \
			> BanditTuningScript.extort_abort_distance_sq(gid):
		return "player_too_far"

	if job.taunt_speaker_id != "":
		var speaker := _npc_simulator.get_enemy_node(job.taunt_speaker_id)
		if speaker == null or not is_instance_valid(speaker):
			return "speaker_missing"

	return ""


func _intent_strength(intent: String) -> int:
	match intent:
		"idle":      return 0
		"alerted":   return 1
		"extorting": return 2
		"hunting":   return 3
		_:           return 0


func _abort_job(gid: String, job: ExtortionJob, reason: String) -> void:
	if job == null or job.is_finished():
		return
	job.mark_aborted()
	_release_job_ai_control(job)
	if _close_choice_ui.is_valid():
		_close_choice_ui.call(gid)
	var group_data: Dictionary = BanditGroupMemory.get_group(gid)
	if String(group_data.get("current_group_intent", "idle")) == "extorting":
		BanditGroupMemory.update_intent(gid, "idle")
	# Feedback visual según el motivo del abort
	_show_abort_feedback(job, reason, group_data)
	Debug.log("extortion", "[EXTORT ABORT] group=%s reason=%s" % [gid, reason])


# ---------------------------------------------------------------------------
# Queue consumption / taunt / collect
# ---------------------------------------------------------------------------

func _consume_extortion_queue() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Limpiar jobs terminados
	var done: Array = []
	for gid in _active_extortions:
		var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
		if job != null and job.is_finished():
			done.append(gid)
	for gid in done:
		_active_extortions.erase(gid)
		Debug.log("extortion", "[EXTORT FLOW] job cleaned group=%s" % gid)

	# Fase taunt
	if _bubble_manager != null:
		var player_pos: Vector2 = _player.global_position
		for gid in _active_extortions:
			var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
			if job == null or job.has_taunted():
				continue
			for eid in job.assigned_ids:
				var enode := _npc_simulator.get_enemy_node(eid)
				if enode == null or not is_instance_valid(enode):
					continue
				if (enode as Node2D).global_position.distance_squared_to(player_pos) \
						> BanditTuningScript.extort_taunt_range_sq(job.group_id):
					continue
				job.mark_taunted(eid)
				var phrase: String = TAUNT_PHRASES[randi() % TAUNT_PHRASES.size()]
				_bubble_manager.show_actor_bubble(enode as Node2D, phrase,
					BanditTuningScript.extort_taunt_bubble_duration(job.group_id))
				Debug.log("extortion", "[EXTORT] taunt group=%s speaker=%s" % [gid, eid])
				break

	# Fase collect
	if _bubble_manager != null and _show_choice_ui.is_valid():
		var player_pos_collect: Vector2 = _player.global_position
		for gid in _active_extortions:
			var job: ExtortionJob = _active_extortions[gid] as ExtortionJob
			if job == null or job.is_finished() or job.is_collecting() or not job.can_open_choice():
				continue
			for eid in job.assigned_ids:
				var enode := _npc_simulator.get_enemy_node(eid)
				if enode == null or not is_instance_valid(enode):
					continue
				if (enode as Node2D).global_position.distance_squared_to(player_pos_collect) \
						> BanditTuningScript.extort_collect_range_sq(job.group_id):
					continue
				job.mark_waiting_choice()
				var inv_pre := _player.get_node_or_null("InventoryComponent") as InventoryComponent
				var player_gold_pre: int = inv_pre.gold if inv_pre != null else 0
				var preview_amount: int = BanditTuningScript.extort_pay_amount(player_gold_pre, gid)
				var is_minimum: bool    = int(player_gold_pre * 0.2) < 1
				_show_choice_ui.call(gid, preview_amount, is_minimum, job.extort_reason)
				Debug.log("extortion", "[EXTORT] collection triggered group=%s speaker=%s" % [gid, eid])
				break

	if not _active_extortions.is_empty():
		return

	# Arrancar job nuevo desde la cola
	for gid in BanditGroupMemory.get_all_group_ids():
		if _active_extortions.has(gid):
			continue
		var group_data: Dictionary = BanditGroupMemory.get_group(gid)
		if String(group_data.get("current_group_intent", "")) != "extorting":
			continue
		var intents: Array = ExtortionQueue.consume_for_group(gid)
		if intents.is_empty():
			continue
		var leader_id: String = String(group_data.get("leader_id", ""))
		if leader_id == "":
			continue
		var leader_node := _npc_simulator.get_enemy_node(leader_id)
		var leader_pos: Vector2 = leader_node.global_position if leader_node != null else Vector2.ZERO
		var guards: Array = []
		for mid_v in group_data.get("member_ids", []):
			var mid: String = String(mid_v)
			if mid == leader_id:
				continue
			var mnode := _npc_simulator.get_enemy_node(mid)
			if mnode == null:
				continue
			guards.append({"id": mid, "dist_sq": mnode.global_position.distance_squared_to(leader_pos)})
		guards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist_sq"] < b["dist_sq"])
		var assigned: Array[String] = [leader_id]
		for i in mini(2, guards.size()):
			assigned.append(guards[i]["id"])
		var new_job: ExtortionJob = ExtortionJob.new(gid, leader_id, assigned)
		# Propagar la causa dominante desde el intent al job (para la UI)
		new_job.extort_reason = String(intents[0].get("extort_reason", "territorial"))
		_active_extortions[gid] = new_job
		for aid in assigned:
			var anode := _npc_simulator.get_enemy_node(aid)
			_set_enemy_scripted_control(anode, true)
		Debug.log("extortion", "[EXTORT FLOW] job started group=%s leader=%s assigned=%d reason=%s" % [
			gid, leader_id, assigned.size(), new_job.extort_reason])
		break


# ---------------------------------------------------------------------------
# Retaliation
# ---------------------------------------------------------------------------

func _check_retaliation() -> void:
	for gid: String in _active_extortions.keys():
		var job: ExtortionJob = _active_extortions.get(gid) as ExtortionJob
		if job == null or job.is_finished() or job.is_aggressive():
			continue
		for aid: String in job.assigned_ids:
			var anode := _npc_simulator.get_enemy_node(aid)
			if anode == null or not is_instance_valid(anode):
				continue
			if "hurt_t" in anode and float(anode.get("hurt_t")) > 0.0:
				Debug.log("extortion", "[EXTORT] retaliation — bandit hit during job group=%s" % gid)
				_resolve_extortion_aggro(job)
				break

	for gid: String in _post_pay_groups.keys():
		var ids: Array = _post_pay_groups[gid] as Array
		var was_hit: bool = false
		for aid in ids:
			var anode := _npc_simulator.get_enemy_node(aid)
			if anode != null and is_instance_valid(anode) \
					and "hurt_t" in anode and float(anode.get("hurt_t")) > 0.0:
				was_hit = true
				break
		if was_hit:
			_post_pay_groups.erase(gid)
			for aid in ids:
				var anode := _npc_simulator.get_enemy_node(aid)
				_set_enemy_scripted_control(anode, false)
			Debug.log("extortion", "[EXTORT] post-pay retaliation — group=%s ai released early" % gid)


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------

func _resolve_extortion_idle(job: ExtortionJob) -> void:
	job.mark_resolved()
	BanditGroupMemory.update_intent(job.group_id, "idle")
	for aid: String in job.assigned_ids:
		var behavior: BanditWorldBehavior = _behavior_for_enemy(aid)
		if behavior != null:
			behavior.force_return_home()
	var ids: Array[String] = job.assigned_ids.duplicate()
	var gid: String        = job.group_id
	_post_pay_groups[gid]  = ids
	var reenable_delay: float = BanditTuningScript.extort_ai_reenable_delay(gid)
	_schedule_callback(reenable_delay, func() -> void:
		_post_pay_groups.erase(gid)
		for aid: String in ids:
			var anode := _npc_simulator.get_enemy_node(aid)
			_set_enemy_scripted_control(anode, false)
	)
	Debug.log("extortion", "[EXTORT] resolved idle — ai re-enable in %.1f s" % reenable_delay)


func _resolve_extortion_warn(job: ExtortionJob) -> void:
	job.mark_warning_strike()
	Debug.log("extortion", "[EXTORT] warn pending (refuse) — approaching player")


func _resolve_extortion_aggro(job: ExtortionJob) -> void:
	if _close_choice_ui.is_valid():
		_close_choice_ui.call(job.group_id)
	job.mark_full_aggro()
	_release_job_ai_control(job)
	Debug.log("extortion", "[EXTORT] resolved aggro")


# ---------------------------------------------------------------------------
# Warning strike tick
# ---------------------------------------------------------------------------

func _tick_warning_strike(job: ExtortionJob, player_pos: Vector2, friction_compensation: float) -> void:
	var speaker_id: String = job.taunt_speaker_id
	var speaker := _npc_simulator.get_enemy_node(speaker_id) if speaker_id != "" else null
	if speaker == null:
		_abort_job(job.group_id, job, "speaker_missing")
		Debug.log("extortion", "[EXTORT] warn strike aborted (speaker missing) group=%s" % job.group_id)
		return

	var to_player: Vector2 = player_pos - (speaker as Node2D).global_position
	var dist: float        = to_player.length()
	var atk_range: float   = BanditTuningScript.extort_warn_strike_range(job.group_id)
	if "attack_range" in speaker:
		atk_range = float(speaker.get("attack_range")) \
			+ BanditTuningScript.extort_warn_strike_range_bonus(job.group_id)

	if dist <= atk_range:
		var reenable_delay: float = BanditTuningScript.extort_ai_reenable_delay(job.group_id)
		if speaker.has_method("begin_scripted_melee_action"):
			speaker.begin_scripted_melee_action(player_pos, reenable_delay)
		job.mark_resolved()
		BanditGroupMemory.update_intent(job.group_id, "idle")
		var ids_warn: Array[String] = job.assigned_ids.duplicate()
		var gid_warn: String        = job.group_id
		_post_pay_groups[gid_warn]  = ids_warn
		_schedule_callback(reenable_delay, func() -> void:
			_post_pay_groups.erase(gid_warn)
			for aid: String in ids_warn:
				if aid != speaker_id:
					_set_enemy_scripted_control(_npc_simulator.get_enemy_node(aid), false)
		)
		for aid: String in job.assigned_ids:
			var behavior: BanditWorldBehavior = _behavior_for_enemy(aid)
			if behavior != null:
				behavior.force_return_home()
		Debug.log("extortion", "[EXTORT] warn strike delivered group=%s" % job.group_id)
	else:
		_set_enemy_scripted_control(speaker, true)
		_drive_enemy_toward_point(speaker, player_pos,
			BanditTuningScript.extort_warn_approach_speed(job.group_id) + friction_compensation)


# ---------------------------------------------------------------------------
# Faction ID helper
# ---------------------------------------------------------------------------

## Obtiene el faction_id del primer enemy asignado al job.
## Si no hay node disponible, retorna el fallback "bandits".
func _get_job_faction_id(job: ExtortionJob) -> String:
	for aid: String in job.assigned_ids:
		var enode := _npc_simulator.get_enemy_node(aid)
		if enode != null and is_instance_valid(enode) and "faction_id" in enode:
			return String(enode.get("faction_id"))
	return "bandits"


# ---------------------------------------------------------------------------
# Reaction bubble helpers
# ---------------------------------------------------------------------------

## Muestra una frase aleatoria del array desde el speaker del job (taunt_speaker_id).
## Silencioso si el speaker ya no existe.
func _show_reaction_bubble(job: ExtortionJob, phrases: Array[String]) -> void:
	if _bubble_manager == null or phrases.is_empty():
		return
	var speaker_id: String = job.taunt_speaker_id
	if speaker_id == "":
		speaker_id = job.assigned_ids[0] if job.assigned_ids.size() > 0 else ""
	if speaker_id == "":
		return
	var speaker := _npc_simulator.get_enemy_node(speaker_id)
	if speaker == null or not is_instance_valid(speaker):
		return
	var phrase: String = phrases[randi() % phrases.size()]
	_bubble_manager.show_actor_bubble(speaker as Node2D, phrase,
		BanditTuningScript.extort_taunt_bubble_duration(job.group_id))


## Muestra feedback visual según el motivo de abort.
## Elige el speaker más apropiado según si el líder sigue vivo o no.
func _show_abort_feedback(job: ExtortionJob, reason: String,
		group_data: Dictionary) -> void:
	if _bubble_manager == null:
		return
	var phrases: Array[String] = []
	match reason:
		"leader_dead":
			phrases = LEADER_KILLED_PHRASES
		"player_too_far":
			phrases = PLAYER_RAN_PHRASES
		_:
			return  # otros aborts son internos, sin feedback visual

	# Para leader_dead: buscar un miembro vivo que pueda hablar
	var speaker := _npc_simulator.get_enemy_node(job.taunt_speaker_id) \
		if job.taunt_speaker_id != "" else null
	if speaker == null or not is_instance_valid(speaker):
		for mid in group_data.get("member_ids", []):
			var mnode := _npc_simulator.get_enemy_node(String(mid))
			if mnode != null and is_instance_valid(mnode):
				speaker = mnode
				break
	if speaker == null:
		return
	var phrase: String = phrases[randi() % phrases.size()]
	_bubble_manager.show_actor_bubble(speaker as Node2D, phrase, 4.0)


# ---------------------------------------------------------------------------
# Poverty taunts
# ---------------------------------------------------------------------------

func _show_poverty_taunts(job: ExtortionJob) -> void:
	if _bubble_manager == null:
		return
	var speaker_id: String = job.taunt_speaker_id
	if speaker_id == "":
		speaker_id = job.assigned_ids[0] if job.assigned_ids.size() > 0 else ""
	if speaker_id == "":
		return
	var dur: float = BanditTuningScript.extort_taunt_bubble_duration(job.group_id)
	var step: float = dur + 0.4
	for i in POVERTY_TAUNT_PHRASES.size():
		var phrase: String = POVERTY_TAUNT_PHRASES[i]
		var delay: float   = step * i
		if delay == 0.0:
			var speaker := _npc_simulator.get_enemy_node(speaker_id)
			if speaker != null and is_instance_valid(speaker):
				_bubble_manager.show_actor_bubble(speaker as Node2D, phrase, dur)
		else:
			_schedule_callback(delay, func() -> void:
				var s := _npc_simulator.get_enemy_node(speaker_id)
				if s != null and is_instance_valid(s):
					_bubble_manager.show_actor_bubble(s as Node2D, phrase, dur)
			)


# ---------------------------------------------------------------------------
# Primitivos de control de IA
# ---------------------------------------------------------------------------

func _behavior_for_enemy(enemy_id: String) -> BanditWorldBehavior:
	if not _get_behavior_for_enemy.is_valid():
		return null
	return _get_behavior_for_enemy.call(enemy_id) as BanditWorldBehavior


func _release_job_ai_control(job: ExtortionJob) -> void:
	for aid: String in job.assigned_ids:
		var anode := _npc_simulator.get_enemy_node(aid)
		_set_enemy_scripted_control(anode, false)


func _set_enemy_scripted_control(enemy: Node, enabled: bool) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_method("set_scripted_control_enabled"):
		enemy.set_scripted_control_enabled(enabled)
	elif "external_ai_override" in enemy:
		enemy.external_ai_override = enabled


func _drive_enemy_toward_point(enemy: Node, target_pos: Vector2, speed: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not enemy is Node2D:
		return
	var to_target: Vector2 = target_pos - (enemy as Node2D).global_position
	if to_target.length() <= 1.0:
		if enemy.has_method("set_scripted_velocity"):
			enemy.set_scripted_velocity(Vector2.ZERO)
		elif "velocity" in enemy:
			enemy.velocity = Vector2.ZERO
		return
	var desired_velocity: Vector2 = to_target.normalized() * speed
	if enemy.has_method("set_scripted_velocity"):
		enemy.set_scripted_velocity(desired_velocity)
	elif "velocity" in enemy:
		enemy.velocity = desired_velocity
