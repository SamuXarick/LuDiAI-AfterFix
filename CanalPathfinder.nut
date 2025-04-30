/**
 * A Canal Pathfinder. It can plan canals, aqueducts and locks. Does not plan buoys.
 *  Tries its best to keep previously built canal routes traversable.
 *
 *  Tips:
 *  - If you don't want to plan for aqueducts, set max_aqueduct_length to 0.
 *  - If you only want to check if a connection already exists by water, set no_existing_water the same as max_cost.
 *  - When specifying source and goal, tiles may be without water, as long as canals can be planned there.
 *
 *  Notes:
 *  - Does not include a BuildPath function. You have to create such function yourself in your Script.
 *  - The pathfinder is able to plan two tile sized aqueducts. The function '_CheckAqueductSlopes' contained in here
 *    is of special interest, as it handles this particular situation. You may have to mimic it in your AI when
 *    building the path.
 */
require("CanalAyStar.nut");
class Canal
{
	_aystar_class = AyStar;
	_pathfinder = null;             ///< A reference to the used AyStar object.
	_running = null;
	cost = null;                    ///< Used to change the costs.

	_max_cost = null;               ///< The maximum cost for a route.
	_cost_tile = null;              ///< The cost for walking a single tile.
	_cost_no_existing_water = null; ///< The cost that is added to _cost_tile if no water exists yet.
	_cost_diagonal_tile = null;     ///< The cost for walking a diagonal tile.
	_cost_turn45 = null;            ///< The cost that is added to _cost_tile if the direction changes 45 degrees.
	_cost_turn90 = null;            ///< The cost that is added to _cost_tile if the direction changes 90 degrees.
	_cost_aqueduct_per_tile = null; ///< The cost per tile of a new aqueduct, this is added to _cost_tile.
	_cost_lock = null;              ///< The cost for a new lock, this is added to _cost_tile.
	_cost_depot = null;             ///< The cost for an existing depot, this is added to _cost_tile.
	_max_aqueduct_length = null;    ///< The maximum length of an aqueduct that will be build.
	_estimate_multiplier = null;    ///< Every estimate is multiplied by this value. Use 1 for a 'perfect' route, higher values for faster pathfinding.
	_search_range = null;           ///< Range to search around source and destination, in either coordinate. 0 indicates unlimited.

	_a = null;
	_b = null;
	_c = null;
	_sqrt = null;
	_min_x = null;
	_max_x = null;
	_min_y = null;
	_max_y = null;

	/* Useful constants */
	_offsets = [AIMap.GetMapSizeX(), -AIMap.GetMapSizeX(), 1, -1];
	_map_size_x = AIMap.GetMapSizeX();
	_map_size = AIMap.GetMapSize();

	constructor()
	{
		this._pathfinder = this._aystar_class(this, this._Cost, this._Estimate, this._Neighbours, this._CheckDirection);
		this._running = false;
		this.cost = this.Cost(this);

		this._max_cost = 10000000;
		this._cost_tile = 100;
		this._cost_no_existing_water = 200;
		this._cost_diagonal_tile = 70;
		this._cost_turn45 = 100;
		this._cost_turn90 = 600;
		this._cost_aqueduct_per_tile = 400;
		this._cost_lock = 925;
		this._cost_depot = 150;
		this._max_aqueduct_length = 6;
		this._estimate_multiplier = 1;
		this._search_range = 0;
	}

	/**
	 * Initialize a path search between sources and goals.
	 * @param sources The source tiles.
	 * @param goals The target tiles.
	 * @param ignored_tiles An array of tiles that cannot occur in the final path.
	 * @see AyStar::InitializePath()
	 */
	function InitializePath(sources, goals, ignored_tiles = [])
	{
		local nsources = [];
		foreach (node in sources) {
			nsources.push([node, 0xFF, []]);
		}
		this._pathfinder.InitializePath(nsources, goals, ignored_tiles);
		if (this._search_range) {
			local pair = [];
			local min_freeform = AIMap.IsValidTile(0) ? 0 : 1;

			foreach (source in sources) {
				foreach (goal in goals) {
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

			local best_distance = this._map_size;
			local best_source = AIMap.TILE_INVALID;
			local best_goal = AIMap.TILE_INVALID;
			for (local i = 0; i < pair.len(); i++) {
				if (pair[i][2] < best_distance) {
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
	 *  aborts immediately and will never find a path.
	 * @return A route if one was found, or false if the amount of iterations was
	 *  reached, or null if no path was found.
	 *  You can call this function over and over as long as it returns false,
	 *  which is an indication it is not yet done looking for a route.
	 * @see AyStar::FindPath()
	 */
	function FindPath(iterations);
};

class Canal.Cost
{
	_main = null;

	function _set(idx, val)
	{
		if (this._main._running) throw("You are not allowed to change parameters of a running pathfinder.");

		switch (idx) {
			case "max_cost":            this._main._max_cost = val; break;
			case "tile":                this._main._cost_tile = val; break;
			case "no_existing_water":   this._main._cost_no_existing_water = val; break;
			case "diagonal_tile":       this._main._cost_diagonal_tile = val; break;
			case "turn45":              this._main._cost_turn45 = val; break;
			case "turn90":              this._main._cost_turn90 = val; break;
			case "aqueduct_per_tile":   this._main._cost_aqueduct_per_tile = val; break;
			case "lock":                this._main._cost_lock = val; break;
			case "depot":               this._main._cost_depot = val; break;
			case "max_aqueduct_length": this._main._max_aqueduct_length = val; break;
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
			case "no_existing_water":   return this._main._cost_no_existing_water;
			case "diagonal_tile":       return this._main._cost_diagonal_tile;
			case "turn45":              return this._main._cost_turn45;
			case "turn90":              return this._main._cost_turn90;
			case "aqueduct_per_tile":   return this._main._cost_aqueduct_per_tile;
			case "lock":                return this._main._cost_lock;
			case "depot":               return this._main._cost_depot;
			case "max_aqueduct_length": return this._main._max_aqueduct_length;
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

function Canal::FindPath(iterations)
{
	local test_mode = AITestMode();
	local ret = this._pathfinder.FindPath(iterations);
	this._running = (ret == false) ? true : false;
	return ret;
}

function Canal::_Cost(self, path, new_tile, new_direction)
{
	/* path == null means this is the first node of a path, so the cost is 0. */
	if (path == null) return 0;

	if (self._search_range) {
		local cur_tile_x = AIMap.GetTileX(new_tile);
		local cur_tile_y = AIMap.GetTileY(new_tile);
		if (cur_tile_x < self._min_x || cur_tile_x > self._max_x || cur_tile_y < self._min_y || cur_tile_y > self._max_y) return path._cost += self._max_cost;
		if (abs(self._a * cur_tile_x + self._b * cur_tile_y + self._c) / self._sqrt > self._search_range) return path._cost += self._max_cost;
	}

	local prev_tile = path._tile;
	local path_prev = path._prev;
	local path_prev_tile = path_prev == null ? null : path_prev._tile;
//	AILog.Info("-Cost, prev_tile: " + prev_tile + " new_tile: " + new_tile);

	/* If the new tile is an aqueduct, check whether we came from the other
	 *  end of the aqueduct or if we just entered the aqueduct. */
	if (self._IsAqueductTile(new_tile)) {
		if (AIBridge.GetOtherBridgeEnd(new_tile) != prev_tile) {
			local cost = 0;
			if (path_prev != null && AIMap.DistanceManhattan(path_prev_tile, prev_tile) == 1 && path_prev_tile - prev_tile != prev_tile - new_tile) {
				cost = self._cost_diagonal_tile;
//				AILog.Info("Enter aqueduct. Cost for a diagonal tile, Before: " + path._cost + " After: " + (path._cost + cost));
			} else {
				cost = self._cost_tile;
//				AILog.Info("Enter aqueduct. Cost for a tile, Before: " + path._cost + " After: " + (path._cost + cost));
			}
			if (path_prev != null && AIMap.DistanceManhattan(path_prev_tile, prev_tile) == 1 && path_prev_tile - prev_tile != prev_tile - new_tile) {
//				AILog.Info("Enter aqueduct. Check for a 45 degrees turn, Before: " + (path._cost + cost) + " After: " + (path._cost + cost + self._cost_turn45));
				cost += self._cost_turn45;
			}
			return path._cost + cost;
		}
//		AILog.Info("Cross aqueduct, Before: " + path._cost + " After: " + (path._cost + AIMap.DistanceManhattan(new_tile, prev_tile) * self._cost_tile));
		return path._cost + AIMap.DistanceManhattan(new_tile, prev_tile) * self._cost_tile;
	}

	/* If the new tile is a lock, check whether we came from the other
	 *  end of the lock or if we just entered the lock. */
	if (self._IsLockEntryExit(new_tile)) {
		if (self._GetOtherLockEnd(new_tile) != prev_tile) {
			local cost = 0;
			if (path_prev != null && AIMap.DistanceManhattan(path_prev_tile, prev_tile) == 1 && path_prev_tile - prev_tile != prev_tile - new_tile) {
				cost = self._cost_diagonal_tile;
//				AILog.Info("Enter lock. Cost for a diagonal tile, Before: " + path._cost + " After: " + (path._cost + cost));
			} else {
				cost = self._cost_tile;
//				AILog.Info("Enter lock. Cost for a tile, Before: " + path._cost + " After: " + (path._cost + cost));
			}
			if (path_prev != null && AIMap.DistanceManhattan(path_prev_tile, prev_tile) == 1 && path_prev_tile - prev_tile != prev_tile - new_tile) {
//				AILog.Info("Enter lock. Check for a 45 degrees turn, Before: " + (path._cost + cost) + " After: " + (path._cost + cost + self._cost_turn45));
				cost += self._cost_turn45;
			}
			return path._cost + cost;
		}
//		AILog.Info("Cross lock, Before: " + path._cost + " After: " + (path._cost + AIMap.DistanceManhattan(new_tile, prev_tile) * self._cost_tile));
		return path._cost + AIMap.DistanceManhattan(new_tile, prev_tile) * self._cost_tile;
	}

	/* If the new tile is a depot, check whether we came from the other
	 *  end of the depot or if we just entered the depot. */
	if (AIMarine.IsWaterDepotTile(new_tile)) {
		if (self._GetOtherDepotTile(new_tile) != prev_tile) {
			local cost = 0;
			if (path_prev != null && AIMap.DistanceManhattan(path_prev_tile, prev_tile) == 1 && path_prev_tile - prev_tile != prev_tile - new_tile) {
				cost = self._cost_diagonal_tile;
//				AILog.Info("Enter depot. Cost for a diagonal tile, Before: " + path._cost + " After: " + (path._cost + cost));
			} else {
				cost = self._cost_tile;
//				AILog.Info("Enter depot. Cost for a tile, Before: " + path._cost + " After: " + (path._cost + cost));
			}
			if (path_prev != null && AIMap.DistanceManhattan(path_prev_tile, prev_tile) == 1 && path_prev_tile - prev_tile != prev_tile - new_tile) {
//				AILog.Info("Enter depot. Check for a 45 degrees turn, Before: " + (path._cost + cost) + " After: " + (path._cost + cost + self._cost_turn45));
				cost += self._cost_turn45;
			}
			return path._cost + cost;
		}
//		AILog.Info("Cross depot, Before: " + path._cost + " After: " + (path._cost + AIMap.DistanceManhattan(new_tile, prev_tile) * self._cost_tile + self._cost_depot));
		return path._cost + AIMap.DistanceManhattan(new_tile, prev_tile) * self._cost_tile + self._cost_depot;
	}

	/* If the two tiles are 1 tile apart and are sloped, or more than 1 tile apart, the pathfinder wants an aqueduct
	 *  to be built. It isn't an existing aqueduct, as that case is already handled. */
	if (AIMap.DistanceManhattan(new_tile, prev_tile) > 1 || AIMap.DistanceManhattan(new_tile, prev_tile) == 1 && self._CheckAqueductSlopes(prev_tile, new_tile)) {
		local cost = path._cost;
		/* If the tiles are exactly 2 tiles apart and both are flat, the pathfinder wants a lock
		 *  to be build. It isn't and existing lock, as that case is already handled. */
		if (AIMap.DistanceManhattan(new_tile, prev_tile) == 2 && self._IsFlatTile(new_tile) && self._IsFlatTile(prev_tile)) {
//			AILog.Info("Build lock. Cross lock, Before: " + cost + " After: " + (cost + 2 * self._cost_tile + self._cost_lock));
			cost += 2 * self._cost_tile + self._cost_lock;
		} else {
//			AILog.Info("Build aqueduct. Cross aqueduct, Before: " + cost + " After: " + (cost + AIMap.DistanceManhattan(new_tile, prev_tile) * (self._cost_tile + self._cost_aqueduct_per_tile) + self._cost_aqueduct_per_tile));
			cost += AIMap.DistanceManhattan(new_tile, prev_tile) * (self._cost_tile + self._cost_aqueduct_per_tile) + self._cost_aqueduct_per_tile;
		}
		if (path_prev != null && path_prev._prev != null) {
			local next_tile = prev_tile + (new_tile - prev_tile) / AIMap.DistanceManhattan(new_tile, prev_tile);
			if (AIMap.DistanceManhattan(next_tile, path_prev._prev._tile) == 3 &&
					path_prev._prev._tile - path_prev_tile != prev_tile - next_tile) {
//				AILog.Info("Build aqueduct or lock. Check for a 45 degrees turn, Before: " + cost + " After: " + (cost + self._cost_turn45));
				cost += self._cost_turn45;
			}
		}
		return cost;
	}

	/* Check for a turn. We do this by substracting the TileID of the current
	 *  node from the TileID of the previous node and comparing that to the
	 *  difference between the tile before the previous node and the node before
	 *  that. */
	local cost = 0;
	if (path_prev != null && AIMap.DistanceManhattan(path_prev_tile, prev_tile) == 1 && path_prev_tile - prev_tile != prev_tile - new_tile) {
		cost = self._cost_diagonal_tile;
//		AILog.Info("Cost for a diagonal tile, Before: " + path._cost + " After: " + (path._cost + cost));
	} else {
		cost = self._cost_tile;
//		AILog.Info("Cost for a tile, Before: " + path._cost + " After: " + (path._cost + cost));
	}
	if (path_prev != null && path_prev._prev != null &&
			AIMap.DistanceManhattan(new_tile, path_prev._prev._tile) == 3 &&
			path_prev._prev._tile - path_prev_tile != prev_tile - new_tile) {
//		AILog.Info("Check for a 45 degrees turn, Before: " + (path._cost + cost) + " After: " + (path._cost + cost + self._cost_turn45));
		cost += self._cost_turn45;
	}

	/* Chek for a 90 degrees turn */
	if (path_prev != null && path_prev._prev != null &&
			new_tile - prev_tile == path_prev._prev._tile - path_prev_tile) {
//		AILog.Info("Check for a 90 degrees turn, Before: " + (path._cost + cost) + " After: " + (path._cost + cost + self._cost_turn90));
		cost += self._cost_turn90;
	}

	/* Check for no existing water */
	if (path_prev != null && !AIMarine.AreWaterTilesConnected(prev_tile, new_tile)) {
//		AILog.Info("Check for no existing water, Before: " + (path._cost + cost) + " After: " + (path._cost + cost + self._cost_no_existing_water));
		cost += self._cost_no_existing_water;
	}

	return path._cost + cost;
}

function Canal::_Estimate(self, cur_tile, cur_direction, goal_tiles)
{
	local min_cost = self._max_cost;
	/* As estimate we multiply the lowest possible cost for a single tile
	 *  with the minimum number of tiles we need to traverse. */
	local cur_tile_x = AIMap.GetTileX(cur_tile);
	local cur_tile_y = AIMap.GetTileY(cur_tile);
	foreach (tile in goal_tiles) {
		local dx = abs(cur_tile_x - AIMap.GetTileX(tile));
		local dy = abs(cur_tile_y - AIMap.GetTileY(tile));
		min_cost = min(min_cost, min(dx, dy) * self._cost_diagonal_tile * 2 + abs(dx - dy) * self._cost_tile);
	}
	return min_cost * self._estimate_multiplier;
}

function Canal::_Neighbours(self, path, cur_node)
{
	/* self._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
	if (path._cost >= self._max_cost) return [];
//	AIExecMode() && AISign.BuildSign(cur_node, cur_node.tostring());
	local tiles = [];

	local prev = path._prev;
	local prev_node = prev == null ? null : prev._tile;

	if (self._IsAqueductTile(cur_node)) {
		local other_end = AIBridge.GetOtherBridgeEnd(cur_node);
		local next_tile = cur_node + (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
		if ((prev == null || next_tile != prev_node) && (AIMarine.AreWaterTilesConnected(cur_node, next_tile) || AIMarine.BuildCanal(next_tile) || self._CanBuildAqueduct(cur_node, next_tile) || AITile.HasTransportType(next_tile, AITile.TRANSPORT_WATER) && (!AITile.IsWaterTile(next_tile) || AIMarine.IsCanalTile(next_tile) || self._IsLockEntryExit(next_tile) && self._CanConnectToLock(cur_node, next_tile) || AIMarine.IsWaterDepotTile(next_tile) && self._CanConnectToDepot(cur_node, next_tile)))) {
			tiles.push([next_tile, self._GetDirection(cur_node, next_tile), []]);
//			AILog.Info(cur_node + "; 1. Aqueduct detected, pushed next_tile = " + next_tile + "; parent_tile = " + (prev == null ? "null" : prev_node));
//			AIController.Sleep(74);
		}
		/* The other end of the aqueduct is a neighbour. */
		if (prev == null || other_end != prev_node) {
			tiles.push([other_end, self._GetDirection(next_tile, cur_node), []]);
//			AILog.Info(cur_node + "; 1. Aqueduct detected, pushed other_end = " + other_end + "; parent_tile = " + (prev == null ? "null" : prev_node));
//			AIController.Sleep(74);
		}
	} else if (self._IsLockEntryExit(cur_node)) {
		local other_end = self._GetOtherLockEnd(cur_node);
		local next_tile = cur_node + (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
		if ((prev == null || next_tile != prev_node) && (AIMarine.AreWaterTilesConnected(cur_node, next_tile) || AIMarine.BuildCanal(next_tile) || self._CanBuildAqueduct(cur_node, next_tile) || AITile.HasTransportType(next_tile, AITile.TRANSPORT_WATER) && (!AITile.IsWaterTile(next_tile) || AIMarine.IsCanalTile(next_tile) || self._IsLockEntryExit(next_tile) && self._CanConnectToLock(cur_node, next_tile) || AIMarine.IsWaterDepotTile(next_tile) && self._CanConnectToDepot(cur_node, next_tile)))) {
			tiles.push([next_tile, self._GetDirection(cur_node, next_tile), []]);
//			AILog.Info(cur_node + "; 1. Lock detected, pushed next_tile = " + next_tile + "; parent_tile = " + (prev == null ? "null" : prev_node));
//			AIController.Sleep(74);
		}
		/* The other end of the lock is a neighbour. */
		if (prev == null || other_end != prev_node) {
			tiles.push([other_end, self._GetDirection(next_tile, cur_node), []]);
//			AILog.Info(cur_node + "; 1. Lock detected, pushed other_end = " + other_end + "; parent_tile = " + (prev == null ? "null" : prev_node));
//			AIController.Sleep(74);
		}
	} else if (AIMarine.IsWaterDepotTile(cur_node)) {
		local other_end = self._GetOtherDepotTile(cur_node);
		local next_tile = cur_node + (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
		if ((prev == null || next_tile != prev_node) && (AIMarine.AreWaterTilesConnected(cur_node, next_tile) || AIMarine.BuildCanal(next_tile) || self._CanBuildAqueduct(cur_node, next_tile) || AITile.HasTransportType(next_tile, AITile.TRANSPORT_WATER) && (!AITile.IsWaterTile(next_tile) || AIMarine.IsCanalTile(next_tile) || self._IsLockEntryExit(next_tile) && self._CanConnectToLock(cur_node, next_tile) || AIMarine.IsWaterDepotTile(next_tile) && self._CanConnectToDepot(cur_node, next_tile)))) {
			tiles.push([next_tile, self._GetDirection(cur_node, next_tile), []]);
//			AILog.Info(cur_node + "; 1. Depot detected, pushed next_tile = " + next_tile + "; parent_tile = " + (prev == null ? "null" : prev_node));
//			AIController.Sleep(74);
		}
		/* The other end of the depot is a neighbour. */
		if (prev == null || other_end != prev_node) {
			tiles.push([other_end, self._GetDirection(next_tile, cur_node), []]);
//			AILog.Info(cur_node + "; 1. Depot detected, pushed other_end = " + other_end + "; parent_tile = " + (prev == null ? "null" : prev_node));
//			AIController.Sleep(74);
		}
	} else if (prev != null && AIMap.DistanceManhattan(cur_node, prev_node) == 2 && self._IsFlatTile(cur_node)) {
		local other_end = prev_node;
		local next_tile = cur_node + (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
		if (AIMarine.AreWaterTilesConnected(cur_node, next_tile) || AIMarine.BuildCanal(next_tile) || self._CanBuildAqueduct(cur_node, next_tile) || AITile.HasTransportType(next_tile, AITile.TRANSPORT_WATER) && (!AITile.IsWaterTile(next_tile) || AIMarine.IsCanalTile(next_tile) || self._IsLockEntryExit(next_tile) && self._CanConnectToLock(cur_node, next_tile) || AIMarine.IsWaterDepotTile(next_tile) && self._CanConnectToDepot(cur_node, next_tile))) {
			local used_tiles = self._GetUsedTiles(cur_node, other_end, false);
			if (!self._UsedTileListsConflict(path._used_tiles, used_tiles)) {
				tiles.push([next_tile, self._GetDirection(cur_node, next_tile), used_tiles]);
//				AILog.Info(cur_node + "; 2. Lock detected, pushed next_tile = " + next_tile + "; parent_tile = " + prev_node);
//				AIController.Sleep(74);
			}
		}
	} else if (prev != null && (AIMap.DistanceManhattan(cur_node, prev_node) > 1 || AIMap.DistanceManhattan(cur_node, prev_node) == 1 && self._CheckAqueductSlopes(prev_node, cur_node))) {
		local other_end = prev_node;
		local next_tile = cur_node + (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
		if (AIMarine.AreWaterTilesConnected(cur_node, next_tile) || AIMarine.BuildCanal(next_tile) || self._CanBuildAqueduct(cur_node, next_tile) || AITile.HasTransportType(next_tile, AITile.TRANSPORT_WATER) && (!AITile.IsWaterTile(next_tile) || AIMarine.IsCanalTile(next_tile) || self._IsLockEntryExit(next_tile) && self._CanConnectToLock(cur_node, next_tile) || AIMarine.IsWaterDepotTile(next_tile) && self._CanConnectToDepot(cur_node, next_tile))) {
			local used_tiles = self._GetUsedTiles(cur_node, other_end, true);
			if (!self._UsedTileListsConflict(path._used_tiles, used_tiles)) {
				tiles.push([next_tile, self._GetDirection(cur_node, next_tile), used_tiles]);
//				AILog.Info(cur_node + "; 2. Aqueduct detected, pushed next_tile = " + next_tile + "; parent_tile = " + prev_node);
//				AIController.Sleep(74);
			}
		}
	} else {
		/* Check all tiles adjacent to the current tile. */
		foreach (offset in self._offsets) {
			local next_tile = cur_node + offset;
			/* Don't turn back */
			if (prev != null && next_tile == prev_node) continue;
//			/* Disallow 90 degree turns */
//			if (prev != null && prev._prev != null && next_tile - cur_node == prev._prev._tile - prev_node) continue;
			/* We add them to the to the neighbours-list if one of the following applies:
			 * 1) There already is a connection between the current tile and the next tile.
			 * 2) We can build a canal to the next tile.
			 * 3) The next tile is the entrance of an aqueduct, depot or lock in the correct direction. */
			if ((prev == null || AIMarine.AreWaterTilesConnected(prev_node, cur_node) || AIMarine.BuildCanal(cur_node) || AITile.HasTransportType(cur_node, AITile.TRANSPORT_WATER)) &&
					(AIMarine.AreWaterTilesConnected(cur_node, next_tile) || AIMarine.BuildCanal(next_tile) || self._CanBuildAqueduct(cur_node, next_tile) || AITile.HasTransportType(next_tile, AITile.TRANSPORT_WATER) && (!AITile.IsWaterTile(next_tile) && !AITile.IsCoastTile(next_tile) && !self._IsAqueductTile(next_tile) || AIMarine.IsCanalTile(next_tile) || self._IsLockEntryExit(next_tile) && self._CanConnectToLock(cur_node, next_tile) || AIMarine.IsWaterDepotTile(next_tile) && self._CanConnectToDepot(cur_node, next_tile) || self._IsAqueductTile(next_tile) && self._CanConnectToAqueduct(cur_node, next_tile)))) {
				tiles.push([next_tile, self._GetDirection(cur_node, next_tile), []]);
//				AILog.Info(cur_node + "; 3. Build Canal, pushed next_tile = " + next_tile + "; parent_tile = " + (prev == null ? "null" : prev_node));
//				AIController.Sleep(74);
			}
		}
		if (prev != null) {
			local aqueduct = self._GetAqueduct(prev_node, cur_node);
			if (aqueduct) {
				tiles.push([aqueduct, self._GetDirection(prev_node, cur_node), []]);
//				AILog.Info(cur_node + "; 4. Build Aqueduct, pushed aqueduct = " + aqueduct + "; parent_tile = " + prev_node);
//				AIController.Sleep(74);
			}
			foreach (offset in self._offsets) {
				local offset_tile = cur_node + offset;
				if (self._IsInclinedTile(offset_tile) && AIMarine.BuildLock(offset_tile) && self._CheckLockDirection(cur_node, offset_tile)) {
					local other_end = offset_tile + offset;
					local next_tile = cur_node + (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
					if (next_tile == prev_node && !self._LockBlocksConnection(cur_node, offset_tile) &&
							(prev._prev == null || AIMap.DistanceManhattan(prev._prev._tile, next_tile) != 2 || self._IsFlatTile(next_tile) && !self._PreviousLockBlocksConnection(next_tile, cur_node))) {
						tiles.push([other_end, self._GetDirection(prev_node, cur_node), []]);
//						AILog.Info(cur_node + "; 4. Build Lock, pushed other_end = " + other_end + "; parent_tile = " + prev_node);
//						AIController.Sleep(74);
					}
				}
			}
		}
	}
	return tiles;
}

function Canal::_CheckDirection(self, tile, existing_direction, new_direction)
{
	return false;
}

/**
 * Get the direction going from a tile to another.
 * @param from The tile we're at.
 * @param to The tile we're heading to.
 * @return The direction towards the tile we're heading.
 */
function Canal::_GetDirection(from, to)
{
	switch (from - to) {
		case 1: return 1;                 // NE
		case -1: return 2;                // SW
		case this._map_size_x: return 4;  // NW
		case -this._map_size_x: return 8; // SE
		default: throw("Shouldn't come here in _GetDirection");
	}
}

/**
 * Get the tiles that become used when planning to build
 *  an aqueduct or a lock to help prevent crossings with
 *  other planned aqueducts or locks.
 *  bit 0..1 - Axis X/Y (value 1 for X or 2 for Y)
 *  bit 2 - Aqueduct Middle (value 4)
 *  bit 3 - Aqueduct Ramp (value 8)
 *  bit 2..3 - Lock (value 12, sets both bits 2 and 3)
 * @param from Tile where the aqueduct or lock starts.
 * @param to Tile where the aqueduct or lock ends.
 * @param is_aqueduct Whether we're planning an aqueduct or lock.
 * @return A list of used tiles with their respective bits.
 */
function Canal::_GetUsedTiles(from, to, is_aqueduct)
{
	local used_list = [];
	local offset = AIMap.GetTileX(from) == AIMap.GetTileX(to) ? this._map_size_x : 1;

	local axis;
	if (offset == 1) {
		axis = 1; // Axis X
	} else if (offset == this._map_size_x) {
		axis = 2; // Axis Y
	}

	local complement = is_aqueduct ? 8 : 12;
	used_list.push([from, axis | complement]);
	used_list.push([to, axis | complement]);

	if (from > to) {
		local swap = from;
		from = to;
		to = swap;
	}

	if (is_aqueduct) {
		complement = 4;
	}
	local tile_offset = from + offset;
	while (tile_offset != to) {
		used_list.push([tile_offset, axis | complement]);
		tile_offset += offset;
	}

	return used_list;
}

/**
 * Checks whether two lists of used tiles conflict with each other.
 * @param prev_used_list List of used tiles (from a previous path node).
 * @param used_list List of used tiles (for the current node).
 * @return true if there is a conflict with one of the tiles.
 */
function Canal::_UsedTileListsConflict(prev_used_list, used_list)
{
	foreach (prev_tile in prev_used_list) {
		foreach (tile in used_list) {
			if (prev_tile[0] == tile[0] && prev_tile[1] & tile[1]) {
				return true;
			}
		}
	}

	return false;
}

/**
 * Get the aqueduct that can be built from the current
 *  tile. Aqueduct is only built on inclined slopes.
 * @param last_node The tile before the to be built aqueduct.
 * @param cur_node The starting tile of the to be built aqueduct.
 * @return The ending tile of the to be built aqueduct, or
 *  false, if the aqueduct can't be built.
 */
function Canal::_GetAqueduct(last_node, cur_node)
{
	local slope = AITile.GetSlope(cur_node);
	local offset;
	if (slope == AITile.SLOPE_NE) {
		offset = -1;
	} else if (slope == AITile.SLOPE_SE) {
		offset = this._map_size_x;
	} else if (slope == AITile.SLOPE_NW) {
		offset = -this._map_size_x;
	} else if (slope == AITile.SLOPE_SW) {
		offset = 1;
	} else {
		return false;
	}

	if (last_node != cur_node + offset) {
		return false;
	}

	local s_min_height = AITile.GetMinHeight(cur_node);
	local s_max_height = AITile.GetMaxHeight(cur_node);
	for (local i = 1; i < this._max_aqueduct_length; i++) {
		local next_tile = cur_node + i * (cur_node - last_node);
		local e_max_height = AITile.GetMaxHeight(next_tile);
		if (e_max_height == -1) {
			return false;
		}
		if (e_max_height < s_max_height) {
			continue;
		}
		if (e_max_height > s_max_height || AITile.GetMinHeight(next_tile) < s_min_height) {
			return false;
		}
		if (AIBridge.BuildBridge(AIVehicle.VT_WATER, 0, cur_node, next_tile)) {
			return next_tile;
		} else {
			return false;
		}
	}

	return false;
}

/**
 * Check whether an aqueduct can be built from the current tile.
 * @param last_node The tile just before the aqueduct.
 * @param cur_node The tile where the aqueduct starts.
 * @return true if an aqueduct can be built, or false if not.
 */
function Canal::_CanBuildAqueduct(last_node, cur_node)
{
	return !AIBridge.IsBridgeTile(cur_node) && this._GetAqueduct(last_node, cur_node);
}

/**
 * Check whether the tile we're coming from connects to an
 *  existing aqueduct in the right direction.
 * @param prev_tile The tile we're coming from.
 * @param aqueduct_tile The entrance of the aqueduct.
 * @return true if the previous tile connects with the aqueduct in the right direction.
 */
function Canal::_CanConnectToAqueduct(prev_tile, aqueduct_tile)
{
	assert(this._IsAqueductTile(aqueduct_tile));

	local slope = AITile.GetSlope(aqueduct_tile);
	local offset;
	if (slope == AITile.SLOPE_NE) {
		offset = -1;
	} else if (slope == AITile.SLOPE_SE) {
		offset = this._map_size_x;
	} else if (slope == AITile.SLOPE_NW) {
		offset = -this._map_size_x;
	} else if (slope == AITile.SLOPE_SW) {
		offset = 1;
	}

	return prev_tile == aqueduct_tile + offset;
}

/**
 * Special check determining the possibility of a two tile sized
 *  aqueduct sharing the same edge to be built here.
 *  Checks wether the slopes are suitable and in the correct
 *  direction for such aqueduct.
 * @param tile_a The starting tile of a two tile sized aqueduct.
 * @param tile_b The ending tile of a two tile sized aqueduct.
 * @return true if the slopes are suitable for a two tile sized aqueduct.
 */
function Canal::_CheckAqueductSlopes(tile_a, tile_b)
{
	local slope_a = AITile.GetSlope(tile_a);
	if (AIMap.DistanceManhattan(tile_a, tile_b) != 1) return false;
	if (!this._IsInclinedTile(tile_a) || !this._IsInclinedTile(tile_b)) return false;

	local slope_a = AITile.GetSlope(tile_a);
	if (AITile.GetComplementSlope(slope_a) != AITile.GetSlope(tile_b)) return false;

	local offset;
	if (slope_a == AITile.SLOPE_NE) {
		offset = 1;
	} else if (slope_a == AITile.SLOPE_SE) {
		offset = -this._map_size_x;
	} else if (slope_a == AITile.SLOPE_SW) {
		offset = -1;
	} else if (slope_a == AITile.SLOPE_NW) {
		offset = this._map_size_x;
	}

	return tile_a + offset == tile_b;
}

/**
 * Check whether a tile is part of an aqueduct.
 * @param tile The tile to check.
 * @return true if the tile is an aqueduct.
 */
function Canal::_IsAqueductTile(tile)
{
	return AIBridge.IsBridgeTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_WATER);
}

/**
 * Get the (other) end tile of a chain of traversable ship depots.
 * @param tile 1) One of the depot tiles where to start the check, or
 *  2) The southern end tile of a chain of ship depots.
 * @return 1) The southern end tile of a chain of ship depots, or
 *  2) The northern end tile of a chain of ship depots.
 */
function Canal::_GetOtherDepotChainEnd(tile)
{
	local end_tile = tile;
	foreach (offset in this._offsets) {
		local next_tile = tile + offset;
		local cur_tile = tile;
		while (AIMarine.IsWaterDepotTile(next_tile) && AIMarine.AreWaterTilesConnected(cur_tile, next_tile)) {
			end_tile = next_tile;
			next_tile += offset;
			cur_tile += offset;
		}
	}

	return end_tile;
}

/**
 * Get the tile of the other part of a ship depot.
 * @param tile The tile of a part of the ship depot.
 * @return The tile of the other part of the same ship depot.
 */
function Canal::_GetOtherDepotTile(tile)
{
	assert(AIMarine.IsWaterDepotTile(tile));

	local end1 = this._GetOtherDepotChainEnd(tile);
	local end2 = this._GetOtherDepotChainEnd(end1);

	if (end1 > end2) {
		local swap = end1;
		end1 = end2;
		end2 = swap;
	}

	local length = AIMap.DistanceManhattan(end1, end2) + 1;

	local offset = 1;
	if (AIMap.GetTileX(end1) == AIMap.GetTileX(end2)) {
		offset = this._map_size_x;
	}

	local next_tile = end1 + offset;
	do {
		if (AIMarine.IsWaterDepotTile(next_tile) && AIMarine.AreWaterTilesConnected(end1, next_tile)) {
			if (end1 == tile) {
				return next_tile;
			} else if (next_tile == tile) {
				return end1;
			}
			end1 += 2 * offset;
			next_tile += 2 * offset;
			length -=2;
		}
	} while (length != 0);
}

/**
 * Check whether the tile we're coming from connects to an
 *  existing ship depot in the right direction.
 * @param prev_tile The tile we're coming from.
 * @param depot_tile The entrance of the ship depot.
 * @return true if the previous tile connects with the ship depot in the right direction.
 */
function Canal::_CanConnectToDepot(prev_tile, depot_tile)
{
	assert(AIMarine.IsWaterDepotTile(depot_tile));

	local next_tile = depot_tile + (depot_tile - prev_tile);
	return AIMarine.IsWaterDepotTile(next_tile) && AIMarine.AreWaterTilesConnected(depot_tile, next_tile);
}

/**
 * Check whether a tile is the entry/exit point of a lock.
 * @param tile The tile to check.
 * @return true if the tile is an entry/exit point of a lock.
 */
function Canal::_IsLockEntryExit(tile)
{
	return AIMarine.IsLockTile(tile) && this._IsFlatTile(tile);
}

/**
 * Get the tile of the middle part of a lock.
 * @param tile The tile of a part of a lock.
 * @return The tile of the middle part of the same lock.
 */
function Canal::_GetLockMiddleTile(tile)
{
	assert(AIMarine.IsLockTile(tile));

	if (this._IsInclinedTile(tile)) return tile;

	assert(this._IsLockEntryExit(tile));

	local other_end = this._GetOtherLockEnd(tile);
	return tile - (tile - other_end) / 2;
}

/**
 * Get the tile of the other end of a lock.
 * @param tile The tile of the entrance of a lock.
 * @return The tile of the other end of the same lock.
 */
function Canal::_GetOtherLockEnd(tile)
{
	assert(this._IsLockEntryExit(tile));

	foreach (offset in this._offsets) {
		local middle_tile = tile + offset;
		if (AIMarine.IsLockTile(middle_tile) && this._IsInclinedTile(middle_tile)) {
			return middle_tile + offset;
		}
	}
}

/**
 * Check whether the tile we're coming from is compatible with the axis of a
 *  lock planned in this location.
 * @param prev_tile The tile we're coming from.
 * @param middle_tile The tile of the middle part of a planned lock.
 * @return true if the previous tile is compatible with the axis of the planned lock.
 */
function Canal::_CheckLockDirection(prev_tile, middle_tile)
{
	assert(this._IsInclinedTile(middle_tile));

	local slope = AITile.GetSlope(middle_tile);
	if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NE) {
		return prev_tile == middle_tile + 1 || prev_tile == middle_tile - 1;
	} else if (slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NW) {
		return prev_tile == middle_tile + this._map_size_x || prev_tile == middle_tile - this._map_size_x;
	}

	return false;
}

/**
 * Check whether a planned lock blocks a ship traversable connection.
 * @param prev_tile The tile of the entry point of a planned lock.
 * @param middle_tile The tile of the middle part of a planned lock.
 * @return true if planning a lock here ends up blocking a ship connection.
 */
function Canal::_LockBlocksConnection(prev_tile, middle_tile)
{
	assert(this._IsInclinedTile(middle_tile));

	local offset_mid;
	local offset_side;
	if (AIMap.GetTileY(prev_tile) != AIMap.GetTileY(middle_tile)) {
		offset_mid = this._map_size_x;
		offset_side = 1;
	} else if (AIMap.GetTileX(prev_tile) != AIMap.GetTileX(middle_tile)) {
		offset_mid = 1;
		offset_side = this._map_size_x;
	}

	/* m = middle, s = side, p = positive, n = negative, 2 = two times */

	local t_mp = middle_tile + offset_mid;
	local t_mp_sp = t_mp + offset_side;
	if (this._IsAqueductTile(t_mp_sp)) return true;
	if (this._IsWaterDockTile(t_mp_sp) && this._GetDockDockingTile(t_mp_sp) == t_mp) return true;

	local t_mp_sn = t_mp - offset_side;
	if (this._IsAqueductTile(t_mp_sn)) return true;
	if (this._IsWaterDockTile(t_mp_sn) && this._GetDockDockingTile(t_mp_sn) == t_mp) return true;

	local t_mn = middle_tile - offset_mid;
	local t_mn_sp = t_mn + offset_side;
	if (this._IsAqueductTile(t_mn_sp)) return true;
	if (this._IsWaterDockTile(t_mn_sp) && this._GetDockDockingTile(t_mn_sp) == t_mn) return true;

	local t_mn_sn = t_mn - offset_side;
	if (this._IsAqueductTile(t_mn_sn)) return true;
	if (this._IsWaterDockTile(t_mn_sn) && this._GetDockDockingTile(t_mn_sn) == t_mn) return true;

	local t_sp = middle_tile + offset_side;
	if (AIMarine.AreWaterTilesConnected(t_mp, t_mp_sp)) {
		if (AIMarine.IsWaterDepotTile(t_mp_sp)) return true;
		if (this._IsLockEntryExit(t_mp_sp)) return true;
		if (this._IsOneCornerRaisedTile(t_mp_sp)) {
			if (AIMarine.AreWaterTilesConnected(t_mp_sp, t_sp)) return true;
		}
	}

	if (AIMarine.AreWaterTilesConnected(t_mn, t_mn_sp)) {
		if (AIMarine.IsWaterDepotTile(t_mn_sp)) return true;
		if (this._IsLockEntryExit(t_mn_sp)) return true;
		if (this._IsOneCornerRaisedTile(t_mn_sp)) {
			if (AIMarine.AreWaterTilesConnected(t_mn_sp, t_sp)) return true;
		}
	}

	local t_sn = middle_tile - offset_side;
	if (AIMarine.AreWaterTilesConnected(t_mp, t_mp_sn)) {
		if (AIMarine.IsWaterDepotTile(t_mp_sn)) return true;
		if (this._IsLockEntryExit(t_mp_sn)) return true;
		if (this._IsOneCornerRaisedTile(t_mp_sn)) {
			if (AIMarine.AreWaterTilesConnected(t_mp_sn, t_sn)) return true;
		}
	}

	if (AIMarine.AreWaterTilesConnected(t_mn, t_mn_sn)) {
		if (AIMarine.IsWaterDepotTile(t_mn_sn)) return true;
		if (this._IsLockEntryExit(t_mn_sn)) return true;
		if (this._IsOneCornerRaisedTile(t_mn_sn)) {
			if (AIMarine.AreWaterTilesConnected(t_mn_sn, t_sn)) return true;
		}
	}

	local t_2mp = t_mp + offset_mid;
	local t_2mp_sp = t_2mp + offset_side;
	local t_2mp_sn = t_2mp - offset_side;
	if (AIMarine.AreWaterTilesConnected(t_mp, t_2mp)) {
		if (AIMarine.AreWaterTilesConnected(t_mp, t_mp_sp)) {
			if (!AIMarine.AreWaterTilesConnected(t_2mp_sp, t_mp_sp) || !AIMarine.AreWaterTilesConnected(t_2mp_sp, t_2mp)) return true;
		}
		if (AIMarine.AreWaterTilesConnected(t_mp, t_mp_sn)) {
			if (!AIMarine.AreWaterTilesConnected(t_2mp_sn, t_mp_sn) || !AIMarine.AreWaterTilesConnected(t_2mp_sn, t_2mp)) return true;
		}
	} else {
		if (this._IsWaterDockTile(t_2mp) && this._GetDockDockingTile(t_2mp) != t_mp) return true;
	}

	if (AIMarine.AreWaterTilesConnected(t_mp, t_mp_sp) && AIMarine.AreWaterTilesConnected(t_mp, t_mp_sn)) {
		if (!AIMarine.AreWaterTilesConnected(t_2mp, t_2mp_sp)) {
			return true;
		} else if (!AIMarine.AreWaterTilesConnected(t_2mp, t_2mp_sn)) {
			return true;
		} else if (!AIMarine.AreWaterTilesConnected(t_2mp_sp, t_mp_sp)) {
			return true;
		} else if (!AIMarine.AreWaterTilesConnected(t_2mp_sn, t_mp_sn)) {
			return true;
		}
	}

	local t_2mn = t_mn - offset_mid;
	local t_2mn_sp = t_2mn + offset_side;
	local t_2mn_sn = t_2mn - offset_side;
	if (AIMarine.AreWaterTilesConnected(t_mn, t_2mn)) {
		if (AIMarine.AreWaterTilesConnected(t_mn, t_mn_sp)) {
			if (!AIMarine.AreWaterTilesConnected(t_2mn_sp, t_mn_sp) || !AIMarine.AreWaterTilesConnected(t_2mn_sp, t_2mn)) return true;
		}
		if (AIMarine.AreWaterTilesConnected(t_mn, t_mn_sn)) {
			if (!AIMarine.AreWaterTilesConnected(t_2mn_sn, t_mn_sn) || !AIMarine.AreWaterTilesConnected(t_2mn_sn, t_2mn)) return true;
		}
	} else {
		if (this._IsWaterDockTile(t_2mn) && this._GetDockDockingTile(t_2mn) != t_mn) return true;
	}

	if (AIMarine.AreWaterTilesConnected(t_mn, t_mn_sp) && AIMarine.AreWaterTilesConnected(t_mn, t_mn_sn)) {
		if (!AIMarine.AreWaterTilesConnected(t_2mn, t_2mn_sp)) {
			return true;
		} else if (!AIMarine.AreWaterTilesConnected(t_2mn, t_2mn_sn)) {
			return true;
		} else if (!AIMarine.AreWaterTilesConnected(t_2mn_sp, t_mn_sp)) {
			return true;
		} else if (!AIMarine.AreWaterTilesConnected(t_2mn_sn, t_mn_sn)) {
			return true;
		}
	}

	return false;
}

/**
 * Checks whether a previously planned lock blocks a ship traversable connection
 *  once another lock is planned right after it.
 * @param prev_lock Tile of the end part of the previous lock.
 * @param new_lock Tile of the starting part of the new lock.
 * @return true if the two planned locks end up blocking a ship connection.
 */
function Canal::_PreviousLockBlocksConnection(prev_lock, new_lock)
{
	local offset;
	if (AIMap.GetTileY(prev_lock) != AIMap.GetTileY(new_lock)) {
		offset = 1;
	} else if (AIMap.GetTileX(prev_lock) != AIMap.GetTileX(new_lock)) {
		offset = this._map_size_x;
	}

	local offset_tile1 = prev_lock + offset;
	local offset_tile2 = prev_lock - offset;
	local offset_tile3 = new_lock + offset;
	local offset_tile4 = new_lock - offset;
	if ((AIMarine.IsLockTile(prev_lock) ||
			(AIMarine.AreWaterTilesConnected(prev_lock, offset_tile1) || this._IsWaterDockTile(offset_tile1) && this._GetDockDockingTile(offset_tile1) == prev_lock) &&
			(AIMarine.AreWaterTilesConnected(prev_lock, offset_tile2) || this._IsWaterDockTile(offset_tile2) && this._GetDockDockingTile(offset_tile2) == prev_lock)) &&
			(AIMarine.AreWaterTilesConnected(new_lock, offset_tile3) || this._IsWaterDockTile(offset_tile3) && this._GetDockDockingTile(offset_tile3) == new_lock) &&
			(AIMarine.AreWaterTilesConnected(new_lock, offset_tile4) || this._IsWaterDockTile(offset_tile4) && this._GetDockDockingTile(offset_tile4) == new_lock)) {
		return true;
	}

	return false;
}

/**
 * Check whether the tile we're coming from connects to an
 *  existing entrance of a lock.
 * @param prev_tile The tile we're coming from.
 * @param lock_tile The entrance tile of the lock.
 * @return true if the previous tile connects with the entrance of a lock.
 */
function Canal::_CanConnectToLock(prev_tile, lock_tile)
{
	assert(this._IsLockEntryExit(lock_tile));

	local middle_tile = this._GetLockMiddleTile(lock_tile);
	local slope = AITile.GetSlope(middle_tile);
	if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NE) {
		return AIMap.GetTileX(prev_tile) != AIMap.GetTileX(lock_tile);
	} else if (slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NW) {
		return AIMap.GetTileY(prev_tile) != AIMap.GetTileY(lock_tile);
	}

	return false;
}

/**
 * Check whether the tile is part of a dock on water, not on the slope.
 * @param tile The tile to check.
 * @return true if the tile is part of a dock on water.
 */
function Canal::_IsWaterDockTile(tile)
{
	return AIMarine.IsDockTile(tile) && this._IsFlatTile(tile);
}

/**
 * Get the tile where ships can use to dock at the given dock.
 * @param dock_tile A tile that is part of the dock.
 * @return The tile where ships dock at the given dock.
 */
function Canal::_GetDockDockingTile(dock_tile)
{
	assert(AIMarine.IsDockTile(dock_tile));

	local dock_slope;
	if (this._IsWaterDockTile(dock_tile)) {
		foreach (offset in this._offsets) {
			local offset_tile = dock_tile + offset;
			if (AIMarine.IsDockTile(offset_tile) && this._IsInclinedTile(offset_tile)) {
				dock_slope = offset_tile;
				break;
			}
		}
	} else {
		dock_slope = dock_tile;
	}

	local slope = AITile.GetSlope(dock_slope);
	if (slope == AITile.SLOPE_NE) {
		return dock_slope + 2;
	} else if (slope == AITile.SLOPE_SE) {
		return dock_slope - 2 * this._map_size_x;
	} else if (slope == AITile.SLOPE_SW) {
		return dock_slope - 2;
	} else if (slope == AITile.SLOPE_NW) {
		return dock_slope + 2 * this._map_size_x;
	}
}

/**
 * Check whether a tile has an inclined slope.
 * @param tile The tile to check.
 * @return true if the tile has an inclined slope.
 */
function Canal::_IsInclinedTile(tile)
{
	local slope = AITile.GetSlope(tile);
	return slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE;
}

/**
 * Check whether a tile is flat.
 * @param tile The tile to check.
 * @return true if the tile is flat.
 */
function Canal::_IsFlatTile(tile)
{
	return AITile.GetSlope(tile) == AITile.SLOPE_FLAT;
}

/**
 * Check whether a tile has one corner raised.
 * @param tile The tile to check.
 * @return true if the tile has one corner raised.
 */
function Canal::_IsOneCornerRaisedTile(tile)
{
	local slope = AITile.GetSlope(tile);
	return slope == AITile.SLOPE_N || slope == AITile.SLOPE_S || slope == AITile.SLOPE_E || slope == AITile.SLOPE_W;
}
