require("DoubleRailAyStar.nut");

/**
 * A DoubleRail Pathfinder.
 */
class DoubleRail
{
	_aystar_class = AyStar;
	_max_cost = null;               ///< The maximum cost for a route.
	_cost_tile = null;              ///< The cost for a single tile.
	_cost_diagonal_tile = null;     ///< The cost for a diagonal tile.
	_cost_turn45 = null;            ///< The cost that is added to _cost_tile if the direction changes 45 degrees.
	_cost_turn90 = null;            ///< The cost that is added to _cost_tile if the direction changes 90 degrees.
	_cost_consecutive_turn = null;  ///< The cost that is added to _cost_tile if two turns are consecutive.
	_cost_slope = null;             ///< The extra cost if a rail tile is sloped.
	_cost_consecutive_slope = null; ///< The extra cost if two consecutive tiles are sloped.
	_cost_bridge_per_tile = null;   ///< The cost per tile of a new bridge, this is added to _cost_tile.
	_cost_tunnel_per_tile = null;   ///< The cost per tile of a new tunnel, this is added to _cost_tile.
	_cost_coast = null;             ///< The extra cost for a coast tile.
	_cost_level_crossing = null;    ///< the extra cost for rail/road level crossings.
	_max_bridge_length = null;      ///< The maximum length of a bridge that will be build.
	_max_tunnel_length = null;      ///< The maximum length of a tunnel that will be build.
	_estimate_multiplier = null;    ///< Every estimate is multiplied by this value. Use 1 for a 'perfect' route, higher values for faster pathfinding.
	_search_range = null;           ///< Range to search around source and destination, in either coordinate. 0 indicates unlimited.

	cost = null;                    ///< Used to change the costs.
	_pathfinder = null;             ///< A reference to the used AyStar object.
	_running = null;
	_goals = null;

	_a = null;
	_b = null;
	_c = null;
	_sqrt = null;
	_min_x = null;
	_max_x = null;
	_min_y = null;
	_max_y = null;

	constructor()
	{
		this._max_cost = 10000000;
		this._cost_tile = 100;
		this._cost_diagonal_tile = 70;
		this._cost_turn45 = 50;
		this._cost_turn90 = 300;
		this._cost_consecutive_turn = 250;
		this._cost_slope = 100;
		this._cost_consecutive_slope = 400;
		this._cost_bridge_per_tile = 150;
		this._cost_tunnel_per_tile = 120;
		this._cost_coast = 20;
		this._cost_level_crossing = 900;
		this._max_bridge_length = 6;
		this._max_tunnel_length = 6;
		this._estimate_multiplier = 1;
		this._search_range = 0;

		this.cost = this.Cost(this);
		this._pathfinder = this._aystar_class(this, this._Cost, this._Estimate, this._Neighbours, this._CheckDirection);
		this._running = false;
	}

	/**
	 * Initialize a path search between sources and goals.
	 * @param sources The source tiles.
	 * @param goals The target tiles.
	 * @param ignored_tiles An array of tiles that cannot occur in the final path.
	 * @see AyStar::InitializePath()
	 */
	function InitializePath(sources, goals, ignored_tiles = []) {
		local test_mode = AITestMode();
//		local nsources = [];

		local dir_source = this._GetMatchingSegmentDir([sources[0][0], sources[1][0]], [sources[0][1], sources[1][1]]);
		local source_segment = Segment(sources, dir_source);
//		AILog.Info("dir_source _GetMatchingSegmentDir = " + Segment.GetName(dir_source));

		local dir_goal = this._GetMatchingSegmentDir([goals[0][0], goals[1][0]], [goals[0][1], goals[1][1]]);
		local goal_segment = Segment(goals, dir_goal, true);
//		AILog.Info("dir_goal _GetMatchingSegmentDir = " + Segment.GetName(dir_goal));

//		foreach (node in sources) {
//			local path = this._pathfinder.Path(null, source_segment, this._Cost, this);
//			path = this._pathfinder.Path(path, source_segment, this._Cost, this);
//			nsources.push(path);
//		}

		this._goals = goal_segment;
		this._pathfinder.InitializePath(source_segment, goal_segment, ignored_tiles);

		if (this._search_range) {
			local pair = [];
			local min_freeform = AIMap.IsValidTile(0) ? 0 : 1

			foreach (source in [sources[0][0], sources[1][0]]) {
				foreach (goal in [goals[0][1], goals[1][1]]) {
					local distance = AIMap.DistanceManhattan(source, goal);
					pair.append([source, goal, distance]);

					local source_x = AIMap.GetTileX(source);
					local source_y = AIMap.GetTileY(source);
					local goal_x = AIMap.GetTileX(goal);
					local goal_y = AIMap.GetTileY(goal);

					this._min_x = max(min_freeform, min(source_x, goal_x) - this._search_range);
					this._min_y = max(min_freeform, min(source_y, goal_y) - this._search_range);
					this._max_x = min(AIMap.GetMapSizeX() - 2, max(source_x, goal_x) + this._search_range);
					this._max_y = min(AIMap.GetMapSizeY() - 2, max(source_y, goal_y) + this._search_range);
				}
			}

			local best_distance = 0;
			local best_source = AIMap.TILE_INVALID;
			local best_goal = AIMap.TILE_INVALID;
			for (local i = 0; i < pair.len(); i++) {
				if (pair[i][2] > best_distance) {
					best_distance = pair[i][2];
					best_source = pair[i][0];
					best_goal = pair[i][1];
				}
			}
			this._a = AIMap.GetTileY(best_source) - AIMap.GetTileY(best_goal);
			this._b = AIMap.GetTileX(best_goal) - AIMap.GetTileX(best_source);
			this._c = AIMap.GetTileX(best_source) * AIMap.GetTileY(best_goal) - AIMap.GetTileX(best_goal) * AIMap.GetTileY(best_source);
			this._sqrt = sqrt(this._a * this._a + this._b * this._b);
		}
	}

	/**
	 * Try to find the path as indicated with InitializePath with the lowest cost.
	 * @param iterations After how many iterations it should abort for a moment.
	 *  This value should either be -1 for infinite, or > 0. Any other value
	 *  aborts immediatly and will never find a path.
	 * @return A route if one was found, or false if the amount of iterations was
	 *  reached, or null if no path was found.
	 *  You can call this function over and over as long as it returns false,
	 *  which is an indication it is not yet done looking for a route.
	 * @see AyStar::FindPath()
	 */
	function FindPath(iterations);
};

class DoubleRail.Cost
{
	_main = null;

	function _set(idx, val)
	{
		if (this._main._running) throw("You are not allowed to change parameters of a running pathfinder.");

		switch (idx) {
			case "max_cost":            this._main._max_cost = val; break;
			case "tile":                this._main._cost_tile = val; break;
			case "diagonal_tile":       this._main._cost_diagonal_tile = val; break;
			case "turn45":              this._main._cost_turn45 = val; break;
			case "turn90":              this._main._cost_turn90 = val; break;
			case "consecutive_turn":    this._main._cost_consecutive_turn = val; break;
			case "slope":               this._main._cost_slope = val; break;
			case "consecutive_slope":   this._main._cost_consecutive_slope = val; break;
			case "bridge_per_tile":     this._main._cost_bridge_per_tile = val; break;
			case "tunnel_per_tile":     this._main._cost_tunnel_per_tile = val; break;
			case "coast":               this._main._cost_coast = val; break;
			case "level_crossing":      this._main._cost_level_crossing = val; break;
			case "max_bridge_length":   this._main._max_bridge_length = val; break;
			case "max_tunnel_length":   this._main._max_tunnel_length = val; break;
			case "estimate_multiplier": this._main._estimate_multiplier = val; break;
			case "search_range":        this._main._search_range = val; break;
			default: throw("the index '" + idx + "' does not exist");
		}

		return val;
	}

	function _get(idx)
	{
		switch (idx) {
			case "max_cost":            return this._main._max_cost;
			case "tile":                return this._main._cost_tile;
			case "diagonal_tile":       return this._main._cost_diagonal_tile;
			case "turn45":              return this._main._cost_turn45;
			case "turn90":              return this._main._cost_turn90;
			case "consecutive_turn":    return this._main._cost_consecutive_turn;
			case "slope":               return this._main._cost_slope;
			case "consecutive_slope":   return this._main._cost_consecutive_slope;
			case "bridge_per_tile":     return this._main._cost_bridge_per_tile;
			case "tunnel_per_tile":     return this._main._cost_tunnel_per_tile;
			case "coast":               return this._main._cost_coast;
			case "level_crossing":      return this._main._cost_level_crossing;
			case "max_bridge_length":   return this._main._max_bridge_length;
			case "max_tunnel_length":   return this._main._max_tunnel_length;
			case "estimate_multiplier": return this._main._estimate_multiplier;
			case "search_range":        return this._main._search_range;
			default: throw("the index '" + idx + "' does not exist");
		}
	}

	constructor(main)
	{
		this._main = main;
	}
};

function DoubleRail::FindPath(iterations)
{
	local test_mode = AITestMode();
	local ret = this._pathfinder.FindPath(iterations);
	this._running = (ret == false) ? true : false;
	if (!this._running && ret != null) {
//		if (ret._segment.m_nodes[0][0][3] == goal_segment.m_nodes[0][0][3] && ret._segment.m_nodes[1][0][3] == goal_segment.m_nodes[1][0][3]) {
//			return this._pathfinder.Path(ret, goal_segment, this._Cost, this);
//		}
	}
	return ret;
}

function DoubleRail::_IsSlopedBridge(end_a, end_b, end)
{
	local direction;
	local slope;
	if (end == end_a) {
		direction = (end_b - end_a) / AIMap.DistanceManhattan(end_a, end_b);
		slope = AITile.GetSlope(end_a);
	} else if (end = end_b) {
		direction = (end_a - end_b) / AIMap.DistanceManhattan(end_b, end_a);
		slope = AITile.GetSlope(end_b);
	} else {
		assert(false);
	}

	return !(((slope == AITile.SLOPE_NE || slope == AITile.SLOPE_STEEP_N || slope == AITile.SLOPE_STEEP_E) && direction == 1) ||
			((slope == AITile.SLOPE_SE || slope == AITile.SLOPE_STEEP_S || slope == AITile.SLOPE_STEEP_E) && direction == -AIMap.GetMapSizeX()) ||
			((slope == AITile.SLOPE_SW || slope == AITile.SLOPE_STEEP_S || slope == AITile.SLOPE_STEEP_W) && direction == -1) ||
			((slope == AITile.SLOPE_NW || slope == AITile.SLOPE_STEEP_N || slope == AITile.SLOPE_STEEP_W) && direction == AIMap.GetMapSizeX()) ||
			slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W);
}

function DoubleRail::_GetBridgeNumSlopes(end_a, end_b, res = false)
{
	local slopes = 0;
	local ret = {};
	ret.rawset(end_a, 0);
	ret.rawset(end_b, 0);
	local direction = (end_b - end_a) / AIMap.DistanceManhattan(end_a, end_b);
	local slope = AITile.GetSlope(end_a);
	if (!(((slope == AITile.SLOPE_NE || slope == AITile.SLOPE_STEEP_N || slope == AITile.SLOPE_STEEP_E) && direction == 1) ||
			((slope == AITile.SLOPE_SE || slope == AITile.SLOPE_STEEP_S || slope == AITile.SLOPE_STEEP_E) && direction == -AIMap.GetMapSizeX()) ||
			((slope == AITile.SLOPE_SW || slope == AITile.SLOPE_STEEP_S || slope == AITile.SLOPE_STEEP_W) && direction == -1) ||
			((slope == AITile.SLOPE_NW || slope == AITile.SLOPE_STEEP_N || slope == AITile.SLOPE_STEEP_W) && direction == AIMap.GetMapSizeX()) ||
			slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W)) {
		slopes++;
		ret.rawset(end_a, 1);
	}

	local slope = AITile.GetSlope(end_b);
	direction = -direction;
	if (!(((slope == AITile.SLOPE_NE || slope == AITile.SLOPE_STEEP_N || slope == AITile.SLOPE_STEEP_E) && direction == 1) ||
			((slope == AITile.SLOPE_SE || slope == AITile.SLOPE_STEEP_S || slope == AITile.SLOPE_STEEP_E) && direction == -AIMap.GetMapSizeX()) ||
			((slope == AITile.SLOPE_SW || slope == AITile.SLOPE_STEEP_S || slope == AITile.SLOPE_STEEP_W) && direction == -1) ||
			((slope == AITile.SLOPE_NW || slope == AITile.SLOPE_STEEP_N || slope == AITile.SLOPE_STEEP_W) && direction == AIMap.GetMapSizeX()) ||
			slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W)) {
		slopes++;
		ret.rawset(end_b, 1);
	}
	return res ? ret : slopes;
}

function DoubleRail::_Cost(path, new_segment, self)
{
	/* path == null means this is the first node of a path, so the cost is 0. */
	if (path == null) return 0;

	local parent_tiles = self._GetParents(path);
	local pppprev_tile;
	local ppprev_tile;
	local pprev_tile;
	local prev_tile;
	local new_tile;

	local costs = 0;

	foreach (j in [0, 1]) {
		pppprev_tile = parent_tiles[j][0];
		ppprev_tile = parent_tiles[j][1];
		pprev_tile = parent_tiles[j][2];
		prev_tile = parent_tiles[j][3];

		for (local i = 0; i < new_segment.m_nodes[j].len(); i++) {
			new_tile = new_segment.m_nodes[j][i][3];
//			AILog.Info("Cost: new_tile = " + new_tile + "; prev_tile = " + prev_tile + "; pprev_tile = " + pprev_tile + "; ppprev_tile = " + ppprev_tile + "; pppprev_tile = " + pppprev_tile);
			costs += self._CostSingleTile(pppprev_tile, ppprev_tile, pprev_tile, prev_tile, new_tile, self);
			ppprev_tile = pprev_tile;
			pprev_tile = prev_tile;
			prev_tile = new_tile;
		}
	}

	return path._cost + costs;
}

function DoubleRail::_CostSingleTile(pppprev_tile, ppprev_tile, pprev_tile, prev_tile, new_tile, self)
{
	if (self._search_range) {
		local cur_tile_x = AIMap.GetTileX(new_tile);
		local cur_tile_y = AIMap.GetTileY(new_tile);
		if (cur_tile_x < self._min_x || cur_tile_x > self._max_x || cur_tile_y < self._min_y || cur_tile_y > self._max_y) return self._max_cost;
		if (abs(self._a * cur_tile_x + self._b * cur_tile_y + self._c) / self._sqrt > self._search_range) return self._max_cost;
	}
//	AIExecMode() && AIBase.Chance(1, 20) && AISign.BuildSign(new_tile, "x");
	/* If the two tiles are more than 1 tile apart, the pathfinder wants a bridge or tunnel
	 *  to be built. */
	if (AIMap.DistanceManhattan(prev_tile, new_tile) > 1) {
		/* Check if we should build a bridge or a tunnel. */
		local cost = 0;
		if (AITunnel.GetOtherTunnelEnd(prev_tile) == new_tile) {
			cost += AIMap.DistanceManhattan(prev_tile, new_tile) * (self._cost_tile + self._cost_tunnel_per_tile) + self._cost_tunnel_per_tile;
		} else {
			cost += AIMap.DistanceManhattan(prev_tile, new_tile) * (self._cost_tile + self._cost_bridge_per_tile) + self._cost_bridge_per_tile + self._GetBridgeNumSlopes(new_tile, prev_tile) * self._cost_slope;
			if (AITile.HasTransportType(prev_tile, AITile.TRANSPORT_WATER)) {
				cost += self._cost_coast;
			}
			if (AITile.HasTransportType(new_tile, AITile.TRANSPORT_WATER)) {
				cost += self._cost_coast;
			}
			if (ppprev_tile && pprev_tile && self._IsSlopedBridge(prev_tile, new_tile, prev_tile)) {
				if (AIMap.DistanceManhattan(ppprev_tile, pprev_tile) > 1) {
					if (AITunnel.GetOtherTunnelEnd(ppprev_tile) != pprev_tile && self._IsSlopedBridge(ppprev_tile, pprev_tile, pprev_tile)) {
						cost += self._cost_consecutive_slope;
					}
				} else if (self._IsSlopedRail(ppprev_tile, pprev_tile, prev_tile)) {
					cost += self._cost_consecutive_slope;
				}
			}
		}
		if (pprev_tile && ppprev_tile &&
				(ppprev_tile - pprev_tile) / AIMap.DistanceManhattan(ppprev_tile, pprev_tile) != (prev_tile - new_tile) / AIMap.DistanceManhattan(prev_tile, new_tile)) {
			cost += self._cost_turn45;
			if (pppprev_tile) {
				if ((AIMap.DistanceManhattan(prev_tile, pppprev_tile) == 3 && pppprev_tile - ppprev_tile != pprev_tile - prev_tile) ||
						(prev_tile - pprev_tile == pppprev_tile - ppprev_tile) ||
						(AIMap.DistanceManhattan(pppprev_tile, ppprev_tile) > 1 && (pppprev_tile - ppprev_tile) / AIMap.DistanceManhattan(pppprev_tile, ppprev_tile) != (pprev_tile - prev_tile) / AIMap.DistanceManhattan(pprev_tile, prev_tile))) {
					cost += self._cost_consecutive_turn;
				}
			}
		}
		return cost;
	}

	/* Check for a turn. We do this by substracting the TileID of the current
	 *  node from the TileID of the previous node and comparing that to the
	 *  difference between the tile before the previous node and the node before
	 *  that. */
	local cost = 0;
	if (pprev_tile) {
		if (AIMap.DistanceManhattan(pprev_tile, prev_tile) == 1 && pprev_tile - prev_tile != prev_tile - new_tile) {
			cost += self._cost_diagonal_tile;
		} else {
			cost += self._cost_tile;
		}
	}
	if (pprev_tile && ppprev_tile) {
		local is_turn = false;
		if ((AIMap.DistanceManhattan(new_tile, ppprev_tile) == 3 && ppprev_tile - pprev_tile != prev_tile - new_tile) ||
				(AIMap.DistanceManhattan(ppprev_tile, pprev_tile) > 1 && (ppprev_tile - pprev_tile) / AIMap.DistanceManhattan(ppprev_tile, pprev_tile) != (prev_tile - new_tile) / AIMap.DistanceManhattan(prev_tile, new_tile))) {
			cost += self._cost_turn45;
			is_turn = true;
		} else if (new_tile - prev_tile == ppprev_tile - pprev_tile) {
			cost += self._cost_turn90;
			is_turn = true;
		}
		if (pppprev_tile && is_turn) {
			if ((AIMap.DistanceManhattan(prev_tile, pppprev_tile) == 3 && pppprev_tile - ppprev_tile != pprev_tile - prev_tile) ||
					(prev_tile - pprev_tile == pppprev_tile - ppprev_tile) ||
					(AIMap.DistanceManhattan(pppprev_tile, ppprev_tile) > 1 && (pppprev_tile - ppprev_tile) / AIMap.DistanceManhattan(pppprev_tile, ppprev_tile) != (pprev_tile - prev_tile) / AIMap.DistanceManhattan(pprev_tile, prev_tile))) {
				cost += self._cost_consecutive_turn;
			}
		}
	}

	/* Check if the new tile is a level crossing. */
	if (AITile.HasTransportType(new_tile, AITile.TRANSPORT_ROAD) || AIRoad.IsRoadTile(new_tile)) {
		cost += self._cost_level_crossing;
	}

	/* Check if the last tile was sloped. */
	if (pprev_tile) {
		if (AIMap.DistanceManhattan(pprev_tile, prev_tile) == 1) {
			if (self._IsSlopedRail(pprev_tile, prev_tile, new_tile)) {
				cost += self._cost_slope;
				if (ppprev_tile) {
					if (AIMap.DistanceManhattan(ppprev_tile, pprev_tile) == 1) {
						if (self._IsSlopedRail(ppprev_tile, pprev_tile, prev_tile)) {
							cost += self._cost_consecutive_slope;
						}
					} else if (AITunnel.GetOtherTunnelEnd(ppprev_tile) != pprev_tile && self._IsSlopedBridge(ppprev_tile, pprev_tile, pprev_tile)) {
						cost += self._cost_consecutive_slope;
					}
				}
			}
//		} else if (AITunnel.GetOtherTunnelEnd(pprev_tile) != prev_tile && self._IsSlopedBridge(pprev_tile, prev_tile, prev_tile)) {
//			cost += self._cost_slope;
		}
	}

	return cost;
}

function DoubleRail::_Estimate(cur_segment, goal_segment, self)
{
	local cost = 0;
	/* As estimate we multiply the lowest possible cost for a single tile with
	 *  with the minimum number of tiles we need to traverse. */
	foreach (j in [0, 1]) {
		local cur_tile = cur_segment.m_nodes[j].top()[0];
		local goal_tile = goal_segment.m_nodes[j].top()[3];
//		AILog.Info("line = " + (j + 1) + "; cur_tile = " + cur_tile + "; goal_tile = " + goal_tile);
		local dx = abs(AIMap.GetTileX(cur_tile) - AIMap.GetTileX(goal_tile));
		local dy = abs(AIMap.GetTileY(cur_tile) - AIMap.GetTileY(goal_tile));
		cost += min(dx, dy) * self._cost_diagonal_tile * 2 + abs(dx - dy) * self._cost_tile;
	}
//	if (cost == 0) AIController.Break("We reached the goal!");
	return cost * self._estimate_multiplier;
}

function DoubleRail::_Neighbours(path, cur_segment, self)
{
	/* self._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
	if (path._cost >= self._max_cost) return [];

	local parent_tiles = self._GetParents(path);
	local pppprev_tile;
	local ppprev_tile;
	local pprev_tile;
	local prev_tile;
	local cur_tile;

	local neighbours = [];
	foreach (neighbour in cur_segment.m_neighbours) {
//		AILog.Info("neighbour = " + Segment.GetName(neighbour));
		local next_segment = Segment(path, neighbour);

		local pushed_all = true;
		if (!Segment.IsCustomSegmentDir(neighbour)) {
			foreach (j in [0, 1]) {
				pppprev_tile = parent_tiles[j][0];
				ppprev_tile = parent_tiles[j][1];
				pprev_tile = parent_tiles[j][2];
				prev_tile = parent_tiles[j][3];
				cur_tile = parent_tiles[j][4];

				for (local i = 0; i < next_segment.m_nodes[j].len(); i++) {
					local next_tile = next_segment.m_nodes[j][i][0];
//					AILog.Info("line = " + (j + 1) + "; node = " + i + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; cur_tile = " + cur_tile + "; next_tile = " + next_tile);
//					/* Disallow 90 degree turns */
//					if (prev_tile && pprev_tile &&
//							next_tile - cur_tile == pprev_tile - prev_tile) {
//						pushed_all = false;
//						AILog.Info("90 degrees detected");
//						break;
//					}
					/* We add them to the to the neighbours-list if we can build a rail to
					 *  them and no rail exists there. */
					if (!prev_tile || !AITile.HasTransportType(cur_tile, AITile.TRANSPORT_RAIL) && AIRail.BuildRail(prev_tile, cur_tile, next_tile)) {
						/* pushes tiles */
					} else {
						pushed_all = false;
						break;
					}
					pprev_tile = prev_tile;
					prev_tile = cur_tile;
					cur_tile = next_tile;
				}
				if (!pushed_all) {
					break;
				}
			}
		} else {
			/* Custom Segment */
			local prev_tile_0 = parent_tiles[0][3];
//			local cur_tile_0 = parent_tiles[0][4];
			local prev_tile_1 = parent_tiles[1][3];
//			local cur_tile_1 = parent_tiles[1][4];
			if (prev_tile_0 && prev_tile_1) {
				local wrap_map = false;
				for (local i = 2; i < self._max_bridge_length; i++) {
					local nodes = [[], []];
					pushed_all = true;
					foreach (j in [0, 1]) {
						prev_tile = parent_tiles[j][3];
						cur_tile = parent_tiles[j][4];
						local bridge_dir = self._GetDirection(null, prev_tile, cur_tile, true);
						local target = cur_tile + i * (cur_tile - prev_tile);
						if (!AIMap.IsValidTile(target)) {
							wrap_map = true;
							break; // don't wrap the map
						}

						local bridge_list = AIBridgeList_Length(i + 1);
						if (!bridge_list.IsEmpty() && AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), cur_tile, target)) {
							local used_tiles = self._GetUsedTiles(cur_tile, target, true);
							if (!self._UsedTileListsConflict(path.GetUsedTiles(), used_tiles)) {
								nodes[j].append([target, bridge_dir, used_tiles, cur_tile, self._GetSegmentDirection(next_segment, j), self._GetNodeID(next_segment, j, 0)]);
								local next_tile = target + (target - cur_tile) / AIMap.DistanceManhattan(cur_tile, target);
								pushed_all = false;
								foreach (offset in [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(-1, 0)]) {
									/* Don't turn back */
									if (next_tile + offset == target) continue;
									if (!AITile.HasTransportType(next_tile, AITile.TRANSPORT_RAIL) && AIRail.BuildRail(target, next_tile, next_tile + offset)) {
										nodes[j].append([next_tile, bridge_dir, [], target, self._GetSegmentDirection(next_segment, j), self._GetNodeID(next_segment, j, 1)]);
										pushed_all = true;
										break;
									}
								}
								if (!pushed_all) {
									break;
								}
							} else {
								pushed_all = false;
								break;
							}
						} else {
							pushed_all = false;
							break;
						}
					}
					if (wrap_map) {
						break;
					}
					if (!pushed_all) {
						continue;
					} else {
						next_segment = Segment(path, neighbour);
						foreach (j in [0, 1]) {
							next_segment.m_nodes[j].extend(nodes[j]);
						}
						neighbours.push(next_segment);
					}
				}

				/* Tunnels */
				local nodes = [[], []];
				foreach (j in [0, 1]) {
					pushed_all = false;
					prev_tile = parent_tiles[j][3];
					cur_tile = parent_tiles[j][4];
					local tunnel_dir = self._GetDirection(null, prev_tile, cur_tile, true);
					local slope = AITile.GetSlope(cur_tile);
					if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE) {
						local other_tunnel_end = AITunnel.GetOtherTunnelEnd(cur_tile);
						if (AIMap.IsValidTile(other_tunnel_end)) {

							local tunnel_length = AIMap.DistanceManhattan(cur_tile, other_tunnel_end);
							local tile_before = cur_tile + (cur_tile - other_tunnel_end) / tunnel_length;
							if (AITunnel.GetOtherTunnelEnd(other_tunnel_end) == cur_tile && tunnel_length >= 2 &&
									tile_before == prev_tile && tunnel_length < self._max_tunnel_length && AITunnel.BuildTunnel(AIVehicle.VT_RAIL, cur_tile)) {
								local used_tiles = self._GetUsedTiles(cur_tile, other_tunnel_end, false);
								if (!self._UsedTileListsConflict(path.GetUsedTiles(), used_tiles)) {
									nodes[j].push([other_tunnel_end, tunnel_dir, used_tiles, cur_tile, self._GetSegmentDirection(next_segment, j), self._GetNodeID(next_segment, j, 0)]);
									local next_tile = other_tunnel_end + (other_tunnel_end - cur_tile) / AIMap.DistanceManhattan(cur_tile, other_tunnel_end);
									pushed_all = false;
									foreach (offset in [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(-1, 0)]) {
										/* Don't turn back */
										if (next_tile + offset == other_tunnel_end) continue;
										if (!AITile.HasTransportType(next_tile, AITile.TRANSPORT_RAIL) && AIRail.BuildRail(other_tunnel_end, next_tile, next_tile + offset)) {
											nodes[j].append([next_tile, tunnel_dir, [], other_tunnel_end, self._GetSegmentDirection(next_segment, j), self._GetNodeID(next_segment, j, 1)]);
											pushed_all = true;
											break;
										}
									}
								}
							}
						}
					}
					if (!pushed_all) {
						break;
					}
				}
				if (pushed_all) {
					if (AIMap.DistanceManhattan(nodes[0][0][3], nodes[0][0][0]) == AIMap.DistanceManhattan(nodes[1][0][3], nodes[1][0][0])) {
						next_segment = Segment(path, neighbour);
						foreach (j in [0, 1]) {
							next_segment.m_nodes[j].extend(nodes[j]);
						}
						neighbours.push(next_segment);
					}
				}
			}
		}
		if (!pushed_all) {
			continue;
		}

		if (!Segment.IsCustomSegmentDir(neighbour)) {
			neighbours.push(next_segment);
		}
	}
//	AILog.Info("neighbours.len() = " + neighbours.len());
	return neighbours;
}

function DoubleRail::_CheckDirection(is_neighbour, existing_direction, new_direction, self)
{
//	local trackdir_left_n = 1 << 6; // 64
//	local trackdir_left_s = 1 << 17; // 131072
//	local trackdir_lower_e = 1 << 7; // 128
//	local trackdir_lower_w = 1 << 13; // 8192
//	local trackdir_upper_w = 1 << 10; // 1024
//	local trackdir_upper_e = 1 << 16; // 65536
//	local trackdir_right_s = 1 << 11; // 2048
//	local trackdir_right_n = 1 << 12; // 4096

//	local trackdir_ne = 1 << 4; // 16
//	local trackdir_nw = 1 << 14; // 16384
//	local trackdir_se = 1 << 19; // 524288
//	local trackdir_sw = 1 << 9; // 512

//	local track_left = trackdir_left_n | trackdir_left_s; // 131136
//	local track_lower = trackdir_lower_e | trackdir_lower_w; // 8320
//	local track_upper = trackdir_upper_w | trackdir_upper_e; // 66560
//	local track_right = trackdir_right_s | trackdir_right_n; // 6144

//	local trackdir_3way_ne = trackdir_ne | trackdir_right_n | trackdir_upper_e; // 69648
//	local trackdir_3way_nw = trackdir_left_n | trackdir_upper_w | trackdir_nw; // 17472
//	local trackdir_3way_se = trackdir_lower_e | trackdir_right_s | trackdir_se; // 526464
//	local trackdir_3way_sw = trackdir_sw | trackdir_lower_w | trackdir_left_s; // 139776

	/* Allowed combinations */
//	if ((existing_direction & ~track_left) == 0) {
//		if (is_neighbour) {
//			if ((new_direction & ~track_right) == 0) return true;
//		} else {
//			if ((new_direction & ~trackdir_3way_nw) == 0) return true;
//			if ((new_direction & ~trackdir_3way_sw) == 0) return true;
//		}
//	}
//	if ((existing_direction & ~track_right) == 0) {
//		if (is_neighbour) {
//			if ((new_direction & ~track_left) == 0) return true;
//		} else {
//			if ((new_direction & ~trackdir_3way_ne) == 0) return true;
//			if ((new_direction & ~trackdir_3way_se) == 0) return true;
//		}
//	}
//	if ((existing_direction & ~track_upper) == 0) {
//		if (is_neighbour) {
//			if ((new_direction & ~track_lower) == 0) return true;
//		} else {
//			if ((new_direction & ~trackdir_3way_ne) == 0) return true;
//			if ((new_direction & ~trackdir_3way_nw) == 0) return true;
//		}
//	}
//	if ((existing_direction & ~track_lower) == 0) {
//		if (is_neighbour) {
//			if ((new_direction & ~track_upper) == 0) return true;
//		} else {
//			if ((new_direction & ~trackdir_3way_se) == 0) return true;
//			if ((new_direction & ~trackdir_3way_sw) == 0) return true;
//		}
//	}

	if (!(existing_direction & ~131136)) {
		if (is_neighbour) {
			if (!(new_direction & ~6144)) return true;
		} else {
			if (!(new_direction & ~17472)) return true;
			if (!(new_direction & ~139776)) return true;
		}
	}
	if (!(existing_direction & ~6144)) {
		if (is_neighbour) {
			if (!(new_direction & ~131136)) return true;
		} else {
			if (!(new_direction & ~69648)) return true;
			if (!(new_direction & ~526464)) return true;
		}
	}
	if (!(existing_direction & ~66560)) {
		if (is_neighbour) {
			if (!(new_direction & ~8320)) return true;
		} else {
			if (!(new_direction & ~69648)) return true;
			if (!(new_direction & ~17472)) return true;
		}
	}
	if (!(existing_direction & ~8320)) {
		if (is_neighbour) {
			if (!(new_direction & ~66560)) return true;
		} else {
			if (!(new_direction & ~526464)) return true;
			if (!(new_direction & ~139776)) return true;
		}
	}

	/* Everything else is disallowed */
	return false;
}

function DoubleRail::_dir(from, to)
{
	if (from - to == 1) return 0;
	if (from - to == -1) return 1;
	if (from - to == AIMap.GetMapSizeX()) return 2;
	if (from - to == -AIMap.GetMapSizeX()) return 3;
	throw("Shouldn't come here in _dir");
}

function DoubleRail::_GetDirection(pre_from, from, to, is_bridge)
{
	if (is_bridge) {
		if (from - to == 1) return 1;
		if (from - to == -1) return 2;
		if (from - to == AIMap.GetMapSizeX()) return 4;
		if (from - to == -AIMap.GetMapSizeX()) return 8;
	}
	return 1 << (4 + (pre_from == null ? 0 : 4 * this._dir(pre_from, from)) + this._dir(from, to));
}

function DoubleRail::_IsSlopedRail(start, middle, end)
{
	local NW = 0; // Set to true if we want to build a rail to / from the north-west
	local NE = 0; // Set to true if we want to build a rail to / from the north-east
	local SW = 0; // Set to true if we want to build a rail to / from the south-west
	local SE = 0; // Set to true if we want to build a rail to / from the south-east

	if (middle - AIMap.GetMapSizeX() == start || middle - AIMap.GetMapSizeX() == end) NW = 1;
	if (middle - 1 == start || middle - 1 == end) NE = 1;
	if (middle + AIMap.GetMapSizeX() == start || middle + AIMap.GetMapSizeX() == end) SE = 1;
	if (middle + 1 == start || middle + 1 == end) SW = 1;

	/* If there is a turn in the current tile, it can't be sloped. */
	if ((NW || SE) && (NE || SW)) return false;

	local slope = AITile.GetSlope(middle);
	/* A rail on a steep slope is always sloped. */
	if (AITile.IsSteepSlope(slope)) return true;

	/* If only one corner is raised, the rail is sloped. */
	if (slope == AITile.SLOPE_N || slope == AITile.SLOPE_W) return true;
	if (slope == AITile.SLOPE_S || slope == AITile.SLOPE_E) return true;

	if (NW && (slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE)) return true;
	if (NE && (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SW)) return true;

	return false;
}

function DoubleRail::_GetUsedTiles(from, to, is_bridge)
{
	local used_list = [];
	local offset = (to - from) / AIMap.DistanceManhattan(from, to);

	local axis;
	if (abs(offset) == 1) {
		axis = 1; // Axis X
	} else if (abs(offset) == AIMap.GetMapSizeX()) {
		axis = 0; // Axis Y
	}

	local from_height = AITile.GetMaxHeight(from);
	local to_height = AITile.GetMaxHeight(to);

	if (is_bridge) {
		local slopes = this._GetBridgeNumSlopes(from, to, true);
		from_height += --slopes.rawget(from);
		to_height += --slopes.rawget(to);
	}

	used_list.push([from, to, axis, is_bridge, from_height]);

	return used_list;
}

/**
 * Checks whether two lists of used tiles conflict with each other.
 * @param prev_used_list List of used tiles (from a previous path node).
 * @param used_list List of used tiles (for the current node).
 * @return true if there is a conflict with one of the tiles.
 */
function DoubleRail::_UsedTileListsConflict(prev_used_list, used_list)
{
	foreach (prev_item in prev_used_list) {
		foreach (item in used_list) {
			/* [from, to, axis, is_bridge, from_height] */
			local prev_from = prev_item[0];
			local prev_to = prev_item[1];
			local prev_axis = prev_item[2];
			local prev_is_bridge = prev_item[3];
			local prev_height = prev_item[4];
//			AILog.Info("NEW:prev_from = " + prev_from + "; prev_to = " + prev_to + "; prev_axis = " + prev_axis + "; prev_is_bridge = " + prev_is_bridge + "; prev_height = " + prev_height);
//			local prev_offset = (prev_to - prev_from) / AIMap.DistanceManhattan(prev_from, prev_to);
			local prev_from_x = AIMap.GetTileX(prev_from);
			local prev_from_y = AIMap.GetTileY(prev_from);
			local prev_to_x = AIMap.GetTileX(prev_to);
			local prev_to_y = AIMap.GetTileY(prev_to);
			local prev_min_x = min(prev_from_x, prev_to_x);
			local prev_max_x = max(prev_from_x, prev_to_x);
			local prev_min_y = min(prev_from_y, prev_to_y);
			local prev_max_y = max(prev_from_y, prev_to_y);

			local from = item[0];
			local to = item[1];
			local axis = item[2];
			local is_bridge = item[3];
			local height = item[4];
//			AILog.Info("NEW:from = " + from + "; to = " + to + "; axis = " + axis + "; is_bridge = " + is_bridge + "; height = " + height);
//			local offset = (from - to) / AIMap.DistanceManhattan(from, to);
			local from_x = AIMap.GetTileX(from);
			local from_y = AIMap.GetTileY(from);
			local to_x = AIMap.GetTileX(to);
			local to_y = AIMap.GetTileY(to);
			local min_x = min(from_x, to_x);
			local max_x = max(from_x, to_x);
			local min_y = min(from_y, to_y);
			local max_y = max(from_y, to_y);

			if (prev_from == from || prev_from == to || prev_to == from || prev_to == to) {
				return true; // tunnel or bridge heads are on top of each other
			}

			if (!prev_is_bridge && !is_bridge) {
				if (prev_axis != axis) {
					if (prev_height == height) {
						if (prev_axis == 1) {
							/* existing axis x tunnel */
							if (min_y <= prev_from_y && prev_from_y <= max_y &&
									prev_min_x <= from_x && from_x <= prev_max_x) {
//								AILog.Info("tunnels are crossing each other, prev_axis == 1");
								return true; //tunnels are crossing each other
							}
						} else {
							/* existing axis y tunnel */
							if (min_x <= prev_from_x && prev_from_x <= max_x &&
									prev_min_y <= from_y && from_y <= prev_max_y) {
//								AILog.Info("tunnels are crossing each other, prev_axis == 0");
								return true; //tunnels are crossing each other
							}
						}
					}
				}
			}

			if (prev_is_bridge && is_bridge) {
				if (prev_axis == axis) {
					if (prev_axis == 1) {
						/* both on axis x */
						if (min_x <= prev_max_x && max_x >= prev_min_x &&
								prev_from_y == from_y) {
//							AILog.Info("bridges are on top of one another, prev_axis == 1");
							return true; // bridges are on top of one another
						}
					} else {
						/* both on axis y */
						if (min_y <= prev_max_y && max_y >= prev_min_y &&
								prev_from_x == from_x) {
//							AILog.Info("bridges are on top of one another, prev_axis == 0");
							return true; // bridges are on top of one another
						}
					}
				} else {
					/* prev_axis != axis */
					if (prev_axis == 1) {
						/* bridge in axis y crossing existing axis x bridge */
						if (min_y <= prev_from_y && prev_from_y <= max_y &&
								prev_min_x <= from_x && from_x <= prev_max_x) {
							local pass = false;
							if (prev_height > height && (from_y == prev_from_y || to_y == prev_from_y)) {
//								AILog.Info("bridge in axis y can cross over the head of the existing bridge, prev_axis == 1");
								pass = true; // bridge in axis y can cross over the head of the existing bridge
							} else if (height > prev_height && (prev_from_x == from_x || prev_to_x == from_x)) {
//								AILog.Info("bridge in axis y can cross below the head of the existing bridge, prev_axis == 1");
								pass = true; // bridge in axis y can cross below the head of the existing bridge
							}
//							AILog.Info("bridge middle parts are crossing each other or doesn't have enough height to cross the existing head, prev_axis == 1");
							if (!pass) return true; // bridge middle parts are crossing each other or doesn't have enough height to cross the existing head
						}
					} else {
						/* bridge in axis x crossing existing axis y bridge */
						if (min_x <= prev_from_x && prev_from_x <= max_x &&
								prev_min_y <= from_y && from_y <= prev_max_y) {
							local pass = false;
							if (prev_height > height && (from_x == prev_from_x || to_x == prev_from_x)) {
//								AILog.Info("bridge in axis x can cross over the head of the existing bridge, prev_axis == 0");
								pass = true; // bridge in axis x can cross over the head of the existing bridge
							} else if (height > prev_height && (prev_from_y == from_y || prev_to_y == from_y)) {
//								AILog.Info("bridge in axis x can cross below the head of the existing bridge, prev_axis == 0");
								pass = true; // bridge in axis x can cross below the head of the existing bridge
							}
//							AILog.Info("bridge middle parts are crossing each other or doesn't have enough height to cross the existing head, prev_axis == 0");
							if (!pass) return true; // bridge middle parts are crossing each other or doesn't have enough height to cross the existing head
						}
					}
				}
			}
		}
	}

	return false;
}

function DoubleRail::_GetParents(path)
{
	local parent_tiles = [[], []];
	local cur_tile;
	local prev_tile;
	local pprev_tile;
	local ppprev_tile;
	local pppprev_tile;
	local temp_path;

	foreach (j in [0, 1]) {
		temp_path = path;
		local temp_path2;
		local i = path._segment.m_nodes[j].len() - 1;

		cur_tile = path._segment.m_nodes[j][i][0];

		local prev_node = temp_path.GetPreviousNode(j, i, 1, true);
		if (prev_node != null) {
			temp_path2 = prev_node[0];
			i = prev_node[1];
			prev_tile = temp_path2._segment.m_nodes[j][i][0];
		} else {
			prev_tile = temp_path._segment.m_nodes[j][i][3];
			pprev_tile = 0;
			ppprev_tile = 0;
			pppprev_tile = 0;
			parent_tiles[j] = [pppprev_tile, ppprev_tile, pprev_tile, prev_tile, cur_tile];
			continue;
		}
		temp_path = temp_path2;

		prev_node = temp_path.GetPreviousNode(j, i, 1, true);
		if (prev_node != null) {
			temp_path2 = prev_node[0];
			i = prev_node[1];
			pprev_tile = temp_path2._segment.m_nodes[j][i][0];
		} else {
			pprev_tile = temp_path._segment.m_nodes[j][i][3];
			ppprev_tile = 0;
			pppprev_tile = 0;
			parent_tiles[j] = [pppprev_tile, ppprev_tile, pprev_tile, prev_tile, cur_tile];
			continue;
		}
		temp_path = temp_path2;

		prev_node = temp_path.GetPreviousNode(j, i, 1, true);
		if (prev_node != null) {
			temp_path2 = prev_node[0];
			i = prev_node[1];
			ppprev_tile = temp_path2._segment.m_nodes[j][i][0];
		} else {
			ppprev_tile = temp_path._segment.m_nodes[j][i][3];
			pppprev_tile = 0;
			parent_tiles[j] = [pppprev_tile, ppprev_tile, pprev_tile, prev_tile, cur_tile];
			continue;
		}
		temp_path = temp_path2;

		prev_node = temp_path.GetPreviousNode(j, i, 1, true);
		if (prev_node != null) {
			temp_path2 = prev_node[0];
			pppprev_tile = temp_path2._segment.m_nodes[j][i][0];
			parent_tiles[j] = [pppprev_tile, ppprev_tile, pprev_tile, prev_tile, cur_tile];
			continue;
		} else {
			pppprev_tile = temp_path._segment.m_nodes[j][i][3];
			parent_tiles[j] = [pppprev_tile, ppprev_tile, pprev_tile, prev_tile, cur_tile];
			continue;
		}

		assert(pppprev_tile != null && ppprev_tile != null && pprev_tile != null && prev_tile != null && cur_tile != null);
		assert((pppprev_tile != ppprev_tile || pppprev_tile == 0) && (ppprev_tile != pprev_tile || ppprev_tile == 0) && (pprev_tile != prev_tile || pprev_tile == 0) && (prev_tile != cur_tile || prev_tile == 0));
		parent_tiles[j] = [pppprev_tile, ppprev_tile, pprev_tile, prev_tile, cur_tile];
	}

	return parent_tiles;
}

enum SegmentDir {
	SW_NE,
	SW_N_NE,
	SW_E_NE,
	SW_N_NW,
	SW_E_SE,
	SE_NW,
	SE_W_NW,
	SE_N_NW,
	SE_W_SW,
	SE_N_NE,
	NE_SW,
	NE_S_SW,
	NE_W_SW,
	NE_S_SE,
	NE_W_NW,
	NW_SE,
	NW_E_SE,
	NW_S_SE,
	NW_E_NE,
	NW_S_SW,
	SW_NE_CUSTOM,
	SE_NW_CUSTOM,
	NE_SW_CUSTOM,
	NW_SE_CUSTOM
};

function DoubleRail::_GetMatchingSegmentDir(from, to)
{
	local from1;
	local to1;
	local from2;
	local to2;
	if (typeof(to[0]) == "array") {
		/* move to the last tile in the array */
		to1 = to[0].top();
		to2 = to[1].top();
	} else {
		to1 = to[0];
		to2 = to[1];
	}
	if (typeof(from[0]) == "array") {
		from1 = from[0].top();
		from2 = from[1].top();
	} else {
		from1 = from[0];
		from2 = from[1];
	}
	local from1_to1 = from1 - to1;
	local from2_to2 = from2 - to2;

	local from2_from1 = from2 - from1;
	local to2_to1 = to2 - to1;
	assert(AIMap.DistanceManhattan(from2, from1) == 1);
	assert(AIMap.DistanceManhattan(to2, to1) == 1);

//	AILog.Info("from1 = " + from1 + "; from2 = " + from2 + "; to1 = " + to1 + "; to2 = " + to2);
//	AILog.Info("from1_to1 = " + from1_to1 + "; from2_to2 = " + from2_to2 + "; from2_from1 = " + from2_from1 + "; to2_to1 = " + to2_to1);
//	AIController.Break(" ");

	switch (from1_to1) {
		case AIMap.GetTileIndex(1, 0):
			switch (from2_to2) {
				case AIMap.GetTileIndex(1, 0):
					assert(from2_from1 == AIMap.GetTileIndex(0, 1));
					assert(to2_to1 == AIMap.GetTileIndex(0, 1));
					return SegmentDir.SW_NE;
				case AIMap.GetTileIndex(2, 1):
					assert(from2_from1 == AIMap.GetTileIndex(0, 1));
					assert(to2_to1 == AIMap.GetTileIndex(-1, 0));
					return SegmentDir.SW_N_NW;
			}

		case AIMap.GetTileIndex(1, 1):
			switch (from2_to2) {
				case AIMap.GetTileIndex(1, 1):
					switch (from2_from1) {
						case AIMap.GetTileIndex(0, 1):
							assert(to2_to1 == AIMap.GetTileIndex(0, 1));
							return SegmentDir.SW_N_NE;
						case AIMap.GetTileIndex(-1, 0):
							assert(to2_to1 == AIMap.GetTileIndex(-1, 0));
							return SegmentDir.SE_N_NW;
					}
			}

		case AIMap.GetTileIndex(1, -1):
			switch (from2_to2) {
				case AIMap.GetTileIndex(1, -1):
					switch (from2_from1) {
						case AIMap.GetTileIndex(0, 1):
							assert(to2_to1 == AIMap.GetTileIndex(0, 1));
							return SegmentDir.SW_E_NE;
						case AIMap.GetTileIndex(1, 0):
							assert(to2_to1 == AIMap.GetTileIndex(1, 0));
							return SegmentDir.NW_E_SE;
					}
			}

		case AIMap.GetTileIndex(2, -1):
			switch (from2_to2) {
				case AIMap.GetTileIndex(1, 0):
					assert(from2_from1 == AIMap.GetTileIndex(0, 1));
					assert(to2_to1 == AIMap.GetTileIndex(-1, 0));
					return SegmentDir.SW_E_SE;
			}

		case AIMap.GetTileIndex(0, 1):
			switch (from2_to2) {
				case AIMap.GetTileIndex(0, 1):
					assert(from2_from1 == AIMap.GetTileIndex(-1, 0));
					assert(to2_to1 == AIMap.GetTileIndex(-1, 0));
					return SegmentDir.SE_NW;
				case AIMap.GetTileIndex(-1, 2):
					assert(from2_from1 == AIMap.GetTileIndex(-1, 0));
					assert(to2_to1 == AIMap.GetTileIndex(0, -1));
					return SegmentDir.SE_W_SW;
			}

		case AIMap.GetTileIndex(-1, 1):
			switch (from2_to2) {
				case AIMap.GetTileIndex(-1, 1):
					switch (from2_from1) {
						case AIMap.GetTileIndex(-1, 0):
							assert(to2_to1 == AIMap.GetTileIndex(-1, 0));
							return SegmentDir.SE_W_NW;
						case AIMap.GetTileIndex(0, -1):
							assert(to2_to1 == AIMap.GetTileIndex(0, -1));
							return SegmentDir.NE_W_SW;
					}
			}

		case AIMap.GetTileIndex(1, 2):
			switch (from2_to2) {
				case AIMap.GetTileIndex(0, 1):
					assert(from2_from1 == AIMap.GetTileIndex(-1, 0));
					assert(to2_to1 == AIMap.GetTileIndex(0, 1));
					return SegmentDir.SE_N_NE;
			}

		case AIMap.GetTileIndex(-1, 0):
			switch (from2_to2) {
				case AIMap.GetTileIndex(-1, 0):
					assert(from2_from1 == AIMap.GetTileIndex(0, -1));
					assert(to2_to1 == AIMap.GetTileIndex(0, -1));
					return SegmentDir.NE_SW;
				case AIMap.GetTileIndex(-2, -1):
					assert(from2_from1 == AIMap.GetTileIndex(0, -1));
					assert(to2_to1 == AIMap.GetTileIndex(1, 0));
					return SegmentDir.NE_S_SE;
			}

		case AIMap.GetTileIndex(-1, -1):
			switch (from2_to2) {
				case AIMap.GetTileIndex(-1, -1):
					switch (from2_from1) {
						case AIMap.GetTileIndex(0, -1):
							assert(to2_to1 == AIMap.GetTileIndex(0, -1));
							return SegmentDir.NE_S_SW;
						case AIMap.GetTileIndex(1, 0):
							assert(to2_to1 == AIMap.GetTileIndex(1, 0));
							return SegmentDir.NW_S_SE;
					}
			}

		case AIMap.GetTileIndex(-2, 1):
			switch (from2_to2) {
				case AIMap.GetTileIndex(-1, 0):
					assert(from2_from1 == AIMap.GetTileIndex(0, -1));
					assert(to2_to1 == AIMap.GetTileIndex(-1, 0));
					return SegmentDir.NE_W_NW;
			}

		case AIMap.GetTileIndex(0, -1):
			switch (from2_to2) {
				case AIMap.GetTileIndex(0, -1):
					assert(from2_from1 == AIMap.GetTileIndex(1, 0));
					assert(to2_to1 == AIMap.GetTileIndex(1, 0));
					return SegmentDir.NW_SE;
				case AIMap.GetTileIndex(1, -2):
					assert(from2_from1 == AIMap.GetTileIndex(1, 0));
					assert(to2_to1 == AIMap.GetTileIndex(0, 1));
					return SegmentDir.NW_E_NE;
			}

		case AIMap.GetTileIndex(-1, -2):
			switch (from2_to2) {
				case AIMap.GetTileIndex(0, -1):
					assert(from2_from1 == AIMap.GetTileIndex(1, 0));
					assert(to2_to1 == AIMap.GetTileIndex(0, -1));
					return SegmentDir.NW_S_SW;
			}
	}
}

function DoubleRail::_GetSegmentDirection(segment, j)
{
	return 1 << (j * 24 + segment.m_segment_dir);
}

function DoubleRail::_GetNodeID(segment, j, i)
{
	return 1 << (j * 32 + i);
}

class Segment extends DoubleRail {
	m_segment_dir = null;
	m_neighbours = null;
	m_nodes = null;
//	m_offsets = null
//	m_dir_from = null;
//	m_dir_to = null;

	constructor(prev_nodes, segment_dir, is_goal_segment = false) {
		m_segment_dir = segment_dir;
		m_neighbours = GetNeighbours(segment_dir);
		m_nodes = typeof(prev_nodes) == "array" ? GetNodes(prev_nodes, segment_dir, is_goal_segment) : GetNextNodes(prev_nodes, segment_dir);
//		m_offsets = GetTilesOffsets(segment_dir);
//		m_dir_from = GetDirFromOffset(segment_dir);
//		m_dir_to = GetDirToOffset(segment_dir);
	}

	function GetName(segment_dir);
	function GetNeighbours(segment_dir);
	function GetTilesOffsets(segment_dir);
	function GetDirFromOffset(segment_dir);
	function GetDirToOffset(segment_dir);
	function GetNodes(prev_tiles, segment_dir);
	function GetNextNodes(path, segment_dir);
	function IsCustomSegment();
	function IsCustomSegmentDir(segment_dir);

	function GetName(segment_dir) {
		switch (segment_dir) {
			case SegmentDir.SW_NE: return "SW_NE";
			case SegmentDir.SW_N_NE: return "SW_N_NE";
			case SegmentDir.SW_E_NE: return "SW_E_NE";
			case SegmentDir.SW_N_NW: return "SW_N_NW";
			case SegmentDir.SW_E_SE: return "SW_E_SE";
			case SegmentDir.SE_NW: return "SE_NW";
			case SegmentDir.SE_W_NW: return "SE_W_NW";
			case SegmentDir.SE_N_NW: return "SE_N_NW";
			case SegmentDir.SE_W_SW: return "SE_W_SW";
			case SegmentDir.SE_N_NE: return "SE_N_NE";
			case SegmentDir.NE_SW: return "NE_SW";
			case SegmentDir.NE_S_SW: return "NE_S_SW";
			case SegmentDir.NE_W_SW: return "NE_W_SW";
			case SegmentDir.NE_S_SE: return "NE_S_SE";
			case SegmentDir.NE_W_NW: return "NE_W_NW";
			case SegmentDir.NW_SE: return "NW_SE";
			case SegmentDir.NW_E_SE: return "NW_E_SE";
			case SegmentDir.NW_S_SE: return "NW_S_SE";
			case SegmentDir.NW_E_NE: return "NW_E_NE";
			case SegmentDir.NW_S_SW: return "NW_S_SW";
			case SegmentDir.SW_NE_CUSTOM: return "SW_NE_CUSTOM";
			case SegmentDir.SE_NW_CUSTOM: return "SE_NW_CUSTOM";
			case SegmentDir.NE_SW_CUSTOM: return "NE_SW_CUSTOM";
			case SegmentDir.NW_SE_CUSTOM: return "NW_SE_CUSTOM";
		}
	}

	function GetNeighbours(segment_dir) {
		switch (segment_dir) {
			case SegmentDir.SW_NE:
			case SegmentDir.SW_N_NE:
			case SegmentDir.SW_E_NE:
			case SegmentDir.NW_E_NE:
			case SegmentDir.SE_N_NE:
			case SegmentDir.SW_NE_CUSTOM:
				return [SegmentDir.SW_NE, SegmentDir.SW_N_NE, SegmentDir.SW_E_NE, SegmentDir.SW_N_NW, SegmentDir.SW_E_SE, SegmentDir.SW_NE_CUSTOM];

			case SegmentDir.SE_NW:
			case SegmentDir.SE_W_NW:
			case SegmentDir.SE_N_NW:
			case SegmentDir.SW_N_NW:
			case SegmentDir.NE_W_NW:
			case SegmentDir.SE_NW_CUSTOM:
				return [SegmentDir.SE_NW, SegmentDir.SE_W_NW, SegmentDir.SE_N_NW, SegmentDir.SE_W_SW, SegmentDir.SE_N_NE, SegmentDir.SE_NW_CUSTOM];

			case SegmentDir.NE_SW:
			case SegmentDir.NE_S_SW:
			case SegmentDir.NE_W_SW:
			case SegmentDir.SE_W_SW:
			case SegmentDir.NW_S_SW:
			case SegmentDir.NE_SW_CUSTOM:
				return [SegmentDir.NE_SW, SegmentDir.NE_S_SW, SegmentDir.NE_W_SW, SegmentDir.NE_S_SE, SegmentDir.NE_W_NW, SegmentDir.NE_SW_CUSTOM];

			case SegmentDir.NW_SE:
			case SegmentDir.NW_E_SE:
			case SegmentDir.NW_S_SE:
			case SegmentDir.NE_S_SE:
			case SegmentDir.SW_E_SE:
			case SegmentDir.NW_SE_CUSTOM:
				return [SegmentDir.NW_SE, SegmentDir.NW_E_SE, SegmentDir.NW_S_SE, SegmentDir.NW_E_NE, SegmentDir.NW_S_SW, SegmentDir.NW_SE_CUSTOM];

		}
	}

	function GetTilesOffsets(segment_dir) {
		switch(segment_dir) {
			case SegmentDir.SW_NE:
				return [[AIMap.GetTileIndex(-1, 0)],
						[AIMap.GetTileIndex(-1, 0)]];

			case SegmentDir.SW_N_NE:
				return [[AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(-1, -1)],
						[AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(-1, -1)]];

			case SegmentDir.SW_E_NE:
				return [[AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(-1, 1)],
						[AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(-1, 1)]];

			case SegmentDir.SW_N_NW:
				return [[AIMap.GetTileIndex(-1, 0)],
						[AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(-1, -1), AIMap.GetTileIndex(-2, -1)]];

			case SegmentDir.SW_E_SE:
				return [[AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(-1, 1), AIMap.GetTileIndex(-2, 1)],
						[AIMap.GetTileIndex(-1, 0)]];

			case SegmentDir.SE_NW:
				return [[AIMap.GetTileIndex(0, -1)],
						[AIMap.GetTileIndex(0, -1)]];

			case SegmentDir.SE_W_NW:
				return [[AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(1, -1)],
						[AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(1, -1)]];

			case SegmentDir.SE_N_NW:
				return [[AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(-1, -1)],
						[AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(-1, -1)]];

			case SegmentDir.SE_W_SW:
				return [[AIMap.GetTileIndex(0, -1)],
						[AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(1, -1), AIMap.GetTileIndex(1, -2)]];

			case SegmentDir.SE_N_NE:
				return [[AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(-1, -1), AIMap.GetTileIndex(-1, -2)],
						[AIMap.GetTileIndex(0, -1)]];

			case SegmentDir.NE_SW:
				return [[AIMap.GetTileIndex(1, 0)],
						[AIMap.GetTileIndex(1, 0)]];

			case SegmentDir.NE_S_SW:
				return [[AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(1, 1)],
						[AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(1, 1)]];

			case SegmentDir.NE_W_SW:
				return [[AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(1, -1)],
						[AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(1, -1)]];

			case SegmentDir.NE_S_SE:
				return [[AIMap.GetTileIndex(1, 0)],
						[AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(1, 1), AIMap.GetTileIndex(2, 1)]];

			case SegmentDir.NE_W_NW:
				return [[AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(1, -1), AIMap.GetTileIndex(2, -1)],
						[AIMap.GetTileIndex(1, 0)]];

			case SegmentDir.NW_SE:
				return [[AIMap.GetTileIndex(0, 1)],
						[AIMap.GetTileIndex(0, 1)]];

			case SegmentDir.NW_E_SE:
				return [[AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(-1, 1)],
						[AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(-1, 1)]];

			case SegmentDir.NW_S_SE:
				return [[AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(1, 1)],
						[AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(1, 1)]];

			case SegmentDir.NW_E_NE:
				return [[AIMap.GetTileIndex(0, 1)],
						[AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(-1, 1), AIMap.GetTileIndex(-1, 2)]];

			case SegmentDir.NW_S_SW:
				return [[AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(1, 1), AIMap.GetTileIndex(1, 2)],
						[AIMap.GetTileIndex(0, 1)]];

		}
	}

	function GetDirFromOffset(segment_dir) {
		switch (segment_dir) {
			case SegmentDir.SW_NE:
			case SegmentDir.SW_N_NE:
			case SegmentDir.SW_E_NE:
			case SegmentDir.SW_N_NW:
			case SegmentDir.SW_E_SE:
			case SegmentDir.SW_NE_CUSTOM:
				return AIMap.GetTileIndex(1, 0);

			case SegmentDir.SE_NW:
			case SegmentDir.SE_W_NW:
			case SegmentDir.SE_N_NW:
			case SegmentDir.SE_W_SW:
			case SegmentDir.SE_N_NE:
			case SegmentDir.SE_NW_CUSTOM:
				return AIMap.GetTileIndex(0, 1);

			case SegmentDir.NE_SW:
			case SegmentDir.NE_S_SW:
			case SegmentDir.NE_W_SW:
			case SegmentDir.NE_S_SE:
			case SegmentDir.NE_W_NW:
			case SegmentDir.NE_SW_CUSTOM:
				return AIMap.GetTileIndex(-1, 0);

			case SegmentDir.NW_SE:
			case SegmentDir.NW_E_SE:
			case SegmentDir.NW_S_SE:
			case SegmentDir.NW_E_NE:
			case SegmentDir.NW_S_SW:
			case SegmentDir.NW_SE_CUSTOM:
				return AIMap.GetTileIndex(0, -1);
		}
	}

	function GetDirToOffset(segment_dir) {
		switch (segment_dir) {
			case SegmentDir.SW_NE:
			case SegmentDir.SW_N_NE:
			case SegmentDir.SW_E_NE:
			case SegmentDir.SE_N_NE:
			case SegmentDir.NW_E_NE:
			case SegmentDir.SW_NE_CUSTOM:
				return AIMap.GetTileIndex(-1, 0);

			case SegmentDir.SE_NW:
			case SegmentDir.SE_W_NW:
			case SegmentDir.SE_N_NW:
			case SegmentDir.NE_W_NW:
			case SegmentDir.SW_N_NW:
			case SegmentDir.SE_NW_CUSTOM:
				return AIMap.GetTileIndex(0, -1);

			case SegmentDir.NE_SW:
			case SegmentDir.NE_S_SW:
			case SegmentDir.NE_W_SW:
			case SegmentDir.NW_S_SW:
			case SegmentDir.SE_W_SW:
			case SegmentDir.NE_SW_CUSTOM:
				return AIMap.GetTileIndex(1, 0);

			case SegmentDir.NW_SE:
			case SegmentDir.NW_E_SE:
			case SegmentDir.NW_S_SE:
			case SegmentDir.SW_E_SE:
			case SegmentDir.NE_S_SE:
			case SegmentDir.NW_SE_CUSTOM:
				return AIMap.GetTileIndex(0, 1);
		}
	}

	function GetNodes(prev_tiles, segment_dir, is_goal_segment = false) {
		local nodes = [[], []];
		local offsets = Segment.GetTilesOffsets(segment_dir);

		foreach (j in [0, 1]) {
			assert(prev_tiles[j].len() > 1);
			local prev_tile = prev_tiles[j][prev_tiles[j].len() - (is_goal_segment ? 1 : 2)];
//			if (is_goal_segment) AILog.Info("line = " + (j + 1) + "; prev_tile = " + prev_tile);

			local pre_from;
			if (prev_tiles[j].len() > 2) {
				pre_from = prev_tiles[j][prev_tiles[j].len() - (is_goal_segment ? 2 : 3)];
			} else {
				pre_from = is_goal_segment ? prev_tile - Segment.GetDirToOffset(segment_dir) : null;
			}

			foreach (i, _ in offsets[j]) {
				local tile = prev_tile;
				local to = (i < --offsets[j].len() ? prev_tile + offsets[j][i + 1] : tile + Segment.GetDirToOffset(segment_dir));
//				if (is_goal_segment) AILog.Info("line = " + (j + 1) + "; pre_from = " + pre_from + "; tile = " + tile + "; to = " + to);
				nodes[j].append([to, pre_from == null ? 0 : this._GetDirection(pre_from, tile, to, false), [], tile, this._GetSegmentDirection(this, j), this._GetNodeID(this, j, i)]);
				pre_from = tile;
			}
		}

//		foreach (j, line in nodes) {
//			foreach (i, val in line) {
//				if (is_goal_segment) AILog.Info("line = " + (j + 1) + "; node = " + i + "; to = " + val[0] + "; dir = " + val[1] + "; used_tiles.len() = " + val[2].len() + "; tile = " + val[3] + "; segment_dir = " + val[4] + "; node_id = " + val[5]);
//			}
//		}

		return nodes;
	}

	function GetNextNodes(path, segment_dir) {
		local nodes = [[], []];

		if (Segment.IsCustomSegmentDir(segment_dir)) {
			return nodes;
		}

		local cur_nodes = path._segment.m_nodes;
		local offsets = Segment.GetTilesOffsets(segment_dir);

		for (local j = 0; j < cur_nodes.len() ; j++) {
			local pre_from = cur_nodes[j].top()[3];
			foreach (i, offset in offsets[j]) {
				local tile = cur_nodes[j].top()[3] + offset;
				local to = (i < --offsets[j].len() ? cur_nodes[j].top()[3] + offsets[j][i + 1] : tile + Segment.GetDirToOffset(segment_dir));
//				AILog.Info("line = " + (j + 1) + "; pre_from = " + pre_from + "; tile = " + tile + "; to = " + to);
				nodes[j].append([to, this._GetDirection(pre_from, tile, to, false), [], tile, this._GetSegmentDirection(this, j), this._GetNodeID(this, j, i)]);
				pre_from = tile;
			}
		}

//		foreach (j, line in nodes) {
//			foreach (i, val in line) {
//				AILog.Info("line = " + (j + 1) + "; node = " + i + "; to = " + val[0] + "; dir = " + val[1] + "; used_tiles.len() = " + val[2].len() + "; tile = " + val[3] + "; segment_dir = " + val[4] + "; node_id = " + val[5]);
//			}
//		}

		return nodes;
	}

	function IsCustomSegment() {
		return this.m_segment_dir >= SegmentDir.SW_NE_CUSTOM;
	}

	function IsCustomSegmentDir(segment_dir) {
		return segment_dir >= SegmentDir.SW_NE_CUSTOM;
	}
}
