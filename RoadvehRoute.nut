require("RoadvehRouteManager.nut");

class RoadRoute extends RoadRouteManager
{
	static START_VEHICLE_COUNT = {
	    [AICargo.CC_PASSENGERS] = 10,
		[AICargo.CC_MAIL] = 5,
	};
	static MIN_VEHICLE_START_COUNT = 5;

	/* These are saved */
	m_city_from = null; // saved
	m_city_to = null; // saved
	m_station_from = null; // saved
	m_station_to = null; // saved
	m_depot_tile = null; // saved
	m_bridge_tiles = null; // saved
	m_cargo_class = null; // saved
	m_last_vehicle_added = null; // saved
	m_last_vehicle_removed = null; // saved
	m_active_route = null; // saved
	m_expanded_from_count = null; // saved
	m_expanded_to_count = null; // saved
	m_sent_to_depot_road_group = null; // saved
	m_group = null; // saved

	/* These are not saved */
	m_engine = null;
	m_vehicle_list = null;
	m_station_id_from = null;
	m_station_id_to = null;
	m_station_name_from = null;
	m_station_name_to = null;
	m_max_vehicle_count_mode = null;
	m_cargo_type = null;
	m_vehicle_type = null;
	m_station_type = null;

	constructor(city_from, city_to, station_from, station_to, depot_tile, bridge_tiles, cargo_class, sent_to_depot_road_group, is_loaded = false)
	{
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_station_from = station_from;
		this.m_station_to = station_to;
		this.m_depot_tile = depot_tile;
		this.m_bridge_tiles = bridge_tiles;
		this.m_cargo_class = cargo_class;
		this.m_sent_to_depot_road_group = sent_to_depot_road_group;

		this.m_last_vehicle_added = 0;
		this.m_last_vehicle_removed = AIDate.GetCurrentDate();
		this.m_active_route = true;
		this.m_expanded_from_count = 0;
		this.m_expanded_to_count = 0;
		this.m_group = AIGroup.GROUP_INVALID;
		this.m_max_vehicle_count_mode = AIController.GetSetting("road_cap_mode");

		this.m_vehicle_list = AIList();
		this.m_station_id_from = AIStation.GetStationID(station_from);
		this.m_station_id_to = AIStation.GetStationID(station_to);
		this.m_station_name_from = AIBaseStation.GetName(this.m_station_id_from);
		this.m_station_name_to = AIBaseStation.GetName(this.m_station_id_to);
		this.m_cargo_type = Utils.GetCargoType(cargo_class);
		this.m_vehicle_type = AIRoad.GetRoadVehicleTypeForCargo(this.m_cargo_type);
		this.m_station_type = this.m_vehicle_type == AIRoad.ROADVEHTYPE_BUS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;

		this.m_engine = GetTruckEngine();

		if (!is_loaded) {
			AddVehiclesToNewRoute();
		}
	}

	function ValidateVehicleList()
	{
		foreach (v, _ in this.m_vehicle_list) {
			if (!AIVehicle.IsValidVehicle(v)) {
				this.m_vehicle_list[v] = null;
				continue;
			}
			if (AIVehicle.GetVehicleType(v) != AIVehicle.VT_ROAD) {
				AILog.Error("r:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
			if (AIVehicle.GetRoadType(v) != AIRoad.ROADTYPE_ROAD) {
				AILog.Error("r:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
			local num_orders = AIOrder.GetOrderCount(v);
			if (num_orders < 2) {
				AILog.Error("r:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
			local order_from = false;
			local order_to = false;
			for (local o = 0; o < num_orders; o++) {
				if (!AIOrder.IsValidVehicleOrder(v, o)) {
					continue;
				}
				if (AIOrder.IsConditionalOrder(v, o)) {
					continue;
				}
				local station_id = AIStation.GetStationID(AIOrder.GetOrderDestination(v, o));
				if (station_id == this.m_station_id_from) {
					order_from = true;
				}
				if (station_id == this.m_station_id_to) {
					order_to = true;
				}
			}
			if (!order_from || !order_to) {
				AILog.Error("r:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
		}
	}

	function SentToDepotList(i)
	{
		local sent_to_depot_list = AIList();
		this.ValidateVehicleList();
		foreach (vehicle, status in this.m_vehicle_list) {
			if (status == i) {
				sent_to_depot_list[vehicle] = i;
			}
		}
		return sent_to_depot_list;
	}

	function GetEngineList()
	{
		local engine_list = AIEngineList(AIVehicle.VT_ROAD);
		foreach (engine_id, _ in engine_list) {
			if (!AIEngine.IsBuildable(engine_id)) {
				engine_list[engine_id] = null;
				continue;
		 	}
			if (AIEngine.GetRoadType(engine_id) != AIRoad.ROADTYPE_ROAD) {
				engine_list[engine_id] = null;
				continue;
			}
			if (!AIEngine.CanRefitCargo(engine_id, this.m_cargo_type)) {
				engine_list[engine_id] = null;
				continue;
			}
			engine_list[engine_id] = AIEngine.IsArticulated(engine_id) ? 1 : 0;
		}

		local station_from_tiles = AITileList_StationType(this.m_station_id_from, this.m_station_type);
		local articulated_viable = false;
		foreach (tile, _ in station_from_tiles) {
			if (AIRoad.IsDriveThroughRoadStationTile(tile)) {
//				AILog.Info(this.m_station_name_from + " is articulated viable!")
				articulated_viable = true;
				break;
			}
		}

		if (articulated_viable) {
			local station_to_tiles = AITileList_StationType(this.m_station_id_to, this.m_station_type);
			articulated_viable = false;
			foreach (tile, _ in station_to_tiles) {
				if (AIRoad.IsDriveThroughRoadStationTile(tile)) {
//					AILog.Info(this.m_station_name_to + " is articulated viable!")
					articulated_viable = true;
					break;
				}
			}
		}

		if (!articulated_viable) {
			engine_list.RemoveValue(1); // remove all articulated engines
		}

		return engine_list;
	}

	function GetTruckEngine()
	{
		local engine_list = GetEngineList();
		if (engine_list.IsEmpty()) return this.m_engine == null ? -1 : this.m_engine;

		local distance = AIMap.DistanceManhattan(this.m_station_from, this.m_station_to);
		local best_income = null;
		local best_engine = null;
		for (local engine = engine_list.Begin(); !engine_list.IsEnd(); engine = engine_list.Next()) {
			local multiplier = Utils.GetEngineReliabilityMultiplier(engine);
			local max_speed = AIEngine.GetMaxSpeed(engine);
			local days_in_transit = (distance * 192 * 16) / (2 * 3 * 74 * max_speed / 4);
			local running_cost = AIEngine.GetRunningCost(engine);
			local capacity = ::caches.GetBuildWithRefitCapacity(this.m_depot_tile, engine, this.m_cargo_type);
			local income = ((capacity * AICargo.GetCargoIncome(this.m_cargo_type, distance, days_in_transit) - running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
//			AILog.Info("Engine: " + AIEngine.GetName(engine) + "; Capacity: " + capacity + "; Max Speed: " + max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + running_cost + "; Distance: " + distance + "; Income: " + income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_engine = engine;
			}
		}

		return best_engine == null ? -1 : best_engine;
	}

	function UpgradeEngine()
	{
		if (!this.m_active_route) return;

		this.m_engine = GetTruckEngine();
	}

	function UpgradeBridges()
	{
		if (!this.m_active_route) return;

		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
//		for (local i = this.m_bridge_tiles.Begin(); !this.m_bridge_tiles.IsEnd(); i = this.m_bridge_tiles.Next()) {
		foreach (tile in this.m_bridge_tiles) {
			local north_tile = tile[0];
			local south_tile = tile[1];

			if (AIBridge.IsBridgeTile(north_tile) && (AIBridge.GetOtherBridgeEnd(north_tile) == south_tile)) {
				local old_bridge = AIBridge.GetBridgeType(north_tile);

				local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(north_tile, south_tile) + 1);
				for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
					bridge_list.SetValue(bridge, AIBridge.GetMaxSpeed(bridge));
				}
				bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
				if (!bridge_list.IsEmpty()) {
					local new_bridge = bridge_list.Begin();
					if (TestBuildBridge().TryBuild(AIVehicle.VT_ROAD, new_bridge, north_tile, south_tile)) {
						AILog.Info("Bridge at tiles " + north_tile + " and " + south_tile + " upgraded from " + AIBridge.GetName(old_bridge, AIVehicle.VT_ROAD) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(AIBridge.GetMaxSpeed(old_bridge)) + ") to " + AIBridge.GetName(new_bridge, AIVehicle.VT_ROAD) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(AIBridge.GetMaxSpeed(new_bridge)) + ")");
					}
				}
			}
		}
	}

	function DeleteSellVehicle(vehicle)
	{
		this.m_vehicle_list[vehicle] = null;
		AIVehicle.SellVehicle(vehicle);
		Utils.RepayLoan();
	}

	function AddVehicle(return_vehicle = false)
	{
		ValidateVehicleList();
		if (m_max_vehicle_count_mode != 2 && this.m_vehicle_list.Count() >= OptimalVehicleCount()) {
			return null;
		}

		/* Clone vehicle, share orders */
		local clone_vehicle_id = AIVehicle.VEHICLE_INVALID;
		local share_orders_vid = AIVehicle.VEHICLE_INVALID;
		foreach (vehicle_id, _ in this.m_vehicle_list) {
			if (this.m_engine != null && AIEngine.IsValidEngine(this.m_engine) && AIEngine.IsBuildable(this.m_engine)) {
				if (AIVehicle.GetEngineType(vehicle_id) == this.m_engine) {
					clone_vehicle_id = vehicle_id;
				}
			}
			if (AIVehicle.GetGroupID(vehicle_id) == this.m_group && AIGroup.IsValidGroup(this.m_group)) {
				share_orders_vid = vehicle_id;
			}
		}

		local new_vehicle = AIVehicle.VEHICLE_INVALID;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			new_vehicle = TestBuildVehicleWithRefit().TryBuild(this.m_depot_tile, this.m_engine, Utils.GetCargoType(this.m_cargo_class));
		} else {
			new_vehicle = TestCloneVehicle().TryClone(this.m_depot_tile, clone_vehicle_id, (AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id) ? true : false);
		}

		if (AIVehicle.IsValidVehicle(new_vehicle)) {
			this.m_vehicle_list[new_vehicle] = 2;
			local vehicle_ready_to_start = false;
			local depot_order_flags = AIOrder.OF_SERVICE_IF_NEEDED | AIOrder.OF_NON_STOP_INTERMEDIATE;
			if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					local load_mode = AIController.GetSetting("road_load_mode");
					if (AIOrder.AppendOrder(new_vehicle, this.m_depot_tile, depot_order_flags) &&
							AIOrder.AppendOrder(new_vehicle, this.m_station_from, AIOrder.OF_NON_STOP_INTERMEDIATE | (load_mode == 0 ? AIOrder.OF_FULL_LOAD_ANY : AIOrder.OF_NONE)) &&
							(load_mode == 1 && AIOrder.AppendConditionalOrder(new_vehicle, 0) && AIOrder.SetOrderCondition(new_vehicle, 2, AIOrder.OC_LOAD_PERCENTAGE) && AIOrder.SetOrderCompareFunction(new_vehicle, 2, AIOrder.CF_EQUALS) && AIOrder.SetOrderCompareValue(new_vehicle, 2, 0) || true) &&
							AIOrder.AppendOrder(new_vehicle, this.m_depot_tile, depot_order_flags) &&
							AIOrder.AppendOrder(new_vehicle, this.m_station_to, AIOrder.OF_NON_STOP_INTERMEDIATE | (load_mode == 0 ? AIOrder.OF_FULL_LOAD_ANY : AIOrder.OF_NONE)) &&
							(load_mode == 1 && AIOrder.AppendConditionalOrder(new_vehicle, 3) && AIOrder.SetOrderCondition(new_vehicle, 5, AIOrder.OC_LOAD_PERCENTAGE) && AIOrder.SetOrderCompareFunction(new_vehicle, 5, AIOrder.CF_EQUALS) && AIOrder.SetOrderCompareValue(new_vehicle, 5, 0) || true)) {
						vehicle_ready_to_start = true;
					} else {
						DeleteSellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						local new_vehicle_order_0_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
						if (new_vehicle_order_0_flags != depot_order_flags) {
							AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_0_flags + " != " + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
							DeleteSellVehicle(new_vehicle);
							return null;
						} else {
							vehicle_ready_to_start = true;
						}
					} else {
						AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						DeleteSellVehicle(new_vehicle);
						return null;
					}
				}
			} else {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					local new_vehicle_order_0_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					if (new_vehicle_order_0_flags != depot_order_flags) {
						if (AIOrder.SetOrderFlags(new_vehicle, 0, depot_order_flags)) {
							vehicle_ready_to_start = true;
						} else {
							DeleteSellVehicle(new_vehicle);
							return null;
						}
					} else {
						vehicle_ready_to_start = true;
					}
				} else {
					if (clone_vehicle_id != share_orders_vid) {
						if (!AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
							AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
							DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					local new_vehicle_order_0_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					if (new_vehicle_order_0_flags != depot_order_flags) {
						AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_0_flags + " != " + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
						DeleteSellVehicle(new_vehicle);
						return null;
					} else {
						vehicle_ready_to_start = true;
					}
				}
			}
			if (vehicle_ready_to_start) {
				AIVehicle.StartStopVehicle(new_vehicle);
//				AILog.Info("new_vehicle = " + AIVehicle.GetName(new_vehicle) + "; clone_vehicle_id = " + AIVehicle.GetName(clone_vehicle_id) + "; share_orders_vid = " + AIVehicle.GetName(share_orders_vid));

				this.m_last_vehicle_added = AIDate.GetCurrentDate();

				if (AIGroup.IsValidGroup(this.m_group) && AIVehicle.GetGroupID(new_vehicle) != this.m_group) {
					AIGroup.MoveVehicle(this.m_group, new_vehicle);
				}
				if (return_vehicle) {
					return new_vehicle;
				} else {
					return 1;
				}
			}
		} else {
			return null;
		}
	}

	function OptimalVehicleCount()
	{
		if (m_max_vehicle_count_mode == 0) return 25;

		local stationDistance = AIMap.DistanceManhattan(this.m_station_from, this.m_station_to);
//		AILog.Info("stationDistance = " + stationDistance);
		local articulatedEngine = AIEngine.IsArticulated(this.m_engine);
		local count_interval = ((AIEngine.GetMaxSpeed(this.m_engine) * 2 * 3 * 74 * MIN_VEHICLE_START_COUNT / 4) / 192) / 16;
//		AILog.Info("count_interval = " + count_interval + "; MaxSpeed = " + AIEngine.GetMaxSpeed(this.m_engine));
		local vehicleCount = /*2 * */(count_interval > 0 ? (stationDistance / count_interval) : 0);
//		AILog.Info("vehicleCount = " + vehicleCount);

		local fromCount = 0;
		local fromTiles = AITileList_StationType(AIStation.GetStationID(this.m_station_from), this.m_cargo_class == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
		for (local tile = fromTiles.Begin(); !fromTiles.IsEnd(); tile = fromTiles.Next()) {
			if (AIRoad.IsDriveThroughRoadStationTile(this.m_station_from)) {
				fromCount += articulatedEngine ? 2 : 4;
			} else {
				fromCount += articulatedEngine ? 0 : 2;
			}
		}

		local toCount = 0;
		local toTiles = AITileList_StationType(AIStation.GetStationID(this.m_station_to), this.m_cargo_class == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
		for (local tile = toTiles.Begin(); !toTiles.IsEnd(); tile = toTiles.Next()) {
			if (AIRoad.IsDriveThroughRoadStationTile(this.m_station_to)) {
				toCount += articulatedEngine ? 2 : 4;
			} else {
				toCount += articulatedEngine ? 0 : 2;
			}
		}

//		AILog.Info("fromCount = " + fromCount);
//		AILog.Info("toCount = " + toCount);
		vehicleCount += 2 * (fromCount < toCount ? fromCount : toCount);

		return vehicleCount;
	}

	function AddVehiclesToNewRoute()
	{
		this.m_group = GroupVehicles();
		local optimal_vehicle_count = OptimalVehicleCount();

		ValidateVehicleList();
		local numvehicles = this.m_vehicle_list.Count();
		local numvehicles_before = numvehicles;
		if (numvehicles >= optimal_vehicle_count) {
			if (this.m_last_vehicle_added < 0) this.m_last_vehicle_added *= -1;
			return 0;
		}

		local routedist = AIMap.DistanceManhattan(this.m_station_from, this.m_station_to);

		local buyVehicleCount = START_VEHICLE_COUNT[this.m_cargo_class];
		buyVehicleCount += m_max_vehicle_count_mode == 0 ? routedist / 20 : optimal_vehicle_count / (this.m_cargo_class == AICargo.CC_PASSENGERS ? 2 : 4);

		if (buyVehicleCount > optimal_vehicle_count - numvehicles) {
			buyVehicleCount = optimal_vehicle_count - numvehicles;
		}

		for (local i = 0; i < buyVehicleCount; ++i) {
			local old_lastVehicleAdded = -this.m_last_vehicle_added;
			if (old_lastVehicleAdded > 0 && AIDate.GetCurrentDate() - old_lastVehicleAdded <= 3) {
				break;
			}
			this.m_last_vehicle_added = 0;
			local added_vehicle = AddVehicle(true);
			if (added_vehicle != null) {
				local nameFrom = AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from));
				local nameTo = AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to));
				if (numvehicles % 2 == 1) {
					AIOrder.SkipToOrder(added_vehicle, 3);
				}
				numvehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on new route from " + (numvehicles % 2 == 1 ? nameTo : nameFrom) + " to " + (numvehicles % 2 == 1 ? nameFrom : nameTo) + "! (" + numvehicles + "/" + optimal_vehicle_count + " road vehicle" + (numvehicles != 1 ? "s" : "") + ", " + routedist + " manhattan tiles)");
				if (buyVehicleCount > 1) {
					this.m_last_vehicle_added *= -1;
					break;
				}
			} else {
				break;
			}
		}
		if (numvehicles < (m_max_vehicle_count_mode == 0 ? 1 : optimal_vehicle_count) && this.m_last_vehicle_added >= 0) {
			this.m_last_vehicle_added = 0;
		}
		return numvehicles - numvehicles_before;
	}

	function SendMoveVehicleToDepot(vehicle_id)
	{
		if (AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_road_group[0] && AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_road_group[1] && AIVehicle.GetState(vehicle_id) != AIVehicle.VS_CRASHED) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			if (!AIVehicle.IsStoppedInDepot(vehicle_id) && !AIVehicle.SendVehicleToDepot(vehicle_id)) {
				local depot_order_flags = AIOrder.OF_STOP_IN_DEPOT | AIOrder.OF_NON_STOP_INTERMEDIATE;
				if (!AIVehicle.HasSharedOrders(vehicle_id)) {
					if (!AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags)) {
						AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
						return 0;
					} else {
						AIOrder.SkipToOrder(vehicle_id, 0);
					}
				} else {
					local shared_list = AIVehicleList_SharedOrders(vehicle_id);
					local copy_orders_vid = AIVehicle.VEHICLE_INVALID;
					for (local v = shared_list.Begin(); !shared_list.IsEnd(); v = shared_list.Next()) {
						if (v != vehicle_id) {
							copy_orders_vid = v;
							break;
						}
					}
					if (AIVehicle.IsValidVehicle(copy_orders_vid)) {
						if (AIOrder.CopyOrders(vehicle_id, copy_orders_vid)) {
							if (!AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags)) {
								AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
								return 0;
							} else {
								AIOrder.SkipToOrder(vehicle_id, 0);
							}
						} else {
							AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
							return 0;
						}
					} else {
						AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
						return 0;
					}
				}
			}
			this.m_last_vehicle_removed = AIDate.GetCurrentDate();

			AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)) + " has been sent to its depot!");

			return 1;
		}

		return 0;
	}

	function SendNegativeProfitVehiclesToDepot()
	{
		if (this.m_last_vehicle_added <= 0 || AIDate.GetCurrentDate() - this.m_last_vehicle_added <= 30) return;
//		AILog.Info("SendNegativeProfitVehiclesToDepot . this.m_last_vehicle_added = " + this.m_last_vehicle_added + "; " + AIDate.GetCurrentDate() + " - " + this.m_last_vehicle_added + " = " + (AIDate.GetCurrentDate() - this.m_last_vehicle_added) + " < 45" + " - " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)));

//		if (AIDate.GetCurrentDate() - this.m_last_vehicle_removed <= 30) return;

		ValidateVehicleList();

		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (SendMoveVehicleToDepot(vehicle)) {
					if (!AIGroup.MoveVehicle(this.m_sent_to_depot_road_group[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_road_group[0]);
					} else {
						this.m_vehicle_list[vehicle] = 0;
					}
					return;
				}
			}
		}
	}

	function SendLowProfitVehiclesToDepot(maxAllRoutesProfit)
	{
		ValidateVehicleList();
		local vehicleList = AIList();
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730) {
				vehicleList.AddItem(vehicle, 0);
			}
		}
		if (vehicleList.IsEmpty()) return;

		local station1 = AIStation.GetStationID(this.m_station_from);
		local station2 = AIStation.GetStationID(this.m_station_to);
		local cargoWaiting1via2 = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, this.m_cargo_type);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, this.m_cargo_type);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

//		AILog.Info("cargoWaiting = " + (cargoWaiting1 + cargoWaiting2));
		if (cargoWaiting1 + cargoWaiting2 < 150) {
			for (local vehicle = vehicleList.Begin(); !vehicleList.IsEnd(); vehicle = vehicleList.Next()) {
				if (AIVehicle.GetProfitLastYear(vehicle) < (maxAllRoutesProfit / 6)) {
					if (SendMoveVehicleToDepot(vehicle)) {
						if (!AIGroup.MoveVehicle(this.m_sent_to_depot_road_group[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_road_group[0]);
						} else {
							this.m_vehicle_list[vehicle] = 0;
						}
					}
				}
			}
		}
	}

	function SellVehiclesInDepot()
	{
		local sent_to_depot_list = this.SentToDepotList(0);

		for (local vehicle = sent_to_depot_list.Begin(); !sent_to_depot_list.IsEnd(); vehicle = sent_to_depot_list.Next()) {
			if (this.m_vehicle_list.HasItem(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local vehicle_name = AIVehicle.GetName(vehicle);
				DeleteSellVehicle(vehicle);

				AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)) + " has been sold!");
			}
		}

		sent_to_depot_list = this.SentToDepotList(1);

		for (local vehicle = sent_to_depot_list.Begin(); !sent_to_depot_list.IsEnd(); vehicle = sent_to_depot_list.Next()) {
			if (this.m_vehicle_list.HasItem(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local skip_to_order = AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT);
				DeleteSellVehicle(vehicle);

				local renewed_vehicle = AddVehicle(true);
				if (renewed_vehicle != null) {
					AIOrder.SkipToOrder(renewed_vehicle, skip_to_order);
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(skip_to_order < 3 ? this.m_station_from : this.m_station_to)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(skip_to_order < 3 ? this.m_station_to : this.m_station_from)) + " has been renewed!");
				}
			}
		}
	}

	function AddRemoveVehicleToRoute(maxed_out_num_vehs)
	{
		if (!this.m_active_route) {
			return 0;
		}

		if (this.m_last_vehicle_added <= 0) {
			return AddVehiclesToNewRoute();
		}

		if (m_max_vehicle_count_mode != AIController.GetSetting("road_cap_mode")) {
			m_max_vehicle_count_mode = AIController.GetSetting("road_cap_mode");
//			AILog.Info("m_max_vehicle_count_mode = " + m_max_vehicle_count_mode);
		}

		ValidateVehicleList();
		local numvehicles = null;
		if (m_max_vehicle_count_mode == 2 && AIDate.GetCurrentDate() -  this.m_last_vehicle_added > 30) {
			numvehicles = this.m_vehicle_list.Count();
			local stoppedList = AIList()
			foreach (vehicle, _ in this.m_vehicle_list) {
				if (AIVehicle.GetCurrentSpeed(vehicle) == 0 && AIVehicle.GetState(vehicle) == AIVehicle.VS_RUNNING) {
					stoppedList.AddItem(vehicle, 0);
				}
			}

			local stoppedCount = stoppedList.Count();
			local max_num_stopped = MIN_VEHICLE_START_COUNT + AIGameSettings.GetValue("vehicle_breakdowns") * 2;
			if (stoppedCount >= max_num_stopped) {
				AILog.Info("Some vehicles on existing route from " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)) + " aren't moving. (" + stoppedCount + "/" + numvehicles + " road vehicles)");

				for (local vehicle = stoppedList.Begin(); !stoppedList.IsEnd(); vehicle = stoppedList.Next()) {
					if (stoppedCount >= max_num_stopped) {
						local old_lastVehicleRemoved = this.m_last_vehicle_removed;
						if (SendMoveVehicleToDepot(vehicle)) {
							if (!AIGroup.MoveVehicle(this.m_sent_to_depot_road_group[0], vehicle)) {
								AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_road_group[0]);
							} else {
								this.m_vehicle_list[vehicle] = 0;
							}
							this.m_last_vehicle_added = AIDate.GetCurrentDate();
							this.m_last_vehicle_removed = old_lastVehicleRemoved;
							stoppedCount--;
						}
					}
				}
				return 0;
			}
		}

		if (AIDate.GetCurrentDate() - this.m_last_vehicle_added < 90) {
			return 0;
		}

		local optimal_vehicle_count = OptimalVehicleCount();
		if (numvehicles == null) {
			numvehicles = this.m_vehicle_list.Count();
		}
		local numvehicles_before = numvehicles;

		if (m_max_vehicle_count_mode != 2 && numvehicles >= optimal_vehicle_count && maxed_out_num_vehs) {
			return 0;
		}

		local station1 = AIStation.GetStationID(this.m_station_from);
		local station2 = AIStation.GetStationID(this.m_station_to);
		local cargoWaiting1via2 = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, this.m_cargo_type);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, this.m_cargo_type);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

		local engine_capacity = ::caches.GetCapacity(this.m_engine, this.m_cargo_type);

		if (cargoWaiting1 > engine_capacity || cargoWaiting2 > engine_capacity) {
			local number_to_add = max(1, (cargoWaiting1 > cargoWaiting2 ? cargoWaiting1 : cargoWaiting2) / engine_capacity);
			local routedist = AIMap.DistanceManhattan(this.m_station_from, this.m_station_to);
			while (number_to_add) {
				number_to_add--;
				local added_vehicle = AddVehicle(true);
				if (added_vehicle != null) {
					numvehicles++;
					local skipped_order = false;
					if (cargoWaiting1 > cargoWaiting2) {
						cargoWaiting1 -= engine_capacity;
					} else {
						cargoWaiting2 -= engine_capacity;
						AIOrder.SkipToOrder(added_vehicle, 3);
						skipped_order = true;
					}
					AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on existing route from " + AIBaseStation.GetName(skipped_order ? station2 : station1) + " to " + AIBaseStation.GetName(skipped_order ? station1 : station2) + "! (" + numvehicles + (m_max_vehicle_count_mode != 2 ? "/" + optimal_vehicle_count : "") + " road vehicle" + (numvehicles != 1 ? "s" : "") + ", " + routedist + " manhattan tiles)");
					if (numvehicles >= m_max_vehicle_count_mode != 2 ? 1 : optimal_vehicle_count) {
						number_to_add = 0;
					}
				}
			}
		}
		return numvehicles - numvehicles_before;
	}

	function RenewVehicles()
	{
		ValidateVehicleList();
		local engine_price = AIEngine.GetPrice(this.m_engine);
		local count = 1 + AIGroup.GetNumVehicles(this.m_sent_to_depot_road_group[1], AIVehicle.VT_ROAD);

		foreach (vehicle, _ in this.m_vehicle_list) {
//			local vehicle_engine = AIVehicle.GetEngineType(vehicle);
//			if (AIGroup.GetEngineReplacement(this.m_group, vehicle_engine) != this.m_engine) {
//				AIGroup.SetAutoReplace(this.m_group, vehicle_engine, this.m_engine);
//			}
			if (AIVehicle.GetAgeLeft(vehicle) <= 365 || AIVehicle.GetEngineType(vehicle) != this.m_engine && Utils.HasMoney(2 * engine_price * count)) {
				if (SendMoveVehicleToDepot(vehicle)) {
					count++;
					if (!AIGroup.MoveVehicle(this.m_sent_to_depot_road_group[1], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_road_group[1]);
					} else {
						this.m_vehicle_list[vehicle] = 1;
					}
				}
			}
		}
	}

	function ExpandRoadStation()
	{
		local result = false;
		if (!this.m_active_route) return result;

		ValidateVehicleList();
//		if (m_max_vehicle_count_mode != 0 && this.m_vehicle_list.Count() < OptimalVehicleCount()) return result; // too slow
		if (this.m_vehicle_list.Count() < OptimalVehicleCount()) return result;

		local articulated = false;
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.IsArticulated(vehicle)) {
				articulated = true;
				break;
			}
		}

		local population = AITown.GetPopulation(this.m_city_from);

		if (population / 1000 > this.m_expanded_from_count + 1) {
			if (RoadBuildManager().BuildTownRoadStation(this.m_city_from, this.m_city_to, this.m_cargo_class, articulated, true, this.m_station_from) != null) {
				++this.m_expanded_from_count;
				result = true;
				AILog.Info("Expanded " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " road station.");
			}
		}

		population = AITown.GetPopulation(this.m_city_to);

		if (population / 1000 > this.m_expanded_to_count + 1) {
			if (RoadBuildManager().BuildTownRoadStation(this.m_city_to, this.m_city_from, this.m_cargo_class, articulated, true, this.m_station_to) != null) {
				++this.m_expanded_to_count;
				result = true;
				AILog.Info("Expanded " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)) + " road station.");
			}
		}

		return result;
	}

	function RemoveIfUnserviced()
	{
		ValidateVehicleList();
		if (this.m_vehicle_list.Count() == 0 && (((!AIEngine.IsValidEngine(this.m_engine) || !AIEngine.IsBuildable(this.m_engine)) && this.m_last_vehicle_added == 0) ||
				(AIDate.GetCurrentDate() - this.m_last_vehicle_added >= 90) && this.m_last_vehicle_added > 0)) {
			this.m_active_route = false;

			local stationFrom_name = AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from));
			local fromTiles = AITileList_StationType(AIStation.GetStationID(this.m_station_from), this.m_cargo_class == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
			for (local tile = fromTiles.Begin(); !fromTiles.IsEnd(); tile = fromTiles.Next()) {
				::scheduledRemovalsTable.Road.rawset(tile, 0);
			}

			local stationTo_name = AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to));
			local toTiles = AITileList_StationType(AIStation.GetStationID(this.m_station_to), this.m_cargo_class == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
			for (local tile = toTiles.Begin(); !toTiles.IsEnd(); tile = toTiles.Next()) {
				::scheduledRemovalsTable.Road.rawset(tile, 0);
			}

			::scheduledRemovalsTable.Road.rawset(this.m_depot_tile, 0);

			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.DeleteGroup(this.m_group);
			}
			AILog.Warning("Removing unserviced road route from " + stationFrom_name + " to " + stationTo_name);
			return true;
		}
		return false;
	}

	function GroupVehicles()
	{
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetGroupID(vehicle) != AIGroup.GROUP_DEFAULT && AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_road_group[0] && AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_road_group[1]) {
				if (!AIGroup.IsValidGroup(this.m_group)) {
					this.m_group = AIVehicle.GetGroupID(vehicle);
					break;
				}
			}
		}

		if (!AIGroup.IsValidGroup(this.m_group)) {
			this.m_group = AIGroup.CreateGroup(AIVehicle.VT_ROAD, AIGroup.GROUP_INVALID);
			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.SetName(this.m_group, (this.m_cargo_class == AICargo.CC_PASSENGERS ? "P" : "M") + AIMap.DistanceManhattan(this.m_station_from, this.m_station_to) + ": " + this.m_station_from + " - " + this.m_station_to);
				AILog.Info("Created " + AIGroup.GetName(this.m_group) + " for road route from " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)));
			}
		}

		return this.m_group;
	}

	function SaveRoute()
	{
		return [this.m_city_from, this.m_city_to, this.m_station_from, this.m_station_to, this.m_depot_tile, this.m_bridge_tiles, this.m_cargo_class, this.m_last_vehicle_added, this.m_last_vehicle_removed, this.m_active_route, this.m_expanded_from_count, this.m_expanded_to_count, this.m_sent_to_depot_road_group, this.m_group];
	}

	function LoadRoute(data)
	{
		local city_from = data[0];
		local city_to = data[1];
		local station_from = data[2];
		local station_to = data[3];
		local depot_tile = data[4];
		local bridge_tiles = data[5];
		local cargo_class = data[6];
		local sent_to_depot_road_group = data[12];

		local route = RoadRoute(city_from, city_to, station_from, station_to, depot_tile, bridge_tiles, cargo_class, sent_to_depot_road_group, true);

		route.m_last_vehicle_added = data[7];
		route.m_last_vehicle_removed = data[8];
		route.m_active_route = data[9];
		route.m_expanded_from_count = data[10];
		route.m_expanded_to_count = data[11];
		route.m_group = data[13];

		local vehicleList = AIVehicleList_Station(AIStation.GetStationID(route.m_station_from));
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_ROAD) {
				route.m_vehicle_list[v] = 2;
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sent_to_depot_road_group[0]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_ROAD) {
				if (route.m_vehicle_list.HasItem(v)) {
					route.m_vehicle_list[v] = 0;
				}
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sent_to_depot_road_group[1]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_ROAD) {
				if (route.m_vehicle_list.HasItem(v)) {
					route.m_vehicle_list[v] = 1;
				}
			}
		}

		return [route, bridge_tiles.len()];
	}
};
