require("TrainRouteManager.nut");

class RailRoute extends RailRouteManager
{
	MAX_PLATFORM_LENGTH = 7;
	MAX_NUM_PLATFORMS = 2;
	STATION_LOADING_INTERVAL = 15;

	m_city_from = null;
	m_city_to = null;
	m_stationFrom = null;
	m_stationTo = null;
	m_depotFrom = null;
	m_depotTo = null;
	m_bridgeTiles = null;
	m_cargo_class = null;
	m_rail_type = null;
	m_stationFromDir = null;
	m_stationToDir = null;

	m_platformLength = null;
	m_routeDistance = null;
	m_engineWagonPair = null; // array in the form [engine, wagon, num_wagons, train_max_speed, train_capacity]
	m_group = null;

	m_last_vehicle_added = null;
	m_last_vehicle_removed = null;

	m_sentToDepotRailGroup = null;

	m_active_route = null;

	m_vehicle_list = null;

	constructor(cityFrom, cityTo, stationFrom, stationTo, depotFrom, depotTo, bridgeTiles, cargoClass, sentToDepotRailGroup, rail_type, stationFromDir, stationToDir, isLoaded = 0)
	{
		AIRail.SetCurrentRailType(rail_type);
		m_city_from = cityFrom;
		m_city_to = cityTo;
		m_stationFrom = stationFrom;
		m_stationTo = stationTo;
		m_depotFrom = depotFrom;
		m_depotTo = depotTo;
		m_bridgeTiles = bridgeTiles;
		m_cargo_class = cargoClass;
		m_rail_type = rail_type;
		m_stationFromDir = stationFromDir;
		m_stationToDir = stationToDir;

		m_platformLength = GetPlatformLength();
		m_routeDistance = GetRouteDistance();
		m_engineWagonPair = GetTrainEngineWagonPair(cargoClass);
		m_group = AIGroup.GROUP_INVALID;
		m_sentToDepotRailGroup = sentToDepotRailGroup;

		m_last_vehicle_added = 0;
		m_last_vehicle_removed = AIDate.GetCurrentDate();

		m_active_route = true;

		m_vehicle_list = {};

		if (!isLoaded) {
			AddVehiclesToNewRoute(cargoClass);
		}
	}

	function ValidateVehicleList()
	{
		local stationFrom = AIStation.GetStationID(m_stationFrom);
		local stationTo = AIStation.GetStationID(m_stationTo);

		local removelist = AIList();
		foreach (v, _ in m_vehicle_list) {
			if (AIVehicle.IsValidVehicle(v)) {
				if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
					local num_orders = AIOrder.GetOrderCount(v);
					if (num_orders == 2) {
						local order_from = false;
						local order_to = false;
						for (local o = 0; o < num_orders; o++) {
							if (AIOrder.IsValidVehicleOrder(v, o) && !AIOrder.IsConditionalOrder(v, o)) {
								local station_id = AIStation.GetStationID(AIOrder.GetOrderDestination(v, o));
								if (station_id == stationFrom) order_from = true;
								if (station_id == stationTo) order_to = true;
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
			m_vehicle_list.rawdelete(v);
		}
	}

	function SentToDepotList(i)
	{
		local sent_to_depot_list = AIList();
		ValidateVehicleList();
		foreach (vehicle, status in m_vehicle_list) {
			if (status == i) sent_to_depot_list.AddItem(vehicle, i);
		}
		return sent_to_depot_list;
	}

	function GetEngineWagonPairs(cargoClass)
	{
		local cargo_type = Utils.GetCargoType(cargoClass);

		local tempList = AIEngineList(AIVehicle.VT_RAIL);
		local engineList = AIList();
		local wagonList = AIList();
		for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
			if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanPullCargo(engine, cargo_type) &&
					AIEngine.CanRunOnRail(engine, m_rail_type) && AIEngine.HasPowerOnRail(engine, m_rail_type)) {
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
				if (::caches.CanAttachToEngine(wagon, engine, cargo_type, m_rail_type, m_depotFrom)) {
					engineWagonPairs.append(pair);
				}
			}
		}

		return engineWagonPairs;
	}

	function GetTrainEngineWagonPair(cargoClass)
	{
		local engineWagonPairList = GetEngineWagonPairs(cargoClass);
		if (engineWagonPairList.len() == 0) return m_engineWagonPair == null ? [-1, -1, -1, -1, -1] : m_engineWagonPair;

		local cargo_type = Utils.GetCargoType(cargoClass);

		local best_income = null;
		local best_pair = null;
		foreach (pair in engineWagonPairList) {
			local engine = pair[0];
			local wagon = pair[1];
			local multiplier = Utils.GetEngineReliabilityMultiplier(engine);
			local engine_max_speed = AIEngine.GetMaxSpeed(engine) == 0 ? 65535 : AIEngine.GetMaxSpeed(engine);
			local wagon_max_speed = AIEngine.GetMaxSpeed(wagon) == 0 ? 65535 : AIEngine.GetMaxSpeed(wagon);
			local train_max_speed = min(engine_max_speed, wagon_max_speed);
			local railtype_max_speed = AIRail.GetMaxSpeed(m_rail_type) == 0 ? 65535 : AIRail.GetMaxSpeed(m_rail_type);
			train_max_speed = min(railtype_max_speed, train_max_speed);
			local days_in_transit = (m_routeDistance * 256 * 16) / (2 * 74 * train_max_speed);
			days_in_transit += STATION_LOADING_INTERVAL;

			local engine_length = ::caches.GetLength(engine, cargo_type, m_depotFrom);
			local wagon_length = ::caches.GetLength(wagon, cargo_type, m_depotFrom);
			local max_train_length = m_platformLength * 16;
			local num_wagons = (max_train_length - engine_length) / wagon_length;
			local engine_capacity = max(0, ::caches.GetBuildWithRefitCapacity(m_depotFrom, engine, cargo_type));
			local wagon_capacity = max(0, ::caches.GetBuildWithRefitCapacity(m_depotFrom, wagon, cargo_type));
			local train_capacity = engine_capacity + wagon_capacity * num_wagons;
			local engine_running_cost = AIEngine.GetRunningCost(engine);
			local wagon_running_cost = AIEngine.GetRunningCost(wagon);
			local train_running_cost = engine_running_cost + wagon_running_cost * num_wagons;

			local income = ((train_capacity * AICargo.GetCargoIncome(cargo_type, m_routeDistance, days_in_transit) - train_running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
//			AILog.Info("EngineWagonPair: [" + AIEngine.GetName(engine) + " -- " + num_wagons + " * " + AIEngine.GetName(wagon) + "; Capacity: " + train_capacity + "; Max Speed: " + train_max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + train_running_cost + "; Distance: " + m_routeDistance + "; Income: " + income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_pair = [engine, wagon, num_wagons, train_max_speed, train_capacity];
			}
		}

		return best_pair == null ? [-1, -1, -1, -1, -1] : best_pair;
	}

	function UpdateEngineWagonPair()
	{
		if (!m_active_route) return;

		m_engineWagonPair = GetTrainEngineWagonPair(m_cargo_class);
	}

	function UpgradeBridges()
	{
		if (!m_active_route) return;

		AIRail.SetCurrentRailType(m_rail_type);
		foreach (tile in m_bridgeTiles) {
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
		m_vehicle_list.rawdelete(vehicle);
		AIVehicle.SellVehicle(vehicle);
		Utils.RepayLoan();
	}

	function AddVehicle(return_vehicle = false, skip_order = false)
	{
		ValidateVehicleList();
		if (m_vehicle_list.len() >= OptimalVehicleCount()) {
			return null;
		}

		/* Clone vehicle, share orders */
		local clone_vehicle_id = AIVehicle.VEHICLE_INVALID;
		local share_orders_vid = AIVehicle.VEHICLE_INVALID;
		foreach (vehicle_id, _ in m_vehicle_list) {
			if (m_engineWagonPair != null && AIEngine.IsValidEngine(m_engineWagonPair[0]) && AIEngine.IsBuildable(m_engineWagonPair[0]) &&
					AIEngine.IsValidEngine(m_engineWagonPair[1]) && AIEngine.IsBuildable(m_engineWagonPair[1])) {
				if (AIVehicle.GetEngineType(vehicle_id) == m_engineWagonPair[0] && AIVehicle.GetWagonEngineType(vehicle_id, 1) == m_engineWagonPair[1]) {
					clone_vehicle_id = vehicle_id;
				}
			}
			if (AIVehicle.GetGroupID(vehicle_id) == m_group && AIGroup.IsValidGroup(m_group)) {
				share_orders_vid = vehicle_id;
			}
		}
		local depot = skip_order ? m_depotTo : m_depotFrom;
		local new_vehicle = AIVehicle.VEHICLE_INVALID;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			local cargo_type = Utils.GetCargoType(m_cargo_class);
			/* Check if we have money first to buy entire parts */
			local cost = AIAccounting();
			AITestMode() && AIVehicle.BuildVehicleWithRefit(depot, this.m_engineWagonPair[0], cargo_type);
			local num_wagons = this.m_engineWagonPair[2];
			while (num_wagons > 0) {
				AITestMode() && AIVehicle.BuildVehicleWithRefit(depot, this.m_engineWagonPair[1], cargo_type);
				num_wagons--;
			}
			if (Utils.HasMoney(cost.GetCosts())) {
				new_vehicle = TestBuildVehicleWithRefit().TryBuild(depot, this.m_engineWagonPair[0], cargo_type);
				if (AIVehicle.IsValidVehicle(new_vehicle)) {
					local num_tries = this.m_engineWagonPair[2];
					local wagon_chain = AIVehicle.VEHICLE_INVALID;
					local num_wagons = 0;
					while (num_tries > 0) {
						local wagon = TestBuildVehicleWithRefit().TryBuild(depot, this.m_engineWagonPair[1], cargo_type);
						if (AIVehicle.IsValidVehicle(wagon) || AIVehicle.IsValidVehicle(wagon_chain)) {
//							AILog.Info("wagon or wagon_chain is valid");
							if (!AIVehicle.IsValidVehicle(wagon_chain)) wagon_chain = wagon;
							num_wagons = AIVehicle.GetNumWagons(wagon_chain);
							num_tries--;
						} else {
							break;
						}
					}
					if (num_wagons < this.m_engineWagonPair[2]) {
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
			m_vehicle_list.rawset(new_vehicle, 2);
			local vehicle_ready_to_start = false;
			if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					if (AIOrder.AppendOrder(new_vehicle, m_stationFrom, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_NONE) &&
							AIOrder.AppendOrder(new_vehicle, m_stationTo, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_NONE)) {
						vehicle_ready_to_start = true;
					} else {
						DeleteSellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						vehicle_ready_to_start = true;
					} else {
						AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						DeleteSellVehicle(new_vehicle);
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
							DeleteSellVehicle(new_vehicle);
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

				m_last_vehicle_added = AIDate.GetCurrentDate();

				if (AIGroup.IsValidGroup(m_group) && AIVehicle.GetGroupID(new_vehicle) != m_group) {
					AIGroup.MoveVehicle(m_group, new_vehicle);
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
//		AILog.Info("m_routeDistance = " + m_routeDistance);
		local max_speed = this.m_engineWagonPair[3];
		local count_interval = max_speed * 74 * STATION_LOADING_INTERVAL / (256 * 16);
//		AILog.Info("count_interval = " + count_interval + "; MaxSpeed = " + max_speed);
		local vehicleCount = (count_interval > 0 ? (m_routeDistance / count_interval) : 0);
//		AILog.Info("vehicleCount = " + vehicleCount);
		local max_num_trains = m_routeDistance / m_platformLength;
//		AILog.Info("max_num_trains = " + max_num_trains);
		vehicleCount = max(2, vehicleCount);

		return vehicleCount;
	}

	function AddVehiclesToNewRoute(cargoClass)
	{
		m_group = GroupVehicles();
		local optimal_vehicle_count = OptimalVehicleCount();

		ValidateVehicleList();
		local numvehicles = m_vehicle_list.len();
		local numvehicles_before = numvehicles;
		if (numvehicles >= optimal_vehicle_count) {
			if (m_last_vehicle_added < 0) m_last_vehicle_added *= -1;
			return 0;
		}

		local buyVehicleCount = 2;

		if (buyVehicleCount > optimal_vehicle_count - numvehicles) {
			buyVehicleCount = optimal_vehicle_count - numvehicles;
		}

		for (local i = 0; i < buyVehicleCount; ++i) {
			local old_lastVehicleAdded = -m_last_vehicle_added;
			if (old_lastVehicleAdded > 0 && AIDate.GetCurrentDate() - old_lastVehicleAdded <= 3) {
				break;
			}
			m_last_vehicle_added = 0;
			local added_vehicle = AddVehicle(true, (numvehicles % 2) == 1);
			if (added_vehicle != null) {
				local nameFrom = AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom));
				local nameTo = AIBaseStation.GetName(AIStation.GetStationID(m_stationTo));
//				if (numvehicles % 2 == 1) {
//					AIOrder.SkipToOrder(added_vehicle, 1);
//				}
				numvehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engineWagonPair[0]) + " on new route from " + (numvehicles % 2 == 1 ? nameTo : nameFrom) + " to " + (numvehicles % 2 == 1 ? nameFrom : nameTo) + "! (" + numvehicles + "/" + optimal_vehicle_count + " train" + (numvehicles != 1 ? "s" : "") + ", " + m_routeDistance + " manhattan tiles)");
				if (buyVehicleCount > 1) {
					m_last_vehicle_added *= -1;
				}
			} else {
				break;
			}
		}
		if (numvehicles < optimal_vehicle_count && m_last_vehicle_added >= 0) {
			m_last_vehicle_added = 0;
		}
		return numvehicles - numvehicles_before;
	}

	function SendMoveVehicleToDepot(vehicle_id)
	{
		if (AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotRailGroup[0] && AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotRailGroup[1] && AIVehicle.GetState(vehicle_id) != AIVehicle.VS_CRASHED) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			if (!AIVehicle.IsStoppedInDepot(vehicle_id) && !AIVehicle.SendVehicleToDepot(vehicle_id)) {
				AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
				return 0;
			}
			m_last_vehicle_removed = AIDate.GetCurrentDate();

			AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " has been sent to its depot!");

			return 1;
		}

		return 0;
	}

	function SendNegativeProfitVehiclesToDepot()
	{
		if (m_last_vehicle_added <= 0 || AIDate.GetCurrentDate() - m_last_vehicle_added <= 30) return;
//		AILog.Info("SendNegativeProfitVehiclesToDepot . m_last_vehicle_added = " + m_last_vehicle_added + "; " + AIDate.GetCurrentDate() + " - " + m_last_vehicle_added + " = " + (AIDate.GetCurrentDate() - m_last_vehicle_added) + " < 45" + " - " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)));

//		if (AIDate.GetCurrentDate() - m_last_vehicle_removed <= 30) return;

		ValidateVehicleList();

		foreach (vehicle, _ in m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (SendMoveVehicleToDepot(vehicle)) {
					if (!AIGroup.MoveVehicle(m_sentToDepotRailGroup[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotRailGroup[0]);
					} else {
						m_vehicle_list.rawset(vehicle, 0);
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

		local cargo_type = Utils.GetCargoType(m_cargo_class);
		local station1 = AIStation.GetStationID(m_stationFrom);
		local station2 = AIStation.GetStationID(m_stationTo);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargo_type);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargo_type);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

//		AILog.Info("cargoWaiting = " + (cargoWaiting1 + cargoWaiting2));
		if (cargoWaiting1 + cargoWaiting2 < 150) {
			for (local vehicle = vehicleList.Begin(); !vehicleList.IsEnd(); vehicle = vehicleList.Next()) {
				if (AIVehicle.GetProfitLastYear(vehicle) < (maxAllRoutesProfit / 6)) {
					if (SendMoveVehicleToDepot(vehicle)) {
						if (!AIGroup.MoveVehicle(m_sentToDepotRailGroup[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotRailGroup[0]);
						} else {
							m_vehicle_list.rawset(vehicle, 0);
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
			if (m_vehicle_list.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local vehicle_name = AIVehicle.GetName(vehicle);
				DeleteSellVehicle(vehicle);

				AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " has been sold!");
			}
		}

		sent_to_depot_list = this.SentToDepotList(1);

		for (local vehicle = sent_to_depot_list.Begin(); !sent_to_depot_list.IsEnd(); vehicle = sent_to_depot_list.Next()) {
			if (m_vehicle_list.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local skip_order = AIVehicle.GetLocation(vehicle) == this.m_depotTo;
				DeleteSellVehicle(vehicle);

				local renewed_vehicle = AddVehicle(true, skip_order);
				if (renewed_vehicle != null) {
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(skip_order ? m_stationFrom : m_stationTo)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(skip_order ? m_stationTo : m_stationFrom)) + " has been renewed!");
				}
			}
		}
	}

	function AddRemoveVehicleToRoute(maxed_out_num_vehs)
	{
		if (!m_active_route) {
			return 0;
		}

		if (m_last_vehicle_added <= 0) {
			return AddVehiclesToNewRoute(m_cargo_class);
		}

		ValidateVehicleList();
		local numvehicles = null;
		if (AIDate.GetCurrentDate() -  m_last_vehicle_added > 30) {
			numvehicles = m_vehicle_list.len();
			local stoppedList = AIList()
			foreach (vehicle, _ in m_vehicle_list) {
				if (AIVehicle.GetCurrentSpeed(vehicle) == 0 && AIVehicle.GetState(vehicle) == AIVehicle.VS_RUNNING) {
					stoppedList.AddItem(vehicle, 0);
				}
			}

			local stoppedCount = stoppedList.Count();
			local max_num_stopped = 4 + AIGameSettings.GetValue("vehicle_breakdowns") * 2;
			if (stoppedCount >= max_num_stopped) {
				AILog.Info("Some vehicles on existing route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " aren't moving. (" + stoppedCount + "/" + numvehicles + " trains)");

				for (local vehicle = stoppedList.Begin(); !stoppedList.IsEnd(); vehicle = stoppedList.Next()) {
					if (stoppedCount >= max_num_stopped) {
						local old_lastVehicleRemoved = m_last_vehicle_removed;
						if (SendMoveVehicleToDepot(vehicle)) {
							if (!AIGroup.MoveVehicle(this.m_sentToDepotRailGroup[0], vehicle)) {
								AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sentToDepotRailGroup[0]);
							} else {
								m_vehicle_list.rawset(vehicle, 0);
							}
							m_last_vehicle_added = AIDate.GetCurrentDate();
							m_last_vehicle_removed = old_lastVehicleRemoved;
							stoppedCount--;
						}
					}
				}
				return 0;
			}
		}

		if (AIDate.GetCurrentDate() - m_last_vehicle_added < 90) {
			return 0;
		}

		local optimal_vehicle_count = OptimalVehicleCount();
		if (numvehicles == null) {
			numvehicles = m_vehicle_list.len();
		}
		local numvehicles_before = numvehicles;

		if (numvehicles >= optimal_vehicle_count && maxed_out_num_vehs) {
			return 0;
		}

		local cargo_type = Utils.GetCargoType(m_cargo_class);
		local station1 = AIStation.GetStationID(m_stationFrom);
		local station2 = AIStation.GetStationID(m_stationTo);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargo_type);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargo_type);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

		local train_capacity = this.m_engineWagonPair[4];

		if (cargoWaiting1 > train_capacity || cargoWaiting2 > train_capacity) {
			local number_to_add = max(1, (cargoWaiting1 > cargoWaiting2 ? cargoWaiting1 : cargoWaiting2) / train_capacity);

			while (number_to_add) {
				number_to_add--;
				local skip_order = cargoWaiting1 <= cargoWaiting2;
				local added_vehicle = AddVehicle(true, skip_order);
				if (added_vehicle != null) {
					numvehicles++;
					if (!skip_order) {
						cargoWaiting1 -= train_capacity;
					} else {
						cargoWaiting2 -= train_capacity;
					}
					AILog.Info("Added " + AIEngine.GetName(this.m_engineWagonPair[0]) + " on existing route from " + AIBaseStation.GetName(skip_order ? station2 : station1) + " to " + AIBaseStation.GetName(skip_order ? station1 : station2) + "! (" + numvehicles + "/" + optimal_vehicle_count + " train" + (numvehicles != 1 ? "s" : "") + ", " + m_routeDistance + " manhattan tiles)");
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
		ValidateVehicleList();
		local engine_price = AIEngine.GetPrice(this.m_engineWagonPair[0]);
		local wagon_price = AIEngine.GetPrice(this.m_engineWagonPair[1]) * this.m_engineWagonPair[2];
		local train_price = engine_price + wagon_price;
		local count = 1 + AIGroup.GetNumVehicles(m_sentToDepotRailGroup[1], AIVehicle.VT_RAIL);

		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAgeLeft(vehicle) <= 365 || AIVehicle.GetEngineType(vehicle) != this.m_engineWagonPair[0] && Utils.HasMoney(2 * train_price * count)) {
				if (SendMoveVehicleToDepot(vehicle)) {
					count++;
					if (!AIGroup.MoveVehicle(m_sentToDepotRailGroup[1], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotRailGroup[1]);
					} else {
						m_vehicle_list.rawset(vehicle, 1);
					}
				}
			}
		}
	}

	function GetPlatformLength()
	{
		local station = RailStation.CreateFromTile(m_stationFrom, m_stationFromDir);
		return station.m_length;
	}

	function GetRouteDistance()
	{
		local stationFrom = RailStation.CreateFromTile(m_stationFrom, m_stationFromDir);
		local stationFromPlatform1 = stationFrom.GetPlatformLine(1);
		local entryFrom = stationFrom.GetEntryTile(stationFromPlatform1);
		local exitFrom = stationFrom.GetExitTile(stationFromPlatform1);
		local offsetFrom = entryFrom - exitFrom;
		local stationFromTile = exitFrom + offsetFrom * stationFrom.m_length;

		local stationTo = RailStation.CreateFromTile(m_stationTo, m_stationToDir);
		local stationToPlatform1 = stationTo.GetPlatformLine(1);
		local entryTo = stationTo.GetEntryTile(stationToPlatform1);
		local exitTo = stationTo.GetExitTile(stationToPlatform1);
		local offsetTo = entryTo - exitTo;
		local stationToTile = exitTo + offsetTo * stationTo.m_length;

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
		::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, rail_type, bot_tile));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_2, rail_type, entry_tile_2, 2 * exit_tile_1 - entry_tile_1));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, rail_type, entry_tile_1, 2 * exit_tile_2 - entry_tile_2));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_2, rail_type, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, rail_type, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
	}

	function ScheduleRemoveDepot(depot)
	{
		local depotFront = AIRail.GetRailDepotFrontTile(depot);
		local depotRaila = abs(depot - depotFront) == 1 ? depotFront - AIMap.GetMapSizeX() : depotFront - 1;
		local depotRailb = 2 * depotFront - depotRaila;
		local depotRailc = 2 * depotFront - depot;
		local rail_type = AIRail.GetRailType(depot);
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, rail_type, depot, depotRaila));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, rail_type, depot, depotRailb));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, rail_type, depot, depotRailc));
		::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(depot, RailStructType.DEPOT, rail_type));
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
				::scheduledRemovalsTable.Train.append(RailStruct.SetRail(frontTile, rail_type, prevTile, nextTile));
				ScheduleRemoveTracks(nextTile, frontTile);
			}
		} else if (AIBridge.IsBridgeTile(frontTile)) {
			local dir = frontTile - prevTile;
			local otherTile = AIBridge.GetOtherBridgeEnd(frontTile);
			local rail_type = AIRail.GetRailType(frontTile);
			if (((otherTile - frontTile) / AIMap.DistanceManhattan(otherTile, frontTile)) == dir) {
				nextTile = otherTile + dir;
			}
			if (nextTile != AIMap.TILE_INVALID) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(frontTile, RailStructType.BRIDGE, rail_type, otherTile));
				ScheduleRemoveTracks(nextTile, otherTile);
			}
		} else if (AITunnel.IsTunnelTile(frontTile)) {
			local dir = frontTile - prevTile;
			local otherTile = AITunnel.GetOtherTunnelEnd(frontTile);
			local rail_type = AIRail.GetRailType(frontTile);
			if (((otherTile - frontTile) / AIMap.DistanceManhattan(otherTile, frontTile)) == dir) {
				nextTile = otherTile + dir;
			}
			if (nextTile != AIMap.TILE_INVALID) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(frontTile, RailStructType.TUNNEL, rail_type, otherTile));
				ScheduleRemoveTracks(nextTile, otherTile);
			}
		}
	}

	function RemoveIfUnserviced()
	{
		ValidateVehicleList();
		if (this.m_vehicle_list.len() == 0 && (((!AIEngine.IsValidEngine(m_engineWagonPair[0]) || !AIEngine.IsBuildable(m_engineWagonPair[0]) || !AIEngine.IsValidEngine(m_engineWagonPair[1]) || !AIEngine.IsBuildable(m_engineWagonPair[1])) && m_last_vehicle_added == 0) ||
				(AIDate.GetCurrentDate() - m_last_vehicle_added >= 90) && m_last_vehicle_added > 0)) {
			m_active_route = false;

			local stationFrom_name = AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom));
			ScheduleRemoveStation(m_stationFrom, m_stationFromDir);
			ScheduleRemoveDepot(m_depotFrom);

			local stationTo_name = AIBaseStation.GetName(AIStation.GetStationID(m_stationTo));
			ScheduleRemoveStation(m_stationTo, m_stationToDir);
			ScheduleRemoveDepot(m_depotTo);

			local station = RailStation.CreateFromTile(m_stationFrom, m_stationFromDir);
			local line = station.GetPlatformLine(2);
			ScheduleRemoveTracks(station.GetExitTile(line, 1), station.GetExitTile(line));

			station = RailStation.CreateFromTile(m_stationTo, m_stationToDir);
			line = station.GetPlatformLine(2);
			ScheduleRemoveTracks(station.GetExitTile(line, 1), station.GetExitTile(line));

			if (AIGroup.IsValidGroup(m_group)) {
				AIGroup.DeleteGroup(m_group);
			}
			AILog.Warning("Removing unserviced rail route from " + stationFrom_name + " to " + stationTo_name);
			return true;
		}
		return false;
	}

	function GroupVehicles()
	{
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetGroupID(vehicle) != AIGroup.GROUP_DEFAULT && AIVehicle.GetGroupID(vehicle) != m_sentToDepotRailGroup[0] && AIVehicle.GetGroupID(vehicle) != m_sentToDepotRailGroup[1]) {
				if (!AIGroup.IsValidGroup(m_group)) {
					m_group = AIVehicle.GetGroupID(vehicle);
					break;
				}
			}
		}

		if (!AIGroup.IsValidGroup(m_group)) {
			m_group = AIGroup.CreateGroup(AIVehicle.VT_RAIL, AIGroup.GROUP_INVALID);
			if (AIGroup.IsValidGroup(m_group)) {
				AIGroup.SetName(m_group, (m_cargo_class == AICargo.CC_PASSENGERS ? "P" : "M") + m_routeDistance + ": " + m_stationFrom + " - " + m_stationTo);
				AILog.Info("Created " + AIGroup.GetName(m_group) + " for rail route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)));
			}
		}

		return m_group;
	}

	function SaveRoute()
	{
		return [m_city_from, m_city_to, m_stationFrom, m_stationTo, m_depotFrom, m_depotTo, m_bridgeTiles, m_cargo_class, m_last_vehicle_added, m_last_vehicle_removed, m_active_route, m_sentToDepotRailGroup, m_group, m_rail_type, m_stationFromDir, m_stationToDir];
	}

	function LoadRoute(data)
	{
		local cityFrom = data[0];
		local cityTo = data[1];
		local stationFrom = data[2];
		local stationTo = data[3];
		local depotFrom = data[4];
		local depotTo = data[5];

		local bridgeTiles = data[6];

		local cargoClass = data[7];
		local rail_type = data[13];

		local sentToDepotRailGroup = data[11];

		local stationFromDir = data[14];
		local stationToDir = data[15];

		local route = RailRoute(cityFrom, cityTo, stationFrom, stationTo, depotFrom, depotTo, bridgeTiles, cargoClass, sentToDepotRailGroup, rail_type, stationFromDir, stationToDir, 1);

		route.m_last_vehicle_added = data[8];
		route.m_last_vehicle_removed = data[9];
		route.m_active_route = data[10];

		route.m_group = data[12];

		local vehicleList = AIVehicleList_Station(AIStation.GetStationID(route.m_stationFrom));
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				route.m_vehicle_list.rawset(v, 2);
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotRailGroup[0]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				if (route.m_vehicle_list.rawin(v)) {
					route.m_vehicle_list.rawset(v, 0);
				}
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotRailGroup[1]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				if (route.m_vehicle_list.rawin(v)) {
					route.m_vehicle_list.rawset(v, 1);
				}
			}
		}

		return [route, bridgeTiles.len()];
	}
};
