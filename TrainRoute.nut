require("TrainRouteManager.nut");

class RailRoute extends RailRouteManager {
	MAX_PLATFORM_LENGTH = 7;
	MAX_NUM_PLATFORMS = 2;
	STATION_LOADING_INTERVAL = 15;

	m_cityFrom = null;
	m_cityTo = null;
	m_stationFrom = null;
	m_stationTo = null;
	m_depotFrom = null;
	m_depotTo = null;
	m_bridgeTiles = null;
	m_cargoClass = null;
	m_railtype = null;
	m_stationFromDir = null;
	m_stationToDir = null;

	m_platformLength = null;
	m_routeDistance = null;
	m_engineWagonPair = null; // array in the form [engine, wagon, num_wagons, train_max_speed, train_capacity]
	m_group = null;

	m_lastVehicleAdded = null;
	m_lastVehicleRemoved = null;

	m_sentToDepotRailGroup = null;

	m_activeRoute = null;

	m_vehicleList = null;

	constructor(cityFrom, cityTo, stationFrom, stationTo, depotFrom, depotTo, bridgeTiles, cargoClass, sentToDepotRailGroup, railtype, stationFromDir, stationToDir, isLoaded = 0) {
		AIRail.SetCurrentRailType(railtype);
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_stationFrom = stationFrom;
		m_stationTo = stationTo;
		m_depotFrom = depotFrom;
		m_depotTo = depotTo;
		m_bridgeTiles = bridgeTiles;
		m_cargoClass = cargoClass;
		m_railtype = railtype;
		m_stationFromDir = stationFromDir;
		m_stationToDir = stationToDir;

		m_platformLength = GetPlatformLength();
		m_routeDistance = GetRouteDistance();
		m_engineWagonPair = GetTrainEngineWagonPair(cargoClass);
		m_group = AIGroup.GROUP_INVALID;
		m_sentToDepotRailGroup = sentToDepotRailGroup;

		m_lastVehicleAdded = 0;
		m_lastVehicleRemoved = AIDate.GetCurrentDate();

		m_activeRoute = true;

		m_vehicleList = {};

		if (!isLoaded) {
			addVehiclesToNewRoute(cargoClass);
		}
	}

	function updateBridges();
	function updateEngine();
	function addVehicle(return_vehicle, depot);
	function addVehiclesToNewRoute(cargoClass);
	function GetEngineList(cargoClass);
	function GetTrainEngine(cargoClass);
	function addremoveVehicleToRoute();

	function ValidateVehicleList() {
		local stationFrom = AIStation.GetStationID(m_stationFrom);
		local stationTo = AIStation.GetStationID(m_stationTo);

		local removelist = AIList();
		foreach (v, _ in m_vehicleList) {
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
			m_vehicleList.rawdelete(v);
		}
	}

	function sentToDepotList(i) {
		local sentToDepotList = AIList();
		ValidateVehicleList();
		foreach (vehicle, status in m_vehicleList) {
			if (status == i) sentToDepotList.AddItem(vehicle, i);
		}
		return sentToDepotList;
	}

	function GetEngineWagonPairs(cargoClass) {
		local cargo = Utils.getCargoId(cargoClass);

		local tempList = AIEngineList(AIVehicle.VT_RAIL);
		local engineList = AIList();
		local wagonList = AIList();
		for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
			if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanPullCargo(engine, cargo) &&
					AIEngine.CanRunOnRail(engine, m_railtype) && AIEngine.HasPowerOnRail(engine, m_railtype)) {
				if (AIEngine.CanRefitCargo(engine, cargo)) {
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
				if (::caches.CanAttachToEngine(wagon, engine, cargo, m_railtype, m_depotFrom)) {
					engineWagonPairs.append(pair);
				}
			}
		}

		return engineWagonPairs;
	}

	function GetTrainEngineWagonPair(cargoClass) {
		local engineWagonPairList = GetEngineWagonPairs(cargoClass);
		if (engineWagonPairList.len() == 0) return m_engineWagonPair == null ? [-1, -1, -1, -1, -1] : m_engineWagonPair;

		local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
		local cargo = Utils.getCargoId(cargoClass);

		local best_income = null;
		local best_pair = null;
		foreach (_, pair in engineWagonPairList) {
			local engine = pair[0];
			local wagon = pair[1];
			local reliability = AIEngine.GetReliability(engine);
			local multiplier = reliability;
			switch (breakdowns) {
				case 0:
					multiplier = 100;
					break;
				case 1:
					multiplier = reliability + (100 - reliability) / 2;
					break;
				case 2:
				default:
					multiplier = reliability;
					break;
			}
			local engine_max_speed = AIEngine.GetMaxSpeed(engine) == 0 ? 65535 : AIEngine.GetMaxSpeed(engine);
			local wagon_max_speed = AIEngine.GetMaxSpeed(wagon) == 0 ? 65535 : AIEngine.GetMaxSpeed(wagon);
			local train_max_speed = min(engine_max_speed, wagon_max_speed);
			local railtype_max_speed = AIRail.GetMaxSpeed(m_railtype) == 0 ? 65535 : AIRail.GetMaxSpeed(m_railtype);
			train_max_speed = min(railtype_max_speed, train_max_speed);
			local days_in_transit = (m_routeDistance * 256 * 16) / (2 * 74 * train_max_speed);
			days_in_transit += STATION_LOADING_INTERVAL;

			local engine_length = ::caches.GetLength(engine, cargo, m_depotFrom);
			local wagon_length = ::caches.GetLength(wagon, cargo, m_depotFrom);
			local max_train_length = m_platformLength * 16;
			local num_wagons = (max_train_length - engine_length) / wagon_length;
			local engine_capacity = max(0, ::caches.GetBuildWithRefitCapacity(m_depotFrom, engine, cargo));
			local wagon_capacity = max(0, ::caches.GetBuildWithRefitCapacity(m_depotFrom, wagon, cargo));
			local train_capacity = engine_capacity + wagon_capacity * num_wagons;
			local engine_running_cost = AIEngine.GetRunningCost(engine);
			local wagon_running_cost = AIEngine.GetRunningCost(wagon);
			local train_running_cost = engine_running_cost + wagon_running_cost * num_wagons;

			local income = ((train_capacity * AICargo.GetCargoIncome(cargo, m_routeDistance, days_in_transit) - train_running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
//			AILog.Info("EngineWagonPair: [" + AIEngine.GetName(engine) + " -- " + num_wagons + " * " + AIEngine.GetName(wagon) + "; Capacity: " + train_capacity + "; Max Speed: " + train_max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + train_running_cost + "; Distance: " + m_routeDistance + "; Income: " + income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_pair = [engine, wagon, num_wagons, train_max_speed, train_capacity];
			}
		}

		return best_pair == null ? [-1, -1, -1, -1, -1] : best_pair;
	}

	function UpdateEngineWagonPair() {
		if (!m_activeRoute) return;

		m_engineWagonPair = GetTrainEngineWagonPair(m_cargoClass);
	}

	function updateBridges() {
		if (!m_activeRoute) return;

		AIRail.SetCurrentRailType(m_railtype);
		foreach (_, tile in m_bridgeTiles) {
			local north_tile = tile[0];
			local south_tile = tile[1];

			if (AIBridge.IsBridgeTile(north_tile) && (AIBridge.GetOtherBridgeEnd(north_tile) == south_tile)) {
				local old_bridge = AIBridge.GetBridgeID(north_tile);

				local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(north_tile, south_tile) + 1);
				for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
					bridge_list.SetValue(bridge, AIBridge.GetMaxSpeed(bridge));
				}
				bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
				if (bridge_list.Count() > 0) {
					local new_bridge = bridge_list.Begin();
					if (TestBuildBridge().TryBuild(AIVehicle.VT_RAIL, new_bridge, north_tile, south_tile)) {
						AILog.Info("Bridge at tiles " + north_tile + " and " + south_tile + " upgraded from " + AIBridge.GetName(old_bridge, AIVehicle.VT_RAIL) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(AIBridge.GetMaxSpeed(old_bridge)) + ") to " + AIBridge.GetName(new_bridge, AIVehicle.VT_RAIL) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(AIBridge.GetMaxSpeed(new_bridge)) + ")");
					}
				}
			}
		}
	}

	function sellVehicle(vehicle) {
		m_vehicleList.rawdelete(vehicle);
		AIVehicle.SellVehicle(vehicle);
		Utils.RepayLoan();
	}

	function addVehicle(return_vehicle = false, skip_order = false) {
		ValidateVehicleList();
		if (m_vehicleList.len() >= optimalVehicleCount()) {
			return null;
		}

		/* Clone vehicle, share orders */
		local clone_vehicle_id = AIVehicle.VEHICLE_INVALID;
		local share_orders_vid = AIVehicle.VEHICLE_INVALID;
		foreach (vehicle_id, _ in m_vehicleList) {
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
			local cargo = Utils.getCargoId(m_cargoClass);
			/* Check if we have money first to buy entire parts */
			local cost = AIAccounting();
			AITestMode() && AIVehicle.BuildVehicleWithRefit(depot, this.m_engineWagonPair[0], cargo);
			local num_wagons = this.m_engineWagonPair[2];
			while (num_wagons > 0) {
				AITestMode() && AIVehicle.BuildVehicleWithRefit(depot, this.m_engineWagonPair[1], cargo);
				num_wagons--;
			}
			if (Utils.HasMoney(cost.GetCosts())) {
				new_vehicle = TestBuildVehicleWithRefit().TryBuild(depot, this.m_engineWagonPair[0], cargo);
				if (AIVehicle.IsValidVehicle(new_vehicle)) {
					local num_tries = this.m_engineWagonPair[2];
					local wagon_chain = AIVehicle.VEHICLE_INVALID;
					local num_wagons = 0;
					while (num_tries > 0) {
						local wagon = TestBuildVehicleWithRefit().TryBuild(depot, this.m_engineWagonPair[1], cargo);
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
							} else {
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
							} else {
//								AILog.Info("Sold wagon chain. Reason: failed to move wagons");
							}
							if (!AIVehicle.SellVehicle(new_vehicle)) {
//								AILog.Info("Failed to sell train. Reason: failed to move wagons");
							} else {
								new_vehicle = AIVehicle.VEHICLE_INVALID;
//								AILog.Info("Sold train. Reason: failed to move wagons");
							}
						} else {
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
			m_vehicleList.rawset(new_vehicle, 2);
			local vehicle_ready_to_start = false;
			if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					if (AIOrder.AppendOrder(new_vehicle, m_stationFrom, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_NONE) &&
							AIOrder.AppendOrder(new_vehicle, m_stationTo, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_NONE)) {
						vehicle_ready_to_start = true;
					} else {
						sellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						vehicle_ready_to_start = true;
					} else {
						AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						sellVehicle(new_vehicle);
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
							sellVehicle(new_vehicle);
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

				m_lastVehicleAdded = AIDate.GetCurrentDate();

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

	function optimalVehicleCount() {
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

	function addVehiclesToNewRoute(cargoClass) {
		m_group = GroupVehicles();
		local optimalVehicleCount = optimalVehicleCount();

		ValidateVehicleList();
		local numvehicles = m_vehicleList.len();
		local numvehicles_before = numvehicles;
		if (numvehicles >= optimalVehicleCount) {
			if (m_lastVehicleAdded < 0) m_lastVehicleAdded *= -1;
			return 0;
		}

		local buyVehicleCount = 2;

		if (buyVehicleCount > optimalVehicleCount - numvehicles) {
			buyVehicleCount = optimalVehicleCount - numvehicles;
		}

		for (local i = 0; i < buyVehicleCount; ++i) {
			local old_lastVehicleAdded = -m_lastVehicleAdded;
			if (old_lastVehicleAdded > 0 && AIDate.GetCurrentDate() - old_lastVehicleAdded <= 3) {
				break;
			}
			m_lastVehicleAdded = 0;
			local added_vehicle = addVehicle(true, (numvehicles % 2) == 1);
			if (added_vehicle != null) {
				local nameFrom = AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom));
				local nameTo = AIBaseStation.GetName(AIStation.GetStationID(m_stationTo));
//				if (numvehicles % 2 == 1) {
//					AIOrder.SkipToOrder(added_vehicle, 1);
//				}
				numvehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engineWagonPair[0]) + " on new route from " + (numvehicles % 2 == 1 ? nameTo : nameFrom) + " to " + (numvehicles % 2 == 1 ? nameFrom : nameTo) + "! (" + numvehicles + "/" + optimalVehicleCount + " train" + (numvehicles != 1 ? "s" : "") + ", " + m_routeDistance + " manhattan tiles)");
				if (buyVehicleCount > 1) {
					m_lastVehicleAdded *= -1;
				}
			} else {
				break;
			}
		}
		if (numvehicles < optimalVehicleCount && m_lastVehicleAdded >= 0) {
			m_lastVehicleAdded = 0;
		}
		return numvehicles - numvehicles_before;
	}

	function sendVehicleToDepot(vehicle_id) {
		if (AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotRailGroup[0] && AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotRailGroup[1] && AIVehicle.GetState(vehicle_id) != AIVehicle.VS_CRASHED) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			if (!AIVehicle.IsStoppedInDepot(vehicle_id) && !AIVehicle.SendVehicleToDepot(vehicle_id)) {
				AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
				return 0;
			}
			m_lastVehicleRemoved = AIDate.GetCurrentDate();

			AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " has been sent to its depot!");

			return 1;
		}

		return 0;
	}

	function sendNegativeProfitVehiclesToDepot() {
		if (m_lastVehicleAdded <= 0 || AIDate.GetCurrentDate() - m_lastVehicleAdded <= 30) return;
//		AILog.Info("sendNegativeProfitVehiclesToDepot . m_lastVehicleAdded = " + m_lastVehicleAdded + "; " + AIDate.GetCurrentDate() + " - " + m_lastVehicleAdded + " = " + (AIDate.GetCurrentDate() - m_lastVehicleAdded) + " < 45" + " - " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)));

//		if (AIDate.GetCurrentDate() - m_lastVehicleRemoved <= 30) return;

		ValidateVehicleList();

		foreach (vehicle, _ in m_vehicleList) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (sendVehicleToDepot(vehicle)) {
					if (!AIGroup.MoveVehicle(m_sentToDepotRailGroup[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotRailGroup[0]);
					} else {
						m_vehicleList.rawset(vehicle, 0);
					}
					return;
				}
			}
		}
	}

	function sendLowProfitVehiclesToDepot(maxAllRoutesProfit) {
		ValidateVehicleList();
		local vehicleList = AIList();
		foreach (vehicle, _ in this.m_vehicleList) {
			if (AIVehicle.GetAge(vehicle) > 730) {
				vehicleList.AddItem(vehicle, 0);
			}
		}
		if (vehicleList.Count() == 0) return;

		local cargoId = Utils.getCargoId(m_cargoClass);
		local station1 = AIStation.GetStationID(m_stationFrom);
		local station2 = AIStation.GetStationID(m_stationTo);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargoId);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargoId);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargoId);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargoId);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

//		AILog.Info("cargoWaiting = " + (cargoWaiting1 + cargoWaiting2));
		if (cargoWaiting1 + cargoWaiting2 < 150) {
			for (local vehicle = vehicleList.Begin(); !vehicleList.IsEnd(); vehicle = vehicleList.Next()) {
				if (AIVehicle.GetProfitLastYear(vehicle) < (maxAllRoutesProfit / 6)) {
					if (sendVehicleToDepot(vehicle)) {
						if (!AIGroup.MoveVehicle(m_sentToDepotRailGroup[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotRailGroup[0]);
						} else {
							m_vehicleList.rawset(vehicle, 0);
						}
					}
				}
			}
		}
	}

	function sellVehiclesInDepot() {
		local sentToDepotList = this.sentToDepotList(0);

		for (local vehicle = sentToDepotList.Begin(); !sentToDepotList.IsEnd(); vehicle = sentToDepotList.Next()) {
			if (m_vehicleList.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local vehicle_name = AIVehicle.GetName(vehicle);
				sellVehicle(vehicle);

				AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " has been sold!");
			}
		}

		sentToDepotList = this.sentToDepotList(1);

		for (local vehicle = sentToDepotList.Begin(); !sentToDepotList.IsEnd(); vehicle = sentToDepotList.Next()) {
			if (m_vehicleList.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local skip_order = AIVehicle.GetLocation(vehicle) == this.m_depotTo;
				sellVehicle(vehicle);

				local renewed_vehicle = addVehicle(true, skip_order);
				if (renewed_vehicle != null) {
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(skip_order ? m_stationFrom : m_stationTo)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(skip_order ? m_stationTo : m_stationFrom)) + " has been renewed!");
				}
			}
		}
	}

	function addremoveVehicleToRoute(maxed_out_num_vehs) {
		if (!m_activeRoute) {
			return 0;
		}

		if (m_lastVehicleAdded <= 0) {
			return addVehiclesToNewRoute(m_cargoClass);
		}

		ValidateVehicleList();
		local numvehicles = null;
		if (AIDate.GetCurrentDate() -  m_lastVehicleAdded > 30) {
			numvehicles = m_vehicleList.len();
			local stoppedList = AIList()
			foreach (vehicle, _ in m_vehicleList) {
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
						local old_lastVehicleRemoved = m_lastVehicleRemoved;
						if (sendVehicleToDepot(vehicle)) {
							if (!AIGroup.MoveVehicle(this.m_sentToDepotRailGroup[0], vehicle)) {
								AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sentToDepotRailGroup[0]);
							} else {
								m_vehicleList.rawset(vehicle, 0);
							}
							m_lastVehicleAdded = AIDate.GetCurrentDate();
							m_lastVehicleRemoved = old_lastVehicleRemoved;
							stoppedCount--;
						}
					}
				}
				return 0;
			}
		}

		if (AIDate.GetCurrentDate() - m_lastVehicleAdded < 90) {
			return 0;
		}

		local optimalVehicleCount = optimalVehicleCount();
		if (numvehicles == null) {
			numvehicles = m_vehicleList.len();
		}
		local numvehicles_before = numvehicles;

		if (numvehicles >= optimalVehicleCount && maxed_out_num_vehs) {
			return 0;
		}

		local cargoId = Utils.getCargoId(m_cargoClass);
		local station1 = AIStation.GetStationID(m_stationFrom);
		local station2 = AIStation.GetStationID(m_stationTo);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargoId);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargoId);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargoId);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargoId);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

		local train_capacity = this.m_engineWagonPair[4];

		if (cargoWaiting1 > train_capacity || cargoWaiting2 > train_capacity) {
			local number_to_add = max(1, (cargoWaiting1 > cargoWaiting2 ? cargoWaiting1 : cargoWaiting2) / train_capacity);

			while (number_to_add) {
				number_to_add--;
				local skip_order = cargoWaiting1 <= cargoWaiting2;
				local added_vehicle = addVehicle(true, skip_order);
				if (added_vehicle != null) {
					numvehicles++;
					if (!skip_order) {
						cargoWaiting1 -= train_capacity;
					} else {
						cargoWaiting2 -= train_capacity;
					}
					AILog.Info("Added " + AIEngine.GetName(this.m_engineWagonPair[0]) + " on existing route from " + AIBaseStation.GetName(skip_order ? station2 : station1) + " to " + AIBaseStation.GetName(skip_order ? station1 : station2) + "! (" + numvehicles + "/" + optimalVehicleCount + " train" + (numvehicles != 1 ? "s" : "") + ", " + m_routeDistance + " manhattan tiles)");
					if (numvehicles >= optimalVehicleCount) {
						number_to_add = 0;
					}
				}
			}
		}
		return numvehicles - numvehicles_before;
	}

	function renewVehicles() {
		ValidateVehicleList();
		local engine_price = AIEngine.GetPrice(this.m_engineWagonPair[0]);
		local wagon_price = AIEngine.GetPrice(this.m_engineWagonPair[1]) * this.m_engineWagonPair[2];
		local train_price = engine_price + wagon_price;
		local count = 1 + AIGroup.GetNumVehicles(m_sentToDepotRailGroup[1], AIVehicle.VT_RAIL);

		foreach (vehicle, _ in this.m_vehicleList) {
			if (AIVehicle.GetAgeLeft(vehicle) <= 365 || AIVehicle.GetEngineType(vehicle) != this.m_engineWagonPair[0] && Utils.HasMoney(2 * train_price * count)) {
				if (sendVehicleToDepot(vehicle)) {
					count++;
					if (!AIGroup.MoveVehicle(m_sentToDepotRailGroup[1], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotRailGroup[1]);
					} else {
						m_vehicleList.rawset(vehicle, 1);
					}
				}
			}
		}
	}

	function GetPlatformLength() {
		local station = RailStation.CreateFromTile(m_stationFrom, m_stationFromDir);
		return station.m_length;
	}

	function GetRouteDistance() {
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

	function ScheduleRemoveStation(stationTile, stationDir) {
		local station = RailStation.CreateFromTile(stationTile, stationDir);
		local top_tile = station.GetTopTile();
		local bot_tile = station.GetBottomTile();
		local entry_tile_2 = station.GetEntryTile(2);
		local exit_tile_2 = station.GetExitTile(2);
		local exit_tile_1 = station.GetExitTile(1);
		local entry_tile_1 = station.GetEntryTile(1);
		local railtype = AIRail.GetRailType(top_tile);
		::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, railtype, bot_tile));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_2, railtype, entry_tile_2, 2 * exit_tile_1 - entry_tile_1));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, railtype, entry_tile_1, 2 * exit_tile_2 - entry_tile_2));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_2, railtype, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, railtype, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
	}

	function ScheduleRemoveDepot(depot) {
		local depotFront = AIRail.GetRailDepotFrontTile(depot);
		local depotRaila = abs(depot - depotFront) == 1 ? depotFront - AIMap.GetMapSizeX() : depotFront - 1;
		local depotRailb = 2 * depotFront - depotRaila;
		local depotRailc = 2 * depotFront - depot;
		local railtype = AIRail.GetRailType(depot);
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, railtype, depot, depotRaila));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, railtype, depot, depotRailb));
		::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, railtype, depot, depotRailc));
		::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(depot, RailStructType.DEPOT, railtype));
	}

	function ScheduleRemoveTracks(frontTile, prevTile) {
		local nextTile = AIMap.TILE_INVALID;
		if (AIRail.IsRailTile(frontTile)) {
			local dir = frontTile - prevTile;
			local track = AIRail.GetRailTracks(frontTile);
			local railtype = AIRail.GetRailType(frontTile);
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
				::scheduledRemovalsTable.Train.append(RailStruct.SetRail(frontTile, railtype, prevTile, nextTile));
				ScheduleRemoveTracks(nextTile, frontTile);
			}
		} else if (AIBridge.IsBridgeTile(frontTile)) {
			local dir = frontTile - prevTile;
			local otherTile = AIBridge.GetOtherBridgeEnd(frontTile);
			local railtype = AIRail.GetRailType(frontTile);
			if (((otherTile - frontTile) / AIMap.DistanceManhattan(otherTile, frontTile)) == dir) {
				nextTile = otherTile + dir;
			}
			if (nextTile != AIMap.TILE_INVALID) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(frontTile, RailStructType.BRIDGE, railtype, otherTile));
				ScheduleRemoveTracks(nextTile, otherTile);
			}
		} else if (AITunnel.IsTunnelTile(frontTile)) {
			local dir = frontTile - prevTile;
			local otherTile = AITunnel.GetOtherTunnelEnd(frontTile);
			local railtype = AIRail.GetRailType(frontTile);
			if (((otherTile - frontTile) / AIMap.DistanceManhattan(otherTile, frontTile)) == dir) {
				nextTile = otherTile + dir;
			}
			if (nextTile != AIMap.TILE_INVALID) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(frontTile, RailStructType.TUNNEL, railtype, otherTile));
				ScheduleRemoveTracks(nextTile, otherTile);
			}
		}
	}

	function removeIfUnserviced() {
		ValidateVehicleList();
		if (this.m_vehicleList.len() == 0 && (((!AIEngine.IsValidEngine(m_engineWagonPair[0]) || !AIEngine.IsBuildable(m_engineWagonPair[0]) || !AIEngine.IsValidEngine(m_engineWagonPair[1]) || !AIEngine.IsBuildable(m_engineWagonPair[1])) && m_lastVehicleAdded == 0) ||
				(AIDate.GetCurrentDate() - m_lastVehicleAdded >= 90) && m_lastVehicleAdded > 0)) {
			m_activeRoute = false;

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

	function GroupVehicles() {
		foreach (vehicle, _ in this.m_vehicleList) {
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
				AIGroup.SetName(m_group, (m_cargoClass == AICargo.CC_PASSENGERS ? "P" : "M") + m_routeDistance + ": " + m_stationFrom + " - " + m_stationTo);
				AILog.Info("Created " + AIGroup.GetName(m_group) + " for rail route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)));
			}
		}

		return m_group;
	}

	function saveRoute() {
		return [m_cityFrom, m_cityTo, m_stationFrom, m_stationTo, m_depotFrom, m_depotTo, m_bridgeTiles, m_cargoClass, m_lastVehicleAdded, m_lastVehicleRemoved, m_activeRoute, m_sentToDepotRailGroup, m_group, m_railtype, m_stationFromDir, m_stationToDir];
	}

	function loadRoute(data) {
		local cityFrom = data[0];
		local cityTo = data[1];
		local stationFrom = data[2];
		local stationTo = data[3];
		local depotFrom = data[4];
		local depotTo = data[5];

		local bridgeTiles = data[6];

		local cargoClass = data[7];
		local railtype = data[13];

		local sentToDepotRailGroup = data[11];

		local stationFromDir = data[14];
		local stationToDir = data[15];

		local route = RailRoute(cityFrom, cityTo, stationFrom, stationTo, depotFrom, depotTo, bridgeTiles, cargoClass, sentToDepotRailGroup, railtype, stationFromDir, stationToDir, 1);

		route.m_lastVehicleAdded = data[8];
		route.m_lastVehicleRemoved = data[9];
		route.m_activeRoute = data[10];

		route.m_group = data[12];

		local vehicleList = AIVehicleList_Station(AIStation.GetStationID(route.m_stationFrom));
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				route.m_vehicleList.rawset(v, 2);
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotRailGroup[0]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				if (route.m_vehicleList.rawin(v)) {
					route.m_vehicleList.rawset(v, 0);
				}
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotRailGroup[1]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				if (route.m_vehicleList.rawin(v)) {
					route.m_vehicleList.rawset(v, 1);
				}
			}
		}

		return [route, bridgeTiles.len()];
	}
}
