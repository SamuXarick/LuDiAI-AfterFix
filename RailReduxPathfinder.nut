/**
 * A class to precalculate some values for the RailRedux Pathfinder, so they don't
 * have to be calculated every time a path is searched. This is used to speed
 * up the pathfinding, as some of these values are used a lot during the search.
 */
class PreRailRedux
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

//	/**
//	 * A table mapping directions to bitfields for rails.
//	 *  The keys of the first dimension are the direction from the previous tile to the current tile.
//	 *  The keys of the second dimension are the direction from the current tile to the next tile.
//	 *  The value is the mapped bitfield for the direction difference.
//	 */
//	_dir_to_dirbit_rail_2d = {
//		[1] = { [-1] = 16, [AIMap.GetMapSizeX()] = 64, [-AIMap.GetMapSizeX()] = 32 },
//		[-1] = { [1] = 128, [AIMap.GetMapSizeX()] = 512, [-AIMap.GetMapSizeX()] = 256 },
//		[AIMap.GetMapSizeX()] = { [1] = 2048, [-1] = 1024, [-AIMap.GetMapSizeX()] = 4096 },
//		[-AIMap.GetMapSizeX()] = { [1] = 16384, [-1] = 8192, [AIMap.GetMapSizeX()] = 32768 }
//	};

	/**
	 * A table mapping directions to bitfields for rails.
	 *  The keys are the direction from the previous tile to the current tile.
	 *  The value is the mapped bitfield for the direction difference.
	 */
	_dir_to_dirbit_rail_1d = {
		[1] = 32,
		[-1] = 16,
		[AIMap.GetMapSizeX()] = 128,
		[-AIMap.GetMapSizeX()] = 64
	};
};

/**
 * A RailRedux Pathfinder.
 */
class RailRedux
{
	/** AyStar Graph */
	_open = null;                       ///< The open list, this is a priority queue of paths that are not yet scanned.
	_closed = null;                     ///< The closed list, this is a list of tiles that are already scanned, with the directions we came from as bitfields.

	/** Costs */
	_max_cost = null;                   ///< The maximum cost for a route.
	_cost_tile = null;                  ///< The cost for a single tile.
	_cost_diagonal_tile = null;         ///< The cost for a diagonal tile.
	_cost_turn = null;                  ///< The cost for a direction change, this is added to _cost_tile.
	_cost_bridge_per_tile = null;       ///< The cost per tile of a new bridge, this is added to _cost_tile.
	_cost_tunnel_per_tile = null;       ///< The cost per tile of a new tunnel, this is added to _cost_tile.
	_max_bridge_length = null;          ///< The maximum length of a bridge that will be built.
	_max_tunnel_length = null;          ///< The maximum length of a tunnel that will be built.

	cost = null;                        ///< Used to change the costs.
	_running = null;                    ///< Indicates if the pathfinder is currently running, that is, if FindPath returned false and it is not yet finished looking for a path.
	_goals = null;                      ///< The goal tiles, this is an array of [tile, next_tile]-pairs.

	/** Precalculated values to speed up the estimation costs. */
	_goals_x = null;                    ///< The x-coordinates of the goal tiles, this is used to speed up the estimation.
	_goals_y = null;                    ///< The y-coordinates of the goal tiles, this is used to speed up the estimation.
	_cost_diagonal_tile_times_2 = null; ///< The cost for a diagonal tile, multiplied by 2, this is used to speed up the estimation. Not a real cost parameter!

	constructor()
	{
		/** Default values for the costs, these can be changed by setting the cost property. */
		this._max_cost = 10000000;
		this._cost_tile = 100;
		this._cost_diagonal_tile = 70;
		this._cost_turn = 50;
		this._cost_bridge_per_tile = 150;
		this._cost_tunnel_per_tile = 120;
		this._max_bridge_length = 6;
		this._max_tunnel_length = 6;

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

class RailRedux.Cost
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
			case "max_cost":          this._main._max_cost = val; break;
			case "tile":              this._main._cost_tile = val; break;
			case "diagonal_tile":     this._main._cost_diagonal_tile = val; this._main._cost_diagonal_tile_times_2 = val * 2; break;
			case "turn":              this._main._cost_turn = val; break;
			case "bridge_per_tile":   this._main._cost_bridge_per_tile = val; break;
			case "tunnel_per_tile":   this._main._cost_tunnel_per_tile = val; break;
			case "max_bridge_length": this._main._max_bridge_length = val; break;
			case "max_tunnel_length": this._main._max_tunnel_length = val; break;
			default: throw "the index '" + idx + "' does not exist";
		}

		return val;
	}

	function _get(idx)
	{
		switch (idx) {
			case "max_cost":          return this._main._max_cost;
			case "tile":              return this._main._cost_tile;
			case "diagonal_tile":     return this._main._cost_diagonal_tile;
			case "turn":              return this._main._cost_turn;
			case "bridge_per_tile":   return this._main._cost_bridge_per_tile;
			case "tunnel_per_tile":   return this._main._cost_tunnel_per_tile;
			case "max_bridge_length": return this._main._max_bridge_length;
			case "max_tunnel_length": return this._main._max_tunnel_length;
			default: throw "the index '" + idx + "' does not exist";
		}
	}
};

function RailRedux::InitializePath(sources, goals, ignored_tiles = [],
	get_tile_x = AIMap.GetTileX,
	get_tile_y = AIMap.GetTileY,
	distance_manhattan = AIMap.DistanceManhattan)
{
	this._goals = goals;
	this._goals_x = [];
	this._goals_y = [];

	foreach (goal in this._goals) {
		this._goals_x.append(get_tile_x(goal[0]));
		this._goals_y.append(get_tile_y(goal[0]));
	}

	this._open = AIPriorityQueue();

	foreach (node in sources) {
		if (typeof(node) == "array") {
			local path = null;
			local n = node.len();
			if (n <= 1) throw "Each source node must be an array containing at least 2 tiles.";
			foreach (i, tile in node) {
				local next_tile = node[n - 1 - i];
				if (path && distance_manhattan(path._tile, next_tile) != 1) throw "Source node tiles must be adjacent to each other."
				path = this._Path(path, next_tile, n - i > 1 ? 0 : 0xFFFF);
			}
			this._open.Insert(path, path._cost + this._Estimate(path._tile));
		} else if (typeof(node) == "table") {
			this._open.Insert(node, node._cost);
		} else {
			throw "Sources must be an array or RailRedux._Path tables"
		}
	}

	this._closed = AIList();

	foreach (tile in ignored_tiles)
		this._closed[tile] = ~0;
}

function RailRedux::FindPath(iterations)
{
	local test_mode = AITestMode();
	local ret = this._FindPath(iterations);
	this._running = ret == false;

	return ret;
}

function RailRedux::_FindPath(iterations)
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
			if (cur_tile == goal[0]) {
				foreach (node in this._Neighbours(path, cur_tile)) {
					if (node[0] == goal[1]) {
						this._CleanPath();
						return this._Path(path, node[0], node[1]);
					}
				}
			}
		}

		/* Scan all neighbours */
		foreach (node in this._Neighbours(path, cur_tile)) {
			/* Calculate the new paths and add them to the open list */
			local new_path = this._Path(path, node[0], node[1]);
			this._open.Insert(new_path, new_path._cost + this._Estimate(node[0]));
		}
	}

	if (this._open.Count()) return false;
	this._CleanPath();

	return;
}

function RailRedux::_PathCollides(path, cur_tile)
{
	local scan_path = path._prev;
	while (scan_path) {
		if (scan_path._tile == cur_tile)
			return true;
		scan_path = scan_path._prev;
	}

	return;
}

function RailRedux::_CleanPath()
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
function RailRedux::_Path(path, next_tile, prev_cur_dirbit)
{
	return {
		_prev = path,
		_tile = next_tile,
		_direction = prev_cur_dirbit,
		_cost = this._Cost(path, next_tile)
	};
}

function RailRedux::_Cost(path, next_tile,
	distance_manhattan = AIMap.DistanceManhattan,
	get_other_tunnel_end = AITunnel.GetOtherTunnelEnd,
	min_tunnelbridge_length = 2,
	cost = 0,
	prev_tile = 0,
	pprev_tile = 0,
	pprev_prev_offset = 0)
{
	/* path == null means this is the first node of a path, so the cost is 0. */
	if (!path) return 0;

	local cur_tile = path._tile;
	if (path._prev) prev_tile = path._prev._tile;
	if (prev_tile && path._prev._prev) pprev_tile = path._prev._prev._tile;
	local cur_next_dist = distance_manhattan(cur_tile, next_tile);
	pprev_prev_offset = pprev_tile - prev_tile;

	/* If the two tiles are more than 1 tile apart, the pathfinder wants a bridge or tunnel
	 *  to be build. It isn't an existing bridge / tunnel, as that case is already handled. */
	if (cur_next_dist >= min_tunnelbridge_length) {
		if (pprev_tile)
			if (pprev_prev_offset / distance_manhattan(pprev_tile, prev_tile) != prev_tile - cur_tile)
				cost += this._cost_turn;

		/* Check if we should build a bridge or a tunnel. */
		if (get_other_tunnel_end(next_tile) == cur_tile)
			cost += cur_next_dist * this._cost_tile + ++cur_next_dist * this._cost_tunnel_per_tile;
		else
			cost += cur_next_dist * this._cost_tile + ++cur_next_dist * this._cost_bridge_per_tile;

		return path._cost + cost;
	}

	/* Check for a turn. We do this by substracting the TileID of the current
	 *  node from the TileID of the previous node and comparing that to the
	 *  difference between the tile before the previous node and the node before
	 *  that. */
	if (prev_tile) {
		local cur_next_offset = cur_tile - next_tile;
		if (prev_tile - cur_tile == cur_next_offset || distance_manhattan(prev_tile, cur_tile) >= min_tunnelbridge_length)
			cost += this._cost_tile;
		else
			cost += this._cost_diagonal_tile;

		if (pprev_tile) {
			if (pprev_prev_offset != cur_next_offset && distance_manhattan(pprev_tile, next_tile) == 3)
				cost += this._cost_turn;
			else if (distance_manhattan(pprev_tile, prev_tile) >= min_tunnelbridge_length && pprev_prev_offset / distance_manhattan(pprev_tile, prev_tile) != cur_next_offset)
				cost += this._cost_turn;
		}
	}

	return path._cost + cost;
}

function RailRedux::_Estimate(cur_tile,
	get_tile_x = AIMap.GetTileX,
	get_tile_y = AIMap.GetTileY,
	min_cost = 0x7FFFFFFFFFFFFFFF,
	estimate_multiplier = 3)
{
	/* As estimate we multiply the lowest possible cost for a single tile with
	 *  with the minimum number of tiles we need to traverse. */
	foreach (index, goal in this._goals) {
		local dx = abs(get_tile_x(cur_tile) - this._goals_x[index]);
		local dy = abs(get_tile_y(cur_tile) - this._goals_y[index]);
		local min = min(dx, dy) * this._cost_diagonal_tile_times_2 + abs(dx - dy) * this._cost_tile;
		if (min < min_cost) min_cost = min;
	}

	return estimate_multiplier * min_cost;
}

function RailRedux::_Neighbours(path, cur_tile,
	has_transport_type = AITile.HasTransportType,
	transport_rail = AITile.TRANSPORT_RAIL,
//	transport_water = AITile.TRANSPORT_WATER,
	transport_road = AITile.TRANSPORT_ROAD,
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
	offsets_array = PreRailRedux()._offsets_array,
//	dir_to_dirbit_rail_2d = PreRailRedux()._dir_to_dirbit_rail_2d,
	dir_to_dirbit_rail_1d = PreRailRedux()._dir_to_dirbit_rail_1d,
	dir_to_dirbit_tunnelbridge = PreRailRedux()._dir_to_dirbit_tunnelbridge,
	wooden_bridge = 0,
	min_tunnelbridge_length = 2,
	pprev_prev_dir = 0,
	bridge_dist = 2)
{
	/* Don't build on rails */
	if (has_transport_type(cur_tile, transport_rail)) return [];
	/* Don't build on coasts */
//	if (has_transport_type(cur_tile, transport_water)) return [];
	/* Don't build level crossings */
	if (has_transport_type(cur_tile, transport_road)) return [];

	/* this._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
	if (path._cost >= this._max_cost) return [];

	local prev_tile = path._prev._tile;
	local prev_cur_dist = distance_manhattan(prev_tile, cur_tile);
	local prev_cur_offset = prev_tile - cur_tile;
	/* Check if the current tile is part of a bridge or tunnel. */
	if (prev_cur_dist >= min_tunnelbridge_length) {
		prev_cur_offset /= prev_cur_dist;
		local next_tile = cur_tile - prev_cur_offset;
		foreach (offset in offsets_array[prev_cur_offset])
			if (build_rail(cur_tile, next_tile, next_tile + offset) && !(this._closed.GetValue(next_tile) & dir_to_dirbit_tunnelbridge[prev_cur_offset]))
				return [[next_tile, dir_to_dirbit_tunnelbridge[prev_cur_offset]]];
		return [];
	}

	local neighbours = [];
	if (path._prev._prev) pprev_prev_dir = path._prev._prev._tile - prev_tile;

	/* Check all neighbours adjacent to the current tile. */
	foreach (offset in offsets_array[prev_cur_offset]) {
		local next_tile = cur_tile + offset;
		/* Disallow 90 degree turns */
		if (offset == pprev_prev_dir) continue;
		/* We add them to the neighbours-list if we can build a rail to
		 *  them and no rail exists there. */
//		if (build_rail(prev_tile, cur_tile, next_tile) && !(this._closed.GetValue(next_tile) & dir_to_dirbit_rail_2d[prev_cur_offset][offset]))
//			neighbours.push([next_tile, dir_to_dirbit_rail_2d[prev_cur_offset][offset]]);
		if (build_rail(prev_tile, cur_tile, next_tile) && !(this._closed.GetValue(next_tile) & dir_to_dirbit_rail_1d[offset]))
			neighbours.push([next_tile, dir_to_dirbit_rail_1d[offset]]);
	}

	/* Check if we can build a tunnel, only if no terraforming is needed. */
	local next_tile = get_other_tunnel_end(cur_tile);
	if (is_valid_tile(next_tile) && get_slope(next_tile) == get_complement_slope(get_slope(cur_tile))) {
		local cur_next_dist = distance_manhattan(cur_tile, next_tile);
		if (cur_tile + (cur_tile - next_tile) / cur_next_dist == prev_tile && cur_next_dist >= min_tunnelbridge_length && cur_next_dist < this._max_tunnel_length && build_tunnel(vt_rail, cur_tile) && !(this._closed.GetValue(next_tile) & dir_to_dirbit_tunnelbridge[prev_cur_offset])) {
			neighbours.push([next_tile, dir_to_dirbit_tunnelbridge[prev_cur_offset]]);
			return neighbours;
		}
	}

	/* Check if we can build a bridge, over a non-buildable tile. */
	if (is_buildable(cur_tile - prev_cur_offset)) return neighbours;
	local cur_max_height = ++get_max_height(cur_tile);
	while (bridge_dist < this._max_bridge_length) {
		local next_tile = cur_tile - prev_cur_offset * bridge_dist++;
		if (!is_valid_tile(next_tile)) break;
		if (get_max_height(next_tile) > cur_max_height) break;
		if (build_bridge(vt_rail, wooden_bridge, cur_tile, next_tile) && !(this._closed.GetValue(next_tile) & dir_to_dirbit_tunnelbridge[prev_cur_offset])) {
			neighbours.push([next_tile, dir_to_dirbit_tunnelbridge[prev_cur_offset]]);
			return neighbours;
		}
	}

	return neighbours;
}
