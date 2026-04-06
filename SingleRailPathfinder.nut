/**
 * A class to precalculate some values for the SingleRail Pathfinder, so they don't
 * have to be calculated every time a path is searched. This is used to speed
 * up the pathfinding, as some of these values are used a lot during the search.
 */
class PreSingleRail
{
	/**
	 * A table of array offset values for different directions.
	 *  The keys of the first dimension are the direction from the previous
	 *  tile to the current tile, and the values are arrays of offsets to
	 *  calculate the next tile in a given direction, excluding the direction
	 *  we came from.
	 */
	_offsets_array = {
		[1] = [-1, AIMap.GetMapSizeX(), -AIMap.GetMapSizeX()],
		[-1] = [1, AIMap.GetMapSizeX(), -AIMap.GetMapSizeX()],
		[AIMap.GetMapSizeX()] = [1, -1, -AIMap.GetMapSizeX()],
		[-AIMap.GetMapSizeX()] = [1, -1, AIMap.GetMapSizeX()]
	};

	/**
	 * A table mapping directions to bitfields for tunnels and bridges.
	 *  The index is the direction from the previous tile to the current tile.
	 *  The value is the mapped bitfield for the direction difference.
	 */
	_dir_to_dirbit_tunnelbridge = {
		[1] = 1,
		[-1] = 2,
		[AIMap.GetMapSizeX()] = 4,
		[-AIMap.GetMapSizeX()] = 8
	};

	/**
	 * A table mapping directions to bitfields for rails.
	 *  The keys of the first dimension are the direction from the previous tile to the current tile.
	 *  The keys of the second dimension are the direction from the current tile to the next tile.
	 *  The value is the mapped bitfield for the direction difference.
	 */
	_dir_to_dirbit_rail_2d = {
		[1] = { [1] = 32, [-1] = 16, [AIMap.GetMapSizeX()] = 128, [-AIMap.GetMapSizeX()] = 64 },
		[-1] = { [1] = 512, [-1] = 256, [AIMap.GetMapSizeX()] = 2048, [-AIMap.GetMapSizeX()] = 1024 },
		[AIMap.GetMapSizeX()] = { [1] = 8192, [-1] = 4096, [AIMap.GetMapSizeX()] = 32768, [-AIMap.GetMapSizeX()] = 16384 },
		[-AIMap.GetMapSizeX()] = { [1] = 131072, [-1] = 65536, [AIMap.GetMapSizeX()] = 524288, [-AIMap.GetMapSizeX()] = 262144 }
	};

	/**
	 * A table mapping slopes/directions combinations for determining a sloped bridge.
	 *  The keys of the first dimension are the result of AITile.GetSlope on a bridge ramp tile.
	 *  The keys of the second dimension are the direction from the bridge ramp tile towards the exit.
	 *  The value is the number of slopes for the slope-direction combination.
	 */
	_is_slope_dir_bridge = {
		[AITile.SLOPE_FLAT] = { [1] = 1, [-1] = 1, [AIMap.GetMapSizeX()] = 1, [-AIMap.GetMapSizeX()] = 1 },
		[AITile.SLOPE_W] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 },
		[AITile.SLOPE_S] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 },
		[AITile.SLOPE_E] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 },
		[AITile.SLOPE_N] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 },
		[AITile.SLOPE_NW] = { [1] = 1, [-1] = 1, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 },
		[AITile.SLOPE_SW] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 1, [-AIMap.GetMapSizeX()] = 1 },
		[AITile.SLOPE_SE] = { [1] = 1, [-1] = 1, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 },
		[AITile.SLOPE_NE] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 1, [-AIMap.GetMapSizeX()] = 1 },
		[AITile.SLOPE_EW] = { [1] = 1, [-1] = 1, [AIMap.GetMapSizeX()] = 1, [-AIMap.GetMapSizeX()] = 1 },
		[AITile.SLOPE_NS] = { [1] = 1, [-1] = 1, [AIMap.GetMapSizeX()] = 1, [-AIMap.GetMapSizeX()] = 1 },
		[AITile.SLOPE_NWS] = { [1] = 1, [-1] = 1, [AIMap.GetMapSizeX()] = 1, [-AIMap.GetMapSizeX()] = 1 },
		[AITile.SLOPE_WSE] = { [1] = 1, [-1] = 1, [AIMap.GetMapSizeX()] = 1, [-AIMap.GetMapSizeX()] = 1 },
		[AITile.SLOPE_SEN] = { [1] = 1, [-1] = 1, [AIMap.GetMapSizeX()] = 1, [-AIMap.GetMapSizeX()] = 1 },
		[AITile.SLOPE_ENW] = { [1] = 1, [-1] = 1, [AIMap.GetMapSizeX()] = 1, [-AIMap.GetMapSizeX()] = 1 },
		[AITile.SLOPE_STEEP_W] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 },
		[AITile.SLOPE_STEEP_S] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 },
		[AITile.SLOPE_STEEP_E] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 },
		[AITile.SLOPE_STEEP_N] = { [1] = 0, [-1] = 0, [AIMap.GetMapSizeX()] = 0, [-AIMap.GetMapSizeX()] = 0 }
	};

	/**
	 * A table mapping slopes/directionbits combinations for determining a sloped rail.
	 *  The keys of the first dimension are the result of AITile.GetSlope on a rail tile.
	 *  The keys of the second dimension are the result of _dir_to_dirbit_rail_2d applied offsets to the rail.
	 *  The value is the number of slopes for the slope-directionbit combination.
	 */
	_is_slope_dirbit_rail = {
		[AITile.SLOPE_FLAT] = { [32] = 0, [128] = 0, [64] = 0, [256] = 0, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 0, [131072] = 0, [65536] = 0, [262144] = 0},
		[AITile.SLOPE_W] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1},
		[AITile.SLOPE_S] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1},
		[AITile.SLOPE_E] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1},
		[AITile.SLOPE_N] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1},
		[AITile.SLOPE_NW] = { [32] = 0, [128] = 0, [64] = 0, [256] = 0, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1},
		[AITile.SLOPE_SW] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 0, [131072] = 0, [65536] = 0, [262144] = 0},
		[AITile.SLOPE_SE] = { [32] = 0, [128] = 0, [64] = 0, [256] = 0, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1},
		[AITile.SLOPE_NE] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 0, [131072] = 0, [65536] = 0, [262144] = 0},
		[AITile.SLOPE_EW] = { [32] = 0, [128] = 0, [64] = 0, [256] = 0, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 0, [131072] = 0, [65536] = 0, [262144] = 0},
		[AITile.SLOPE_NS] = { [32] = 0, [128] = 0, [64] = 0, [256] = 0, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 0, [131072] = 0, [65536] = 0, [262144] = 0},
		[AITile.SLOPE_NWS] = { [32] = 0, [128] = 0, [64] = 0, [256] = 0, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 0, [131072] = 0, [65536] = 0, [262144] = 0},
		[AITile.SLOPE_WSE] = { [32] = 0, [128] = 0, [64] = 0, [256] = 0, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 0, [131072] = 0, [65536] = 0, [262144] = 0},
		[AITile.SLOPE_SEN] = { [32] = 0, [128] = 0, [64] = 0, [256] = 0, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 0, [131072] = 0, [65536] = 0, [262144] = 0},
		[AITile.SLOPE_ENW] = { [32] = 0, [128] = 0, [64] = 0, [256] = 0, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 0, [131072] = 0, [65536] = 0, [262144] = 0},
		[AITile.SLOPE_STEEP_W] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1},
		[AITile.SLOPE_STEEP_S] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1},
		[AITile.SLOPE_STEEP_E] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1},
		[AITile.SLOPE_STEEP_N] = { [32] = 1, [128] = 0, [64] = 0, [256] = 1, [2048] = 0, [1024] = 0, [8192] = 0, [4096] = 0, [32768] = 1, [131072] = 0, [65536] = 0, [262144] = 1}
	};
};

/**
 * A SingleRail Pathfinder.
 */
class SingleRail
{
	/** AyStar Graph */
	_open = null;                       ///< The open list, this is a priority queue of paths that are not yet scanned.
	_closed = null;                     ///< The closed list, this is a list of tiles that are already scanned, with the directions we came from as bitfields.

	/** Costs */
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

	cost = null;                        ///< Used to change the costs.
	_running = null;                    ///< Indicates if the pathfinder is currently running, that is, if FindPath returned false and it is not yet finished looking for a path.
	_goals = null;                      ///< The goal tiles, this is an array of [tile, next_tile]-pairs.

	/** Precalculated values to speed up the estimation costs. */
	_goals_x = null;                    ///< The x-coordinates of the goal tiles, this is used to speed up the estimation.
	_goals_y = null;                    ///< The y-coordinates of the goal tiles, this is used to speed up the estimation.
	_cost_diagonal_tile_times_2 = null; ///< The cost for a diagonal tile, multiplied by 2, this is used to speed up the estimation. Not a real cost parameter!
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
		/** Default values for the costs, these can be changed by setting the cost property. */
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

		/** The cost property is used to change the costs, it will throw an error if you try to change the costs while the pathfinder is running. */
		this.cost = this.Cost(this);
		this._running = false;

		/** Precalculate some values to speed up the estimation. */
		this._cost_diagonal_tile_times_2 = this._cost_diagonal_tile * 2;
	}

	/**
	 * Initialize a path search between sources and goals.
	 * @param sources The source nodes. This must be an array of [tile, direction]-pairs.
	 * @param goals The target tiles. This must be an array of [tile, next_tile]-pairs.
	 * @param ignored_tiles An array of tiles that cannot occur in the final path.
	 */
	function InitializePath(sources, goals, ignored_tiles = []);

	/**
	 * Try to find the path as indicated with InitializePath with the lowest cost.
	 * @param iterations After how many iterations it should abort for a moment.
	 *  This value should either be -1 for infinite, or > 0. Any other value
	 *  aborts immediatly and will never find a path.
	 * @return A route if one was found, or false if the amount of iterations was
	 *  reached, or null if no path was found.
	 *  You can call this function over and over as long as it returns false,
	 *  which is an indication it is not yet done looking for a route.
	 */
	function FindPath(iterations);
};

class SingleRail.Cost
{
	_main = null;

	constructor(main)
	{
		this._main = main;
	}

	function _set(idx, val)
	{
		if (this._main._running) throw "You are not allowed to change parameters of a running pathfinder.";

		switch (idx) {
			case "max_cost":            this._main._max_cost = val; break;
			case "tile":                this._main._cost_tile = val; break;
			case "diagonal_tile":       this._main._cost_diagonal_tile = val; this._main._cost_diagonal_tile_times_2 = val * 2; break;
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
			default: throw "the index '" + idx + "' does not exist";
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
			default: throw "the index '" + idx + "' does not exist";
		}
	}
};

function SingleRail::InitializePath(sources, goals, ignored_tiles = [],
	get_tile_x = AIMap.GetTileX,
	get_tile_y = AIMap.GetTileY,
	is_valid_tile = AIMap.IsValidTile,
	distance_manhattan = AIMap.DistanceManhattan,
	get_map_size_x = AIMap.GetMapSizeX(),
	get_map_size_y = AIMap.GetMapSizeY(),
	dir_to_dirbit_rail_2d = PreSingleRail()._dir_to_dirbit_rail_2d)
{
	this._goals = goals;
	this._goals_x = [];
	this._goals_y = [];

	foreach (goal in this._goals) {
		this._goals_x.append(get_tile_x(goal[0]));
		this._goals_y.append(get_tile_y(goal[0]));
	}

	this._open = AIPriorityQueue();

	if (this._search_range) {
		local pair = [];
		local min_freeform = is_valid_tile(0) ? 0 : 1;

		foreach (source in sources) {
			foreach (goal in this._goals) {
				local distance = distance_manhattan(source[1], goal[1]);
				pair.append([source[1], goal[1], distance]);

				local source_x = get_tile_x(source[1]);
				local source_y = get_tile_y(source[1]);
				local goal_x = get_tile_x(goal[1]);
				local goal_y = get_tile_y(goal[1]);

				this._min_x = max(min_freeform, min(source_x, goal_x) - this._search_range);
				this._min_y = max(min_freeform, min(source_y, goal_y) - this._search_range);
				this._max_x = min(get_map_size_x - 2, max(source_x, goal_x) + this._search_range);
				this._max_y = min(get_map_size_y - 2, max(source_y, goal_y) + this._search_range);
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
		this._a = get_tile_y(best_source) - get_tile_y(best_goal);
		this._b = get_tile_x(best_goal) - get_tile_x(best_source);
		this._c = get_tile_x(best_source) * get_tile_y(best_goal) - get_tile_x(best_goal) * get_tile_y(best_source);
		this._sqrt = sqrt(this._a * this._a + this._b * this._b);
	}

	foreach (node in sources) {
		if (typeof(node) == "array") {
			local path = null;
			local n = node.len();
			if (n < 2) throw "Each source node must be an array containing at least 2 tiles.";
			foreach (i, tile in node) {
				local next_tile = node[n - 1 - i];
				if (path && distance_manhattan(path._tile, next_tile) != 1) throw "Source node tiles must be adjacent to each other."
//				path = this._Path(path, next_tile, path ? dir_to_dirbit_rail_2d[path._prev ? path._prev._tile - path._tile : path._tile - next_tile][next_tile - path._tile] : ~0);
				path = this._Path(path, next_tile, n - i > 1 ? 0 : 0xFFFFF);
			}
			this._open.Insert(path, path._cost + this._Estimate(path._tile));
		} else if (typeof(node) == "table") {
			this._open.Insert(node, node._cost);
		} else {
			throw "Sources must be an array or SingleRail._Path tables"
		}
	}

	this._closed = AIList();

	foreach (tile in ignored_tiles)
		this._closed[tile] = ~0;
}

function SingleRail::FindPath(iterations)
{
	local test_mode = AITestMode();
	local ret = this._FindPath(iterations);
	this._running = ret == false;

	return ret;
}

function SingleRail::_FindPath(iterations)
{
	while (this._open.Count() && iterations--) {
		/* Get the path with the best score so far */
		local path = this._open.Pop();
		local cur_tile = path._tile;
		local prev_cur_dirbit = path._direction;

		/* Make sure we didn't already passed it */
		if (this._closed.HasItem(cur_tile)) {
			/* If the direction is already on the list, skip this entry */
			if (this._closed[cur_tile] & prev_cur_dirbit) continue;

			/* Scan the path for a possible collision */
			if (this._PathCollides(path, cur_tile)) continue;

			/* Add the new direction */
			this._closed[cur_tile] += prev_cur_dirbit;
		} else
			/* New entry, make sure we don't check it again */
			this._closed[cur_tile] = prev_cur_dirbit;

		/* Check if we found the end */
		foreach (goal in this._goals) {
			if (cur_tile == goal[2] && path._prev._tile == goal[1] && path._prev._prev._tile == goal[0]) {
				this._CleanPath();
				return path;
			}
		}

		/* Scan all neighbours */
		foreach (node in this._Neighbours(path, cur_tile)) {
			/* Calculate the new paths and add them to the open list */
			local new_path = this._Path(path, node[0], node[1]);

			/* Check if we're near the end */
			foreach (goal in this._goals) {
				if (node[0] == goal[1] && cur_tile == goal[0]) {
					new_path = this._Path(new_path, goal[2], 0);
					break;
				}
			}

			/* this._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
			if (new_path._cost >= this._max_cost) continue;

			this._open.Insert(new_path, new_path._cost + this._Estimate(node[0]));
		}
	}

	if (this._open.Count()) return false;
	this._CleanPath();

	return;
}

function SingleRail::_PathCollides(path, cur_tile)
{
	local scan_path = path._prev;
	while (scan_path) {
		if (scan_path._tile == cur_tile)
			return true;
		scan_path = scan_path._prev;
	}

	return;
}

function SingleRail::_CleanPath()
{
	this._closed = null;
	this._open = null;
	this._goals = null;

	return;
}

/**
 * The path of the AyStar algorithm.
 *  It is reversed, that is, the first entry is more close to the goal-nodes
 *  than his _prev. You can walk this table to find the whole path.
 *  The last entry has a _prev of null.
 */
function SingleRail::_Path(path, next_tile, prev_cur_dirbit)
{
	return {
		_prev = path,
		_tile = next_tile,
		_direction = prev_cur_dirbit,
		_cost = this._Cost(path, next_tile)
	};
}

function SingleRail::_Cost(path, next_tile,
	get_tile_x = AIMap.GetTileX,
	get_tile_y = AIMap.GetTileY,
	distance_manhattan = AIMap.DistanceManhattan,
	get_other_tunnel_end = AITunnel.GetOtherTunnelEnd,
	is_slope_dir_bridge = PreSingleRail()._is_slope_dir_bridge,
	dir_to_dirbit_rail_2d = PreSingleRail()._dir_to_dirbit_rail_2d,
	is_slope_dirbit_rail = PreSingleRail()._is_slope_dirbit_rail,
	get_slope = AITile.GetSlope,
	has_transport_type = AITile.HasTransportType,
	transport_water = AITile.TRANSPORT_WATER,
	transport_road = AITile.TRANSPORT_ROAD,
	is_road_tile = AIRoad.IsRoadTile,
	min_tunnelbridge_length = 2)
{
	/* path == null means this is the first node of a path, so the cost is 0. */
	if (!path) return 0;

	if (this._search_range) {
		local cur_tile_x = get_tile_x(next_tile);
		local cur_tile_y = get_tile_y(next_tile);
		if (cur_tile_x < this._min_x || cur_tile_x > this._max_x || cur_tile_y < this._min_y || cur_tile_y > this._max_y) return this._max_cost;
		if (abs(this._a * cur_tile_x + this._b * cur_tile_y + this._c) / this._sqrt > this._search_range) return this._max_cost;
	}

	local cur_tile = path._tile;
	local prev_tile = path._prev ? path._prev._tile : 0;
	local pprev_tile = prev_tile && path._prev._prev ? path._prev._prev._tile : 0;
	local cur_next_dist = distance_manhattan(cur_tile, next_tile);
	local pprev_prev_offset = pprev_tile - prev_tile;
	local ppprev_tile = pprev_tile && path._prev._prev._prev ? path._prev._prev._prev._tile : 0;
	local ppprev_pprev_offset = ppprev_tile - pprev_tile;
	local prev_cur_offset = prev_tile - cur_tile;

	local cost = 0;

	/* If the two tiles are more than 1 tile apart, the pathfinder wants a bridge or tunnel
	 *  to be built. It isn't an existing bridge / tunnel, as that case is already handled. */
	if (cur_next_dist >= min_tunnelbridge_length) {
		if (pprev_tile && pprev_prev_offset / distance_manhattan(pprev_tile, prev_tile) != prev_cur_offset) {
			cost += this._cost_turn45;
			if (ppprev_tile)
				if (ppprev_pprev_offset != prev_cur_offset && distance_manhattan(ppprev_tile, cur_tile) == 3)
					cost += this._cost_consecutive_turn;
				else if (-prev_cur_offset == ppprev_pprev_offset)
					cost += this._cost_consecutive_turn;
				else if (distance_manhattan(ppprev_tile, pprev_tile) >= min_tunnelbridge_length && ppprev_pprev_offset / distance_manhattan(ppprev_tile, pprev_tile) != prev_cur_offset)
					cost += this._cost_consecutive_turn;
		}

		/* Check if we should build a bridge or a tunnel. */
		if (get_other_tunnel_end(cur_tile) == next_tile)
			cost += cur_next_dist * this._cost_tile + ++cur_next_dist * this._cost_tunnel_per_tile;
		else {
			if (pprev_tile && prev_tile && is_slope_dir_bridge[get_slope(cur_tile)][-prev_cur_offset])
				if (distance_manhattan(pprev_tile, prev_tile) >= min_tunnelbridge_length) {
					if (get_other_tunnel_end(pprev_tile) != prev_tile && is_slope_dir_bridge[get_slope(prev_tile)][pprev_prev_offset / distance_manhattan(pprev_tile, prev_tile)])
						cost += this._cost_consecutive_slope;
				} else if (is_slope_dirbit_rail[get_slope(prev_tile)][dir_to_dirbit_rail_2d[pprev_prev_offset][prev_cur_offset]])
					cost += this._cost_consecutive_slope;
			cost += cur_next_dist * this._cost_tile + (is_slope_dir_bridge[get_slope(next_tile)][prev_cur_offset] + is_slope_dir_bridge[get_slope(cur_tile)][-prev_cur_offset]) * this._cost_slope + ++cur_next_dist * this._cost_bridge_per_tile;
			if (has_transport_type(cur_tile, transport_water))
				cost += this._cost_coast;
			if (has_transport_type(next_tile, transport_water))
				cost += this._cost_coast;
		}

		return path._cost + cost;
	}

	/* Check for a turn. We do this by substracting the TileID of the current
	 *  node from the TileID of the previous node and comparing that to the
	 *  difference between the tile before the previous node and the node before
	 *  that. */
	if (prev_tile) {
		local prev_cur_dist_is_1 = distance_manhattan(prev_tile, cur_tile) < min_tunnelbridge_length;
		local cur_next_offset = cur_tile - next_tile;
		if (prev_cur_offset != cur_next_offset && prev_cur_dist_is_1)
			cost += this._cost_diagonal_tile;
		else
			cost += this._cost_tile;

		if (prev_cur_dist_is_1)
			if (is_slope_dirbit_rail[get_slope(cur_tile)][dir_to_dirbit_rail_2d[prev_cur_offset][cur_next_offset]]) {
				cost += this._cost_slope;
				if (pprev_tile)
					if (distance_manhattan(pprev_tile, prev_tile) >= min_tunnelbridge_length) {
						if (get_other_tunnel_end(pprev_tile) != prev_tile && is_slope_dir_bridge[get_slope(prev_tile)][pprev_prev_offset / distance_manhattan(pprev_tile, prev_tile)])
							cost += this._cost_consecutive_slope;
					} else if (is_slope_dirbit_rail[get_slope(prev_tile)][dir_to_dirbit_rail_2d[pprev_prev_offset][prev_cur_offset]])
						cost += this._cost_consecutive_slope;
			}

		if (pprev_tile) {
			if (pprev_prev_offset != cur_next_offset && distance_manhattan(pprev_tile, next_tile) == 3) {
				cost += this._cost_turn45;
				if (ppprev_tile)
					if (ppprev_pprev_offset != prev_cur_offset && distance_manhattan(ppprev_tile, cur_tile) == 3)
						cost += this._cost_consecutive_turn;
					else if (-prev_cur_offset == ppprev_pprev_offset)
						cost += this._cost_consecutive_turn;
					else if (distance_manhattan(ppprev_tile, pprev_tile) >= min_tunnelbridge_length && ppprev_pprev_offset / distance_manhattan(ppprev_tile, pprev_tile) != prev_cur_offset / distance_manhattan(prev_tile, cur_tile))
						cost += this._cost_consecutive_turn;
			} else if (-cur_next_offset == pprev_prev_offset) {
				cost += this._cost_turn90;
				if (ppprev_tile)
					if (ppprev_pprev_offset != prev_cur_offset && distance_manhattan(ppprev_tile, cur_tile) == 3)
						cost += this._cost_consecutive_turn;
					else if (-prev_cur_offset == ppprev_pprev_offset)
						cost += this._cost_consecutive_turn;
					else if (distance_manhattan(ppprev_tile, pprev_tile) >= min_tunnelbridge_length && ppprev_pprev_offset / distance_manhattan(ppprev_tile, pprev_tile) != prev_cur_offset / distance_manhattan(prev_tile, cur_tile))
						cost += this._cost_consecutive_turn;
			} else if (distance_manhattan(pprev_tile, prev_tile) >= min_tunnelbridge_length && pprev_prev_offset / distance_manhattan(pprev_tile, prev_tile) != cur_next_offset) {
				cost += this._cost_turn45;
				if (ppprev_tile)
					if (ppprev_pprev_offset != prev_cur_offset && distance_manhattan(ppprev_tile, cur_tile) == 3)
						cost += this._cost_consecutive_turn;
					else if (-prev_cur_offset == ppprev_pprev_offset)
						cost += this._cost_consecutive_turn;
					else if (distance_manhattan(ppprev_tile, pprev_tile) >= min_tunnelbridge_length && ppprev_pprev_offset / distance_manhattan(ppprev_tile, pprev_tile) != prev_cur_offset / distance_manhattan(prev_tile, cur_tile))
						cost += this._cost_consecutive_turn;
			}
		}
	}

	/* Check if the new tile is a level crossing. */
	if (has_transport_type(next_tile, transport_road) || is_road_tile(next_tile))
		cost += this._cost_level_crossing;

	return path._cost + cost;
}

function SingleRail::_Estimate(cur_tile,
	get_tile_x = AIMap.GetTileX,
	get_tile_y = AIMap.GetTileY)
{
	local min_cost = this._max_cost;
	/* As estimate we multiply the lowest possible cost for a single tile with
	 *  with the minimum number of tiles we need to traverse. */
	foreach (index, goal in this._goals) {
		local dx = abs(get_tile_x(cur_tile) - this._goals_x[index]);
		local dy = abs(get_tile_y(cur_tile) - this._goals_y[index]);
		local min = min(dx, dy) * this._cost_diagonal_tile_times_2 + abs(dx - dy) * this._cost_tile;
		if (min < min_cost) min_cost = min;
	}

	return min_cost * this._estimate_multiplier;
}

function SingleRail::_Neighbours(path, cur_tile,
	has_transport_type = AITile.HasTransportType,
	transport_rail = AITile.TRANSPORT_RAIL,
//	transport_water = AITile.TRANSPORT_WATER,
//	transport_road = AITile.TRANSPORT_ROAD,
	distance_manhattan = AIMap.DistanceManhattan,
	build_rail = AIRail.BuildRail,
	get_other_tunnel_end = AITunnel.GetOtherTunnelEnd,
	is_valid_tile = AIMap.IsValidTile,
	get_slope = AITile.GetSlope,
	get_complement_slope = AITile.GetComplementSlope,
	build_tunnel = AITunnel.BuildTunnel,
	vt_rail = AIVehicle.VT_RAIL,
	is_buildable = AITile.IsBuildable,
	get_max_height = AITile.GetMaxHeight,
	build_bridge = AIBridge.BuildBridge,
	offsets_array = PreSingleRail()._offsets_array,
	dir_to_dirbit_rail_2d = PreSingleRail()._dir_to_dirbit_rail_2d,
	dir_to_dirbit_tunnelbridge = PreSingleRail()._dir_to_dirbit_tunnelbridge,
	wooden_bridge = 0,
	min_tunnelbridge_length = 2)
{
	/* Don't build on rails */
	if (has_transport_type(cur_tile, transport_rail)) return [];
//	/* Don't build on coasts */
//	if (has_transport_type(cur_tile, transport_water)) return [];
//	/* Don't build level crossings */
//	if (has_transport_type(cur_tile, transport_road)) return [];

	local prev_tile = path._prev._tile;
	local dist = distance_manhattan(cur_tile, prev_tile);
	local prev_cur_offset = prev_tile - cur_tile;
	/* Check if the current tile is part of a bridge or tunnel. */
	if (dist >= min_tunnelbridge_length) {
		prev_cur_offset /= dist;
		local next_tile = cur_tile - prev_cur_offset;
		foreach (offset in offsets_array[prev_cur_offset])
			if (build_rail(cur_tile, next_tile, next_tile + offset) && !(this._closed.GetValue(next_tile) & dir_to_dirbit_tunnelbridge[prev_cur_offset]))
				return [[next_tile, dir_to_dirbit_tunnelbridge[prev_cur_offset]]];
		return [];
	}

	local neighbours = [];
//	local pprev_prev_dir = path._prev._prev ? path._prev._prev._tile - prev_tile : 0;

	/* Check all neighbours adjacent to the current tile. */
	foreach (offset in offsets_array[prev_cur_offset]) {
		local next_tile = cur_tile + offset;
//		/* Disallow 90 degree turns */
//		if (offset == pprev_prev_dir) continue;
		/* We add them to the neighbours-list if we can build a rail to
		 *  them and no rail exists there. */
		if (build_rail(prev_tile, cur_tile, next_tile) && !(this._closed.GetValue(next_tile) & dir_to_dirbit_rail_2d[prev_cur_offset][offset]))
			neighbours.push([next_tile, dir_to_dirbit_rail_2d[prev_cur_offset][offset]]);
	}

	/* Check if we can build a tunnel, only if no terraforming is needed. */
	local next_tile = get_other_tunnel_end(cur_tile);
	if (is_valid_tile(next_tile) && get_slope(next_tile) == get_complement_slope(get_slope(cur_tile))) {
		local dist = distance_manhattan(cur_tile, next_tile);
		if (cur_tile + (cur_tile - next_tile) / dist == prev_tile && dist >= min_tunnelbridge_length && dist < this._max_tunnel_length && build_tunnel(vt_rail, cur_tile) && !(this._closed.GetValue(next_tile) & dir_to_dirbit_tunnelbridge[prev_cur_offset])) {
			neighbours.push([next_tile, dir_to_dirbit_tunnelbridge[prev_cur_offset]]);
			return neighbours;
		}
	}

	/* Check if we can build bridges. */
	local cur_max_height = ++get_max_height(cur_tile);
	local dist = min_tunnelbridge_length;
	while (dist < this._max_bridge_length) {
		local next_tile = cur_tile - prev_cur_offset * dist++;
		if (!is_valid_tile(next_tile)) break;
		if (get_max_height(next_tile) > cur_max_height) break;
		if (build_bridge(vt_rail, wooden_bridge, cur_tile, next_tile) && !(this._closed.GetValue(next_tile) & dir_to_dirbit_tunnelbridge[prev_cur_offset]))
			neighbours.push([next_tile, dir_to_dirbit_tunnelbridge[prev_cur_offset]]);
	}

	return neighbours;
}
