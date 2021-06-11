/**
 * An AyStar implementation.
 *	It solves graphs by finding the fastest route from one point to the other.
 */
class AyStar
{
	_queue_class = AIPriorityQueue;
	_pf_instance = null;
	_cost_callback = null;
	_estimate_callback = null;
	_neighbours_callback = null;
	_open = null;
	_closed = null;
	_goal = null;

	/**
	 * @param pf_instance An instance that'll be used as 'this' for all
	 *	the callback functions.
	 * @param cost_callback A function that returns the cost of a path. It
	 *	should accept three parameters, old_path, new_tile and
	 *	cost_callback_param. old_path is an instance of AyStar.Path, and
	 *	new_node is the new node that is added to that path. It should return
	 *	the cost of the path including new_node.
	 * @param estimate_callback A function that returns an estimate from a node
	 *	to the goal node. It should accept three parameters, tile,
	 *	goal_node and estimate_callback_param. It should return an estimate to
	 *	the cost between node and goal_node.
	 *	Note that this estimate is not allowed to be higher than the real cost
	 *	between node and goal_node. A lower value is fine, however the closer it
	 *	is to the real value, the better the performance.
	 * @param neighbours_callback A function that returns all neighbouring nodes
	 *	from a given node. It should accept three parameters, current_path, node
	 *	and neighbours_callback_param. It should return an array containing all
	 *	neighbouring nodes, which are an array in the form [tile, direction].
	 */
	constructor(pf_instance, cost_callback, estimate_callback, neighbours_callback)
	{
		this._pf_instance = pf_instance;
		this._cost_callback = cost_callback;
		this._estimate_callback = estimate_callback;
		this._neighbours_callback = neighbours_callback;
	}

	/**
	 * Initialize a path search between source and goal.
	 * @param source The source node. This is a pair in the form [tile, direction].
	 * @param goal The target tile. This is a tile.
	 */
	function InitializePath(source, goal);

	/**
	 * Try to find the path as indicated with InitializePath with the lowest cost.
	 * @param iterations After how many iterations it should abort for a moment.
	 *	This value should be > 0. Any other value aborts immediately and will never
	 *	find a path.
	 * @return A route if one was found, or false if the amount of iterations was
	 *	reached, or null if no path was found.
	 *	You can call this function over and over as long as it returns false,
	 *	which is an indication it is not yet done looking for a route.
	 */
	function FindPath(iterations);
};

function AyStar::InitializePath(source, goal)
{
	this._open = this._queue_class();
	this._closed = AIList();

	local new_path = this.Path(null, source[0], source[1], this._cost_callback, this._pf_instance);
	this._open.Insert(new_path, new_path._cost + this._estimate_callback(this._pf_instance, source[0], goal));

	this._goal = goal;
}

function AyStar::FindPath(iterations)
{
	while (this._open.Count() && iterations-- > 0) {
		/* Get the path with the best score so far */
		local path = this._open.Pop();
		local cur_tile = path._tile;
		local dir = path._direction;
		/* Make sure we didn't already passed it */
		if (this._closed.HasItem(cur_tile)) {
			/* If the direction is already on the list, skip this entry */
			if (this._closed.GetValue(cur_tile) & dir) continue;

//			/* Scan the path for a possible collision */
//			local scan_path = path.GetParent();
//
//			local mismatch = false;
//			while (scan_path != null) {
//				if (scan_path._tile == cur_tile) {
//					mismatch = true;
//					break;
//				}
//				scan_path = scan_path.GetParent();
//			}
//			if (mismatch) continue;

			/* Add the new direction */
			this._closed.SetValue(cur_tile, this._closed.GetValue(cur_tile) | dir);
		} else {
			/* New entry, make sure we don't check it again */
			this._closed.AddItem(cur_tile, dir);
		}
		/* Check if we found the end */
		if (cur_tile == this._goal) {
			this._CleanPath();
			return path;
		}
		/* Scan all neighbours */
		local neighbours = this._neighbours_callback(this._pf_instance, path, cur_tile);
		foreach (node in neighbours) {
			if (this._closed.GetValue(node[0]) & node[1]) continue;
			/* Calculate the new paths and add them to the open list */
			local new_path = this.Path(path, node[0], node[1], this._cost_callback, this._pf_instance);
			this._open.Insert(new_path, new_path._cost + this._estimate_callback(this._pf_instance, node[0], this._goal));
		}
	}

	if (this._open.Count()) return false;
	this._CleanPath();
	return null;
}

function AyStar::_CleanPath()
{
	this._closed = null;
	this._open = null;
	this._goal = null;
}

/**
 * The path of the AyStar algorithm.
 *	It is reversed, that is, the first entry is more close to the goal-nodes
 *	than his GetParent(). You can walk this list to find the whole path.
 *	The last entry has a GetParent() of null.
 */
class AyStar.Path
{
	_prev = null;
	_tile = null;
	_direction = null;
	_cost = null;

	constructor(old_path, new_tile, new_direction, cost_callback, pf_instance)
	{
		this._prev = old_path;
		this._tile = new_tile;
		this._direction = new_direction;
		this._cost = cost_callback(pf_instance, old_path, new_tile);
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
};
