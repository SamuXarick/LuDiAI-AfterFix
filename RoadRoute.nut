require("RoadRouteManager.nut");

class RoadRoute
{
	static START_VEHICLE_COUNT = {
	    [AICargo.CC_PASSENGERS] = 10,
		[AICargo.CC_MAIL] = 5,
	};
	static MIN_VEHICLE_START_COUNT = 5;

	/* These are saved */
	m_city_from = null;
	m_city_to = null;
	m_station_from = null;
	m_station_to = null;
	m_depot_tile = null;
	m_bridge_tiles = null;
	m_cargo_class = null;
	m_last_vehicle_added = null;
	m_last_vehicle_removed = null;
	m_active_route = null;
	m_expanded_from_count = null;
	m_expanded_to_count = null;
	m_group = null;

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
	m_route_dist = null;

	constructor(city_from, city_to, station_from, station_to, depot_tile, bridge_tiles, cargo_class, is_loaded = false)
	{
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_station_from = station_from;
		this.m_station_to = station_to;
		this.m_depot_tile = depot_tile;
		this.m_bridge_tiles = bridge_tiles;
		this.m_cargo_class = cargo_class;

		this.m_last_vehicle_added = 0;
		this.m_last_vehicle_removed = AIDate.GetCurrentDate();
		this.m_active_route = true;
		this.m_expanded_from_count = 0;
		this.m_expanded_to_count = 0;
		this.m_group = AIGroup.GROUP_INVALID;
		this.m_max_vehicle_count_mode = AIController.GetSetting("road_cap_mode");

		this.m_vehicle_list = AIList();
		this.m_vehicle_list.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
		this.m_station_id_from = AIStation.GetStationID(station_from);
		this.m_station_id_to = AIStation.GetStationID(station_to);
		this.m_station_name_from = AIBaseStation.GetName(this.m_station_id_from);
		this.m_station_name_to = AIBaseStation.GetName(this.m_station_id_to);
		this.m_cargo_type = Utils.GetCargoType(cargo_class);
		this.m_vehicle_type = AIRoad.GetRoadVehicleTypeForCargo(this.m_cargo_type);
		this.m_station_type = this.m_vehicle_type == AIRoad.ROADVEHTYPE_BUS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;
		this.m_route_dist = AIMap.DistanceManhattan(this.m_station_from, this.m_station_to);

		/* This requires the values above to be initialized */
		this.m_engine = this.GetTruckEngine();

		if (!is_loaded) {
			this.AddVehiclesToNewRoute();
		}
	}

	function ValidateVehicleList()
	{
		this.m_vehicle_list = AIVehicleList_Station(this.m_station_id_from, AIVehicle.VT_ROAD);
	}

	function GetEngineList()
	{
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
			if (!articulated_viable && AIEngine.IsArticulated(engine_id)) {
				engine_list[engine_id] = null;
				continue;
			}
		}

		return engine_list;
	}

	function GetTruckEngine()
	{
		local engine_list = this.GetEngineList();
		if (engine_list.IsEmpty()) {
			return this.m_engine == null ? -1 : this.m_engine;
		}

		local best_income = null;
		local best_engine = null;
		foreach (engine_id, _ in engine_list) {
			local multiplier = Utils.GetEngineReliabilityMultiplier(engine_id);
			local max_speed = AIEngine.GetMaxSpeed(engine_id);
			local days_in_transit = (this.m_route_dist * 192 * 16) / (2 * 3 * 74 * max_speed / 4);
			local running_cost = AIEngine.GetRunningCost(engine_id);
			local capacity = ::caches.GetBuildWithRefitCapacity(this.m_depot_tile, engine_id, this.m_cargo_type);
			local income = ((capacity * AICargo.GetCargoIncome(this.m_cargo_type, this.m_route_dist, days_in_transit) - running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
//			AILog.Info("Engine: " + AIEngine.GetName(engine_id) + "; Capacity: " + capacity + "; Max Speed: " + max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + running_cost + "; Distance: " + this.m_route_dist + "; Income: " + income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_engine = engine_id;
			}
		}

		return best_engine == null ? -1 : best_engine;
	}

	function UpgradeEngine()
	{
		if (!this.m_active_route) return;

		this.m_engine = this.GetTruckEngine();
	}

	function UpgradeBridges()
	{
		if (!this.m_active_route) return;

		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
		foreach (tile in this.m_bridge_tiles) {
			local north_tile = tile[0];
			local south_tile = tile[1];

			if (AIBridge.IsBridgeTile(north_tile) && (AIBridge.GetOtherBridgeEnd(north_tile) == south_tile)) {
				local bridge_type_list = AIBridgeList_Length(AIMap.DistanceManhattan(north_tile, south_tile) + 1);
				foreach (bridge_type, _ in bridge_type_list) {
					bridge_type_list[bridge_type] = AIBridge.GetMaxSpeed(bridge_type);
				}

				if (!bridge_type_list.IsEmpty()) {
					local old_bridge_type = AIBridge.GetBridgeType(north_tile);
					local old_bridge_speed = AIBridge.GetMaxSpeed(old_bridge_type);
					local new_bridge_type = bridge_type_list.Begin();
					local new_bridge_speed = AIBridge.GetMaxSpeed(new_bridge_type);
					if (new_bridge_speed > old_bridge_speed) {
						if (TestBuildBridge().TryBuild(AIVehicle.VT_ROAD, new_bridge_type, north_tile, south_tile)) {
							AILog.Info("Bridge at tiles " + north_tile + " and " + south_tile + " upgraded from " + AIBridge.GetName(old_bridge_type, AIVehicle.VT_ROAD) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(old_bridge_speed) + ") to " + AIBridge.GetName(new_bridge_type, AIVehicle.VT_ROAD) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(new_bridge_speed) + ")");
						}
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
		this.ValidateVehicleList();
		if (this.m_max_vehicle_count_mode != 2 && this.m_vehicle_list.Count() >= this.OptimalVehicleCount()) {
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
			new_vehicle = TestBuildVehicleWithRefit().TryBuild(this.m_depot_tile, this.m_engine, this.m_cargo_type);
		} else {
			local is_same_vehicle = AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id;
			new_vehicle = TestCloneVehicle().TryClone(this.m_depot_tile, clone_vehicle_id, is_same_vehicle);
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
						this.DeleteSellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						local new_vehicle_order_0_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
						if (new_vehicle_order_0_flags != depot_order_flags) {
							AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_0_flags + " != " + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
							this.DeleteSellVehicle(new_vehicle);
							return null;
						} else {
							vehicle_ready_to_start = true;
						}
					} else {
						AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						this.DeleteSellVehicle(new_vehicle);
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
							this.DeleteSellVehicle(new_vehicle);
							return null;
						}
					} else {
						vehicle_ready_to_start = true;
					}
				} else {
					if (clone_vehicle_id != share_orders_vid) {
						if (!AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
							AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
							this.DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					local new_vehicle_order_0_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					if (new_vehicle_order_0_flags != depot_order_flags) {
						AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_0_flags + " != " + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
						this.DeleteSellVehicle(new_vehicle);
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
		if (this.m_max_vehicle_count_mode == 0) return 25;

//		AILog.Info("this.m_route_dist = " + this.m_route_dist);
		local count_interval = Utils.GetEngineTileDist(this.m_engine, MIN_VEHICLE_START_COUNT);
//		AILog.Info("count_interval = " + count_interval + "; MaxSpeed = " + AIEngine.GetMaxSpeed(this.m_engine));
		local vehicle_count = /*2 * */(count_interval > 0 ? (this.m_route_dist / count_interval) : 0);
//		AILog.Info("vehicle_count = " + vehicle_count);

		local articulated_engine = AIEngine.IsArticulated(this.m_engine);
		local from_count = 0;
		local from_tiles = AITileList_StationType(this.m_station_id_from, this.m_station_type);
		foreach (tile, _ in from_tiles) {
			if (AIRoad.IsDriveThroughRoadStationTile(this.m_station_from)) {
				from_count += articulated_engine ? 2 : 4;
			} else {
				from_count += articulated_engine ? 0 : 2;
			}
		}

		local to_count = 0;
		local to_tiles = AITileList_StationType(this.m_station_id_to, this.m_cargo_type);
		foreach (tile, _ in to_tiles) {
			if (AIRoad.IsDriveThroughRoadStationTile(this.m_station_to)) {
				to_count += articulated_engine ? 2 : 4;
			} else {
				to_count += articulated_engine ? 0 : 2;
			}
		}

//		AILog.Info("from_count = " + from_count);
//		AILog.Info("to_count = " + to_count);
		vehicle_count += 2 * (from_count < to_count ? from_count : to_count);

		return vehicle_count;
	}

	function AddVehiclesToNewRoute()
	{
		this.GroupVehicles();
		local optimal_vehicle_count = this.OptimalVehicleCount();

		this.ValidateVehicleList();
		local num_vehicles = this.m_vehicle_list.Count();
		local num_vehicles_before = num_vehicles;
		if (num_vehicles >= optimal_vehicle_count) {
			if (this.m_last_vehicle_added < 0) this.m_last_vehicle_added *= -1;
			return 0;
		}

		local buy_vehicle_count = START_VEHICLE_COUNT[this.m_cargo_class];
		buy_vehicle_count += this.m_max_vehicle_count_mode == 0 ? this.m_route_dist / 20 : optimal_vehicle_count / (this.m_cargo_class == AICargo.CC_PASSENGERS ? 2 : 4);

		if (buy_vehicle_count > optimal_vehicle_count - num_vehicles) {
			buy_vehicle_count = optimal_vehicle_count - num_vehicles;
		}

		for (local i = 0; i < buy_vehicle_count; ++i) {
			local old_last_vehicle_added = -this.m_last_vehicle_added;
			if (old_last_vehicle_added > 0 && AIDate.GetCurrentDate() - old_last_vehicle_added <= 3) {
				break;
			}
			this.m_last_vehicle_added = 0;
			local added_vehicle = this.AddVehicle(true);
			if (added_vehicle != null) {
				if (num_vehicles % 2 == 1) {
					AIOrder.SkipToOrder(added_vehicle, 3);
				}
				num_vehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on new route from " + (num_vehicles % 2 == 1 ? this.m_station_name_to : this.m_station_name_from) + " to " + (num_vehicles % 2 == 1 ? this.m_station_name_from : this.m_station_name_to) + "! (" + num_vehicles + "/" + optimal_vehicle_count + " road vehicle" + (num_vehicles != 1 ? "s" : "") + ", " + this.m_route_dist + " manhattan tiles)");
				if (buy_vehicle_count > 1) {
					this.m_last_vehicle_added *= -1;
					break;
				}
			} else {
				break;
			}
		}
		if (num_vehicles < (this.m_max_vehicle_count_mode == 0 ? 1 : optimal_vehicle_count) && this.m_last_vehicle_added >= 0) {
			this.m_last_vehicle_added = 0;
		}
		return num_vehicles - num_vehicles_before;
	}

	function SendMoveVehicleToDepot(vehicle_id)
	{
		if (AIVehicle.GetState(vehicle_id) != AIVehicle.VS_CRASHED && !AIVehicle.IsStoppedInDepot(vehicle_id) && (AIOrder.IsCurrentOrderPartOfOrderList(vehicle_id) || !AIOrder.IsGotoDepotOrder(vehicle_id, AIOrder.ORDER_CURRENT) || (AIOrder.GetOrderFlags(vehicle_id, AIOrder.ORDER_CURRENT) & AIOrder.OF_STOP_IN_DEPOT) == 0)) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			if (!AIVehicle.SendVehicleToDepot(vehicle_id)) {
				AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
				return false;
			}
			this.m_last_vehicle_removed = AIDate.GetCurrentDate();

			AILog.Info(vehicle_name + " on route from " + this.m_station_name_from + " to " + this.m_station_name_to + " has been sent to its depot!");

			return true;
		}

		return false;
//		if (AIVehicle.GetState(vehicle_id) != AIVehicle.VS_CRASHED) {
//			local vehicle_name = AIVehicle.GetName(vehicle_id);
//			if (!AIVehicle.IsStoppedInDepot(vehicle_id) && !AIVehicle.SendVehicleToDepot(vehicle_id)) {
//				local depot_order_flags = AIOrder.OF_STOP_IN_DEPOT | AIOrder.OF_NON_STOP_INTERMEDIATE;
//				if (!AIVehicle.HasSharedOrders(vehicle_id)) {
//					if (!AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags)) {
//						AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
//						return false;
//					} else {
//						AIOrder.SkipToOrder(vehicle_id, 0);
//					}
//				} else {
//					local shared_list = AIVehicleList_SharedOrders(vehicle_id);
//					local copy_orders_vid = AIVehicle.VEHICLE_INVALID;
//					foreach (v, _ in shared_list) {
//						if (v != vehicle_id) {
//							copy_orders_vid = v;
//							break;
//						}
//					}
//					if (AIVehicle.IsValidVehicle(copy_orders_vid)) {
//						if (AIOrder.CopyOrders(vehicle_id, copy_orders_vid)) {
//							if (!AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags)) {
//								AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
//								return false;
//							} else {
//								AIOrder.SkipToOrder(vehicle_id, 0);
//							}
//						} else {
//							AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
//							return false;
//						}
//					} else {
//						AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
//						return false;
//					}
//				}
//			}
//			this.m_last_vehicle_removed = AIDate.GetCurrentDate();
//
//			AILog.Info(vehicle_name + " on route from " + this.m_station_name_from + " to " + this.m_station_name_to + " has been sent to its depot!");
//
//			return true;
//		}
//
//		return false;
	}

	function SendNegativeProfitVehiclesToDepot()
	{
		if (this.m_last_vehicle_added <= 0 || AIDate.GetCurrentDate() - this.m_last_vehicle_added <= 30) return;
//		AILog.Info("this.SendNegativeProfitVehiclesToDepot . this.m_last_vehicle_added = " + this.m_last_vehicle_added + "; " + AIDate.GetCurrentDate() + " - " + this.m_last_vehicle_added + " = " + (AIDate.GetCurrentDate() - this.m_last_vehicle_added) + " < 45" + " - " + this.m_station_name_from + " to " + this.m_station_name_to);

//		if (AIDate.GetCurrentDate() - this.m_last_vehicle_removed <= 30) return;

		this.ValidateVehicleList();

		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (this.SendMoveVehicleToDepot(vehicle)) {
					return;
				}
			}
		}
	}

	function SendLowProfitVehiclesToDepot(max_all_routes_profit)
	{
		this.ValidateVehicleList();
		local vehicle_list = AIList();
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730) {
				vehicle_list[vehicle] = 0;
			}
		}
		if (vehicle_list.IsEmpty()) return;

		local cargo_waiting_from_via_to = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_from, this.m_station_id_to, this.m_cargo_type);
		local cargo_waiting_from_any = AIStation.GetCargoWaitingVia(this.m_station_id_from, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_from = cargo_waiting_from_via_to + cargo_waiting_from_any;
		local cargo_waiting_to_via_from = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_to, this.m_station_id_from, this.m_cargo_type);
		local cargo_waiting_to_any = AIStation.GetCargoWaitingVia(this.m_station_id_to, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_to = cargo_waiting_to_via_from + cargo_waiting_to_any;

//		AILog.Info("cargo_waiting = " + (cargo_waiting_from + cargo_waiting_to));
		if (cargo_waiting_from + cargo_waiting_to < 150) {
			foreach (vehicle, _ in vehicle_list) {
				if (AIVehicle.GetProfitLastYear(vehicle) < (max_all_routes_profit / 6)) {
					this.SendMoveVehicleToDepot(vehicle);
				}
			}
		}
	}

	function SellVehiclesInDepot()
	{
		this.ValidateVehicleList();
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.IsStoppedInDepot(vehicle)) {
				local vehicle_name = AIVehicle.GetName(vehicle);
				this.DeleteSellVehicle(vehicle);

				AILog.Info(vehicle_name + " on route from " + this.m_station_name_from + " to " + this.m_station_name_to + " has been sold!");
			}
		}
	}

	function AddRemoveVehicleToRoute(maxed_out_num_vehs)
	{
		if (!this.m_active_route) {
			return 0;
		}

		if (this.m_last_vehicle_added <= 0) {
			return this.AddVehiclesToNewRoute();
		}

		if (this.m_max_vehicle_count_mode != AIController.GetSetting("road_cap_mode")) {
			this.m_max_vehicle_count_mode = AIController.GetSetting("road_cap_mode");
//			AILog.Info("this.m_max_vehicle_count_mode = " + this.m_max_vehicle_count_mode);
		}

		this.ValidateVehicleList();
		local num_vehicles = null;
		if (this.m_max_vehicle_count_mode == 2 && AIDate.GetCurrentDate() -  this.m_last_vehicle_added > 30) {
			num_vehicles = this.m_vehicle_list.Count();
			local stopped_list = AIList();
			foreach (vehicle, _ in this.m_vehicle_list) {
				if (AIVehicle.GetCurrentSpeed(vehicle) == 0 && AIVehicle.GetState(vehicle) == AIVehicle.VS_RUNNING) {
					stopped_list[vehicle] = 0;
				}
			}

			local stopped_count = stopped_list.Count();
			local max_num_stopped = MIN_VEHICLE_START_COUNT + AIGameSettings.GetValue("vehicle_breakdowns") * 2;
			if (stopped_count >= max_num_stopped) {
				AILog.Info("Some vehicles on existing route from " + this.m_station_name_from + " to " + this.m_station_name_to + " aren't moving. (" + stopped_count + "/" + num_vehicles + " road vehicles)");

				foreach (vehicle, _ in stopped_list) {
					if (stopped_count >= max_num_stopped) {
						local old_last_vehicle_removed = this.m_last_vehicle_removed;
						if (this.SendMoveVehicleToDepot(vehicle)) {
							this.m_last_vehicle_added = AIDate.GetCurrentDate();
							this.m_last_vehicle_removed = old_last_vehicle_removed;
							stopped_count--;
						}
					}
				}
				return 0;
			}
		}

		if (AIDate.GetCurrentDate() - this.m_last_vehicle_added < 90) {
			return 0;
		}

		local optimal_vehicle_count = this.OptimalVehicleCount();
		if (num_vehicles == null) {
			num_vehicles = this.m_vehicle_list.Count();
		}
		local num_vehicles_before = num_vehicles;

		if (this.m_max_vehicle_count_mode != 2 && num_vehicles >= optimal_vehicle_count && maxed_out_num_vehs) {
			return 0;
		}

		local cargo_waiting_from_via_to = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_from, this.m_station_id_to, this.m_cargo_type);
		local cargo_waiting_from_any = AIStation.GetCargoWaitingVia(this.m_station_id_from, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_from = cargo_waiting_from_via_to + cargo_waiting_from_any;
		local cargo_waiting_to_via_from = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_to, this.m_station_id_from, this.m_cargo_type);
		local cargo_waiting_to_any = AIStation.GetCargoWaitingVia(this.m_station_id_to, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_to = cargo_waiting_to_via_from + cargo_waiting_to_any;

		local engine_capacity = ::caches.GetCapacity(this.m_engine, this.m_cargo_type);

		if (cargo_waiting_from > engine_capacity || cargo_waiting_to > engine_capacity) {
			local number_to_add = max(1, (cargo_waiting_from > cargo_waiting_to ? cargo_waiting_from : cargo_waiting_to) / engine_capacity);

			while (number_to_add) {
				number_to_add--;
				local added_vehicle = this.AddVehicle(true);
				if (added_vehicle != null) {
					num_vehicles++;
					local skipped_order = false;
					if (cargo_waiting_from > cargo_waiting_to) {
						cargo_waiting_from -= engine_capacity;
					} else {
						cargo_waiting_to -= engine_capacity;
						skipped_order = AIOrder.SkipToOrder(added_vehicle, 3);
					}
					AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on existing route from " + (skipped_order ? this.m_station_name_to : this.m_station_name_from) + " to " + (skipped_order ? this.m_station_name_from : this.m_station_name_to) + "! (" + num_vehicles + (this.m_max_vehicle_count_mode != 2 ? "/" + optimal_vehicle_count : "") + " road vehicle" + (num_vehicles != 1 ? "s" : "") + ", " + this.m_route_dist + " manhattan tiles)");
					if (num_vehicles >= this.m_max_vehicle_count_mode != 2 ? 1 : optimal_vehicle_count) {
						number_to_add = 0;
					}
				}
			}
		}
		return num_vehicles - num_vehicles_before;
	}

	function RenewVehicles()
	{
		this.ValidateVehicleList();
		foreach (vehicle, _ in this.m_vehicle_list) {
			local vehicle_engine = AIVehicle.GetEngineType(vehicle);
			if (AIGroup.GetEngineReplacement(this.m_group, vehicle_engine) != this.m_engine) {
				AIGroup.SetAutoReplace(this.m_group, vehicle_engine, this.m_engine);
			}
		}
	}

	function ExpandRoadStation()
	{
		local result = false;
		if (!this.m_active_route) return result;

		this.ValidateVehicleList();
//		if (this.m_max_vehicle_count_mode != 0 && this.m_vehicle_list.Count() < this.OptimalVehicleCount()) return result; // too slow
		if (this.m_vehicle_list.Count() < this.OptimalVehicleCount()) return result;

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
				AILog.Info("Expanded " + this.m_station_name_from + " road station.");
			}
		}

		population = AITown.GetPopulation(this.m_city_to);

		if (population / 1000 > this.m_expanded_to_count + 1) {
			if (RoadBuildManager().BuildTownRoadStation(this.m_city_to, this.m_city_from, this.m_cargo_class, articulated, true, this.m_station_to) != null) {
				++this.m_expanded_to_count;
				result = true;
				AILog.Info("Expanded " + this.m_station_name_to + " road station.");
			}
		}

		return result;
	}

	function RemoveIfUnserviced()
	{
		this.ValidateVehicleList();
		if (this.m_vehicle_list.IsEmpty() && (((!AIEngine.IsValidEngine(this.m_engine) || !AIEngine.IsBuildable(this.m_engine)) && this.m_last_vehicle_added == 0) ||
				(AIDate.GetCurrentDate() - this.m_last_vehicle_added >= 90) && this.m_last_vehicle_added > 0)) {
			this.m_active_route = false;

			local from_tiles = AITileList_StationType(this.m_station_id_from, this.m_station_type);
			foreach (tile, _ in from_tiles) {
				::scheduled_removals[AITile.TRANSPORT_ROAD].rawset(tile, 0);
			}

			local to_tiles = AITileList_StationType(this.m_station_id_to, this.m_station_type);
			foreach (tile, _ in to_tiles) {
				::scheduled_removals[AITile.TRANSPORT_ROAD].rawset(tile, 0);
			}

			::scheduled_removals[AITile.TRANSPORT_ROAD].rawset(this.m_depot_tile, 0);

			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.DeleteGroup(this.m_group);
			}
			AILog.Warning("Removing unserviced road route from " + this.m_station_name_from + " to " + this.m_station_name_to);
			return true;
		}
		return false;
	}

	function GroupVehicles()
	{
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetGroupID(vehicle) != AIGroup.GROUP_DEFAULT) {
				if (!AIGroup.IsValidGroup(this.m_group)) {
					this.m_group = AIVehicle.GetGroupID(vehicle);
					break;
				}
			}
		}

		if (!AIGroup.IsValidGroup(this.m_group)) {
			this.m_group = AIGroup.CreateGroup(AIVehicle.VT_ROAD, AIGroup.GROUP_INVALID);
			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.SetName(this.m_group, (this.m_cargo_class == AICargo.CC_PASSENGERS ? "P" : "M") + this.m_route_dist + ": " + this.m_station_from + " - " + this.m_station_to);
				AILog.Info("Created " + AIGroup.GetName(this.m_group) + " for road route from " + this.m_station_name_from + " to " + this.m_station_name_to);
			}
		}
	}

	function SaveRoute()
	{
		return [this.m_city_from, this.m_city_to, this.m_station_from, this.m_station_to, this.m_depot_tile, this.m_bridge_tiles, this.m_cargo_class, this.m_last_vehicle_added, this.m_last_vehicle_removed, this.m_active_route, this.m_expanded_from_count, this.m_expanded_to_count, this.m_group];
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

		local route = RoadRoute(city_from, city_to, station_from, station_to, depot_tile, bridge_tiles, cargo_class, true);

		route.m_last_vehicle_added = data[7];
		route.m_last_vehicle_removed = data[8];
		route.m_active_route = data[9];
		route.m_expanded_from_count = data[10];
		route.m_expanded_to_count = data[11];
		route.m_group = data[12];

		return [route, bridge_tiles.len()];
	}
};
