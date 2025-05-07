require("TrainRouteManager.nut");

class RailRoute
{
	static MAX_PLATFORM_LENGTH = 7;
	static MAX_NUM_PLATFORMS = 2;
	static STATION_LOADING_INTERVAL = 20;

	/* These are saved */
	m_city_from = null;
	m_city_to = null;
	m_station_from = null;
	m_station_to = null;
	m_depot_tile_from = null;
	m_depot_tile_to = null;
	m_bridge_tiles = null;
	m_cargo_class = null;
	m_last_vehicle_added = null;
	m_last_vehicle_removed = null;
	m_active_route = null;
	m_sent_to_depot_rail_group = null;
	m_group = null;
	m_rail_type = null;
	m_station_from_dir = null;
	m_station_to_dir = null;

	/* These are not saved */
	m_station_name_from = null;
	m_station_name_to = null;
	m_platform_length = null;
	m_route_dist = null;
	m_engine_wagon_pair = null; // array in the form [engine, wagon, num_wagons, train_max_speed, train_capacity]
	m_vehicle_list = null;

	constructor(city_from, city_to, station_from, station_to, depot_tile_from, depot_tile_to, bridge_tiles, cargo_class, sent_to_depot_rail_group, rail_type, station_from_dir, station_to_dir, is_loaded = false)
	{
		AIRail.SetCurrentRailType(rail_type);
		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_station_from = station_from;
		this.m_station_to = station_to;
		this.m_depot_tile_from = depot_tile_from;
		this.m_depot_tile_to = depot_tile_to;
		this.m_bridge_tiles = bridge_tiles;
		this.m_cargo_class = cargo_class;
		this.m_rail_type = rail_type;
		this.m_station_from_dir = station_from_dir;
		this.m_station_to_dir = station_to_dir;
		this.m_station_name_from = AIBaseStation.GetName(AIStation.GetStationID(station_from));
		this.m_station_name_to = AIBaseStation.GetName(AIStation.GetStationID(station_to));

		this.m_platform_length = this.GetPlatformLength();
		this.m_route_dist = this.GetRouteDistance();
		this.m_engine_wagon_pair = this.GetTrainEngineWagonPair(cargo_class);
		this.m_group = AIGroup.GROUP_INVALID;
		this.m_sent_to_depot_rail_group = sent_to_depot_rail_group;

		this.m_last_vehicle_added = 0;
		this.m_last_vehicle_removed = AIDate.GetCurrentDate();

		this.m_active_route = true;

		this.m_vehicle_list = {};

		if (!is_loaded) {
			this.AddVehiclesToNewRoute(cargo_class);
		}
	}

	function ValidateVehicleList()
	{
		local station_from = AIStation.GetStationID(this.m_station_from);
		local station_to = AIStation.GetStationID(this.m_station_to);

		local removelist = AIList();
		foreach (v, _ in this.m_vehicle_list) {
			if (AIVehicle.IsValidVehicle(v)) {
				if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
					local num_orders = AIOrder.GetOrderCount(v);
					if (num_orders == 2) {
						local order_from = false;
						local order_to = false;
						for (local o = 0; o < num_orders; o++) {
							if (AIOrder.IsValidVehicleOrder(v, o) && !AIOrder.IsConditionalOrder(v, o)) {
								local station_id = AIStation.GetStationID(AIOrder.GetOrderDestination(v, o));
								if (station_id == station_from) order_from = true;
								if (station_id == station_to) order_to = true;
							}
						}
						if (!order_from || !order_to) {
							removelist.AddItem(v, 0);
						}
					} else {
						removelist.AddItem(v, 0);
					}
				} else {
					removelist.AddItem(v, 0);
				}
			} else {
				removelist.AddItem(v, 0);
			}
		}

		for (local v = removelist.Begin(); !removelist.IsEnd(); v = removelist.Next()) {
			local exists = AIVehicle.IsValidVehicle(v);
			if (exists) {
				AILog.Error("t:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
//				AIController.Break(" ");
			}
			this.m_vehicle_list.rawdelete(v);
		}
	}

	function SentToDepotList(i)
	{
		local sent_to_depot_list = AIList();
		this.ValidateVehicleList();
		foreach (vehicle, status in this.m_vehicle_list) {
			if (status == i) sent_to_depot_list.AddItem(vehicle, i);
		}
		return sent_to_depot_list;
	}

	function GetEngineWagonPairs(cargo_class)
	{
		local cargo_type = Utils.GetCargoType(cargo_class);

		local tempList = AIEngineList(AIVehicle.VT_RAIL);
		local engineList = AIList();
		local wagonList = AIList();
		for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
			if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanPullCargo(engine, cargo_type) &&
					AIEngine.CanRunOnRail(engine, this.m_rail_type) && AIEngine.HasPowerOnRail(engine, this.m_rail_type)) {
				if (AIEngine.CanRefitCargo(engine, cargo_type)) {
					if (AIEngine.IsWagon(engine)) {
						wagonList.AddItem(engine, 0);
					} else {
						engineList.AddItem(engine, 0);
					}
				} else if (AIEngine.GetCapacity(engine) == -1) {
					if (AIEngine.IsWagon(engine)) {
//						wagonList.AddItem(engine, 0);
					} else {
						engineList.AddItem(engine, 0);
					}
				}
			}
		}

		local engineWagonPairs = [];
		for (local engine = engineList.Begin(); !engineList.IsEnd(); engine = engineList.Next()) {
			for (local wagon = wagonList.Begin(); !wagonList.IsEnd(); wagon = wagonList.Next()) {
				local pair = [engine, wagon];
				if (::caches.CanAttachToEngine(wagon, engine, cargo_type, this.m_rail_type, this.m_depot_tile_from)) {
					engineWagonPairs.append(pair);
				}
			}
		}

		return engineWagonPairs;
	}

	function GetTrainEngineWagonPair(cargo_class)
	{
		local engineWagonPairList = this.GetEngineWagonPairs(cargo_class);
		if (engineWagonPairList.len() == 0) return this.m_engine_wagon_pair == null ? [-1, -1, -1, -1, -1] : this.m_engine_wagon_pair;

		local cargo_type = Utils.GetCargoType(cargo_class);

		local best_income = null;
		local best_pair = null;
		foreach (pair in engineWagonPairList) {
			local engine = pair[0];
			local wagon = pair[1];
			local multiplier = Utils.GetEngineReliabilityMultiplier(engine);
			local engine_max_speed = AIEngine.GetMaxSpeed(engine) == 0 ? 65535 : AIEngine.GetMaxSpeed(engine);
			local wagon_max_speed = AIEngine.GetMaxSpeed(wagon) == 0 ? 65535 : AIEngine.GetMaxSpeed(wagon);
			local train_max_speed = min(engine_max_speed, wagon_max_speed);
			local rail_type_max_speed = AIRail.GetMaxSpeed(this.m_rail_type) == 0 ? 65535 : AIRail.GetMaxSpeed(this.m_rail_type);
			train_max_speed = min(rail_type_max_speed, train_max_speed);
			local days_in_transit = (this.m_route_dist * 256 * 16) / (2 * 74 * train_max_speed);
			days_in_transit += STATION_LOADING_INTERVAL;

			local engine_length = ::caches.GetLength(engine, cargo_type, this.m_depot_tile_from);
			local wagon_length = ::caches.GetLength(wagon, cargo_type, this.m_depot_tile_from);
			local max_train_length = this.m_platform_length * 16;
			local num_wagons = (max_train_length - engine_length) / wagon_length;
			local engine_capacity = max(0, ::caches.GetBuildWithRefitCapacity(this.m_depot_tile_from, engine, cargo_type));
			local wagon_capacity = max(0, ::caches.GetBuildWithRefitCapacity(this.m_depot_tile_from, wagon, cargo_type));
			local train_capacity = engine_capacity + wagon_capacity * num_wagons;
			local engine_running_cost = AIEngine.GetRunningCost(engine);
			local wagon_running_cost = AIEngine.GetRunningCost(wagon);
			local train_running_cost = engine_running_cost + wagon_running_cost * num_wagons;

			local income = ((train_capacity * AICargo.GetCargoIncome(cargo_type, this.m_route_dist, days_in_transit) - train_running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
//			AILog.Info("EngineWagonPair: [" + AIEngine.GetName(engine) + " -- " + num_wagons + " * " + AIEngine.GetName(wagon) + "; Capacity: " + train_capacity + "; Max Speed: " + train_max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + train_running_cost + "; Distance: " + this.m_route_dist + "; Income: " + income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_pair = [engine, wagon, num_wagons, train_max_speed, train_capacity];
			}
		}

		return best_pair == null ? [-1, -1, -1, -1, -1] : best_pair;
	}

	function UpdateEngineWagonPair()
	{
		if (!this.m_active_route) return;

		this.m_engine_wagon_pair = this.GetTrainEngineWagonPair(this.m_cargo_class);
	}

	function UpgradeBridges()
	{
		if (!this.m_active_route) return;

		AIRail.SetCurrentRailType(this.m_rail_type);
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
					if (TestBuildBridge().TryBuild(AIVehicle.VT_RAIL, new_bridge, north_tile, south_tile)) {
						AILog.Info("Bridge at tiles " + north_tile + " and " + south_tile + " upgraded from " + AIBridge.GetName(old_bridge, AIVehicle.VT_RAIL) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(AIBridge.GetMaxSpeed(old_bridge)) + ") to " + AIBridge.GetName(new_bridge, AIVehicle.VT_RAIL) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(AIBridge.GetMaxSpeed(new_bridge)) + ")");
					}
				}
			}
		}
	}

	function DeleteSellVehicle(vehicle)
	{
		this.m_vehicle_list.rawdelete(vehicle);
		AIVehicle.SellVehicle(vehicle);
		Utils.RepayLoan();
	}

	function AddVehicle(return_vehicle = false, skip_order = false)
	{
		this.ValidateVehicleList();
		if (this.m_vehicle_list.len() >= this.OptimalVehicleCount()) {
			return null;
		}

		/* Clone vehicle, share orders */
		local clone_vehicle_id = AIVehicle.VEHICLE_INVALID;
		local share_orders_vid = AIVehicle.VEHICLE_INVALID;
		foreach (vehicle_id, _ in this.m_vehicle_list) {
			if (this.m_engine_wagon_pair != null && AIEngine.IsValidEngine(this.m_engine_wagon_pair[0]) && AIEngine.IsBuildable(this.m_engine_wagon_pair[0]) &&
					AIEngine.IsValidEngine(this.m_engine_wagon_pair[1]) && AIEngine.IsBuildable(this.m_engine_wagon_pair[1])) {
				if (AIVehicle.GetEngineType(vehicle_id) == this.m_engine_wagon_pair[0] && AIVehicle.GetWagonEngineType(vehicle_id, 1) == this.m_engine_wagon_pair[1]) {
					clone_vehicle_id = vehicle_id;
				}
			}
			if (AIVehicle.GetGroupID(vehicle_id) == this.m_group && AIGroup.IsValidGroup(this.m_group)) {
				share_orders_vid = vehicle_id;
			}
		}
		local depot = skip_order ? this.m_depot_tile_to : this.m_depot_tile_from;
		local new_vehicle = AIVehicle.VEHICLE_INVALID;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			local cargo_type = Utils.GetCargoType(this.m_cargo_class);
			/* Check if we have money first to buy entire parts */
			local cost = AIAccounting();
			AITestMode() && AIVehicle.BuildVehicleWithRefit(depot, this.m_engine_wagon_pair[0], cargo_type);
			local num_wagons = this.m_engine_wagon_pair[2];
			while (num_wagons > 0) {
				AITestMode() && AIVehicle.BuildVehicleWithRefit(depot, this.m_engine_wagon_pair[1], cargo_type);
				num_wagons--;
			}
			if (Utils.HasMoney(cost.GetCosts())) {
				new_vehicle = TestBuildVehicleWithRefit().TryBuild(depot, this.m_engine_wagon_pair[0], cargo_type);
				if (AIVehicle.IsValidVehicle(new_vehicle)) {
					local num_tries = this.m_engine_wagon_pair[2];
					local wagon_chain = AIVehicle.VEHICLE_INVALID;
					local num_wagons = 0;
					while (num_tries > 0) {
						local wagon = TestBuildVehicleWithRefit().TryBuild(depot, this.m_engine_wagon_pair[1], cargo_type);
						if (AIVehicle.IsValidVehicle(wagon) || AIVehicle.IsValidVehicle(wagon_chain)) {
//							AILog.Info("wagon or wagon_chain is valid");
							if (!AIVehicle.IsValidVehicle(wagon_chain)) wagon_chain = wagon;
							num_wagons = AIVehicle.GetNumWagons(wagon_chain);
							num_tries--;
						} else {
							break;
						}
					}
					if (num_wagons < this.m_engine_wagon_pair[2]) {
						if (AIVehicle.IsValidVehicle(wagon_chain)) {
							if (!AIVehicle.SellWagonChain(wagon_chain, 0)) {
//								AILog.Info("Failed to sell wagon chain. Reason: missing wagons");
//							} else {
//								AILog.Info("Sold wagon chain. Reason: missing wagons");
							}
						}
						if (!AIVehicle.SellVehicle(new_vehicle)) {
//							AILog.Info("Failed to sell train. Reason: missing wagons");
						} else {
							new_vehicle = AIVehicle.VEHICLE_INVALID;
//							AILog.Info("Sold train. Reason: missing wagons");
						}
					} else {
//						AILog.Info("new_vehicle = " + AIVehicle.IsValidVehicle(new_vehicle) + "; wagon_chain = " + AIVehicle.IsValidVehicle(wagon_chain));
						if (!AIVehicle.MoveWagonChain(wagon_chain, 0, new_vehicle, 0)) {
//							AILog.Info("Failed to move wagon chain");
							if (!AIVehicle.SellWagonChain(wagon_chain, 0)) {
//								AILog.Info("Failed to sell wagon chain. Reason: failed to move wagons");
//							} else {
//								AILog.Info("Sold wagon chain. Reason: failed to move wagons");
							}
							if (!AIVehicle.SellVehicle(new_vehicle)) {
//								AILog.Info("Failed to sell train. Reason: failed to move wagons");
							} else {
								new_vehicle = AIVehicle.VEHICLE_INVALID;
//								AILog.Info("Sold train. Reason: failed to move wagons");
							}
//						} else {
//							AILog.Info("Wagon chain moved successfully");
//							AILog.Info("new_vehicle = " + AIVehicle.IsValidVehicle(new_vehicle) + "; wagon_chain = " + AIVehicle.IsValidVehicle(wagon_chain));
//							AILog.Info("number of wagons in new_vehicle = " + AIVehicle.GetNumWagons(new_vehicle));
						}
					}
				}
			}
		} else {
			new_vehicle = TestCloneVehicle().TryClone(depot, clone_vehicle_id, (AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id) ? true : false);
		}

		if (AIVehicle.IsValidVehicle(new_vehicle)) {
			this.m_vehicle_list.rawset(new_vehicle, 2);
			local vehicle_ready_to_start = false;
			if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					if (AIOrder.AppendOrder(new_vehicle, this.m_station_from, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_NONE) &&
							AIOrder.AppendOrder(new_vehicle, this.m_station_to, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_NONE)) {
						vehicle_ready_to_start = true;
					} else {
						this.DeleteSellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						vehicle_ready_to_start = true;
					} else {
						AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						this.DeleteSellVehicle(new_vehicle);
						return null;
					}
				}
			} else {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					vehicle_ready_to_start = true;
				} else {
					if (clone_vehicle_id != share_orders_vid) {
						if (!AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
							AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
							this.DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					vehicle_ready_to_start = true;
				}
			}
			if (vehicle_ready_to_start) {
				if (skip_order) AIOrder.SkipToOrder(new_vehicle, 1);
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
//		AILog.Info("this.m_route_dist = " + this.m_route_dist);
		local train_max_speed = this.m_engine_wagon_pair[3];
//		AILog.Info("train_max_speed = " + train_max_speed);
		/* (train_max_speed * 2 * 74 * (STATION_LOADING_INTERVAL / 2)) / (256 * 16) */
		local count_interval = train_max_speed * STATION_LOADING_INTERVAL * 37 / 2048;
//		AILog.Info("count_interval = " + count_interval);
//		local days_in_transit = (this.m_route_dist * 256 * 16) / (2 * 74 * train_max_speed) + STATION_LOADING_INTERVAL;
//		AILog.Info("days_in_transit = " + days_in_transit);
		local max_num_trains_by_interval = (count_interval > 0 ? (2 * this.m_route_dist / (train_max_speed * STATION_LOADING_INTERVAL * 37 / 2048)) : 0);
//		AILog.Info("max_num_trains_by_interval = " + max_num_trains_by_interval);
		local vehicleCount = max(2, max_num_trains_by_interval);
//		AILog.Info("vehicleCount = " + vehicleCount);
		return vehicleCount;
	}

	function AddVehiclesToNewRoute(cargo_class)
	{
		this.m_group = this.GroupVehicles();
		local optimal_vehicle_count = this.OptimalVehicleCount();

		this.ValidateVehicleList();
		local numvehicles = this.m_vehicle_list.len();
		local numvehicles_before = numvehicles;
		if (numvehicles >= optimal_vehicle_count) {
			if (this.m_last_vehicle_added < 0) this.m_last_vehicle_added *= -1;
			return 0;
		}

		local buyVehicleCount = optimal_vehicle_count * 2 / 3;

		if (buyVehicleCount > optimal_vehicle_count - numvehicles) {
			buyVehicleCount = optimal_vehicle_count - numvehicles;
		}

		for (local i = 0; i < buyVehicleCount; ++i) {
			local old_lastVehicleAdded = -this.m_last_vehicle_added;
			if (old_lastVehicleAdded > 0 && AIDate.GetCurrentDate() - old_lastVehicleAdded <= 3) {
				break;
			}
			this.m_last_vehicle_added = 0;
			local added_vehicle = this.AddVehicle(true, (numvehicles % 2) == 1);
			if (added_vehicle != null) {
				local nameFrom = AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from));
				local nameTo = AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to));
//				if (numvehicles % 2 == 1) {
//					AIOrder.SkipToOrder(added_vehicle, 1);
//				}
				numvehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engine_wagon_pair[0]) + " on new route from " + (numvehicles % 2 == 1 ? nameTo : nameFrom) + " to " + (numvehicles % 2 == 1 ? nameFrom : nameTo) + "! (" + numvehicles + "/" + optimal_vehicle_count + " train" + (numvehicles != 1 ? "s" : "") + ", " + this.m_route_dist + " manhattan tiles)");
				if (buyVehicleCount > 1) {
					this.m_last_vehicle_added *= -1;
					break;
				}
			} else {
				break;
			}
		}
		if (numvehicles < optimal_vehicle_count && this.m_last_vehicle_added >= 0) {
			this.m_last_vehicle_added = 0;
		}
		return numvehicles - numvehicles_before;
	}

	function SendMoveVehicleToDepot(vehicle_id)
	{
		if (AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_rail_group[0] && AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_rail_group[1] && AIVehicle.GetState(vehicle_id) != AIVehicle.VS_CRASHED) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			if (!AIVehicle.IsStoppedInDepot(vehicle_id) && !AIVehicle.SendVehicleToDepot(vehicle_id)) {
				AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
				return 0;
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
//		AILog.Info("this.SendNegativeProfitVehiclesToDepot . this.m_last_vehicle_added = " + this.m_last_vehicle_added + "; " + AIDate.GetCurrentDate() + " - " + this.m_last_vehicle_added + " = " + (AIDate.GetCurrentDate() - this.m_last_vehicle_added) + " < 45" + " - " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)));

//		if (AIDate.GetCurrentDate() - this.m_last_vehicle_removed <= 30) return;

		this.ValidateVehicleList();

		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (this.SendMoveVehicleToDepot(vehicle)) {
					if (!AIGroup.MoveVehicle(this.m_sent_to_depot_rail_group[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_rail_group[0]);
					} else {
						this.m_vehicle_list.rawset(vehicle, 0);
					}
					return;
				}
			}
		}
	}

	function SendLowProfitVehiclesToDepot(max_all_routes_profit)
	{
		this.ValidateVehicleList();
		local vehicleList = AIList();
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730) {
				vehicleList.AddItem(vehicle, 0);
			}
		}
		if (vehicleList.IsEmpty()) return;

		local cargo_type = Utils.GetCargoType(this.m_cargo_class);
		local station1 = AIStation.GetStationID(this.m_station_from);
		local station2 = AIStation.GetStationID(this.m_station_to);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargo_type);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargo_type);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

//		AILog.Info("cargo_waiting = " + (cargoWaiting1 + cargoWaiting2));
		if (cargoWaiting1 + cargoWaiting2 < 150) {
			for (local vehicle = vehicleList.Begin(); !vehicleList.IsEnd(); vehicle = vehicleList.Next()) {
				if (AIVehicle.GetProfitLastYear(vehicle) < (max_all_routes_profit / 6)) {
					if (this.SendMoveVehicleToDepot(vehicle)) {
						if (!AIGroup.MoveVehicle(this.m_sent_to_depot_rail_group[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_rail_group[0]);
						} else {
							this.m_vehicle_list.rawset(vehicle, 0);
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
			if (this.m_vehicle_list.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local vehicle_name = AIVehicle.GetName(vehicle);
				this.DeleteSellVehicle(vehicle);

				AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)) + " has been sold!");
			}
		}

		sent_to_depot_list = this.SentToDepotList(1);

		for (local vehicle = sent_to_depot_list.Begin(); !sent_to_depot_list.IsEnd(); vehicle = sent_to_depot_list.Next()) {
			if (this.m_vehicle_list.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local skip_order = AIVehicle.GetLocation(vehicle) == this.m_depot_tile_to;
				this.DeleteSellVehicle(vehicle);

				local renewed_vehicle = this.AddVehicle(true, skip_order);
				if (renewed_vehicle != null) {
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(skip_order ? this.m_station_from : this.m_station_to)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(skip_order ? this.m_station_to : this.m_station_from)) + " has been renewed!");
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
			return this.AddVehiclesToNewRoute(this.m_cargo_class);
		}

		this.ValidateVehicleList();
		local numvehicles = null;
		if (AIDate.GetCurrentDate() -  this.m_last_vehicle_added > 30) {
			numvehicles = this.m_vehicle_list.len();
			local stoppedList = AIList()
			foreach (vehicle, _ in this.m_vehicle_list) {
				if (AIVehicle.GetCurrentSpeed(vehicle) == 0 && AIVehicle.GetState(vehicle) == AIVehicle.VS_RUNNING) {
					stoppedList.AddItem(vehicle, 0);
				}
			}

			local stoppedCount = stoppedList.Count();
			local max_num_stopped = 4 + AIGameSettings.GetValue("vehicle_breakdowns") * 2;
			if (stoppedCount >= max_num_stopped) {
				AILog.Info("Some vehicles on existing route from " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)) + " aren't moving. (" + stoppedCount + "/" + numvehicles + " trains)");

				for (local vehicle = stoppedList.Begin(); !stoppedList.IsEnd(); vehicle = stoppedList.Next()) {
					if (stoppedCount >= max_num_stopped) {
						local old_lastVehicleRemoved = this.m_last_vehicle_removed;
						if (this.SendMoveVehicleToDepot(vehicle)) {
							if (!AIGroup.MoveVehicle(this.m_sent_to_depot_rail_group[0], vehicle)) {
								AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_rail_group[0]);
							} else {
								this.m_vehicle_list.rawset(vehicle, 0);
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

		local optimal_vehicle_count = this.OptimalVehicleCount();
		if (numvehicles == null) {
			numvehicles = this.m_vehicle_list.len();
		}
		local numvehicles_before = numvehicles;

		if (numvehicles >= optimal_vehicle_count && maxed_out_num_vehs) {
			return 0;
		}

		local cargo_type = Utils.GetCargoType(this.m_cargo_class);
		local station1 = AIStation.GetStationID(this.m_station_from);
		local station2 = AIStation.GetStationID(this.m_station_to);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargo_type);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargo_type);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

		local train_capacity = this.m_engine_wagon_pair[4];

		if (cargoWaiting1 > train_capacity || cargoWaiting2 > train_capacity) {
			local number_to_add = max(1, (cargoWaiting1 > cargoWaiting2 ? cargoWaiting1 : cargoWaiting2) / train_capacity);

			while (number_to_add) {
				number_to_add--;
				local skip_order = cargoWaiting1 <= cargoWaiting2;
				local added_vehicle = this.AddVehicle(true, skip_order);
				if (added_vehicle != null) {
					numvehicles++;
					if (!skip_order) {
						cargoWaiting1 -= train_capacity;
					} else {
						cargoWaiting2 -= train_capacity;
					}
					AILog.Info("Added " + AIEngine.GetName(this.m_engine_wagon_pair[0]) + " on existing route from " + AIBaseStation.GetName(skip_order ? station2 : station1) + " to " + AIBaseStation.GetName(skip_order ? station1 : station2) + "! (" + numvehicles + "/" + optimal_vehicle_count + " train" + (numvehicles != 1 ? "s" : "") + ", " + this.m_route_dist + " manhattan tiles)");
					if (numvehicles >= optimal_vehicle_count) {
						number_to_add = 0;
					}
				}
			}
		}
		return numvehicles - numvehicles_before;
	}

	function RenewVehicles()
	{
		this.ValidateVehicleList();
		local engine_price = AIEngine.GetPrice(this.m_engine_wagon_pair[0]);
		local wagon_price = AIEngine.GetPrice(this.m_engine_wagon_pair[1]) * this.m_engine_wagon_pair[2];
		local train_price = engine_price + wagon_price;
		local count = 1 + AIGroup.GetNumVehicles(this.m_sent_to_depot_rail_group[1], AIVehicle.VT_RAIL);

		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAgeLeft(vehicle) <= 365 || AIVehicle.GetEngineType(vehicle) != this.m_engine_wagon_pair[0] && Utils.HasMoney(2 * train_price * count)) {
				if (this.SendMoveVehicleToDepot(vehicle)) {
					count++;
					if (!AIGroup.MoveVehicle(this.m_sent_to_depot_rail_group[1], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_rail_group[1]);
					} else {
						this.m_vehicle_list.rawset(vehicle, 1);
					}
				}
			}
		}
	}

	function GetPlatformLength()
	{
		local station = RailStation.CreateFromTile(this.m_station_from, this.m_station_from_dir);
		return station.m_length;
	}

	function GetRouteDistance()
	{
		local station_from = RailStation.CreateFromTile(this.m_station_from, this.m_station_from_dir);
		local stationFromPlatform1 = station_from.GetPlatformLine(1);
		local entryFrom = station_from.GetEntryTile(stationFromPlatform1);
		local exitFrom = station_from.GetExitTile(stationFromPlatform1);
		local offsetFrom = entryFrom - exitFrom;
		local stationFromTile = exitFrom + offsetFrom * station_from.m_length;

		local station_to = RailStation.CreateFromTile(this.m_station_to, this.m_station_to_dir);
		local stationToPlatform1 = station_to.GetPlatformLine(1);
		local entryTo = station_to.GetEntryTile(stationToPlatform1);
		local exitTo = station_to.GetExitTile(stationToPlatform1);
		local offsetTo = entryTo - exitTo;
		local stationToTile = exitTo + offsetTo * station_to.m_length;

		return AIMap.DistanceManhattan(stationFromTile, stationToTile);
	}

	function ScheduleRemoveStation(stationTile, stationDir)
	{
		local station = RailStation.CreateFromTile(stationTile, stationDir);
		local top_tile = station.GetTopTile();
		local bot_tile = station.GetBottomTile();
		local entry_tile_2 = station.GetEntryTile(2);
		local exit_tile_2 = station.GetExitTile(2);
		local exit_tile_1 = station.GetExitTile(1);
		local entry_tile_1 = station.GetEntryTile(1);
		local rail_type = AIRail.GetRailType(top_tile);
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetStruct(top_tile, RailStructType.STATION, rail_type, bot_tile));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(exit_tile_2, rail_type, entry_tile_2, 2 * exit_tile_1 - entry_tile_1));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(exit_tile_1, rail_type, entry_tile_1, 2 * exit_tile_2 - entry_tile_2));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(exit_tile_2, rail_type, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(exit_tile_1, rail_type, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
	}

	function ScheduleRemoveDepot(depot)
	{
		local depotFront = AIRail.GetRailDepotFrontTile(depot);
		local depotRaila = abs(depot - depotFront) == 1 ? depotFront - AIMap.GetMapSizeX() : depotFront - 1;
		local depotRailb = 2 * depotFront - depotRaila;
		local depotRailc = 2 * depotFront - depot;
		local rail_type = AIRail.GetRailType(depot);
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(depotFront, rail_type, depot, depotRaila));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(depotFront, rail_type, depot, depotRailb));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(depotFront, rail_type, depot, depotRailc));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetStruct(depot, RailStructType.DEPOT, rail_type));
	}

	function ScheduleRemoveTracks(frontTile, prevTile)
	{
		local nextTile = AIMap.TILE_INVALID;
		if (AIRail.IsRailTile(frontTile)) {
			local dir = frontTile - prevTile;
			local track = AIRail.GetRailTracks(frontTile);
			local rail_type = AIRail.GetRailType(frontTile);
			local bits = Utils.CountBits(track);
			if (bits >= 1 && bits <= 2) {
				switch (dir) {
					case 1: { // NE
						switch (track) {
							case AIRail.RAILTRACK_NE_SW: {
								nextTile = frontTile + 1;
								break;
							}
							case AIRail.RAILTRACK_NW_NE:
							case AIRail.RAILTRACK_NW_NE | AIRail.RAILTRACK_SW_SE: {
								nextTile = frontTile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NE_SE:
							case AIRail.RAILTRACK_NE_SE | AIRail.RAILTRACK_NW_SW: {
								nextTile = frontTile + AIMap.GetMapSizeX();
								break;
							}
						}
						break;
					}
					case -1: { // SW
						switch (track) {
							case AIRail.RAILTRACK_NE_SW: {
								nextTile = frontTile - 1;
								break;
							}
							case AIRail.RAILTRACK_NW_SW:
							case AIRail.RAILTRACK_NW_SW | AIRail.RAILTRACK_NE_SE: {
								nextTile = frontTile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_SW_SE:
							case AIRail.RAILTRACK_SW_SE | AIRail.RAILTRACK_NW_NE: {
								nextTile = frontTile + AIMap.GetMapSizeX();
								break;
							}
						}
						break;
					}
					case AIMap.GetMapSizeX(): { // NW
						switch (track) {
							case AIRail.RAILTRACK_NW_SE: {
								nextTile = frontTile + AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NW_NE:
							case AIRail.RAILTRACK_NW_NE | AIRail.RAILTRACK_SW_SE: {
								nextTile = frontTile - 1;
								break;
							}
							case AIRail.RAILTRACK_NW_SW:
							case AIRail.RAILTRACK_NW_SW | AIRail.RAILTRACK_NE_SE: {
								nextTile = frontTile + 1;
								break;
							}
						}
						break;
					}
					case -AIMap.GetMapSizeX(): { // SE
						switch (track) {
							case AIRail.RAILTRACK_NW_SE: {
								nextTile = frontTile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NE_SE:
							case AIRail.RAILTRACK_NE_SE | AIRail.RAILTRACK_NW_SW: {
								nextTile = frontTile - 1;
								break;
							}
							case AIRail.RAILTRACK_SW_SE:
							case AIRail.RAILTRACK_SW_SE | AIRail.RAILTRACK_NW_NE: {
								nextTile = frontTile + 1;
								break;
							}
						}
						break;
					}
				}
			}
			if (nextTile != AIMap.TILE_INVALID) {
				::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(frontTile, rail_type, prevTile, nextTile));
				this.ScheduleRemoveTracks(nextTile, frontTile);
			}
		} else if (AIBridge.IsBridgeTile(frontTile)) {
			local dir = frontTile - prevTile;
			local otherTile = AIBridge.GetOtherBridgeEnd(frontTile);
			local rail_type = AIRail.GetRailType(frontTile);
			if (((otherTile - frontTile) / AIMap.DistanceManhattan(otherTile, frontTile)) == dir) {
				nextTile = otherTile + dir;
			}
			if (nextTile != AIMap.TILE_INVALID) {
				::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetStruct(frontTile, RailStructType.BRIDGE, rail_type, otherTile));
				this.ScheduleRemoveTracks(nextTile, otherTile);
			}
		} else if (AITunnel.IsTunnelTile(frontTile)) {
			local dir = frontTile - prevTile;
			local otherTile = AITunnel.GetOtherTunnelEnd(frontTile);
			local rail_type = AIRail.GetRailType(frontTile);
			if (((otherTile - frontTile) / AIMap.DistanceManhattan(otherTile, frontTile)) == dir) {
				nextTile = otherTile + dir;
			}
			if (nextTile != AIMap.TILE_INVALID) {
				::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetStruct(frontTile, RailStructType.TUNNEL, rail_type, otherTile));
				this.ScheduleRemoveTracks(nextTile, otherTile);
			}
		}
	}

	function RemoveIfUnserviced()
	{
		this.ValidateVehicleList();
		if (this.m_vehicle_list.len() == 0 && (((!AIEngine.IsValidEngine(this.m_engine_wagon_pair[0]) || !AIEngine.IsBuildable(this.m_engine_wagon_pair[0]) || !AIEngine.IsValidEngine(this.m_engine_wagon_pair[1]) || !AIEngine.IsBuildable(this.m_engine_wagon_pair[1])) && this.m_last_vehicle_added == 0) ||
				(AIDate.GetCurrentDate() - this.m_last_vehicle_added >= 90) && this.m_last_vehicle_added > 0)) {
			this.m_active_route = false;

			local stationFrom_name = AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from));
			this.ScheduleRemoveStation(this.m_station_from, this.m_station_from_dir);
			this.ScheduleRemoveDepot(this.m_depot_tile_from);

			local stationTo_name = AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to));
			this.ScheduleRemoveStation(this.m_station_to, this.m_station_to_dir);
			this.ScheduleRemoveDepot(this.m_depot_tile_to);

			local station = RailStation.CreateFromTile(this.m_station_from, this.m_station_from_dir);
			local line = station.GetPlatformLine(2);
			this.ScheduleRemoveTracks(station.GetExitTile(line, 1), station.GetExitTile(line));

			station = RailStation.CreateFromTile(this.m_station_to, this.m_station_to_dir);
			line = station.GetPlatformLine(2);
			this.ScheduleRemoveTracks(station.GetExitTile(line, 1), station.GetExitTile(line));

			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.DeleteGroup(this.m_group);
			}
			AILog.Warning("Removing unserviced rail route from " + stationFrom_name + " to " + stationTo_name);
			return true;
		}
		return false;
	}

	function GroupVehicles()
	{
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetGroupID(vehicle) != AIGroup.GROUP_DEFAULT && AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_rail_group[0] && AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_rail_group[1]) {
				if (!AIGroup.IsValidGroup(this.m_group)) {
					this.m_group = AIVehicle.GetGroupID(vehicle);
					break;
				}
			}
		}

		if (!AIGroup.IsValidGroup(this.m_group)) {
			this.m_group = AIGroup.CreateGroup(AIVehicle.VT_RAIL, AIGroup.GROUP_INVALID);
			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.SetName(this.m_group, (this.m_cargo_class == AICargo.CC_PASSENGERS ? "P" : "M") + this.m_route_dist + ": " + this.m_station_from + " - " + this.m_station_to);
				AILog.Info("Created " + AIGroup.GetName(this.m_group) + " for rail route from " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_station_to)));
			}
		}

		return this.m_group;
	}

	function SaveRoute()
	{
		return [this.m_city_from, this.m_city_to, this.m_station_from, this.m_station_to, this.m_depot_tile_from, this.m_depot_tile_to, this.m_bridge_tiles, this.m_cargo_class, this.m_last_vehicle_added, this.m_last_vehicle_removed, this.m_active_route, this.m_sent_to_depot_rail_group, this.m_group, this.m_rail_type, this.m_station_from_dir, this.m_station_to_dir];
	}

	function LoadRoute(data)
	{
		local city_from = data[0];
		local city_to = data[1];
		local station_from = data[2];
		local station_to = data[3];
		local depot_tile_from = data[4];
		local depot_tile_to = data[5];

		local bridge_tiles = data[6];

		local cargo_class = data[7];
		local rail_type = data[13];

		local sent_to_depot_rail_group = data[11];

		local station_from_dir = data[14];
		local station_to_dir = data[15];

		local route = RailRoute(city_from, city_to, station_from, station_to, depot_tile_from, depot_tile_to, bridge_tiles, cargo_class, sent_to_depot_rail_group, rail_type, station_from_dir, station_to_dir, true);

		route.m_last_vehicle_added = data[8];
		route.m_last_vehicle_removed = data[9];
		route.m_active_route = data[10];

		route.m_group = data[12];

		local vehicleList = AIVehicleList_Station(AIStation.GetStationID(route.m_station_from));
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				route.m_vehicle_list.rawset(v, 2);
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sent_to_depot_rail_group[0]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				if (route.m_vehicle_list.rawin(v)) {
					route.m_vehicle_list.rawset(v, 0);
				}
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sent_to_depot_rail_group[1]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				if (route.m_vehicle_list.rawin(v)) {
					route.m_vehicle_list.rawset(v, 1);
				}
			}
		}

		return [route, bridge_tiles.len()];
	}
};
