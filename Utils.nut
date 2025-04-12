class OrthogonalTileArea
{
	tile_top = null; ///< The base tile of the area
	tile_bot = null; ///< The last tile of the area
	w = null; ///< The width of the area
	h = null; ///< The height of the area
	sx = null; ///< The x coordinate of base tile
	sy = null; ///< the y coordinate of base tile
	ex = null; ///< The x coordinate of last tile
	ey = null; ///< The y coordinate of last tile

	constructor(top, width, height)
	{
		assert(AIMap.IsValidTile(top));
		assert(width > 0);
		assert(height > 0);

		this.sx = AIMap.GetTileX(top);
		this.sy = AIMap.GetTileY(top);
		local borders = AIGameSettings.GetValue("freeform_edges");
		this.ex = this.sx + width - borders;
		this.ey = this.sy + height - borders;

		this.tile_top = top;
		this.tile_bot = AIMap.GetTileIndex(this.ex, this.ey);
		this.w = min(width, AIMap.GetMapSizeX() - this.sx - borders);
		this.h = min(height, AIMap.GetMapSizeY() - this.sy - borders);
	}

	function CreateArea(start, end)
	{
		assert(AIMap.IsValidTile(start));
		assert(AIMap.IsValidTile(end));

		local sx = AIMap.GetTileX(start);
		local sy = AIMap.GetTileY(start);
		local ex = AIMap.GetTileX(end);
		local ey = AIMap.GetTileY(end);

		if (sx > ex) { local temp = sx; sx = ex; ex = temp; }
		if (sy > ey) { local temp = sy; sy = ey; ey = temp; }

		local top = AIMap.GetTileIndex(sx, sy);
		local width = ex - sx + 1;
		local height = ey - sy + 1;

		return OrthogonalTileArea(top, width, height);
	}

	function Expand(rad_x, rad_y, bot = true)
	{
		assert(rad_x >= 0);
		assert(rad_y >= 0);

		local borders = AIGameSettings.GetValue("freeform_edges");
		local x = this.sx;
		local y = this.sy;

		this.sx = max(x - rad_x, borders);
		this.sy = max(y - rad_y, borders);
		if (bot) {
			this.ex = min(x + this.w + rad_x, AIMap.GetMapSizeX() - borders) - 1;
			this.ey = min(y + this.h + rad_y, AIMap.GetMapSizeY() - borders) - 1;
		}

		this.tile_top = AIMap.GetTileIndex(this.sx, this.sy);
		this.tile_bot = AIMap.GetTileIndex(this.ex, this.ey);
		this.w = this.ex - this.sx + 1;
		this.h = this.ey - this.sy + 1;

		return this;
	}

	function Intersects(ta)
	{
		return ta.sx <= this.ex && ta.ex >= this.sx && ta.sy <= this.ey && ta.ey >= this.sy;
	}

	function Contains(tile)
	{
		assert(AIMap.IsValidTile(tile));

		local x = AIMap.GetTileX(tile);
		local y = AIMap.GetTileY(tile);

		return x <= this.ex && x >= this.sx && y <= this.ey && y >= this.sy;
	}

	function DistanceManhattan(tile)
	{
		assert(AIMap.IsValidTile(tile));

		local x = AIMap.GetTileX(tile);
		local y = AIMap.GetTileY(tile);

		local dx = x < this.sx ? this.sx - x : (x > this.ex ? x - this.ex : 0);
		local dy = y < this.sy ? this.sy - y : (y > this.ey ? y - this.ey : 0);

		return dx + dy;
	}

//	function IsEqual(ta)
//	{
//		return ta.tile_top == this.tile_top && ta.tile_bot == this.tile_bot && ta.w == this.w && ta.h == this.h && ta.sx == this.sx && ta.sy == this.sy && ta.ex == this.ex && ta.ey == this.ey;
//	}

	function PrintValues()
	{
		AILog.Info("tile_top: " + this.tile_top + ", tile_bot: " + this.tile_bot + ", w: " + this.w + ", h: " + this.h + ", sx: " + this.sx + ", sy: " + this.sy + ", ex: " + this.ex + ", ey: " + this.ey);
	}
};

class Utils
{
	function CountBits(value)
	{
		assert(typeof(value) == "integer");

		local num;
		for (num = 0; value != 0; num++) {
			value = value & (value - 1);
		}
		return num;
	}

	function Clamp(a, min, max)
	{
		assert(min <= max);
		if (a <= min) return min;
		if (a >= max) return max;
		return a;
	}

	function ConvertKmhishSpeedToDisplaySpeed(speed)
	{
		local velocity = AIGameSettings.GetValue("units_velocity");
		local unit_str = " km-ish/h";
		local converted_speed = speed;

		if (velocity == 0) { // Imperial
			unit_str = " mph";
			converted_speed = ((speed * 10 * 1) >> 0) / 16;
		} else if (velocity == 1) { // Metric
			unit_str = " km/h";
			converted_speed = ((speed * 10 * 103) >> 6) / 16;
		} else if (velocity == 2) { // SI
			unit_str = " m/s";
			converted_speed = ((speed * 10 * 1831) >> 12) / 16;
		}

		return converted_speed + unit_str;
	}

	function GetValidOffsetTile(tile, offsetX, offsetY)
	{
		local oldX = AIMap.GetTileX(tile);
		local oldY = AIMap.GetTileY(tile);

		local newX = oldX;
		local newY = oldY;

		if (offsetX > 0) {
			for (local x = offsetX; x > 0; x--) {
				if (AIMap.IsValidTile(AIMap.GetTileIndex(newX + 1, newY))) {
					newX = newX + 1;
				}
			}
		} else {
			for (local x = offsetX; x < 0; x++) {
				if (AIMap.IsValidTile(AIMap.GetTileIndex(newX - 1, newY))) {
					newX = newX - 1;
				}
			}
		}

		if (offsetY > 0) {
			for (local y = offsetY; y > 0; y--) {
				if (AIMap.IsValidTile(AIMap.GetTileIndex(newX, newY + 1))) {
					newY = newY + 1;
				}
			}
		} else {
			for (local y = offsetY; y < 0; y++) {
				if (AIMap.IsValidTile(AIMap.GetTileIndex(newX, newY - 1))) {
					newY = newY - 1;
				}
			}
		}

		return AIMap.GetTileIndex(newX, newY);
	}

	/**
	 * GetOffsetTile
	 * @param tile - The starting tile.
	 * @param offsetX - The x-axis offset.
	 * @param offsetY - The y-axis offset.
	 * @return - The offset tile.
	 */
	function GetOffsetTile(tile, offsetX, offsetY)
	{
		local oldX = AIMap.GetTileX(tile);
		local oldY = AIMap.GetTileY(tile);

		local newX = oldX + offsetX;
		local newY = oldY + offsetY;

		local freeform = AIMap.IsValidTile(0) ? 0 : 1;
		if (((newX < freeform) || (newY < freeform)) // 0 if freeform_edges off
			&& (((newX > AIMap.GetMapSizeX() - 2) || (newY > AIMap.GetMapSizeY() - 2)))) {
			return AIMap.TILE_INVALID;
		}

		return AIMap.GetTileIndex(newX, newY);
	}

	/**
	 * GetAdjacentTiles
	 * @param tile - The starting tile.
	 * @return - The AITileList of adjacent tiles.
	 */
	function GetAdjacentTiles(tile)
	{
		local adjTiles = AITileList();

		local offsetTile = Utils.GetOffsetTile(tile, 0, -1)
		if (offsetTile != AIMap.TILE_INVALID) {
			adjTiles.AddTile(offsetTile);
		}

		offsetTile = Utils.GetOffsetTile(tile, 1, 0)
		if (offsetTile != AIMap.TILE_INVALID) {
			adjTiles.AddTile(offsetTile);
		}

		offsetTile = Utils.GetOffsetTile(tile, 0, 1)
		if (offsetTile != AIMap.TILE_INVALID) {
			adjTiles.AddTile(offsetTile);
		}

		offsetTile = Utils.GetOffsetTile(tile, -1, 0)
		if (offsetTile != AIMap.TILE_INVALID) {
			adjTiles.AddTile(offsetTile);
		}

		return adjTiles;
	};

	function IsDockBuildableTile(tile, cheaper_route)
	{
		local slope = AITile.GetSlope(tile);
		if (slope == AITile.SLOPE_FLAT) return [false, null];

		local offset = 0;
		local tile2 = AIMap.TILE_INVALID;
		if (AITile.IsBuildable(tile) && (
				slope == AITile.SLOPE_NE && (offset = AIMap.GetTileIndex(1, 0)) ||
				slope == AITile.SLOPE_SE && (offset = AIMap.GetTileIndex(0, -1)) ||
				slope == AITile.SLOPE_SW && (offset = AIMap.GetTileIndex(-1, 0)) ||
				slope == AITile.SLOPE_NW && (offset = AIMap.GetTileIndex(0, 1)))) {
			tile2 = tile + offset;
			if (!AIMap.IsValidTile(tile2)) return [false, null];
			if (AITile.GetSlope(tile2) != AITile.SLOPE_FLAT) return [false, null];
			if (!(!cheaper_route && AITile.IsBuildable(tile2) || AITile.IsWaterTile(tile2) && !AIMarine.IsWaterDepotTile(tile2) && !AIMarine.IsLockTile(tile2))) return [false, null];
			local tile3 = tile2 + offset;
			if (!AIMap.IsValidTile(tile3)) return [false, null];
			if (AITile.GetSlope(tile3) != AITile.SLOPE_FLAT) return [false, null];
			if (!(!cheaper_route && AITile.IsBuildable(tile3) || AITile.IsWaterTile(tile3) && !AIMarine.IsWaterDepotTile(tile3) && !AIMarine.IsLockTile(tile3))) return [false, null];
		}

		return [true, tile2];
	}

	function AreOtherDocksNearby(tile_north, tile_south)
	{
		/* check if there are other docks squareSize squares nearby */
		local squareSize = AIStation.GetCoverageRadius(AIStation.STATION_DOCK) * 2;

		local square = AITileList();
		if (!AIController.GetSetting("is_friendly")) {
			squareSize = 2;
			/* don't care about enemy stations when is_friendly is off */
			square.AddRectangle(Utils.GetValidOffsetTile(tile_north, -1 * squareSize, -1 * squareSize), Utils.GetValidOffsetTile(tile_south, squareSize, squareSize));

			/* if another dock of mine is nearby return true */
			for (local tile = square.Begin(); !square.IsEnd(); tile = square.Next()) {
				if (Utils.IsTileMyDock(tile)) { // negate second expression to merge your stations
					return true;
				}
			}
		} else {
			square.AddRectangle(Utils.GetValidOffsetTile(tile_north, -1 * squareSize, -1 * squareSize), Utils.GetValidOffsetTile(tile_south, squareSize, squareSize));

			/* if any other station is nearby, except my own airports, return true */
			for (local tile = square.Begin(); !square.IsEnd(); tile = square.Next()) {
				if (AITile.IsStationTile(tile)) {
					if (AITile.GetOwner(tile) != ::caches.m_my_company_id) {
						return true;
					} else {
						local stationTiles = AITileList_StationType(AIStation.GetStationID(tile), AIStation.STATION_DOCK);
						if (stationTiles.HasItem(tile)) {
							return true;
						}
					}
				}
			}
		}

		return false;
	}

	function IsTileMyDock(tile)
	{
		return AITile.IsStationTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id && AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_DOCK);
	}

	function IsTileMyStationWithoutRoadStation(tile, cargo_class)
	{
		return AITile.IsStationTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id && !AIStation.HasStationType(AIStation.GetStationID(tile), cargo_class == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
	}

	function IsTileMyStationWithoutRoadStationOfAnyType(tile)
	{
		return AITile.IsStationTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id && !AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_BUS_STOP) && !AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_TRUCK_STOP);
	}

	function IsTileMyStationWithoutDock(tile)
	{
		return AITile.IsStationTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id && !AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_DOCK);
	}

	function IsTileMyStationWithoutRailwayStation(tile)
	{
		return AITile.IsStationTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id && !AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN);
	}

	/**
	 * GetCargoType - Returns either mail cargo_type, or passenger cargo_type.
	 * @param cargo_class - either AICargo.CC_MAIL, or AICargo.CC_PASSENGERS
	 * @return - Cargo list.
	 */
	function GetCargoType(cargo_class)
	{
		local cargo_type = 0xFF;
		for (local cargo_type2 = ::caches.m_cargo_type_list.Begin(); !::caches.m_cargo_type_list.IsEnd(); cargo_type2 = ::caches.m_cargo_type_list.Next()) {
			if (AICargo.HasCargoClass(cargo_type2, cargo_class)) {
				cargo_type = cargo_type2;
				break;
			}
		}
//		assert(AICargo.IsValidCargo(cargo_type));

		/* both AICargo.CC_MAIL and AICargo.CC_PASSENGERS should return the first available cargo_type */
		return cargo_type;
	}

	function CheckAdjacentNonRoadStation(stationTile, stationId)
	{
		if (stationId != AIStation.STATION_NEW) {
			return stationId;
		}

		if (!AIController.GetSetting("station_spread") || !AIGameSettings.GetValue("distant_join_stations")) {
			return AIStation.STATION_NEW;
		}

		local spread_rad = AIGameSettings.GetValue("station_spread") - 1;

		local tileList = AITileList();
		local spreadrectangle = [Utils.GetValidOffsetTile(stationTile, -1 * spread_rad, -1 * spread_rad), Utils.GetValidOffsetTile(stationTile, spread_rad, spread_rad)];
		tileList.AddRectangle(spreadrectangle[0], spreadrectangle[1]);

		local templist = AITileList();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (Utils.IsTileMyStationWithoutRoadStationOfAnyType(tile)) {
				tileList.SetValue(tile, AIStation.GetStationID(tile));
			} else {
				templist.AddTile(tile);
			}
		}
		tileList.RemoveList(templist);

		local stationList = AIList();

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tileList.Next()) {
			stationList.AddItem(tileList.GetValue(tile), AIMap.DistanceManhattan(tile, stationTile));
		}

		local spreadrectangle_top_x = AIMap.GetTileX(spreadrectangle[0]);
		local spreadrectangle_top_y = AIMap.GetTileY(spreadrectangle[0]);
		local spreadrectangle_bot_x = AIMap.GetTileX(spreadrectangle[1]);
		local spreadrectangle_bot_y = AIMap.GetTileY(spreadrectangle[1]);

		local list = AIList();
		list.AddList(stationList);
		for (local stationId = stationList.Begin(); !stationList.IsEnd(); stationId = stationList.Next()) {
			local stationTiles = AITileList_StationType(stationId, AIStation.STATION_ANY);
			local station_top_x = AIMap.GetTileX(AIBaseStation.GetLocation(stationId));
			local station_top_y = AIMap.GetTileY(AIBaseStation.GetLocation(stationId));
			local station_bot_x = station_top_x;
			local station_bot_y = station_top_y;
			for (local tile = stationTiles.Begin(); !stationTiles.IsEnd(); tile = stationTiles.Next()) {
				local tile_x = AIMap.GetTileX(tile);
				local tile_y = AIMap.GetTileY(tile);
				if (tile_x < station_top_x) {
					station_top_x = tile_x;
				}
				if (tile_x > station_bot_x) {
					station_bot_x = tile_x;
				}
				if (tile_y < station_top_y) {
					station_top_y = tile_y;
				}
				if (tile_y > station_bot_y) {
					station_bot_y = tile_y;
				}
			}

			if (spreadrectangle_top_x > station_top_x ||
				spreadrectangle_top_y > station_top_y ||
				spreadrectangle_bot_x < station_bot_x ||
				spreadrectangle_bot_y < station_bot_y) {
				list.RemoveItem(stationId);
			}
		}
		list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		local adjacentStation = AIStation.STATION_NEW;
		if (!list.IsEmpty()) {
			adjacentStation = list.Begin();
//			AILog.Info("adjacentStation = " + AIStation.GetName(adjacentStation) + " ; stationtTile = " + AIMap.GetTileX(stationTile) + "," + AIMap.GetTileY(stationTile));
		}

		return adjacentStation;
	}

	function CheckAdjacentNonDock(stationTile)
	{
		if (!AIController.GetSetting("station_spread") || !AIGameSettings.GetValue("distant_join_stations")) {
			return AIStation.STATION_NEW;
		}

		local tileList = AITileList();
		local spreadrectangle = Utils.ExpandAdjacentDockRect(stationTile);
		tileList.AddRectangle(spreadrectangle[0], spreadrectangle[1]);

		local templist = AITileList();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (Utils.IsTileMyStationWithoutDock(tile)) {
				tileList.SetValue(tile, AIStation.GetStationID(tile));
			} else {
				templist.AddTile(tile);
			}
		}
		tileList.RemoveList(templist);

		local stationList = AIList();

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tileList.Next()) {
			stationList.AddItem(tileList.GetValue(tile), AIMap.DistanceManhattan(tile, stationTile));
		}

		local spreadrectangle_top_x = AIMap.GetTileX(spreadrectangle[0]);
		local spreadrectangle_top_y = AIMap.GetTileY(spreadrectangle[0]);
		local spreadrectangle_bot_x = AIMap.GetTileX(spreadrectangle[1]);
		local spreadrectangle_bot_y = AIMap.GetTileY(spreadrectangle[1]);

		local list = AIList();
		list.AddList(stationList);
		for (local stationId = stationList.Begin(); !stationList.IsEnd(); stationId = stationList.Next()) {
			local stationTiles = AITileList_StationType(stationId, AIStation.STATION_ANY);
			local station_top_x = AIMap.GetTileX(AIBaseStation.GetLocation(stationId));
			local station_top_y = AIMap.GetTileY(AIBaseStation.GetLocation(stationId));
			local station_bot_x = station_top_x;
			local station_bot_y = station_top_y;
			for (local tile = stationTiles.Begin(); !stationTiles.IsEnd(); tile = stationTiles.Next()) {
				local tile_x = AIMap.GetTileX(tile);
				local tile_y = AIMap.GetTileY(tile);
				if (tile_x < station_top_x) {
					station_top_x = tile_x;
				}
				if (tile_x > station_bot_x) {
					station_bot_x = tile_x;
				}
				if (tile_y < station_top_y) {
					station_top_y = tile_y;
				}
				if (tile_y > station_bot_y) {
					station_bot_y = tile_y;
				}
			}

			if (spreadrectangle_top_x > station_top_x ||
				spreadrectangle_top_y > station_top_y ||
				spreadrectangle_bot_x < station_bot_x ||
				spreadrectangle_bot_y < station_bot_y) {
				list.RemoveItem(stationId);
			}
		}
		list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		local adjacentStation = AIStation.STATION_NEW;
		if (!list.IsEmpty()) {
			adjacentStation = list.Begin();
//			AILog.Info("adjacentStation = " + AIStation.GetName(adjacentStation) + " ; stationtTile = " + AIMap.GetTileX(stationTile) + "," + AIMap.GetTileY(stationTile));
		}

		return adjacentStation;
	}

	function ExpandAdjacentDockRect(dockTile)
	{
		local slope = AITile.GetSlope(dockTile);
		if (slope != AITile.SLOPE_SW && slope != AITile.SLOPE_NW && slope != AITile.SLOPE_SE && slope != AITile.SLOPE_NE) return [dockTile, dockTile]; // shouldn't happen

		local offset = 0;
		local tile2 = AIMap.TILE_INVALID;
		if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
		if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
		if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
		if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
		tile2 = dockTile + offset;

		local temp_tile1 = dockTile;
		local temp_tile2 = tile2;
		if (temp_tile1 > temp_tile2) {
			local swap = temp_tile1;
			temp_tile1 = temp_tile2;
			temp_tile2 = swap;
		}

		local x_length = 1;
		local y_length = 1;
		if (temp_tile2 - temp_tile1 == 1) {
			x_length = 2;
		} else {
			y_length = 2;
		}

		local spread_rad = AIGameSettings.GetValue("station_spread");
		local dock_x = x_length;
		local dock_y = y_length;

		local remaining_x = spread_rad - dock_x;
		local remaining_y = spread_rad - dock_y;

		local tile_top_x = AIMap.GetTileX(temp_tile1);
		local tile_top_y = AIMap.GetTileY(temp_tile1);
		local tile_bot_x = tile_top_x + dock_x - 1;
		local tile_bot_y = tile_top_y + dock_y - 1;

		for (local x = remaining_x; x > 0; x--) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(tile_top_x - 1, tile_top_y))) {
				tile_top_x = tile_top_x - 1;
			}
			if (AIMap.IsValidTile(AIMap.GetTileIndex(tile_bot_x + 1, tile_bot_y))) {
				tile_bot_x = tile_bot_x + 1;
			}
		}

		for (local y = remaining_y; y > 0; y--) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(tile_top_x, tile_top_y - 1))) {
				tile_top_y = tile_top_y - 1;
			}
			if (AIMap.IsValidTile(AIMap.GetTileIndex(tile_bot_x, tile_bot_y + 1))) {
				tile_bot_y = tile_bot_y + 1;
			}
		}

//		AILog.Info("spreadrectangle top = " + tile_top_x + "," + tile_top_y + " ; spreadrectangle bottom = " + tile_bot_x + "," + tile_bot_y);
		return [AIMap.GetTileIndex(tile_top_x, tile_top_y), AIMap.GetTileIndex(tile_bot_x, tile_bot_y)];
	}

	/**
	 * Distance a vehicle engine runs when moving at its maximum speed for the given time
	 */
	function GetEngineTileDist(engine_id, days_in_transit)
	{
		local veh_type = AIEngine.GetVehicleType(engine_id);
		/* Assuming going in axis, it is the same as distancemanhattan */
		if (veh_type == AIVehicle.VT_ROAD) {
			return ((AIEngine.GetMaxSpeed(engine_id) * 2 * 74 * days_in_transit * 3) / 4) / (192 * 16);
		} else if (veh_type == AIVehicle.VT_WATER) {
			return (AIEngine.GetMaxSpeed(engine_id) * 2 * 74 * days_in_transit) / (256 * 16);
		} else {
			assert(!AIEngine.IsValidEngine(engine_id) || !AIEngine.IsBuildable(engine_id));
			return 0;
		}
	}

	function GetEngineReliabilityMultiplier(engine_id)
	{
		local reliability = AIEngine.GetReliability(engine_id);
		switch (AIGameSettings.GetValue("vehicle_breakdowns")) {
			case 0:
				return 100;
			case 1:
				return reliability + (100 - reliability) / 2;
			case 2:
			default:
				return reliability;
		}
	}

	function RemovingCanalBlocksConnection(tile)
	{
		local t_sw = tile + AIMap.GetTileIndex(1, 0);
		local t_ne = tile + AIMap.GetTileIndex(-1, 0);
		local t_se = tile + AIMap.GetTileIndex(0, 1);
		local t_nw = tile + AIMap.GetTileIndex(0, -1);

		if (AIMarine.IsLockTile(t_se) && AITile.GetSlope(t_se) == AITile.SLOPE_FLAT && Utils.CheckLockDirection(t_se, Utils.GetLockMiddleTile(t_se)) ||
				AIMarine.IsLockTile(t_nw) && AITile.GetSlope(t_nw) == AITile.SLOPE_FLAT && Utils.CheckLockDirection(t_nw, Utils.GetLockMiddleTile(t_nw)) ||
				AIMarine.IsLockTile(t_ne) && AITile.GetSlope(t_ne) == AITile.SLOPE_FLAT && Utils.CheckLockDirection(t_ne, Utils.GetLockMiddleTile(t_ne)) ||
				AIMarine.IsLockTile(t_sw) && AITile.GetSlope(t_sw) == AITile.SLOPE_FLAT && Utils.CheckLockDirection(t_sw, Utils.GetLockMiddleTile(t_sw))) {
			return true;
		}

		if (AIMarine.IsDockTile(t_se) && Utils.GetDockDockingTile(t_se) == tile ||
				AIMarine.IsDockTile(t_nw) && Utils.GetDockDockingTile(t_nw) == tile ||
				AIMarine.IsDockTile(t_ne) && Utils.GetDockDockingTile(t_ne) == tile ||
				AIMarine.IsDockTile(t_sw) && Utils.GetDockDockingTile(t_sw) == tile) {
			return true;
		}

		local t_e = tile + AIMap.GetTileIndex(-1, 1);

		if (AIMarine.AreWaterTilesConnected(tile, t_se) && AIMarine.AreWaterTilesConnected(tile, t_ne)) {
			if (!(AIMarine.AreWaterTilesConnected(t_e, t_se) && AIMarine.AreWaterTilesConnected(t_e, t_ne))) {
				return true;
			}
		}

		local t_n = tile + AIMap.GetTileIndex(-1, -1);

		if (AIMarine.AreWaterTilesConnected(tile, t_nw) && AIMarine.AreWaterTilesConnected(tile, t_ne)) {
			if (!(AIMarine.AreWaterTilesConnected(t_n, t_nw) && AIMarine.AreWaterTilesConnected(t_n, t_ne))) {
				return true;
			}
		}

		local t_s = tile + AIMap.GetTileIndex(1, 1);

		if (AIMarine.AreWaterTilesConnected(tile, t_se) && AIMarine.AreWaterTilesConnected(tile, t_sw)) {
			if (!(AIMarine.AreWaterTilesConnected(t_s, t_se) && AIMarine.AreWaterTilesConnected(t_s, t_sw))) {
				return true;
			}
		}

		local t_w = tile + AIMap.GetTileIndex(1, -1);

		if (AIMarine.AreWaterTilesConnected(tile, t_nw) && AIMarine.AreWaterTilesConnected(tile, t_sw)) {
			if (!(AIMarine.AreWaterTilesConnected(t_w, t_nw) && AIMarine.AreWaterTilesConnected(t_w, t_sw))) {
				return true;
			}
		}

		if (AIMarine.AreWaterTilesConnected(tile, t_se) && AIMarine.AreWaterTilesConnected(tile, t_nw)) {
			if (AIMarine.AreWaterTilesConnected(t_s, t_se) && AIMarine.AreWaterTilesConnected(t_s, t_sw)) {
				if (!(AIMarine.AreWaterTilesConnected(t_w, t_nw) && AIMarine.AreWaterTilesConnected(t_w, t_sw))) {
					return true;
				}
			} else if (AIMarine.AreWaterTilesConnected(t_e, t_se) && AIMarine.AreWaterTilesConnected(t_e, t_ne)) {
				if (!(AIMarine.AreWaterTilesConnected(t_n, t_nw) && AIMarine.AreWaterTilesConnected(t_n, t_ne))) {
					return true;
				}
			} else {
				return true;
			}
		}

		if (AIMarine.AreWaterTilesConnected(tile, t_ne) && AIMarine.AreWaterTilesConnected(tile, t_sw)) {
			if (AIMarine.AreWaterTilesConnected(t_e, t_se) && AIMarine.AreWaterTilesConnected(t_e, t_ne)) {
				if (!(AIMarine.AreWaterTilesConnected(t_s, t_se) && AIMarine.AreWaterTilesConnected(t_s, t_sw))) {
					return true;
				}
			} else if (AIMarine.AreWaterTilesConnected(t_n, t_nw) && AIMarine.AreWaterTilesConnected(t_n, t_ne)) {
				if (!(AIMarine.AreWaterTilesConnected(t_w, t_nw) && AIMarine.AreWaterTilesConnected(t_w, t_sw))) {
					return true;
				}
			} else {
				return true;
			}
		}

		return false;
	}

	/**
	 * Get the tile where ships can use to dock at the given dock.
	 * @param dock_tile A tile that is part of the dock.
	 * @return The tile where ships dock at the given dock.
	 */
	function GetDockDockingTile(dock_tile)
	{
		assert(AIMarine.IsDockTile(dock_tile));

		local dock_slope;
		if (AITile.GetSlope(dock_tile) == AITile.SLOPE_FLAT) {
			foreach (offset in [AIMap.GetMapSizeX(), -AIMap.GetMapSizeX(), 1, -1]) {
				local offset_tile = dock_tile + offset;
				if (AIMarine.IsDockTile(offset_tile)) {
					local slope = AITile.GetSlope(offset_tile);
					if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE) {
						dock_slope = offset_tile;
						break;
					}
				}
			}
		} else {
			dock_slope = dock_tile;
		}

		local slope = AITile.GetSlope(dock_slope);
		if (slope == AITile.SLOPE_NE) {
			return dock_slope + 2;
		} else if (slope == AITile.SLOPE_SE) {
			return dock_slope - 2 * AIMap.GetMapSizeX();
		} else if (slope == AITile.SLOPE_SW) {
			return dock_slope - 2;
		} else if (slope == AITile.SLOPE_NW) {
			return dock_slope + 2 * AIMap.GetMapSizeX();
		}
	}

	/**
	 * Check whether the tile we're coming from is compatible with the axis of a
	 *  lock planned in this location.
	 * @param prev_tile The tile we're coming from.
	 * @param middle_tile The tile of the middle part of a planned lock.
	 * @return true if the previous tile is compatible with the axis of the planned lock.
	 */
	function CheckLockDirection(prev_tile, middle_tile)
	{
		local slope = AITile.GetSlope(middle_tile);
		assert(slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE);

		if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NE) {
			return prev_tile == middle_tile + 1 || prev_tile == middle_tile - 1;
		} else if (slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NW) {
			return prev_tile == middle_tile + AIMap.GetMapSizeX() || prev_tile == middle_tile - AIMap.GetMapSizeX();
		}

		return false;
	}

	/**
	 * Get the tile of the middle part of a lock.
	 * @param tile The tile of a part of a lock.
	 * @return The tile of the middle part of the same lock.
	 */
	function GetLockMiddleTile(tile)
	{
		assert(AIMarine.IsLockTile(tile));

		local slope = AITile.GetSlope(tile);
		if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE) return tile;

		assert(slope == AITile.SLOPE_FLAT);

		local other_end = Utils.GetOtherLockEnd(tile);
		return tile - (tile - other_end) / 2;
	}

	/**
	 * Get the tile of the other end of a lock.
	 * @param tile The tile of the entrance of a lock.
	 * @return The tile of the other end of the same lock.
	 */
	function GetOtherLockEnd(tile)
	{
		assert(AIMarine.IsLockTile(tile) && AITile.GetSlope(tile) == AITile.SLOPE_FLAT);

		foreach (offset in [AIMap.GetMapSizeX(), -AIMap.GetMapSizeX(), 1, -1]) {
			local middle_tile = tile + offset;
			local slope = AITile.GetSlope(middle_tile);
			if (AIMarine.IsLockTile(middle_tile) && (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE)) {
				return middle_tile + offset;
			}
		}
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
	function CheckAqueductSlopes(tile_a, tile_b)
	{
		if (AIMap.DistanceManhattan(tile_a, tile_b) != 1) return false;
		local slope_a = AITile.GetSlope(tile_a);
		local slope_b = AITile.GetSlope(tile_b);
		if ((slope_a != AITile.SLOPE_SW && slope_a != AITile.SLOPE_NW && slope_a != AITile.SLOPE_SE && slope_a != AITile.SLOPE_NE) ||
				(slope_b != AITile.SLOPE_SW && slope_b != AITile.SLOPE_NW && slope_b != AITile.SLOPE_SE && slope_b != AITile.SLOPE_NE)) {
			return false;
		}

		if (AITile.GetComplementSlope(slope_a) != slope_b) return false;

		local offset;
		if (slope_a == AITile.SLOPE_NE) {
			offset = 1;
		} else if (slope_a == AITile.SLOPE_SE) {
			offset = -AIMap.GetMapSizeX();
		} else if (slope_a == AITile.SLOPE_SW) {
			offset = -1;
		} else if (slope_a == AITile.SLOPE_NW) {
			offset = AIMap.GetMapSizeX();
		}

		return tile_a + offset == tile_b;
	}

	function EstimateTownRectangle(town_id)
	{
		local townLocation = AITown.GetLocation(town_id);
		local rectangleIncreaseKoeficient = 1;

		local topCornerTile = townLocation;
		local bottomCornerTile = townLocation;

		local isMaxExpanded = false;
		while (!isMaxExpanded) {
			local maxExpandedCounter = 0;
			for (local i = 0; i < 4; ++i) {
				switch(i) {
					case 0:
						local offsetTile = Utils.GetOffsetTile(topCornerTile, -1 * rectangleIncreaseKoeficient, 0);

						if (offsetTile == AIMap.TILE_INVALID) {
							++maxExpandedCounter;
							continue;
						}

						if (AITown.IsWithinTownInfluence(town_id, offsetTile)) {
							topCornerTile = offsetTile;
						}
						else {
							++maxExpandedCounter;
							continue;
						}
						break;

					case 1:
						local offsetTile = Utils.GetOffsetTile(bottomCornerTile, 0, rectangleIncreaseKoeficient);

						if (offsetTile == AIMap.TILE_INVALID) {
							++maxExpandedCounter;
							continue;
						}

						if (AITown.IsWithinTownInfluence(town_id, offsetTile)) {
							bottomCornerTile = offsetTile;
						}
						else {
							++maxExpandedCounter;
							continue;
						}
						break;

					case 2:
						local offsetTile = Utils.GetOffsetTile(bottomCornerTile, rectangleIncreaseKoeficient, 0);

						if (offsetTile == AIMap.TILE_INVALID) {
							++maxExpandedCounter;
							continue;
						}

						if (AITown.IsWithinTownInfluence(town_id, offsetTile)) {
							bottomCornerTile = offsetTile;
						}
						else {
							++maxExpandedCounter;
							continue;
						}
						break;

					case 3:
						local offsetTile = Utils.GetOffsetTile(topCornerTile, 0, -1 * rectangleIncreaseKoeficient);

						if (offsetTile == AIMap.TILE_INVALID) {
							++maxExpandedCounter;
						}

						if (AITown.IsWithinTownInfluence(town_id, offsetTile)) {
							topCornerTile = offsetTile;
						}
						else {
							++maxExpandedCounter;
						}
						break;

					default:
						break;
				}
			}

			if (maxExpandedCounter == 4) {
				isMaxExpanded = true;
			}
		}

		return [topCornerTile, bottomCornerTile];
	}

	/**
	 * Check if we have enough money (via loan and on bank).
	 */
	function HasMoney(money)
	{
		if (AIGameSettings.IsValid("infinite_money") && AIGameSettings.GetValue("infinite_money")) return true;

		local loan_amount = AICompany.GetLoanAmount();
		local max_loan_amount = AICompany.GetMaxLoanAmount();
		local bank_balance = AICompany.GetBankBalance(::caches.m_my_company_id);
//		AILog.Info("loan_amount = " + loan_amount + "; max_loan_amount = " + max_loan_amount + "; bank_balance = " + bank_balance);
//		AILog.Info("bank_balance + max_loan_amount - loan_amount >= money : " + (bank_balance + max_loan_amount - loan_amount) + " >= " + money + " : " + (bank_balance + max_loan_amount - loan_amount >= money));
		return (bank_balance + max_loan_amount - loan_amount) >= money;
	}

	function GetMoney(money)
	{
		local bank_balance = AICompany.GetBankBalance(::caches.m_my_company_id);
		if (bank_balance >= money) return;
		local request_loan = money - bank_balance;
		local loan_interval = AICompany.GetLoanInterval();
		local over_interval = request_loan % loan_interval;
		request_loan += loan_interval - over_interval;
		local loan_amount = AICompany.GetLoanAmount();
		local max_loan_amount = AICompany.GetMaxLoanAmount();
		if (loan_amount + request_loan > max_loan_amount) {
			AICompany.SetLoanAmount(max_loan_amount);
		} else {
			AICompany.SetLoanAmount(loan_amount + request_loan);
		}
	}

	function RepayLoan()
	{
		local bank_balance = AICompany.GetBankBalance(::caches.m_my_company_id);
		local loan_amount = AICompany.GetLoanAmount();
		local repay_loan = loan_amount - bank_balance > 0 ? loan_amount - bank_balance : 0;
		AICompany.SetMinimumLoanAmount(repay_loan);
	}
};

class MoneyTest
{
	function DoMoneyTest()
	{
		local price = GetPrice();
		if (Utils.HasMoney(price)) {
			Utils.GetMoney(price);
		}
		if (DoAction()) {
			Utils.RepayLoan();
			return true;
		}
//		AILog.Error(AIError.GetLastErrorString());
		Utils.RepayLoan();
		return false;
	}
};

class TestDemolishTile extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AITile.DemolishTile(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITile.DemolishTile(l);
		return cost.GetCosts();
	}

	function TryDemolish(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestRemoveRoadStation extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.RemoveRoadStation(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.RemoveRoadStation(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestRemoveRoadDepot extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.RemoveRoadDepot(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.RemoveRoadDepot(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestBuildRoad extends MoneyTest
{
	s = null;
	e = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildRoad(s, e);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoad(s, e);
		return cost.GetCosts();
	}

	function TryBuild(start, end)
	{
		s = start;
		e = end;
		return DoMoneyTest();
	}
};

class TestBuildTunnel extends MoneyTest
{
	t = null;
	l = null;

	function DoAction()
	{
		return AIExecMode() && AITunnel.BuildTunnel(t, l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITunnel.BuildTunnel(t, l);
		return cost.GetCosts();
	}

	function TryBuild(vehicleType, location)
	{
		t = vehicleType;
		l = location;
		return DoMoneyTest();
	}
};

class TestRemoveTunnel extends MoneyTest
{
	t = null;

	function DoAction()
	{
		return AIExecMode() && AITunnel.RemoveTunnel(t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITunnel.RemoveTunnel(t);
		return cost.GetCosts();
	}

	function TryRemove(tile)
	{
		t = tile;
		return DoMoneyTest();
	}
};

class TestBuildBridge extends MoneyTest
{
	t = null;
	i = null;
	s = null;
	e = null;

	function DoAction()
	{
		return AIExecMode() && AIBridge.BuildBridge(t, i, s, e);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIBridge.BuildBridge(t, i, s, e);
		return cost.GetCosts();
	}

	function TryBuild(vehicleType, bridgeId, start, end)
	{
		t = vehicleType;
		i = bridgeId;
		s = start;
		e = end;
		return DoMoneyTest();
	}
};

class TestRemoveBridge extends MoneyTest
{
	t = null;

	function DoAction()
	{
		return AIExecMode() && AIBridge.RemoveBridge(t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIBridge.RemoveBridge(t);
		return cost.GetCosts();
	}

	function TryRemove(tile)
	{
		t = tile;
		return DoMoneyTest();
	}
};

class TestBuildRoadStation extends MoneyTest
{
	l = null;
	e = null;
	t = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildRoadStation(l, e, t, i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoadStation(l, e, t, i);
		return cost.GetCosts();
	}

	function TryBuild(location, exit, vehicleType, stationId)
	{
		l = location;
		e = exit;
		t = vehicleType;
		i = stationId;
		return DoMoneyTest();
	}
};

class TestBuildDriveThroughRoadStation extends MoneyTest
{
	l = null;
	e = null;
	t = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildDriveThroughRoadStation(l, e, t, i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildDriveThroughRoadStation(l, e, t, i);
		return cost.GetCosts();
	}

	function TryBuild(location, exit, vehicleType, stationId)
	{
		l = location;
		e = exit;
		t = vehicleType;
		i = stationId;
		return DoMoneyTest();
	}
};

class TestBuildRoadDepot extends MoneyTest
{
	l = null;
	e = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildRoadDepot(l, e);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoadDepot(l, e);
		return cost.GetCosts();
	}

	function TryBuild(location, exit)
	{
		l = location;
		e = exit;
		return DoMoneyTest();
	}
};

class TestBuildAirport extends MoneyTest
{
	l = null;
	t = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIAirport.BuildAirport(l, t, i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIAirport.BuildAirport(l, t, i);
		return cost.GetCosts();
	}

	function TryBuild(airport_location, airport_type, airport_stationId)
	{
		l = airport_location;
		t = airport_type;
		i = airport_stationId;
		if (DoMoneyTest()) {
			return true;
		}
//		assert(AIError.GetLastError() != AIError.ERR_STATION_TOO_SPREAD_OUT);
		return false;
	}
};

class TestRemoveAirport extends MoneyTest
{
	l = null;

	function DoAction()
	{
		if (AIExecMode() && AIAirport.RemoveAirport(l)) {
			return true;
		}
		return false;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIAirport.RemoveAirport(l);
		return cost.GetCosts();
	}

	function TryRemove(airport_location)
	{
		l = airport_location;
		if (DoMoneyTest()) {
			return true;
		}
		return false;
	}
};

class TestRemoveCanal extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.RemoveCanal(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.RemoveCanal(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestBuildCanal extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildCanal(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildCanal(l);
		return cost.GetCosts();
	}

	function TryBuild(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestBuildDock extends MoneyTest
{
	l = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildDock(l, i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildDock(l, i);
		return cost.GetCosts();
	}

	function TryBuild(location, stationId)
	{
		l = location;
		i = stationId;
		return DoMoneyTest();
	}
};

class TestBuildLock extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildLock(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildLock(l);
		return cost.GetCosts();
	}

	function TryBuild(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestRemoveDock extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.RemoveDock(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.RemoveDock(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestBuildWaterDepot extends MoneyTest
{
	t = null;
	b = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildWaterDepot(t, b);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildWaterDepot(t, b);
		return cost.GetCosts();
	}

	function TryBuild(top, bottom)
	{
		t = top;
		b = bottom;
		return DoMoneyTest();
	}
};

class TestRemoveWaterDepot extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.RemoveWaterDepot(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.RemoveWaterDepot(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestBuildRailStation extends MoneyTest
{
	t = null;
	d = null;
	n = null;
	l = null;
	s = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildRailStation(t, d, n, l, s);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildRailStation(t, d, n, l, s);
		return cost.GetCosts();
	}

	function TryBuild(tile, direction, num_platforms, platform_length, stationId)
	{
		t = tile;
		d = direction;
		n = num_platforms;
		l = platform_length;
		s = stationId;
		return DoMoneyTest();
	}
};

class TestBuildRail extends MoneyTest
{
	f = null;
	l = null;
	t = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildRail(f, l, t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildRail(f, l, t);
		return cost.GetCosts();
	}

	function TryBuild(from, location, to)
	{
		f = from;
		l = location;
		t = to;
		return DoMoneyTest();
	}
};

// class TestConvertRailType extends MoneyTest
// {
// 	s = null;
// 	e = null;
// 	c = null;

// 	function DoAction()
// 	{
// 		return AIExecMode() && AIRail.ConvertRailType(s, e, c);
// 	}

// 	function GetPrice()
// 	{
// 		local cost = AIAccounting();
// 		AITestMode() && AIRail.ConvertRailType(s, e, c);
// 		return cost.GetCosts();
// 	}

// 	function TryConvert(start_tile, end_tile, convert_to)
// 	{
// 		s = start_tile;
// 		e = end_tile;
// 		c = convert_to;
// 		return DoMoneyTest();
// 	}
// };

class TestBuildRailDepot extends MoneyTest
{
	t = null;
	f = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildRailDepot(t, f);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildRailDepot(t, f);
		return cost.GetCosts();
	}

	function TryBuild(tile, front)
	{
		t = tile;
		f = front;
		return DoMoneyTest();
	}
};

class TestRemoveRailStationTileRectangle extends MoneyTest
{
	f = null;
	t = null;
	k = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.RemoveRailStationTileRectangle(f, t, k);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.RemoveRailStationTileRectangle(f, t, k);
		return cost.GetCosts();
	}

	function TryRemove(from, to, keep_rail)
	{
		f = from;
		t = to;
		k = keep_rail;
		return DoMoneyTest();
	}
};

class TestRemoveRail extends MoneyTest
{
	f = null;
	l = null;
	t = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.RemoveRail(f, l, t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.RemoveRail(f, l, t);
		return cost.GetCosts();
	}

	function TryRemove(from, location, to)
	{
		f = from;
		l = location;
		t = to;
		return DoMoneyTest();
	}
};

class TestBuildSignal extends MoneyTest
{
	l = null;
	t = null;
	s = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildSignal(l, t, s);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildSignal(l, t, s);
		return cost.GetCosts();
	}

	function TryBuild(location, to, signal)
	{
		l = location;
		t = to;
		s = signal;
		return DoMoneyTest();
	}
};

class TestBuildVehicleWithRefit extends MoneyTest
{
	d = null;
	e = null;
	c = null;
	v = null;

	function DoAction()
	{
		v = AIVehicle.BuildVehicleWithRefit(d, e, c);
		if (!AIVehicle.IsValidVehicle(v)) {
			return false;
		}
		return true;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIVehicle.BuildVehicleWithRefit(d, e, c);
		return cost.GetCosts();
	}

	function TryBuild(depot, engine, cargo_type)
	{
		d = depot;
		e = engine;
		c = cargo_type;
		if (DoMoneyTest()) {
			return v;
		}
		return AIVehicle.VEHICLE_INVALID;
	}
};

class TestCloneVehicle extends MoneyTest
{
	d = null;
	v = null;
	s = null;
	c = null;

	function DoAction()
	{
		c = AIVehicle.CloneVehicle(d, v, s);
		if (!AIVehicle.IsValidVehicle(c)) {
			return false;
		}
		return true;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIVehicle.CloneVehicle(d, v, s);
		return cost.GetCosts();
	}

	function TryClone(depot, vehicle, shared)
	{
		d = depot;
		v = vehicle;
		s = shared;
		if (DoMoneyTest()) {
			return c;
		}
		return AIVehicle.VEHICLE_INVALID;
	}
};

class TestPerformTownAction extends MoneyTest
{
	t = null;
	a = null;

	function DoAction()
	{
		if (AIExecMode() && AITown.PerformTownAction(t, a)) {
			return true;
		}
		return false;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITown.PerformTownAction(t, a);
		return cost.GetCosts();
	}

	function TryPerform(town_id, action)
	{
		t = town_id;
		a = action;
		return DoMoneyTest();
	}

	function TestCost(town_id, action)
	{
		t = town_id;
		a = action;
		return GetPrice();
	}
};

class TestBuildHQ extends MoneyTest
{
	t = null;

	function DoAction()
	{
		if (AIExecMode() && AICompany.BuildCompanyHQ(t)) {
			return true;
		}
		return false;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AICompany.BuildCompanyHQ(t);
		return cost.GetCosts();
	}

	function TryBuild(tile)
	{
		t = tile;
		return DoMoneyTest();
	}
};

class TestFoundTown extends MoneyTest
{
	t = null;
	s = null;
	c = null;
	l = null;
	n = null;

	function DoAction()
	{
		if (AIExecMode() && AITown.FoundTown(t, s, c, l, n)) {
			return true;
		}
		return false;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITown.FoundTown(t, s, c, l, n);
		return cost.GetCosts();
	}

	function TryFound(tile, size, city, layout, name)
	{
		t = tile;
		s = size;
		c = city;
		l = layout;
		n = name;
		return DoMoneyTest();
	}

	function TestCost(tile, size, city, layout, name)
	{
		t = tile;
		s = size;
		c = city;
		l = layout;
		n = name;
		return GetPrice();
	}
};
