/**
 * An AyStar implementation.
 *  It solves graphs by finding the fastest route from one point to the other.
 */
class AyStar
{
	_queue_class = AIPriorityQueue;
	_pf_instance = null;
	_cost_callback = null;
	_estimate_callback = null;
	_neighbours_callback = null;
	_check_direction_callback = null;
	_open = null;
	_closed = null;
	_goals = null;

	/**
	 * @param pf_instance An instance that'll be used as 'this' for all
	 *  the callback functions.
	 * @param cost_callback A function that returns the cost of a path. It
	 *  should accept four parameters, old_path, new_tile, new_direction and
	 *  cost_callback_param. old_path is an instance of AyStar.Path, and
	 *  new_node is the new node that is added to that path. It should return
	 *  the cost of the path including new_node.
	 * @param estimate_callback A function that returns an estimate from a node
	 *  to the goal node. It should accept four parameters, tile, direction,
	 *  goal_nodes and estimate_callback_param. It should return an estimate to
	 *  the cost from the lowest cost between node and any node out of goal_nodes.
	 *  Note that this estimate is not allowed to be higher than the real cost
	 *  between node and any of goal_nodes. A lower value is fine, however the
	 *  closer it is to the real value, the better the performance.
	 * @param neighbours_callback A function that returns all neighbouring nodes
	 *  from a given node. It should accept three parameters, current_path, node
	 *  and neighbours_callback_param. It should return an array containing all
	 *  neighbouring nodes, which are an array in the form [tile, direction].
	 * @param check_direction_callback A function that returns either false or
	 *  true. It should accept four parameters, tile, existing_direction,
	 *  new_direction and check_direction_callback_param. It should check
	 *  if both directions can go together on a single tile.
	 */
	constructor(pf_instance, cost_callback, estimate_callback, neighbours_callback, check_direction_callback)
	{
		if (typeof(pf_instance) != "instance") throw("'pf_instance' has to be an instance.");
		if (typeof(cost_callback) != "function") throw("'cost_callback' has to be a function-pointer.");
		if (typeof(estimate_callback) != "function") throw("'estimate_callback' has to be a function-pointer.");
		if (typeof(neighbours_callback) != "function") throw("'neighbours_callback' has to be a function-pointer.");
		if (typeof(check_direction_callback) != "function") throw("'check_direction_callback' has to be a function-pointer.");

		this._pf_instance = pf_instance;
		this._cost_callback = cost_callback;
		this._estimate_callback = estimate_callback;
		this._neighbours_callback = neighbours_callback;
		this._check_direction_callback = check_direction_callback;
	}

	/**
	 * Initialize a path search between sources and goals.
	 * @param sources The source nodes. This can an array of either [tile, direction]-pairs or AyStar.Path-instances.
	 * @param goals The target tiles. This can be an array of either tiles or [tile, next_tile]-pairs.
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

function AyStar::InitializePath(sources, goals, ignored_tiles = [])
{
	if (typeof(sources) != "array" || sources.len() == 0) throw("sources has to be a non-empty array.");
	if (typeof(goals) != "array" || goals.len() == 0) throw("goals has to be a non-empty array.");

	this._open = this._queue_class();
	this._closed = AIList();
//	this._closed = {};

	foreach (node in sources) {
		if (typeof(node) == "array") {
			if (node[1] <= 0) throw("directional value should never be zero or negative.");

			local new_path = this.Path(null, node[0], node[1], node[2], this._cost_callback, this._pf_instance);
			this._open.Insert(new_path, new_path._cost + this._estimate_callback(this._pf_instance, node[0], node[1], goals));
		} else {
			this._open.Insert(node, node._cost);
		}
	}

	this._goals = goals;

	foreach (tile in ignored_tiles) {
		this._closed.AddItem(tile, ~0);
//		this._closed.rawset(tile, ~0);
	}
}

function AyStar::FindPath(iterations)
{
	if (this._open == null) throw("can't execute over an uninitialized path");

	while (this._open.Count() > 0 && (iterations == -1 || iterations-- > 0)) {
		/* Get the path with the best score so far */
		local path = this._open.Pop();
		local cur_tile = path._tile;
		local direction = path._direction;
//		local text = "Path so far: ";
//		local temp = path._prev;
//		while (temp != null) {
//			text += "[" + temp._tile + ", " + temp._direction + "], ";
//			temp = temp._prev;
//		}
//		AILog.Warning(text);
//		AILog.Warning("cur_path cost = " + path._cost);
//		AILog.Error("1 - [" + cur_tile + ", " + direction + "]");
//		AIController.Break("");
		local scan_path;
		local scan_dir;

//		AILog.Info("###cur_tile = " + cur_tile + "; direction = " + direction);
		/* Make sure we didn't already passed it */
		if (this._closed.HasItem(cur_tile)) {
//		if (this._closed.rawin(cur_tile)) {
			local old_dir = this._closed.GetValue(cur_tile);
//			local old_dir = this._closed.rawget(cur_tile);
//			AILog.Info(" best path: this._closed.HasItem (" + cur_tile + ") == true");
			/* If the direction is already on the list, skip this entry */
			if ((old_dir & direction) != 0) {
//				AILog.Info("  Direction is already on the list! (" + old_dir + " & " + direction + ") != 0");
				continue;
			}

			/* Scan the path for a possible collision */
			scan_path = path._prev;
			scan_dir = direction;

			local mismatch = false;
			while (scan_path != null) {
				local scan_tile = scan_path._tile;
				local scan_prev_dir = scan_path._direction;
//				AILog.Info("  scan_tile = " + scan_tile + "; scan_dir = " + scan_dir + "; scan_prev_dir = " + scan_prev_dir);
				if (scan_tile == cur_tile) {
//					AILog.Info("   scan_path has tile " + cur_tile + " == true");
					if (!this._check_direction_callback(this._pf_instance, false, scan_dir, direction)) {
//						AILog.Info("    mismatch = true!; scan_dir = " + scan_dir + "; direction = " + direction);
						mismatch = true;
					}
					break;
				}
				scan_dir = scan_prev_dir;
				scan_path = scan_path._prev;
			}
			if (mismatch) continue;

			/* Add the new direction */
			this._closed.SetValue(cur_tile, old_dir | direction);
//			this._closed.rawset(cur_tile, old_dir | direction);
//			AILog.Info(" Add the new direction: cur_tile = " + cur_tile + "; old_dir = " + old_dir + "; direction = " + direction + "; old_dir | direction = " + (old_dir | direction));
		} else {
			/* New entry, make sure we don't check it again */
			this._closed.AddItem(cur_tile, direction);
//			this._closed.rawset(cur_tile, direction);
//			AILog.Info(" New entry! Make sure we don't check it again: cur_tile = " + cur_tile + "; direction = " + direction);
		}

		/* Check if we found the end */
		foreach (goal in this._goals) {
			if (typeof(goal) == "array") {
				if (cur_tile == goal[2] && path._prev._tile == goal[1] && path._prev._prev._tile == goal[0]) {
//					AIController.Break("Goal reached!");
//					local count = 0;
//					local scan_path = path;
//					while (scan_path != null) {
//						count++;
//						scan_path = scan_path.GetParent();
//					}
//					local array = array(count);
//					scan_path = path;
//					while (scan_path != null) {
//						count--;
//						array[count] = scan_path;
//						scan_path = scan_path.GetParent();
//					}
//					local cost_prev = 0;
//					foreach (id, scan in array) {
//						local cost = scan._cost;
//						local diff = cost - cost_prev;
//						local temp = this.Path(scan.GetParent(), scan._tile, scan._direction, scan._used_tiles, this._cost_callback, this._pf_instance);
//						AILog.Info("id #" + id + " - " + scan._tile + " / " + scan._direction + "; Cost: " + cost + "; Diff: " + diff);
//						cost_prev = cost;
//					}
					return path;
				}
//				if (cur_tile == goal[1] && path._prev._tile == goal[0]) {
//					this._CleanPath();
//					return path;
//				}
//				if (cur_tile == goal[0]) {
//					local neighbours = this._neighbours_callback(this._pf_instance, path, cur_tile);
//					foreach (node in neighbours) {
//						if (node[0] == goal[1]) {
//							this._CleanPath();
//							return path;
//						}
//					}
//					continue;
//				}
			} else {
				if (cur_tile == goal) {
					this._CleanPath();
					return path;
				}
			}
		}

		/* Scan all neighbours */
		local neighbours = this._neighbours_callback(this._pf_instance, path, cur_tile);
//		AILog.Warning("Scan all neighbours = " + neighbours.len());

//		AILog.Info("cur_tile = " + cur_tile + " has " + neighbours.len() + " neighbours");
		foreach (node in neighbours) {
			local neighbour_tile = node[0];
			local neighbour_dir = node[1];
//			AILog.Info(" neighbour_tile = " + neighbour_tile + "; neighbour_dir = " + neighbour_dir);
			if (neighbour_dir <= 0) throw("directional value should never be zero or negative.");

			if (this._closed.HasItem(neighbour_tile)) {
//			if (this._closed.rawin(neighbour_tile)) {
				local closed_dir = this._closed.GetValue(neighbour_tile);
//				local closed_dir = this._closed.rawget(neighbour_tile);
//				AILog.Info("  neighbours: this._closed.HasItem(" + neighbour_tile + ") == true");
				if ((closed_dir & neighbour_dir) != 0) {
//					AILog.Info("   closed_dir = " + closed_dir + "; neighbour_dir = " + neighbour_dir + ": (" + closed_dir + " & " + neighbour_dir + ") != 0");
					continue;
				}
			}

			if (scan_path != null && !this._check_direction_callback(this._pf_instance, true, scan_dir, neighbour_dir)) {
//				AILog.Info("    collision = true!; scan_dir = " + scan_dir + "; neighbour_dir = " + neighbour_dir);
				continue;
			}

			/* Calculate the new paths and add them to the open list */
			local new_path = this.Path(path, neighbour_tile, neighbour_dir, node[2], this._cost_callback, this._pf_instance);

			/* Check if we're near the end */
			foreach (goal in this._goals) {
				if (typeof(goal) == "array") {
					if (neighbour_tile == goal[1] && cur_tile == goal[0]) {
//						AILog.Info("we're pushing the end goal! " + goal[2] + " / " + neighbour_tile + " / " + cur_tile);
						neighbour_tile = goal[2];
						neighbour_dir = 0;
						new_path = this.Path(new_path, neighbour_tile, neighbour_dir, [], this._cost_callback, this._pf_instance);
						break;
					}
				}
			}
			if (new_path._cost >= this._pf_instance._max_cost) {
//				AILog.Info("new_path._cost >= this._pf_instance._max_cost : " + new_path._cost + " >= " + this._pf_instance._max_cost);
				continue;
			}

//			AILog.Info("cost + estimate = " + new_path._cost + " + " + this._estimate_callback(this._pf_instance, neighbour_tile, neighbour_dir, this._goals) + " = " + (new_path._cost + this._estimate_callback(this._pf_instance, neighbour_tile, neighbour_dir, this._goals)));
			this._open.Insert(new_path, (new_path._cost + this._estimate_callback(this._pf_instance, neighbour_tile, neighbour_dir, this._goals)));
		}
	}

	if (this._open.Count() > 0) return false;
	this._CleanPath();
	return null;
}

function AyStar::_CleanPath()
{
	this._closed = null;
	this._open = null;
	this._goals = null;
}

/**
 * The path of the AyStar algorithm.
 *  It is reversed, that is, the first entry is more close to the goal-nodes
 *  than his GetParent(). You can walk this list to find the whole path.
 *  The last entry has a GetParent() of null.
 */
class AyStar.Path
{
	_prev = null;
	_tile = null;
	_direction = null;
	_cost = null;
	_used_tiles = null;

	constructor(old_path, new_tile, new_direction, new_used_tiles, cost_callback, pf_instance)
	{
		this._prev = old_path;
		this._tile = new_tile;
		this._direction = new_direction;
		this._cost = cost_callback(pf_instance, old_path, new_tile, new_direction);
		this._used_tiles = new_used_tiles;
	};

	/**
	 * Return the tile where this (partial-)path ends.
	 */
	function GetTile() { return this._tile; }

	/**
	 * Return the direction from which we entered the tile in this (partial-)path.
	 */
	function GetDirection() { return this._direction; }

	/**
	 * Return an instance of this class leading to the previous node.
	 */
	function GetParent() { return this._prev; }

	/**
	 * Return the cost of this (partial-)path from the beginning up to this node.
	 */
	function GetCost() { return this._cost; }

	/**
	 * Return the used tiles of this (partial-)path from the beginning up to this node.
	 */
	function GetUsedTiles() {
		local used_tiles = [];
		local path = this;
		do {
			used_tiles.extend(path._used_tiles);
			path = path._prev;
		} while (path != null);
		return used_tiles;
	}
};
