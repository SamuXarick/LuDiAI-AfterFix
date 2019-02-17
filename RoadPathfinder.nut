require("AyStar.nut");

/**
 * A Road Pathfinder.
 *  This road pathfinder tries to find a buildable / existing route for
 *  road vehicles. You can changes the costs below using for example
 *  roadpf.cost.turn = 30. Note that it's not allowed to change the cost
 *  between consecutive calls to FindPath. You can change the cost before
 *  the first call to FindPath and after FindPath has returned an actual
 *  route. To use only existing roads, set cost.no_existing_road to
 *  cost.max_cost.
 */
class Road
{
	_aystar_class = AyStar;
	_max_cost = null;              ///< The maximum cost for a route.
	_cost_tile = null;             ///< The cost for a single road tile, bridge tile or tunnel tile.
	_cost_no_existing_road = null; ///< The cost that is added to _cost_tile if no road connection exists between two tiles. Cost is doubled when the tile to enter has no road, no bridge and no tunnel.
	_cost_turn = null;             ///< The cost that is added to _cost_tile if the direction changes.
	_cost_slope = null;            ///< The extra cost if a road tile or bridge head is sloped.
	_cost_bridge_per_tile = null;  ///< The extra cost per tile for a bridge.
	_cost_tunnel_per_tile = null;  ///< The extra cost per tile for a tunnel.
	_cost_coast = null;            ///< The extra cost if a new road tile or new bridge head is on a coast tile with water.
	_cost_drive_through = null;    ///< The extra cost if a road tile is part of a drive through road station.
	_max_bridge_length = null;     ///< The maximum length of a bridge that will be built. Length includes bridge heads.
	_max_tunnel_length = null;     ///< The maximum length of a tunnel that will be built. Length includes entrance and exit.
	_pathfinder = null;            ///< A reference to the used AyStar object.

	cost = null;                   ///< Used to change the costs.
	_running = null;
	_map_size_x = AIMap.GetMapSizeX();
	_best_estimate = AIMap.GetMapSize();

	constructor()
	{
		this._max_cost = 10000000;
		this._cost_tile = 100;
		this._cost_no_existing_road = 20;
		this._cost_turn = 100;
		this._cost_slope = 200;
		this._cost_bridge_per_tile = 150;
		this._cost_tunnel_per_tile = 120;
		this._cost_coast = 20;
		this._cost_drive_through = 0;
		this._max_bridge_length = 10;
		this._max_tunnel_length = 20;
		this._pathfinder = this._aystar_class(this, this._Cost, this._Estimate, this._Neighbours);

		this.cost = this.Cost(this);
		this._running = false;
	}

	/**
	 * Initialize a path search between source and goal.
	 * @param source The source tile.
	 * @param goal The target tile.
	 * @see AyStar::InitializePath()
	 */
	function InitializePath(source, goal) {
		this._best_estimate = AIMap.DistanceSquare(source, goal);
		this._pathfinder.InitializePath([source, 0xFF], goal);
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

class Road.Cost
{
	_main = null;

	function _set(idx, val)
	{
		if (this._main._running) throw("You are not allowed to change parameters of a running pathfinder.");

		switch (idx) {
			case "max_cost":          this._main._max_cost = val; break;
			case "tile":              this._main._cost_tile = val; break;
			case "no_existing_road":  this._main._cost_no_existing_road = val; break;
			case "turn":              this._main._cost_turn = val; break;
			case "slope":             this._main._cost_slope = val; break;
			case "bridge_per_tile":   this._main._cost_bridge_per_tile = val; break;
			case "tunnel_per_tile":   this._main._cost_tunnel_per_tile = val; break;
			case "coast":             this._main._cost_coast = val; break;
			case "drive_through":     this._main._cost_drive_through = val; break;
			case "max_bridge_length": this._main._max_bridge_length = val; break;
			case "max_tunnel_length": this._main._max_tunnel_length = val; break;
			default: throw("the index '" + idx + "' does not exist");
		}

		return val;
	}

	function _get(idx)
	{
		switch (idx) {
			case "max_cost":          return this._main._max_cost;
			case "tile":              return this._main._cost_tile;
			case "no_existing_road":  return this._main._cost_no_existing_road;
			case "turn":              return this._main._cost_turn;
			case "slope":             return this._main._cost_slope;
			case "bridge_per_tile":   return this._main._cost_bridge_per_tile;
			case "tunnel_per_tile":   return this._main._cost_tunnel_per_tile;
			case "coast":             return this._main._cost_coast;
			case "drive_through":     return this._main._cost_drive_through;
			case "max_bridge_length": return this._main._max_bridge_length;
			case "max_tunnel_length": return this._main._max_tunnel_length;
			default: throw("the index '" + idx + "' does not exist");
		}
	}

	constructor(main)
	{
		this._main = main;
	}
};

function Road::FindPath(iterations)
{
	local test_mode = AITestMode();
	local ret = this._pathfinder.FindPath(iterations);
	this._running = (ret == false) ? true : false;
	return ret;
}

function Road::_GetBridgeNumSlopesEfficient(end_a, end_b,
		map_size_x = Road._map_size_x, _AITile = AITile)
{
	local slopes = 0;
	local direction = (end_b - end_a) / AIMap.DistanceManhattan(end_a, end_b);
	local slope = _AITile.GetSlope(end_a);
	if (!((slope == _AITile.SLOPE_NE && direction == 1) || (slope == _AITile.SLOPE_SE && direction == -map_size_x) ||
			(slope == _AITile.SLOPE_SW && direction == -1) || (slope == _AITile.SLOPE_NW && direction == map_size_x) ||
			slope == _AITile.SLOPE_N || slope == _AITile.SLOPE_E || slope == _AITile.SLOPE_S || slope == _AITile.SLOPE_W)) {
		slopes++;
	}

	slope = _AITile.GetSlope(end_b);
	direction = -direction;
	if (!((slope == _AITile.SLOPE_NE && direction == 1) || (slope == _AITile.SLOPE_SE && direction == -map_size_x) ||
			(slope == _AITile.SLOPE_SW && direction == -1) || (slope == _AITile.SLOPE_NW && direction == map_size_x) ||
			slope == _AITile.SLOPE_N || slope == _AITile.SLOPE_E || slope == _AITile.SLOPE_S || slope == _AITile.SLOPE_W)) {
		slopes++;
	}

	return slopes;
}

function Road::_CostHelperEfficient(self, path, new_tile, coast_cost_only = null,
		_AIBridge = AIBridge, _AITunnel = AITunnel, _AIRoad = AIRoad, _AITile = AITile, _AICompany = AICompany)
{
	local prev_tile = path.GetTile();
	local cost = 0;

    if (coast_cost_only != true) {
		cost += self._cost_tile;

		local dist = 0;
		local par_tile = 0;
		if (path.GetParent() != null) {
			dist = AIMap.DistanceManhattan(path.GetParent().GetTile(), prev_tile);
			par_tile = path.GetParent().GetTile();
		}

		if (dist == 1) {
			/* Check for a turn. We do this by substracting the TileID of the current node from
			 * the TileID of the previous node and comparing that to the difference between the
			 * previous node and the node before that. */
			if (prev_tile - par_tile != new_tile - prev_tile) {
				cost += self._cost_turn;
			}

			/* Check if the last tile was sloped. */
			if (!_AIBridge.IsBridgeTile(prev_tile) && !_AITunnel.IsTunnelTile(prev_tile) && self._IsSlopedRoadEfficient(par_tile, prev_tile, new_tile)) {
				cost += self._cost_slope;
			}
		}

		if (!_AIRoad.AreRoadTilesConnected(prev_tile, new_tile)) {
			cost += self._cost_no_existing_road * 2;
			if (_AIRoad.IsRoadTile(new_tile) || _AIBridge.IsBridgeTile(new_tile) || _AITunnel.IsTunnelTile(new_tile) ||
					(_AIRoad.IsRoadStationTile(new_tile) || _AIRoad.IsRoadDepotTile(new_tile)) && _AITile.GetOwner(new_tile) == _AICompany.ResolveCompanyID(_AICompany.COMPANY_SELF)) {
				cost -= self._cost_no_existing_road;
			}
		}

		if (_AIRoad.IsDriveThroughRoadStationTile(new_tile)) {
			cost += self._cost_drive_through;
		}
	}

	if (coast_cost_only != null) {
		/* Check if the new tile is a coast tile with water. */
		if (_AITile.IsCoastTile(new_tile) && _AITile.HasTransportType(new_tile, _AITile.TRANSPORT_WATER)) {
			cost += self._cost_coast;
		}
	}

	return cost;
}

function Road::_Cost(self, path, new_tile,
		_AIBridge = AIBridge, _AITunnel = AITunnel)
{
	/* path == null means this is the first node of a path, so the cost is 0. */
	if (path == null) return 0;

	local prev_tile = path.GetTile();
	local dist = AIMap.DistanceManhattan(new_tile, prev_tile);

	/* If the new tile is a bridge / tunnel tile, check whether we came from the other
	 * end of the bridge / tunnel or if we just entered the bridge / tunnel. */
	if (_AIBridge.IsBridgeTile(new_tile)) {
		if (_AIBridge.GetOtherBridgeEnd(new_tile) != prev_tile) {
			return path.GetCost() + self._CostHelperEfficient(self, path, new_tile);
		}
		return path.GetCost() + (dist + 1) * self._cost_bridge_per_tile + dist * self._cost_tile + self._GetBridgeNumSlopesEfficient(new_tile, prev_tile) * self._cost_slope;
	}
	if (_AITunnel.IsTunnelTile(new_tile)) {
		if (_AITunnel.GetOtherTunnelEnd(new_tile) != prev_tile) {
			return path.GetCost() + self._CostHelperEfficient(self, path, new_tile);
		}
		return path.GetCost() + (dist + 1) * self._cost_tunnel_per_tile + dist * self._cost_tile;
	}

	/* If the two tiles are more than 1 tile apart, the pathfinder wants a bridge or tunnel
	 * to be built. It isn't an existing bridge / tunnel, as that case is already handled. */
	if (dist > 1) {
		/* Check if we should build a bridge or a tunnel. */
		if (_AITunnel.GetOtherTunnelEnd(new_tile) == prev_tile) {
			return path.GetCost() + (dist + 1) * self._cost_tunnel_per_tile + dist * (self._cost_tile + self._cost_no_existing_road * 2);
		} else {
			return path.GetCost() + (dist + 1) * self._cost_bridge_per_tile + dist * (self._cost_tile + self._cost_no_existing_road * 2) + self._GetBridgeNumSlopesEfficient(new_tile, prev_tile) * self._cost_slope + self._CostHelperEfficient(self, path, new_tile, true);
		}
	}

	return path.GetCost() + self._CostHelperEfficient(self, path, new_tile, false);
}

function Road::_Estimate(self, cur_tile, goal_tile)
{
	return AIMap.DistanceManhattan(cur_tile, goal_tile) * self._cost_tile;
}

function Road::_Neighbours(self, path, cur_node,
		_AIBridge = AIBridge, _AITunnel = AITunnel, _AITile = AITile, _AIMap = AIMap, _AIRoad = AIRoad, _AIRail = AIRail, _AICompany = AICompany, _AIVehicle = AIVehicle)
{
	/* self._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
	if (path.GetCost() >= self._max_cost) return [];

	local par = path.GetParent() != null;
	local last_node = par ? path.GetParent().GetTile() : 0;

	local tiles = [];

	/* Check if the current tile is part of a bridge or tunnel. */
	local other_end = 0;
	if (_AIBridge.IsBridgeTile(cur_node)) {
		other_end = _AIBridge.GetOtherBridgeEnd(cur_node);
	} else if (_AITunnel.IsTunnelTile(cur_node)) {
		other_end = _AITunnel.GetOtherTunnelEnd(cur_node);
	}
	if (other_end && _AITile.HasTransportType(cur_node, _AITile.TRANSPORT_ROAD)) {
		local next_tile = cur_node + (cur_node - other_end) / _AIMap.DistanceManhattan(cur_node, other_end);
		if ((_AIRoad.AreRoadTilesConnected(cur_node, next_tile) || _AITile.IsBuildable(next_tile) || _AIRoad.IsRoadTile(next_tile) && _AIRoad.BuildRoad(cur_node, next_tile)) && !_AIRail.IsLevelCrossingTile(next_tile) &&
				(!_AIRoad.IsDriveThroughRoadStationTile(next_tile) || _AIRoad.GetRoadStationFrontTile(next_tile) == cur_node || _AIRoad.GetDriveThroughBackTile(next_tile) == cur_node)) {
			tiles.push([next_tile, self._GetDirectionEfficient(cur_node, next_tile, false)]);
		}
		/* The other end of the bridge / tunnel is a neighbour. */
		tiles.push([other_end, self._GetDirectionEfficient(next_tile, cur_node, true) << 4]);
	} else if (last_node && _AIMap.DistanceManhattan(cur_node, last_node) > 1) {
		local next_tile = cur_node + (cur_node - last_node) / _AIMap.DistanceManhattan(cur_node, last_node);
		if (_AIRoad.AreRoadTilesConnected(cur_node, next_tile) && !_AIRail.IsLevelCrossingTile(next_tile) ||
				_AIRoad.BuildRoad(cur_node, next_tile) && !_AIRail.IsRailTile(next_tile)) {
			tiles.push([next_tile, self._GetDirectionEfficient(cur_node, next_tile, false)]);
		}
	} else {
		local offsets = [_AIMap.GetTileIndex(0, 1), _AIMap.GetTileIndex(0, -1), _AIMap.GetTileIndex(1, 0), _AIMap.GetTileIndex(-1, 0)];
		/* Check all tiles adjacent to the current tile. */
		foreach (offset in offsets) {
			local next_tile = cur_node + offset;
			/* We add them to the to the neighbours-list if one of the following applies:
			 * 1) There already is a connection between the current tile and the next tile, and it's not a level crossing.
			 * 2) We can build a road to the next tile, except when it's a level crossing.
			 *    We can connect to a regular road station or a road depot owned by us.
			 * 3) The next tile is the entrance of a tunnel / bridge in the correct direction. */
			if (_AIRoad.AreRoadTilesConnected(cur_node, next_tile) && !_AIRail.IsLevelCrossingTile(next_tile)) {
				tiles.push([next_tile, self._GetDirectionEfficient(cur_node, next_tile, false)]);
			} else if ((_AITile.IsBuildable(next_tile) || _AIRoad.IsRoadTile(next_tile) && !_AIRail.IsLevelCrossingTile(next_tile) ||
					(_AIRoad.IsRoadStationTile(next_tile) || _AIRoad.IsRoadDepotTile(next_tile)) && _AITile.GetOwner(next_tile) == _AICompany.ResolveCompanyID(_AICompany.COMPANY_SELF)) &&
					(!par || _AIRoad.CanBuildConnectedRoadPartsHere(cur_node, last_node, next_tile)) &&
					_AIRoad.BuildRoad(cur_node, next_tile)) {
				tiles.push([next_tile, self._GetDirectionEfficient(cur_node, next_tile, false)]);
			} else if (self._CheckTunnelBridgeEfficient(cur_node, next_tile) &&
					(!par || _AIRoad.CanBuildConnectedRoadPartsHere(cur_node, last_node, next_tile)) && _AIRoad.BuildRoad(cur_node, next_tile)) {
				tiles.push([next_tile, self._GetDirectionEfficient(cur_node, next_tile, false)]);
			}
		}
		if (par) {
			/*
			 * Get a list of all bridges and tunnels that can be built from the
			 * current tile. Tunnels will only be built if no terraforming
			 * is needed on both ends. */
			local bridge_dir = self._GetDirectionEfficient(last_node, cur_node, true) << 4;
			for (local i = 2; i < self._max_bridge_length;) {
				local target = cur_node + i * (cur_node - last_node);
				local bridge_list = AIBridgeList_Length(++i);
				if (!bridge_list.IsEmpty() && _AIBridge.BuildBridge(_AIVehicle.VT_ROAD, bridge_list.Begin(), cur_node, target)) {
					tiles.push([target, bridge_dir]);
				}
			}

			local slope = _AITile.GetSlope(cur_node);
			if (slope == _AITile.SLOPE_SW || slope == _AITile.SLOPE_NW || slope == _AITile.SLOPE_SE || slope == _AITile.SLOPE_NE) {
				local other_tunnel_end = _AITunnel.GetOtherTunnelEnd(cur_node);
				if (_AIMap.IsValidTile(other_tunnel_end)) {
					local tunnel_length = _AIMap.DistanceManhattan(cur_node, other_tunnel_end);
					if (_AITunnel.GetOtherTunnelEnd(other_tunnel_end) == cur_node && tunnel_length >= 2 &&
							cur_node + (cur_node - other_tunnel_end) / tunnel_length == last_node && tunnel_length < self._max_tunnel_length && _AITunnel.BuildTunnel(_AIVehicle.VT_ROAD, cur_node)) {
						tiles.push([other_tunnel_end, bridge_dir]);
					}
				}
			}
		}
	}

	return tiles;
}

function Road::_GetDirectionEfficient(from, to, is_bridge,
		map_size_x = Road._map_size_x, _AITile = AITile)
{
	if (!is_bridge && _AITile.GetSlope(to) == _AITile.SLOPE_FLAT) return 0xFF;
	local difference = from - to;
	if (difference == 1) return 1;
	if (difference == -1) return 2;
	if (difference == map_size_x) return 4;
	return 8; // if (difference == -map_size_x)
}

function Road::_IsSlopedRoadEfficient(start, middle, end, map_size_x = Road._map_size_x,
		_AITile = AITile)
{
	local NW = middle - map_size_x;
	local NE = middle - 1;
	local SE = middle + map_size_x;
	local SW = middle + 1;

	NW = NW == start || NW == end; //Set to true if we want to build a road to / from the north-west
	NE = NE == start || NE == end; //Set to true if we want to build a road to / from the north-east
	SE = SE == start || SE == end; //Set to true if we want to build a road to / from the south-west
	SW = SW == start || SW == end; //Set to true if we want to build a road to / from the south-east

	/* If there is a turn in the current tile, it can't be sloped. */
	if ((NW || SE) && (NE || SW)) return false;

	local slope = _AITile.GetSlope(middle);
	/* A road on a steep slope is always sloped. */
	if (_AITile.IsSteepSlope(slope)) return true;

	/* If only one corner is raised, the road is sloped. */
	if (slope == _AITile.SLOPE_N || slope == _AITile.SLOPE_W) return true;
	if (slope == _AITile.SLOPE_S || slope == _AITile.SLOPE_E) return true;

	if (NW && (slope == _AITile.SLOPE_NW || slope == _AITile.SLOPE_SE)) return true;
	if (NE && (slope == _AITile.SLOPE_NE || slope == _AITile.SLOPE_SW)) return true;

	return false;
}

function Road::_CheckTunnelBridgeEfficient(current_tile, new_tile,
		map_size_x = Road._map_size_x, _AIBridge = AIBridge, _AITunnel = AITunnel)
{
	local dir2;
	if (_AIBridge.IsBridgeTile(new_tile)) {
		dir2 = _AIBridge.GetOtherBridgeEnd(new_tile) - new_tile;
	} else if (_AITunnel.IsTunnelTile(new_tile)) {
		dir2 = _AITunnel.GetOtherTunnelEnd(new_tile) - new_tile;
	} else {
		return false;
	}

	local dir = new_tile - current_tile;
	if ((dir < 0 && dir2 > 0) || (dir > 0 && dir2 < 0)) return false;
	dir = abs(dir);
	dir2 = abs(dir2);
	if ((dir >= map_size_x && dir2 < map_size_x) ||
		(dir < map_size_x && dir2 >= map_size_x)) return false;

	return true;
}