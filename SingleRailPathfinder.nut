require("SingleRailAyStar.nut");

/**
 * A SingleRail Pathfinder.
 */
class SingleRail
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
		if (this._search_range) {
			local pair = [];
			local min_freeform = AIMap.IsValidTile(0) ? 0 : 1;

			foreach (source in sources) {
				foreach (goal in goals) {
					local distance = AIMap.DistanceManhattan(source[1], goal[1]);
					pair.append([source[1], goal[1], distance]);

					local source_x = AIMap.GetTileX(source[1]);
					local source_y = AIMap.GetTileY(source[1]);
					local goal_x = AIMap.GetTileX(goal[1]);
					local goal_y = AIMap.GetTileY(goal[1]);

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

		local nsources = [];
		foreach (node in sources) {
			local path = null;
			local n = node.len();
			foreach (i, tile in node) {
				path = this._pathfinder.Path(path, node[n - 1 - i], n - i > 2 ? 0 : 0xFFFFF, [], this._Cost, this);
			}
			nsources.push(path);
		}
		this._goals = goals;
		this._pathfinder.InitializePath(nsources, goals, ignored_tiles);
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

class SingleRail.Cost
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

function SingleRail::FindPath(iterations)
{
	local test_mode = AITestMode();
	local ret = this._pathfinder.FindPath(iterations);
	this._running = (ret == false) ? true : false;
	return ret;
}

function SingleRail::_IsSlopedBridge(end_a, end_b, end)
{
	local direction;
	local slope;
	if (end == end_a) {
		direction = (end_b - end_a) / AIMap.DistanceManhattan(end_a, end_b);
		slope = AITile.GetSlope(end_a);
	} else if (end == end_b) {
		direction = (end_a - end_b) / AIMap.DistanceManhattan(end_b, end_a);
		slope = AITile.GetSlope(end_b);
	} else {
		throw "end " + end + "must match either end_a or end_b in _IsSlopedBridge";
	}

	return !(((slope == AITile.SLOPE_NE || slope == AITile.SLOPE_STEEP_N || slope == AITile.SLOPE_STEEP_E) && direction == 1) ||
			((slope == AITile.SLOPE_SE || slope == AITile.SLOPE_STEEP_S || slope == AITile.SLOPE_STEEP_E) && direction == -AIMap.GetMapSizeX()) ||
			((slope == AITile.SLOPE_SW || slope == AITile.SLOPE_STEEP_S || slope == AITile.SLOPE_STEEP_W) && direction == -1) ||
			((slope == AITile.SLOPE_NW || slope == AITile.SLOPE_STEEP_N || slope == AITile.SLOPE_STEEP_W) && direction == AIMap.GetMapSizeX()) ||
			slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W);
}

function SingleRail::_GetBridgeNumSlopes(end_a, end_b, res = false)
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

function SingleRail::_Cost(self, path, new_tile, new_direction)
{
	/* path == null means this is the first node of a path, so the cost is 0. */
	if (path == null) return 0;

	if (self._search_range) {
		local cur_tile_x = AIMap.GetTileX(new_tile);
		local cur_tile_y = AIMap.GetTileY(new_tile);
		if (cur_tile_x < self._min_x || cur_tile_x > self._max_x || cur_tile_y < self._min_y || cur_tile_y > self._max_y) return self._max_cost;
		if (abs(self._a * cur_tile_x + self._b * cur_tile_y + self._c) / self._sqrt > self._search_range) return self._max_cost;
	}

	local prev_tile = path._tile;
	local pprev_tile = path._prev != null ? path._prev._tile : 0;
	local ppprev_tile = pprev_tile && path._prev._prev != null ? path._prev._prev._tile : 0;
	local pppprev_tile = ppprev_tile && path._prev._prev._prev != null ? path._prev._prev._prev._tile : 0;
	local dist = AIMap.DistanceManhattan(prev_tile, new_tile);

//	AILog.Warning("---Cost. new_tile = " + new_tile + "; new_direction = " + new_direction);
	/* If the two tiles are more than 1 tile apart, the pathfinder wants a bridge or tunnel
	 *  to be built. */
	if (dist > 1) {
		/* Check if we should build a bridge or a tunnel. */
		local cost = 0;
		if (AITunnel.GetOtherTunnelEnd(prev_tile) == new_tile) {
//			AILog.Info("Cross tunnel. Cost before: " + cost + "; Cost: " + (dist * self._cost_tile + (dist + 1) * self._cost_tunnel_per_tile) + "; Cost After: " + (cost + dist * self._cost_tile + (dist + 1) * self._cost_tunnel_per_tile));
			cost += dist * self._cost_tile + (dist + 1) * self._cost_tunnel_per_tile;
		} else {
//			AILog.Info("Cross bridge, including slopes. Cost before: " + cost + "; Cost: " + (dist * self._cost_tile + (dist + 1) * self._cost_bridge_per_tile + self._GetBridgeNumSlopes(prev_tile, new_tile) * self._cost_slope) + "; Cost After: " + (cost + dist * self._cost_tile + (dist + 1) * self._cost_bridge_per_tile + self._GetBridgeNumSlopes(prev_tile, new_tile) * self._cost_slope));
			cost += dist * self._cost_tile + (dist + 1) * self._cost_bridge_per_tile + self._GetBridgeNumSlopes(prev_tile, new_tile) * self._cost_slope;
			if (AITile.HasTransportType(prev_tile, AITile.TRANSPORT_WATER)) {
//				AILog.Info("Coast prev_tile. Cost before: " + cost + "; Cost: " + (self._cost_coast) + "; Cost After: " + (cost + self._cost_coast));
				cost += self._cost_coast;
			}
			if (AITile.HasTransportType(new_tile, AITile.TRANSPORT_WATER)) {
//				AILog.Info("Coast new_tile. Cost before: " + cost + "; Cost: " + (self._cost_coast) + "; Cost After: " + (cost + self._cost_coast));
				cost += self._cost_coast;
			}
			if (ppprev_tile && pprev_tile && self._IsSlopedBridge(prev_tile, new_tile, prev_tile)) {
				if (AIMap.DistanceManhattan(ppprev_tile, pprev_tile) > 1) {
					if (AITunnel.GetOtherTunnelEnd(ppprev_tile) != pprev_tile && self._IsSlopedBridge(ppprev_tile, pprev_tile, pprev_tile)) {
//						AILog.Info("s1:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//						AILog.Info("Consecutive slope type 1. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_slope) + "; Cost After: " + (cost + self._cost_consecutive_slope));
						cost += self._cost_consecutive_slope;
					}
				} else if (self._IsSlopedRail(ppprev_tile, pprev_tile, prev_tile)) {
//					AILog.Info("s2:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//					AILog.Info("Consecutive slope type 2. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_slope) + "; Cost After: " + (cost + self._cost_consecutive_slope));
					cost += self._cost_consecutive_slope;
				}
			}
		}
		if (pprev_tile && ppprev_tile &&
				(ppprev_tile - pprev_tile) / AIMap.DistanceManhattan(ppprev_tile, pprev_tile) != (prev_tile - new_tile) / dist) {
//			AILog.Info("Turn 45 degrees type 1. Cost before: " + cost + "; Cost: " + (self._cost_turn45) + "; Cost After: " + (cost + self._cost_turn45));
			cost += self._cost_turn45;
			if (pppprev_tile) {
				if (AIMap.DistanceManhattan(prev_tile, pppprev_tile) == 3 && pppprev_tile - ppprev_tile != pprev_tile - prev_tile) {
//					AILog.Info("t1:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//					AILog.Info("Consecutive turn type 1. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_turn) + "; Cost After: " + (cost + self._cost_consecutive_turn));
					cost += self._cost_consecutive_turn;
				} else if (prev_tile - pprev_tile == pppprev_tile - ppprev_tile) {
//					AILog.Info("t2:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//					AILog.Info("Consecutive turn type 2. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_turn) + "; Cost After: " + (cost + self._cost_consecutive_turn));
					cost += self._cost_consecutive_turn;
				} else if (AIMap.DistanceManhattan(pppprev_tile, ppprev_tile) > 1 && (pppprev_tile - ppprev_tile) / AIMap.DistanceManhattan(pppprev_tile, ppprev_tile) != (pprev_tile - prev_tile) / AIMap.DistanceManhattan(pprev_tile, prev_tile)) {
//					AILog.Info("t3:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//					AILog.Info("Consecutive turn type 3. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_turn) + "; Cost After: " + (cost + self._cost_consecutive_turn));
					cost += self._cost_consecutive_turn;
				}
			}
		}
//		AILog.Info("Cost for this node: " + path._cost + " + " + cost + " = " + (path._cost + cost));
		return path._cost + cost;
	}

	/* Check for a turn. We do this by substracting the TileID of the current
	 *  node from the TileID of the previous node and comparing that to the
	 *  difference between the tile before the previous node and the node before
	 *  that. */
	local cost = 0;
	if (pprev_tile) {
		if (AIMap.DistanceManhattan(pprev_tile, prev_tile) == 1 && pprev_tile - prev_tile != prev_tile - new_tile) {
//			AILog.Info("Diagonal tile. Cost before: " + cost + "; Cost: " + (self._cost_diagonal_tile) + "; Cost After: " + (cost + self._cost_diagonal_tile));
			cost += self._cost_diagonal_tile;
		} else {
//			AILog.Info("Tile. Cost before: " + cost + "; Cost: " + (self._cost_tile) + "; Cost After: " + (cost + self._cost_tile));
			cost += self._cost_tile;
		}
	}
	if (pprev_tile && ppprev_tile) {
		local is_turn = false;
		if (AIMap.DistanceManhattan(new_tile, ppprev_tile) == 3 && ppprev_tile - pprev_tile != prev_tile - new_tile) {
//			AILog.Info("Turn 45 degrees type 2. Cost before: " + cost + "; Cost: " + (self._cost_turn45) + "; Cost After: " + (cost + self._cost_turn45));
			cost += self._cost_turn45;
			is_turn = true;
		} else if (new_tile - prev_tile == ppprev_tile - pprev_tile) {
//			AILog.Info("Turn 90 degrees. Cost before: " + cost + "; Cost: " + (self._cost_turn90) + "; Cost After: " + (cost + self._cost_turn90));
			cost += self._cost_turn90;
			is_turn = true;
		} else if (AIMap.DistanceManhattan(ppprev_tile, pprev_tile) > 1 && (ppprev_tile - pprev_tile) / AIMap.DistanceManhattan(ppprev_tile, pprev_tile) != (prev_tile - new_tile) / dist) {
//			AILog.Info("Turn 45 degrees type 3. Cost before: " + cost + "; Cost: " + (self._cost_turn45) + "; Cost After: " + (cost + self._cost_turn45));
			cost += self._cost_turn45;
			is_turn = true;
		}
		if (pppprev_tile && is_turn) {
			if (AIMap.DistanceManhattan(prev_tile, pppprev_tile) == 3 && pppprev_tile - ppprev_tile != pprev_tile - prev_tile) {
//				AILog.Info("t4:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//				AILog.Info("Consecutive turn type 4. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_turn) + "; Cost After: " + (cost + self._cost_consecutive_turn));
				cost += self._cost_consecutive_turn;
			} else if (prev_tile - pprev_tile == pppprev_tile - ppprev_tile) {
//				AILog.Info("t5:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//				AILog.Info("Consecutive turn type 5. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_turn) + "; Cost After: " + (cost + self._cost_consecutive_turn));
				cost += self._cost_consecutive_turn;
			} else if (AIMap.DistanceManhattan(pppprev_tile, ppprev_tile) > 1 && (pppprev_tile - ppprev_tile) / AIMap.DistanceManhattan(pppprev_tile, ppprev_tile) != (pprev_tile - prev_tile) / AIMap.DistanceManhattan(pprev_tile, prev_tile)) {
//				AILog.Info("t6:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//				AILog.Info("Consecutive turn type 6. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_turn) + "; Cost After: " + (cost + self._cost_consecutive_turn));
				cost += self._cost_consecutive_turn;
			}
		}
	}

	/* Check if the new tile is a level crossing. */
	if (AITile.HasTransportType(new_tile, AITile.TRANSPORT_ROAD) || AIRoad.IsRoadTile(new_tile)) {
//		AILog.Info("Level crossing. Cost before: " + cost + "; Cost: " + (self._cost_level_crossing) + "; Cost After: " + (cost + self._cost_level_crossing));
		cost += self._cost_level_crossing;
	}

	/* Check if the last tile was sloped. */
	if (pprev_tile) {
		if (AIMap.DistanceManhattan(pprev_tile, prev_tile) == 1) {
			if (self._IsSlopedRail(pprev_tile, prev_tile, new_tile)) {
//				AILog.Info("Slope type 1. Cost before: " + cost + "; Cost: " + (self._cost_slope) + "; Cost After: " + (cost + self._cost_slope));
				cost += self._cost_slope;
				if (ppprev_tile) {
					if (AIMap.DistanceManhattan(ppprev_tile, pprev_tile) == 1) {
						if (self._IsSlopedRail(ppprev_tile, pprev_tile, prev_tile)) {
//							AILog.Info(s3:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//							AILog.Info("Consecutive slope type 3. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_slope) + "; Cost After: " + (cost + self._cost_consecutive_slope));
							cost += self._cost_consecutive_slope;
						}
					} else if (AITunnel.GetOtherTunnelEnd(ppprev_tile) != pprev_tile && self._IsSlopedBridge(ppprev_tile, pprev_tile, pprev_tile)) {
//						AILog.Info("s4:pppprev_tile = " + pppprev_tile + "; ppprev_tile = " + ppprev_tile + "; pprev_tile = " + pprev_tile + "; prev_tile = " + prev_tile + "; new_tile = " + new_tile);
//						AILog.Info("Consecutive slope type 4. Cost before: " + cost + "; Cost: " + (self._cost_consecutive_slope) + "; Cost After: " + (cost + self._cost_consecutive_slope));
						cost += self._cost_consecutive_slope;
					}
				}
			}
//		} else if (AITunnel.GetOtherTunnelEnd(pprev_tile) != prev_tile && self._IsSlopedBridge(pprev_tile, prev_tile, prev_tile)) {
///			AILog.Info("Slope type 2. Cost before: " + cost + "; Cost: " + (self._cost_slope) + "; Cost After: " + (cost + self._cost_slope));
//			cost += self._cost_slope;
		}
	}

//	AILog.Info("Cost for this node: " + path._cost + " + " + cost + " = " + (path._cost + cost));
	return path._cost + cost;
}

function SingleRail::_Estimate(self, cur_tile, cur_direction, goal_tiles)
{
	local min_cost = self._max_cost;
	/* As estimate we multiply the lowest possible cost for a single tile
	 *  with the minimum number of tiles we need to traverse. */
	foreach (tile in goal_tiles) {
		local dx = abs(AIMap.GetTileX(cur_tile) - AIMap.GetTileX(tile[1]));
		local dy = abs(AIMap.GetTileY(cur_tile) - AIMap.GetTileY(tile[1]));
		min_cost = min(min_cost, min(dx, dy) * self._cost_diagonal_tile * 2 + abs(dx - dy) * self._cost_tile);
	}
	return min_cost * self._estimate_multiplier;
}

function SingleRail::_Neighbours(self, path, cur_node)
{
	if (AITile.HasTransportType(cur_node, AITile.TRANSPORT_RAIL)) return [];
	/* self._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
	if (path._cost >= self._max_cost) return [];
	local tiles = [];
	local offsets = [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(0, -1),
	                 AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(-1, 0)];

	local prev_tile = path._prev != null ? path._prev._tile : 0;
//	local pprev_tile = pprev_tile && path._prev._prev != null ? path._prev._prev._tile : 0;

	local dist = AIMap.DistanceManhattan(cur_node, prev_tile);
	if (prev_tile && dist > 1) {
		local next_tile = cur_node + (cur_node - prev_tile) / dist;
		foreach (offset in offsets) {
			/* Don't turn back */
			if (next_tile + offset == cur_node) continue;
			if (AIRail.BuildRail(cur_node, next_tile, next_tile + offset)) {
				tiles.push([next_tile, self._GetDirection(prev_tile, cur_node, next_tile, true), []]);
				break;
			}
		}
	} else {
		/* Check all tiles adjacent to the current tile. */
		foreach (offset in offsets) {
			local next_tile = cur_node + offset;
			/* Don't turn back */
			if (prev_tile && next_tile == prev_tile) continue;
//			/* Disallow 90 degree turns */
//			if (prev_tile && pprev_tile &&
//					next_tile - cur_node == pprev_tile - prev_tile) continue;
			/* We add them to the to the neighbours-list if we can build a rail to
			 *  them and no rail exists there. */
			if (!prev_tile || AIRail.BuildRail(prev_tile, cur_node, next_tile)) {
				tiles.push([next_tile, self._GetDirection(prev_tile ? prev_tile : null, cur_node, next_tile, false), []]);
			}
		}
		if (prev_tile) {
			/**
			 * Get a list of all bridges and tunnels that can be built from the
			 *  current tile. Tunnels will only be built if no terraforming
			 *  is needed on both ends.
			 */
			local bridge_dir = self._GetDirection(null, prev_tile, cur_node, true);

			for (local i = 2; i < self._max_bridge_length; i++) {
				local target = cur_node + i * (cur_node - prev_tile);
				if (!AIMap.IsValidTile(target)) break; // don't wrap the map
				local bridge_list = AIBridgeList_Length(i + 1);
				if (!bridge_list.IsEmpty() && AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), cur_node, target)) {
					local used_tiles = self._GetUsedTiles(cur_node, target, true);
					if (!self._UsedTileListsConflict(path.GetUsedTiles(), used_tiles)) {
						tiles.push([target, bridge_dir, used_tiles]);
					}
				}
			}

			local slope = AITile.GetSlope(cur_node);
			if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE) {
				local other_tunnel_end = AITunnel.GetOtherTunnelEnd(cur_node);
				if (AIMap.IsValidTile(other_tunnel_end)) {

					local tunnel_length = AIMap.DistanceManhattan(cur_node, other_tunnel_end);
					local tile_before = cur_node + (cur_node - other_tunnel_end) / tunnel_length;
					if (AITunnel.GetOtherTunnelEnd(other_tunnel_end) == cur_node && tunnel_length >= 2 &&
							tile_before == prev_tile && tunnel_length < self._max_tunnel_length && AITunnel.BuildTunnel(AIVehicle.VT_RAIL, cur_node)) {
						local used_tiles = self._GetUsedTiles(cur_node, other_tunnel_end, false);
						if (!self._UsedTileListsConflict(path.GetUsedTiles(), used_tiles)) {
							tiles.push([other_tunnel_end, bridge_dir, used_tiles]);
						}
					}
				}
			}
		}
	}
	return tiles;
}

function SingleRail::_CheckDirection(self, is_neighbour, existing_direction, new_direction)
{
//	local trackdir_left_n = 1 << 6;   // 64
//	local trackdir_left_s = 1 << 17;  // 131072
//	local trackdir_lower_e = 1 << 7;  // 128
//	local trackdir_lower_w = 1 << 13; // 8192
//	local trackdir_upper_w = 1 << 10; // 1024
//	local trackdir_upper_e = 1 << 16; // 65536
//	local trackdir_right_s = 1 << 11; // 2048
//	local trackdir_right_n = 1 << 12; // 4096

//	local track_left = trackdir_left_n | trackdir_left_s;    // 131136
//	local track_lower = trackdir_lower_e | trackdir_lower_w; // 8320
//	local track_upper = trackdir_upper_w | trackdir_upper_e; // 66560
//	local track_right = trackdir_right_s | trackdir_right_n; // 6144

//	local trackdir_3way_ne = (1 << 4) | (1 << 12) | (1 << 16); // 69648
//	local trackdir_3way_nw = (1 << 6) | (1 << 10) | (1 << 14); // 17472
//	local trackdir_3way_se = (1 << 7) | (1 << 11) | (1 << 19); // 526464
//	local trackdir_3way_sw = (1 << 9) | (1 << 13) | (1 << 17); // 139776

//	/* Allowed combinations */
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

	/* Allowed combinations */
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

function SingleRail::_dir(from, to)
{
	if (from - to == 1) return 0;
	if (from - to == -1) return 1;
	if (from - to == AIMap.GetMapSizeX()) return 2;
	if (from - to == -AIMap.GetMapSizeX()) return 3;
	throw("Shouldn't come here in _dir");
}

function SingleRail::_GetDirection(pre_from, from, to, is_bridge)
{
	if (is_bridge) {
		if (from - to == 1) return 1;
		if (from - to == -1) return 2;
		if (from - to == AIMap.GetMapSizeX()) return 4;
		if (from - to == -AIMap.GetMapSizeX()) return 8;
	}
	return 1 << (4 + (pre_from == null ? 0 : 4 * this._dir(pre_from, from)) + this._dir(from, to));
}

function SingleRail::_IsSlopedRail(start, middle, end)
{
	local NW = middle - AIMap.GetMapSizeX();
	local NE = middle - 1;
	local SE = middle + AIMap.GetMapSizeX();
	local SW = middle + 1;

	NW = NW == start || NW == end; // Set to true if we want to build a rail to / from the north-west
	NE = NE == start || NE == end; // Set to true if we want to build a rail to / from the north-east
	SE = SE == start || SE == end; // Set to true if we want to build a rail to / from the south-west
	SW = SW == start || SW == end; // Set to true if we want to build a rail to / from the south-east

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

/**
 * Get the tiles that become used when planning to build
 *  a bridge or a tunnel to help prevent crossings with
 *  other planned bridges or tunnels.
 * @param from Tile where the bridge or tunnel starts.
 * @param to Tile where the bridge or tunnel ends.
 * @param is_bridge Whether we're planning a bridge or a tunnel.
 * @return A list of used tiles with their respective bits.
 */
function SingleRail::_GetUsedTiles(from, to, is_bridge)
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
function SingleRail::_UsedTileListsConflict(prev_used_list, used_list)
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
