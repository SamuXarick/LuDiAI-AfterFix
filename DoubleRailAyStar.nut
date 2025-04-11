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
	if (typeof(sources) != "instance") throw("sources has to be a Segment.");
	if (typeof(goals) != "instance") throw("goals has to be a Segment.");

	this._open = this._queue_class();
	this._closed = {};

	this._goals = goals;

	local path = this.Path(null, sources, this._cost_callback, this._pf_instance);
//	local neighbours = this._neighbours_callback(path, sources, this._pf_instance);
//	foreach (node in neighbours) {
//		local new_path = this.Path(path, node, this._cost_callback, this._pf_instance);
		this._open.Insert(path, path._cost + this._estimate_callback(path._segment, this._goals, this._pf_instance));
//	}

	foreach (tile in ignored_tiles) {
		this._closed.rawset(tile, [~0, ~0, ~0]);
	}
}

function AyStar::FindPath(iterations)
{
	if (this._open == null) throw("can't execute over an uninitialized path");

	while (!this._open.IsEmpty() && (iterations == -1 || iterations-- > 0)) {
		/* Get the path with the best score so far */
		local path = this._open.Pop();
		local cur_segment = path.GetSegment();
//		local text = "Path so far: ";
//		local temp = path._prev;
//		while (temp != null) {
//			text += Segment.GetName(temp._segment.m_segment_dir) + ", ";
//			temp = temp.GetParent();
//		}
//		AILog.Warning(text);
//		AILog.Warning("cur_segment cost + estimate = " + path._cost + " +" + this._estimate_callback(cur_segment, this._goals, this._pf_instance) + "=== " + (path._cost + this._estimate_callback(cur_segment, this._goals, this._pf_instance)));
//		AILog.Error("1 - " + Segment.GetName(cur_segment.m_segment_dir));
//		AIController.Break("");
		local closed_copy = {};
		closed_copy = clone this._closed;

		local collider = AIList();
		local passed_all = true;
		foreach (j in [0, 1]) {
			for (local i = 0; i < cur_segment.m_nodes[j].len(); i++) {
				local cur_tile = cur_segment.m_nodes[j][i][0];
				local direction = cur_segment.m_nodes[j][i][1];
				local segment_dir = cur_segment.m_nodes[j][i][4];
				local node_id = cur_segment.m_nodes[j][i][5];

//				AILog.Info("###line = " + (j + 1) + "; node = " + i + "; cur_tile = " + cur_tile + "; direction = " + direction + "; segment_dir = " + segment_dir + "; node_id = " + node_id);
				/* Make sure we didn't already passed it */
				if (this._closed.rawin(cur_tile)) {
					local old_dir = this._closed.rawget(cur_tile);
//					AILog.Info("line = " + (j + 1) + "; node = " + i + ";  best path: this._closed.rawin (" + cur_tile + ") == true");
					/* If the direction is already on the list, skip this entry */
					if ((old_dir[0] & direction) != 0 && (old_dir[1] & segment_dir) != 0 && (old_dir[2] & node_id) != 0) {
//						AILog.Info("line = " + (j + 1) + "; node = " + i + ";   Direction is already on the list! (old_dir[0] & direction) != 0 (" + old_dir[0] + " & " + direction + ") != 0 , (old_dir[1] & segment_dir) != 0 (" + old_dir[1] + " & " + segment_dir + ") != 0 , (old_dir[2] & node_id) != 0 (" + old_dir[2] + " & " + node_id + ") !=0");
						passed_all = false;
						break;
					}

					/* Scan the path for a possible collision */
					foreach (cur_j in [0, 1]) {
						local scan_path = path;
						local cur_i = cur_j == j ? i : 0;
						local scan_dir = cur_segment.m_nodes[cur_j][cur_i][1];
						local scan_prev_dir;
						local scan_node = scan_path.GetPreviousNode(cur_j, cur_i, 1, true);

//						AILog.Info("Scan path start: cur_j = " + (cur_j + 1) + "; cur_i = " + cur_i);
						local temp_i;

						local mismatch = false;
						while (scan_node != null) {
							scan_path = scan_node[0];
							temp_i = scan_node[1];
							local scan_tile = scan_path._segment.m_nodes[cur_j][temp_i][0];
							scan_prev_dir = scan_path._segment.m_nodes[cur_j][temp_i][1];
//							AILog.Info("line = " + (cur_j + 1) + "; node = " + temp_i + ";   scan_tile = " + scan_tile + "; scan_dir = " + scan_dir + "; scan_prev_dir = " + scan_prev_dir);
							if (scan_tile == cur_tile) {
//								AILog.Info("line = " + (cur_j + 1) + "; node = " + temp_i + ";    scan_path has tile " + cur_tile + " == true");
								if (!this._check_direction_callback(false, scan_dir, direction, this._pf_instance)) {
//									AILog.Info("line = " + (cur_j + 1) + "; node = " + temp_i + ";     mismatch = true!; scan_dir = " + scan_dir + "; direction = " + direction);
									mismatch = true;
									break;
								}
								/* this is a possible collision, but needs further confirmation from the neighbour part below */
								collider.AddItem(scan_tile, scan_dir);
//								AILog.Info("possible collision! scan_tile = " + scan_tile + "; scan_dir = " + scan_dir);
								break;
							}
							scan_dir = scan_prev_dir;
							scan_node = scan_path.GetPreviousNode(cur_j, temp_i, 1, true);
						}
						if (mismatch) {
							passed_all = false;
							break;
						}
					}
					if (!passed_all) {
						break;
					}

					local old_dir = this._closed.rawget(cur_tile);
					/* Add the new direction */
					closed_copy.rawset(cur_tile, [old_dir[0] | direction, old_dir[1] | segment_dir, old_dir[2] | node_id]);
//					this._closed.rawset(cur_tile, [old_dir[0] | direction, old_dir[1] | segment_dir, old_dir[2] | node_id]);
//					AILog.Info("line = " + (j + 1) + "; node = " + i + ";  Add the new direction: cur_tile = " + cur_tile + "; old_dir[0] | direction = " + old_dir[0] + " | " + direction + " = " + (old_dir[0] | direction) + "; old_dir[1] | segment_dir = " + old_dir[1] + " | " + segment_dir + " = " + (old_dir[1] | segment_dir) + "; old_dir[2] | node_id = " + old_dir[2] + " | " + node_id + " = " + (old_dir[2] | node_id));
				} else {
					/* New entry, make sure we don't check it again */
					closed_copy.rawset(cur_tile, [direction, segment_dir, node_id]);
//					this._closed.rawset(cur_tile, [direction, segment_dir, node_id]);
//					AILog.Info("line = " + (j + 1) + "; node = " + i + ";  New entry! Make sure we don't check it again: cur_tile = " + cur_tile + "; direction = " + direction + "; segment_dir = " + segment_dir + "; node_id = " + node_id);
				}
			}

			if (!passed_all) {
				break;
			}

		}
		if (passed_all) {
			this._closed.clear();
			this._closed = clone closed_copy;
		} else {
//			AILog.Warning("Cur_Segment " + Segment.GetName(cur_segment.m_segment_dir) + " didn't pass all");
			continue;
		}

		/* Check if we found the end */
		local estimate = this._estimate_callback(cur_segment, this._goals, this._pf_instance);
//		AILog.Info("estimate==" + estimate);
		if (estimate == 0) {
//			local count = 0;
//			local scan_path = path;
//			while (scan_path != null) {
//				count++;
//				scan_path = scan_path.GetParent();
//			}
//			local array = array(count);
//			scan_path = path;
//			while (scan_path != null) {
//				count--;
//				array[count] = scan_path;
//				scan_path = scan_path.GetParent();
//			}
//			local cost_prev = 0;
//			foreach (id, scan in array) {
//				local cost = scan._cost;
//				local diff = cost - cost_prev;
//				AILog.Info("id #" + id + " - " + Segment.GetName(scan._segment.m_segment_dir) + "; Cost: " + cost + "; Diff: " + diff);
//				cost_prev = cost;
//			}
//			AIController.Break("Path found");
			this._CleanPath();
			return path;
		}
//		local neighbours = this._neighbours_callback(path, cur_segment, this._pf_instance);
//		foreach (neighbour in neighbours) {
//			local neighbour_tile1 = neighbour.m_nodes[0].top()[0];
//			local neighbour_tile2 = neighbour.m_nodes[1].top()[0];
///			AILog.Info("goal_tile1 = " + neighbour_tile1 + "; goal_tile2 = " + neighbour_tile2);
//			if (neighbour_tile1 == this._goals.m_nodes[0][0][3] && neighbour_tile2 == this._goals.m_nodes[1][0][3]) {
//				AILog.Info("WE REACHED GOAL!");
//				this._CleanPath();
//				return this.Path(path, neighbour, this._cost_callback, this._pf_instance);
//			}
//		}

		/* Scan all neighbours */
		local neighbours = this._neighbours_callback(path, cur_segment, this._pf_instance);
//		AILog.Warning("Scan all neighbours = " + neighbours.len());
		foreach (neighbour in neighbours) {
			passed_all = true;
//			AILog.Info("Neighbour " + Segment.GetName(neighbour.m_segment_dir));
			foreach (j in [0, 1]) {
				for (local i = 0; i < neighbour.m_nodes[j].len(); i++) {
					local neighbour_tile = neighbour.m_nodes[j][i][0];
					local neighbour_prev_tile = neighbour.m_nodes[j][i][3];
					local neighbour_dir = neighbour.m_nodes[j][i][1];
					local neigh_seg_dir = neighbour.m_nodes[j][i][4];
					local neigh_node_id = neighbour.m_nodes[j][i][5];
//					AILog.Info("line = " + (j + 1) + "; node = " + i + ";  neighbour_tile = " + neighbour_tile + "; neighbour_dir = " + neighbour_dir + "; neigh_seg_dir = " + neigh_seg_dir + "; neigh_node_id = " + neigh_node_id);
//					if (neighbour_dir <= 0) throw("directional value should never be zero or negative.");
//					if (neigh_seg_dir <= 0) throw("segment directional value should never be zero or negative.");

					if (this._closed.rawin(neighbour_tile)) {
						local closed_dir = this._closed.rawget(neighbour_tile);
//						AILog.Info("line = " + (j + 1) + "; node = " + i + ";   neighbours: this._closed.rawin(" + neighbour_tile + ") == true");
						if ((closed_dir[0] & neighbour_dir) != 0 && (closed_dir[1] & neigh_seg_dir) != 0 && (closed_dir[2] & neigh_node_id) != 0) {
//							AILog.Info("line = " + (j + 1) + "; node = " + i + ";    Direction already on the list! (closed_dir[0] & neighbour_dir) != 0 (" + closed_dir[0] + " & " + neighbour_dir + ") != 0 , (closed_dir[1] & neigh_seg_dir) != 0 (" + closed_dir[1] + " & " + neigh_seg_dir + ") != 0 , (closed_dir[2] & neigh_node_id) != 0 (" + closed_dir[2] + " & " + neigh_node_id + ") != 0");
							passed_all = false;
							break;
						}
					}

					foreach (collision_tile, collision_dir in collider) {
//						AILog.Info("collision_tile = " + collision_tile + "; collision_dir = " + collision_dir);
						if (neighbour_prev_tile == collision_tile) {
							if (!this._check_direction_callback(true, neighbour_dir, collision_dir, this._pf_instance)) {
//								AILog.Info("    collision = true!; neighbour_prev_tile = " + neighbour_prev_tile + "; neighbour_dir = " + neighbour_dir + "; collision_dir = " + collision_dir);
								passed_all = false;
								break;
							}
						}
					}
					if (!passed_all) {
						break;
					}
				}
				if (!passed_all) {
					break;
				}
			}

			if (passed_all) {
				/* Calculate the new paths and add them to the open list */
				local new_path = this.Path(path, neighbour, this._cost_callback, this._pf_instance);
				if (new_path._cost >= this._pf_instance._max_cost) {
					continue;
				}
//				AILog.Info("cost + estimate = " + new_path._cost + " + " + this._estimate_callback(neighbour, this._goals, this._pf_instance) + " = " + (new_path._cost + this._estimate_callback(neighbour, this._goals, this._pf_instance)));
				this._open.Insert(new_path, new_path._cost + this._estimate_callback(neighbour, this._goals, this._pf_instance));
			}
		}
	}

	if (!this._open.IsEmpty()) return false;
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
	_segment = null;
	_cost = null;

	constructor(old_path, new_segment, cost_callback, pf_instance)
	{
		this._prev = old_path;
		this._segment = new_segment;
		this._cost = cost_callback(old_path, new_segment, pf_instance);
	}

	/**
	 * Return the segment where this (partial-)path ends.
	 */
	function GetSegment() { return this._segment; }

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
	function GetUsedTiles()
	{
		local used_tiles = [];
		local path = this;
		do {
			foreach (line in path._segment.m_nodes) {
				foreach (node in line) {
					used_tiles.extend(node[2]);
				}
			}
			path = path._prev;
		} while (path != null);
		return used_tiles;
	}

	function GetPreviousNode(cur_j, cur_i, depth = 1, return_path_and_cur_i = false)
	{
		local node;
		local cur_path = this;
//		AILog.Info("1 - depth = " + depth + ", " + cur_path._segment.m_nodes[cur_j][cur_i][0]);
		while (depth > 0) {
			depth--;
			if (cur_i > 0) {
				cur_i--;
//				AILog.Info("2a - depth = " + depth + ", " + cur_path._segment.m_nodes[cur_j][cur_i][0]);
				if (depth == 0) {
//					AILog.Info("2b - depth = " + depth + ", return " + cur_path._segment.m_nodes[cur_j][cur_i][0]);
					if (!return_path_and_cur_i) return cur_path._segment.m_nodes[cur_j][cur_i];
					if (return_path_and_cur_i) return [cur_path, cur_i];
				}
			} else {
				cur_path = cur_path._prev;
				if (cur_path != null) {
//					AILog.Info("3a - depth = " + depth + ", " + cur_path._segment.m_nodes[cur_j].top()[0]);
					cur_i = cur_path._segment.m_nodes[cur_j].len() - 1;
					if (depth == 0) {
//						AILog.Info("3b - depth = " + depth + ", return " + cur_path._segment.m_nodes[cur_j].top()[0]);
						if (!return_path_and_cur_i) return cur_path._segment.m_nodes[cur_j].top();
						if (return_path_and_cur_i) return [cur_path, cur_i];
					}
				} else {
//					AILog.Info("4 - depth = " + depth + ", return null");
					return null;
				}
			}
		}
	}
};
