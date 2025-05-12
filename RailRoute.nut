require("RailRouteManager.nut");

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
	m_station_id_from = null;
	m_station_id_to = null;
	m_station_name_from = null;
	m_station_name_to = null;
	m_rail_station_from = null;
	m_rail_station_to = null;
	m_route_dist = null;
	m_engine_wagon_pair = null; // array in the form [engine, wagon, num_wagons, train_max_speed, train_capacity]
	m_vehicle_list = null;
	m_cargo_type = null;

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
		this.m_sent_to_depot_rail_group = sent_to_depot_rail_group;
		this.m_rail_type = rail_type;
		this.m_station_from_dir = station_from_dir;
		this.m_station_to_dir = station_to_dir;

		this.m_last_vehicle_added = 0;
		this.m_last_vehicle_removed = AIDate.GetCurrentDate();
		this.m_active_route = true;
		this.m_group = AIGroup.GROUP_INVALID;

		this.m_station_id_from = AIStation.GetStationID(station_from);
		this.m_station_id_to = AIStation.GetStationID(station_to);
		this.m_station_name_from = AIBaseStation.GetName(this.m_station_id_from);
		this.m_station_name_to = AIBaseStation.GetName(this.m_station_id_to);
		this.m_rail_station_from = RailStation.CreateFromTile(station_from, station_from_dir);
		this.m_rail_station_to = RailStation.CreateFromTile(station_to, station_to_dir);
		this.m_route_dist = this.GetRouteDistance();
		this.m_vehicle_list = AIList();
		this.m_cargo_type = Utils.GetCargoType(cargo_class);

		/* This requires the values above to be initialized */
		this.m_engine_wagon_pair = this.GetTrainEngineWagonPair();

		if (!is_loaded) {
			this.AddVehiclesToNewRoute();
		}
	}

	function ValidateVehicleList()
	{
//		this.m_vehicle_list = AIVehicleList_Station(this.m_station_id_from);
//		foreach (v, _ in this.m_vehicle_list) {
//			if (AIVehicle.GetVehicleType(v) != AIVehicle.VT_RAIL) {
//				this.m_vehicle_list[v] = null;
//			}
//		}
		foreach (v, _ in this.m_vehicle_list) {
			if (!AIVehicle.IsValidVehicle(v)) {
				this.m_vehicle_list[v] = null;
				continue;
			}
			if (AIVehicle.GetVehicleType(v) != AIVehicle.VT_RAIL) {
				AILog.Error("t:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
			local num_orders = AIOrder.GetOrderCount(v);
			if (num_orders != 2) {
				AILog.Error("t:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
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
				AILog.Error("t:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
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

	function GetEngineWagonPairs()
	{
		local train_list = AIEngineList(AIVehicle.VT_RAIL);
		local engine_list = AIList();
		local wagon_list = AIList();
		foreach (train_id, _ in train_list) {
			if (!AIEngine.IsValidEngine(train_id)) {
				continue;
			}
			if (!AIEngine.IsBuildable(train_id)) {
				continue;
			}
			if (!AIEngine.CanPullCargo(train_id, this.m_cargo_type)) {
				continue;
			}
			if (!AIEngine.CanRunOnRail(train_id, this.m_rail_type)) {
				continue;
			}
			if (!AIEngine.HasPowerOnRail(train_id, this.m_rail_type)) {
				continue;
			}
			if (AIEngine.CanRefitCargo(train_id, this.m_cargo_type)) {
				if (AIEngine.IsWagon(train_id)) {
					wagon_list[train_id] = 0;
				} else {
					engine_list[train_id] = 0;
				}
			} else if (AIEngine.GetCapacity(train_id) == -1) {
				if (AIEngine.IsWagon(train_id)) {
//					wagon_list[train_id] = 0;
				} else {
					engine_list[train_id] = 0;
				}
			}
		}

		local engine_wagon_pairs = [];
		foreach (engine_id, _ in engine_list) {
			foreach (wagon_id, _ in wagon_list) {
				local pair = [engine_id, wagon_id];
				if (::caches.CanAttachToEngine(wagon_id, engine_id, this.m_cargo_type, this.m_rail_type, this.m_depot_tile_from)) {
					engine_wagon_pairs.append(pair);
				}
			}
		}

		return engine_wagon_pairs;
	}

	function GetTrainEngineWagonPair()
	{
		local engine_wagon_pairs = this.GetEngineWagonPairs();
		if (engine_wagon_pairs.len() == 0) {
			return this.m_engine_wagon_pair == null ? [-1, -1, -1, -1, -1] : this.m_engine_wagon_pair;
		}

		local best_income = null;
		local best_pair = null;
		foreach (pair in engine_wagon_pairs) {
			local engine_id = pair[0];
			local wagon_id = pair[1];
			local multiplier = Utils.GetEngineReliabilityMultiplier(engine_id);
			local engine_max_speed = AIEngine.GetMaxSpeed(engine_id) == 0 ? 65535 : AIEngine.GetMaxSpeed(engine_id);
			local wagon_max_speed = AIEngine.GetMaxSpeed(wagon_id) == 0 ? 65535 : AIEngine.GetMaxSpeed(wagon_id);
			local train_max_speed = min(engine_max_speed, wagon_max_speed);
			local rail_type_max_speed = AIRail.GetMaxSpeed(this.m_rail_type) == 0 ? 65535 : AIRail.GetMaxSpeed(this.m_rail_type);
			train_max_speed = min(rail_type_max_speed, train_max_speed);
			local days_in_transit = (this.m_route_dist * 256 * 16) / (2 * 74 * train_max_speed);
			days_in_transit += STATION_LOADING_INTERVAL;

			local engine_length = ::caches.GetLength(engine_id, this.m_cargo_type, this.m_depot_tile_from);
			local wagon_length = ::caches.GetLength(wagon_id, this.m_cargo_type, this.m_depot_tile_from);
			local max_train_length = min(this.m_rail_station_from.m_length, this.m_rail_station_to.m_length) * 16;
			local num_wagons = (max_train_length - engine_length) / wagon_length;
			local engine_capacity = max(0, ::caches.GetBuildWithRefitCapacity(this.m_depot_tile_from, engine_id, this.m_cargo_type));
			local wagon_capacity = max(0, ::caches.GetBuildWithRefitCapacity(this.m_depot_tile_from, wagon_id, this.m_cargo_type));
			local train_capacity = engine_capacity + wagon_capacity * num_wagons;
			local engine_running_cost = AIEngine.GetRunningCost(engine_id);
			local wagon_running_cost = AIEngine.GetRunningCost(wagon_id);
			local train_running_cost = engine_running_cost + wagon_running_cost * num_wagons;

			local income = ((train_capacity * AICargo.GetCargoIncome(this.m_cargo_type, this.m_route_dist, days_in_transit) - train_running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
//			AILog.Info("EngineWagonPair: [" + AIEngine.GetName(engine_id) + " -- " + num_wagons + " * " + AIEngine.GetName(wagon_id) + "; Capacity: " + train_capacity + "; Max Speed: " + train_max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + train_running_cost + "; Distance: " + this.m_route_dist + "; Income: " + income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_pair = [engine_id, wagon_id, num_wagons, train_max_speed, train_capacity];
			}
		}

		return best_pair == null ? [-1, -1, -1, -1, -1] : best_pair;
	}

	function UpdateEngineWagonPair()
	{
		if (!this.m_active_route) return;

		this.m_engine_wagon_pair = this.GetTrainEngineWagonPair();
	}

	function UpgradeBridges()
	{
		if (!this.m_active_route) return;

		AIRail.SetCurrentRailType(this.m_rail_type);
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
						if (TestBuildBridge().TryBuild(AIVehicle.VT_RAIL, new_bridge_type, north_tile, south_tile)) {
							AILog.Info("Bridge at tiles " + north_tile + " and " + south_tile + " upgraded from " + AIBridge.GetName(old_bridge_type, AIVehicle.VT_RAIL) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(old_bridge_speed) + ") to " + AIBridge.GetName(new_bridge_type, AIVehicle.VT_RAIL) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(new_bridge_speed) + ")");
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

	function AddVehicle(return_vehicle = false, skip_order = false)
	{
		this.ValidateVehicleList();
		if (this.m_vehicle_list.Count() >= this.OptimalVehicleCount()) {
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
		local depot_tile = skip_order ? this.m_depot_tile_to : this.m_depot_tile_from;
		local new_vehicle = AIVehicle.VEHICLE_INVALID;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			/* Check first if we have money to buy entire parts */
			local cost = AIAccounting();
			AITestMode() && AIVehicle.BuildVehicleWithRefit(depot_tile, this.m_engine_wagon_pair[0], this.m_cargo_type);
			local num_wagons = this.m_engine_wagon_pair[2];
			while (num_wagons > 0) {
				AITestMode() && AIVehicle.BuildVehicleWithRefit(depot_tile, this.m_engine_wagon_pair[1], this.m_cargo_type);
				num_wagons--;
			}
			if (Utils.HasMoney(cost.GetCosts())) {
				new_vehicle = TestBuildVehicleWithRefit().TryBuild(depot_tile, this.m_engine_wagon_pair[0], this.m_cargo_type);
				if (AIVehicle.IsValidVehicle(new_vehicle)) {
					local num_tries = this.m_engine_wagon_pair[2];
					local wagon_chain = AIVehicle.VEHICLE_INVALID;
					local num_wagons = 0;
					while (num_tries > 0) {
						local wagon = TestBuildVehicleWithRefit().TryBuild(depot_tile, this.m_engine_wagon_pair[1], this.m_cargo_type);
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
			local is_same_vehicle = AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id;
			new_vehicle = TestCloneVehicle().TryClone(depot_tile, clone_vehicle_id, is_same_vehicle);
		}

		if (AIVehicle.IsValidVehicle(new_vehicle)) {
			this.m_vehicle_list[new_vehicle] = 2;
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
		local vehicle_count = max(2, max_num_trains_by_interval);
//		AILog.Info("vehicle_count = " + vehicle_count);
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

		local buy_vehicle_count = optimal_vehicle_count * 2 / 3;

		if (buy_vehicle_count > optimal_vehicle_count - num_vehicles) {
			buy_vehicle_count = optimal_vehicle_count - num_vehicles;
		}

		for (local i = 0; i < buy_vehicle_count; ++i) {
			local old_last_vehicle_added = -this.m_last_vehicle_added;
			if (old_last_vehicle_added > 0 && AIDate.GetCurrentDate() - old_last_vehicle_added <= 3) {
				break;
			}
			this.m_last_vehicle_added = 0;
			local added_vehicle = this.AddVehicle(true, (num_vehicles % 2) == 1);
			if (added_vehicle != null) {
//				if (num_vehicles % 2 == 1) {
//					AIOrder.SkipToOrder(added_vehicle, 1);
//				}
				num_vehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engine_wagon_pair[0]) + " on new route from " + (num_vehicles % 2 == 1 ? this.m_station_name_to : this.m_station_name_from) + " to " + (num_vehicles % 2 == 1 ? this.m_station_name_from : this.m_station_name_to) + "! (" + num_vehicles + "/" + optimal_vehicle_count + " train" + (num_vehicles != 1 ? "s" : "") + ", " + this.m_route_dist + " manhattan tiles)");
				if (buy_vehicle_count > 1) {
					this.m_last_vehicle_added *= -1;
					break;
				}
			} else {
				break;
			}
		}
		if (num_vehicles < optimal_vehicle_count && this.m_last_vehicle_added >= 0) {
			this.m_last_vehicle_added = 0;
		}
		return num_vehicles - num_vehicles_before;
	}

	function SendMoveVehicleToDepot(vehicle_id)
	{
		if (AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_rail_group[0] && AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_rail_group[1] && AIVehicle.GetState(vehicle_id) != AIVehicle.VS_CRASHED && !AIVehicle.IsStoppedInDepot(vehicle_id) && (AIOrder.IsCurrentOrderPartOfOrderList(vehicle_id) || !AIOrder.IsGotoDepotOrder(vehicle_id, AIOrder.ORDER_CURRENT) || (AIOrder.GetOrderFlags(vehicle_id, AIOrder.ORDER_CURRENT) & AIOrder.OF_STOP_IN_DEPOT) == 0)) {
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
					if (!AIGroup.MoveVehicle(this.m_sent_to_depot_rail_group[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_rail_group[0]);
					} else {
						this.m_vehicle_list[vehicle] = 0;
					}
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
					if (this.SendMoveVehicleToDepot(vehicle)) {
						if (!AIGroup.MoveVehicle(this.m_sent_to_depot_rail_group[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_rail_group[0]);
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

		foreach (vehicle, _ in sent_to_depot_list) {
			if (this.m_vehicle_list.HasItem(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local vehicle_name = AIVehicle.GetName(vehicle);
				this.DeleteSellVehicle(vehicle);

				AILog.Info(vehicle_name + " on route from " + this.m_station_name_from + " to " + this.m_station_name_to + " has been sold!");
			}
		}

		sent_to_depot_list = this.SentToDepotList(1);

		foreach (vehicle, _ in sent_to_depot_list) {
			if (this.m_vehicle_list.HasItem(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local skip_order = AIVehicle.GetLocation(vehicle) == this.m_depot_tile_to;
				this.DeleteSellVehicle(vehicle);

				local renewed_vehicle = this.AddVehicle(true, skip_order);
				if (renewed_vehicle != null) {
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + (skip_order ? this.m_station_name_from : this.m_station_name_to) + " to " + (skip_order ? this.m_station_name_to : this.m_station_name_from) + " has been renewed!");
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
			return this.AddVehiclesToNewRoute();
		}

		this.ValidateVehicleList();
		local num_vehicles = null;
		if (AIDate.GetCurrentDate() -  this.m_last_vehicle_added > 30) {
			num_vehicles = this.m_vehicle_list.Count();
			local stopped_list = AIList()
			foreach (vehicle, _ in this.m_vehicle_list) {
				if (AIVehicle.GetCurrentSpeed(vehicle) == 0 && AIVehicle.GetState(vehicle) == AIVehicle.VS_RUNNING) {
					stopped_list[vehicle] = 0;
				}
			}

			local stopped_count = stopped_list.Count();
			local max_num_stopped = 4 + AIGameSettings.GetValue("vehicle_breakdowns") * 2;
			if (stopped_count >= max_num_stopped) {
				AILog.Info("Some vehicles on existing route from " + this.m_station_name_from + " to " + this.m_station_name_to + " aren't moving. (" + stopped_count + "/" + num_vehicles + " trains)");

				foreach (vehicle, _ in stopped_list) {
					if (stopped_count >= max_num_stopped) {
						local old_last_vehicle_removed = this.m_last_vehicle_removed;
						if (this.SendMoveVehicleToDepot(vehicle)) {
							if (!AIGroup.MoveVehicle(this.m_sent_to_depot_rail_group[0], vehicle)) {
								AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_rail_group[0]);
							} else {
								this.m_vehicle_list[vehicle] = 0;
							}
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

		if (num_vehicles >= optimal_vehicle_count && maxed_out_num_vehs) {
			return 0;
		}

		local cargo_waiting_from_via_to = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_from, this.m_station_id_to, this.m_cargo_type);
		local cargo_waiting_from_any = AIStation.GetCargoWaitingVia(this.m_station_id_from, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_from = cargo_waiting_from_via_to + cargo_waiting_from_any;
		local cargo_waiting_to_via_from = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_to, this.m_station_id_from, this.m_cargo_type);
		local cargo_waiting_to_any = AIStation.GetCargoWaitingVia(this.m_station_id_to, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_to = cargo_waiting_to_via_from + cargo_waiting_to_any;

		local train_capacity = this.m_engine_wagon_pair[4];

		if (cargo_waiting_from > train_capacity || cargo_waiting_to > train_capacity) {
			local number_to_add = max(1, (cargo_waiting_from > cargo_waiting_to ? cargo_waiting_from : cargo_waiting_to) / train_capacity);

			while (number_to_add) {
				number_to_add--;
				local skip_order = cargo_waiting_from <= cargo_waiting_to;
				local added_vehicle = this.AddVehicle(true, skip_order);
				if (added_vehicle != null) {
					num_vehicles++;
					if (!skip_order) {
						cargo_waiting_from -= train_capacity;
					} else {
						cargo_waiting_to -= train_capacity;
					}
					AILog.Info("Added " + AIEngine.GetName(this.m_engine_wagon_pair[0]) + " on existing route from " + (skip_order ? this.m_station_name_to : this.m_station_name_from) + " to " + (skip_order ? this.m_station_name_from : this.m_station_name_to) + "! (" + num_vehicles + "/" + optimal_vehicle_count + " train" + (num_vehicles != 1 ? "s" : "") + ", " + this.m_route_dist + " manhattan tiles)");
					if (num_vehicles >= optimal_vehicle_count) {
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
						this.m_vehicle_list[vehicle] = 1;
					}
				}
			}
		}
	}

	function GetRouteDistance()
	{
		local line = this.m_rail_station_from.GetPlatformLine(1);
		local exit_tile = this.m_rail_station_from.GetExitTile(line);
		local offset = this.m_rail_station_from.GetEntryTile(line) - exit_tile;
		local station_from_tile = exit_tile + offset * this.m_rail_station_from.m_length;

		line = this.m_rail_station_to.GetPlatformLine(1);
		exit_tile = this.m_rail_station_to.GetExitTile(line);
		offset = this.m_rail_station_to.GetEntryTile(line) - exit_tile;
		local station_to_tile = exit_tile + offset * this.m_rail_station_to.m_length;

		return AIMap.DistanceManhattan(station_from_tile, station_to_tile);
	}

	function ScheduleRemoveStation(rail_station)
	{
		local top_tile = rail_station.GetTopTile();
		local bot_tile = rail_station.GetBottomTile();
		local entry_tile_2 = rail_station.GetEntryTile(2);
		local exit_tile_2 = rail_station.GetExitTile(2);
		local exit_tile_1 = rail_station.GetExitTile(1);
		local entry_tile_1 = rail_station.GetEntryTile(1);
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, 2 * exit_tile_1 - entry_tile_1));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, 2 * exit_tile_2 - entry_tile_2));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
	}

	function ScheduleRemoveDepot(depot_tile)
	{
		local depot_front_tile = AIRail.GetRailDepotFrontTile(depot_tile);
		local depot_rail_a = abs(depot_tile - depot_front_tile) == 1 ? depot_front_tile - AIMap.GetMapSizeX() : depot_front_tile - 1;
		local depot_rail_b = 2 * depot_front_tile - depot_rail_a;
		local depot_rail_c = 2 * depot_front_tile - depot_tile;
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(depot_front_tile, this.m_rail_type, depot_tile, depot_rail_a));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(depot_front_tile, this.m_rail_type, depot_tile, depot_rail_b));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(depot_front_tile, this.m_rail_type, depot_tile, depot_rail_c));
		::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetStruct(depot_tile, RailStructType.DEPOT, this.m_rail_type));
	}

	function ScheduleRemoveTracks(front_tile, prev_tile)
	{
		local next_tile = AIMap.TILE_INVALID;
		if (AIRail.IsRailTile(front_tile)) {
			local offset = front_tile - prev_tile;
			local track = AIRail.GetRailTracks(front_tile);
			local bits = Utils.CountBits(track);
			if (bits >= 1 && bits <= 2) {
				switch (offset) {
					case 1: { // NE
						switch (track) {
							case AIRail.RAILTRACK_NE_SW: {
								next_tile = front_tile + 1;
								break;
							}
							case AIRail.RAILTRACK_NW_NE:
							case AIRail.RAILTRACK_NW_NE | AIRail.RAILTRACK_SW_SE: {
								next_tile = front_tile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NE_SE:
							case AIRail.RAILTRACK_NE_SE | AIRail.RAILTRACK_NW_SW: {
								next_tile = front_tile + AIMap.GetMapSizeX();
								break;
							}
						}
						break;
					}
					case -1: { // SW
						switch (track) {
							case AIRail.RAILTRACK_NE_SW: {
								next_tile = front_tile - 1;
								break;
							}
							case AIRail.RAILTRACK_NW_SW:
							case AIRail.RAILTRACK_NW_SW | AIRail.RAILTRACK_NE_SE: {
								next_tile = front_tile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_SW_SE:
							case AIRail.RAILTRACK_SW_SE | AIRail.RAILTRACK_NW_NE: {
								next_tile = front_tile + AIMap.GetMapSizeX();
								break;
							}
						}
						break;
					}
					case AIMap.GetMapSizeX(): { // NW
						switch (track) {
							case AIRail.RAILTRACK_NW_SE: {
								next_tile = front_tile + AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NW_NE:
							case AIRail.RAILTRACK_NW_NE | AIRail.RAILTRACK_SW_SE: {
								next_tile = front_tile - 1;
								break;
							}
							case AIRail.RAILTRACK_NW_SW:
							case AIRail.RAILTRACK_NW_SW | AIRail.RAILTRACK_NE_SE: {
								next_tile = front_tile + 1;
								break;
							}
						}
						break;
					}
					case -AIMap.GetMapSizeX(): { // SE
						switch (track) {
							case AIRail.RAILTRACK_NW_SE: {
								next_tile = front_tile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NE_SE:
							case AIRail.RAILTRACK_NE_SE | AIRail.RAILTRACK_NW_SW: {
								next_tile = front_tile - 1;
								break;
							}
							case AIRail.RAILTRACK_SW_SE:
							case AIRail.RAILTRACK_SW_SE | AIRail.RAILTRACK_NW_NE: {
								next_tile = front_tile + 1;
								break;
							}
						}
						break;
					}
				}
			}
			if (next_tile != AIMap.TILE_INVALID) {
				::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetRail(front_tile, this.m_rail_type, prev_tile, next_tile));
				this.ScheduleRemoveTracks(next_tile, front_tile);
			}
		} else if (AIBridge.IsBridgeTile(front_tile)) {
			local offset = front_tile - prev_tile;
			local other_tile = AIBridge.GetOtherBridgeEnd(front_tile);
			if (((other_tile - front_tile) / AIMap.DistanceManhattan(other_tile, front_tile)) == offset) {
				next_tile = other_tile + offset;
			}
			if (next_tile != AIMap.TILE_INVALID) {
				::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetStruct(front_tile, RailStructType.BRIDGE, this.m_rail_type, other_tile));
				this.ScheduleRemoveTracks(next_tile, other_tile);
			}
		} else if (AITunnel.IsTunnelTile(front_tile)) {
			local offset = front_tile - prev_tile;
			local other_tile = AITunnel.GetOtherTunnelEnd(front_tile);
			if (((other_tile - front_tile) / AIMap.DistanceManhattan(other_tile, front_tile)) == offset) {
				next_tile = other_tile + offset;
			}
			if (next_tile != AIMap.TILE_INVALID) {
				::scheduled_removals[AITile.TRANSPORT_RAIL].append(RailStruct.SetStruct(front_tile, RailStructType.TUNNEL, this.m_rail_type, other_tile));
				this.ScheduleRemoveTracks(next_tile, other_tile);
			}
		}
	}

	function RemoveIfUnserviced()
	{
		this.ValidateVehicleList();
		if (this.m_vehicle_list.IsEmpty() && (((!AIEngine.IsValidEngine(this.m_engine_wagon_pair[0]) || !AIEngine.IsBuildable(this.m_engine_wagon_pair[0]) || !AIEngine.IsValidEngine(this.m_engine_wagon_pair[1]) || !AIEngine.IsBuildable(this.m_engine_wagon_pair[1])) && this.m_last_vehicle_added == 0) ||
				(AIDate.GetCurrentDate() - this.m_last_vehicle_added >= 90) && this.m_last_vehicle_added > 0)) {
			this.m_active_route = false;

			this.ScheduleRemoveStation(this.m_rail_station_from);
			this.ScheduleRemoveDepot(this.m_depot_tile_from);

			this.ScheduleRemoveStation(this.m_rail_station_to);
			this.ScheduleRemoveDepot(this.m_depot_tile_to);

			local line = this.m_rail_station_from.GetPlatformLine(2);
			this.ScheduleRemoveTracks(this.m_rail_station_from.GetExitTile(line, 1), this.m_rail_station_from.GetExitTile(line));

			line = this.m_rail_station_to.GetPlatformLine(2);
			this.ScheduleRemoveTracks(this.m_rail_station_to.GetExitTile(line, 1), this.m_rail_station_to.GetExitTile(line));

			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.DeleteGroup(this.m_group);
			}
			AILog.Warning("Removing unserviced rail route from " + this.m_station_name_from + " to " + this.m_station_name_to);
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
				AILog.Info("Created " + AIGroup.GetName(this.m_group) + " for rail route from " + this.m_station_name_from + " to " + this.m_station_name_to);
			}
		}
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

		local vehicle_list = AIVehicleList_Station(route.m_station_id_from);
		foreach (v, _ in vehicle_list) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				route.m_vehicle_list[v] = 2;
			}
		}

		vehicle_list = AIVehicleList_Group(route.m_sent_to_depot_rail_group[0]);
		foreach (v, _ in vehicle_list) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				if (route.m_vehicle_list.HasItem(v)) {
					route.m_vehicle_list[v] = 0;
				}
			}
		}

		vehicle_list = AIVehicleList_Group(route.m_sent_to_depot_rail_group[1]);
		foreach (v, _ in vehicle_list) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				if (route.m_vehicle_list.HasItem(v)) {
					route.m_vehicle_list[v] = 1;
				}
			}
		}

		return [route, bridge_tiles.len()];
	}
};
