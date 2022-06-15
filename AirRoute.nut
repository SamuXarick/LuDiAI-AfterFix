require("AirRouteManager.nut");

class AirRoute extends RouteManager {
	m_cityFrom = null;
	m_cityTo = null;
	m_airportFrom = null;
	m_airportTo = null;
	m_cargoClass = null;

	m_engine = null;
	m_group = null;

	m_lastVehicleAdded = null;
	m_lastVehicleRemoved = null;

	m_sentToDepotAirGroup = null;

	m_activeRoute = null;

	m_vehicleList = null;

	constructor(cityFrom, cityTo, airportFrom, airportTo, cargoClass, sentToDepotAirGroup, isLoaded = 0) {
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_airportFrom = airportFrom;
		m_airportTo = airportTo;
		m_cargoClass = cargoClass;

		m_engine = GetAircraftEngine(cargoClass);
		m_group = AIGroup.GROUP_INVALID;
		m_sentToDepotAirGroup = sentToDepotAirGroup;

		m_lastVehicleAdded = 0;
		m_lastVehicleRemoved = AIDate.GetCurrentDate();

		m_activeRoute = true;

		m_vehicleList = {};

		if (!isLoaded) {
			addVehiclesToNewRoute(cargoClass);
		}
	}

	function updateEngine();
	function addVehicle(return_vehicle);
	function addVehiclesToNewRoute(cargoClass);
	function GetAircraftEngine(cargoClass);
	function addremoveVehicleToRoute();

	function ValidateVehicleList() {
		local stationFrom = AIStation.GetStationID(m_airportFrom);
		local stationTo = AIStation.GetStationID(m_airportTo);

		local removelist = AIList();
		foreach (v, _ in m_vehicleList) {
			if (AIVehicle.IsValidVehicle(v)) {
				if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_AIR) {
					local num_orders = AIOrder.GetOrderCount(v);
					if (num_orders == 2) {
						local order_from = false;
						local order_to = false;
						for (local o = 0; o < num_orders; o++) {
							if (AIOrder.IsValidVehicleOrder(v, o)) {
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
				AILog.Error("Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
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

	function GetAircraftEngine(cargoClass) {
		local airport1_type = AIAirport.GetAirportType(m_airportFrom);
		local airport2_type = AIAirport.GetAirportType(m_airportTo);

		local small_aircraft = airport1_type == AIAirport.AT_SMALL || airport2_type == AIAirport.AT_SMALL ||
			airport1_type == AIAirport.AT_COMMUTER || airport2_type == AIAirport.AT_COMMUTER;

		local helicopter = airport1_type == AIAirport.AT_HELIPORT || airport2_type == AIAirport.AT_HELIPORT ||
			airport1_type == AIAirport.AT_HELIDEPOT || airport2_type == AIAirport.AT_HELIDEPOT ||
			airport1_type == AIAirport.AT_HELISTATION || airport2_type == AIAirport.AT_HELISTATION;

		local hangar = helicopter ? airport1_type == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(m_airportTo) : AIAirport.GetHangarOfAirport(m_airportFrom) : AIAirport.GetHangarOfAirport(m_airportFrom);

		local squaredist = AIMap.DistanceSquare(m_airportFrom, m_airportTo);
		local fakedist = WrightAI.DistanceRealFake(m_airportFrom, m_airportTo);

		local cargo = Utils.getCargoId(cargoClass);

		local engine_list = AIEngineList(AIVehicle.VT_AIR);
		local removelist = AIList();
		for (local engine = engine_list.Begin(); !engine_list.IsEnd(); engine = engine_list.Next()) {
			if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, cargo)) {
				if (small_aircraft && AIEngine.GetPlaneType(engine) == AIAirport.PT_BIG_PLANE) {
					removelist.AddItem(engine, 0);
					continue;
				}
				if (helicopter && AIEngine.GetPlaneType(engine) != AIAirport.PT_HELICOPTER) {
					removelist.AddItem(engine, 0);
					continue;
				}
				if (WrightAI.GetMaximumOrderDistance(engine) < squaredist) {
					removelist.AddItem(engine, 0);
					continue;
				}
				local primary_capacity = Utils.GetBuildWithRefitCapacity(hangar, engine, cargo);
				local secondary_capacity = AIController.GetSetting("select_town_cargo") == 2 ? Utils.GetBuildWithRefitSecondaryCapacity(hangar, engine) : 0;
				local engine_income = WrightAI.GetEngineRouteIncome(engine, cargo, fakedist, primary_capacity, secondary_capacity);
				if (engine_income <= 0) {
					removelist.AddItem(engine, 0);
				}
				engine_list.SetValue(engine, engine_income);
			}
		}
		engine_list.RemoveList(removelist);
		engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		if (engine_list.Count() == 0) return m_engine == null ? -1 : m_engine;
		return engine_list.Begin();
	}

	function updateEngine() {
		if (!m_activeRoute) return;

		m_engine = GetAircraftEngine(m_cargoClass);
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
			if (m_engine != null && AIEngine.IsValidEngine(m_engine) && AIEngine.IsBuildable(m_engine)) {
				if (AIVehicle.GetEngineType(vehicle_id) == m_engine) {
					clone_vehicle_id = vehicle_id;
				}
			}
			if (AIVehicle.GetGroupID(vehicle_id) == m_group && AIGroup.IsValidGroup(m_group)) {
				share_orders_vid = vehicle_id;
			}
		}

		local airport1_type = AIAirport.GetAirportType(m_airportFrom);
		local airport2_type = AIAirport.GetAirportType(m_airportTo);
		local hangar1 = airport1_type == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(m_airportTo) : AIAirport.GetHangarOfAirport(m_airportFrom);
		local hangar2 = airport2_type == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(m_airportFrom) : AIAirport.GetHangarOfAirport(m_airportTo);
		local best_hangar = skip_order == true ? hangar2 : hangar1;

		local new_vehicle = AIVehicle.VEHICLE_INVALID;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			new_vehicle = TestBuildVehicleWithRefit().TryBuild(best_hangar, this.m_engine, Utils.getCargoId(m_cargoClass));
		} else {
			new_vehicle = TestCloneVehicle().TryClone(best_hangar, clone_vehicle_id, (AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id) ? true : false);
		}

		if (AIVehicle.IsValidVehicle(new_vehicle)) {
			m_vehicleList.rawset(new_vehicle, 2);
			local vehicle_ready_to_start = false;
			local order_1 = AIAirport.IsHangarTile(m_airportFrom) ? AIMap.GetTileIndex(AIMap.GetTileX(m_airportFrom), AIMap.GetTileY(m_airportFrom) + 1) : m_airportFrom;
			local order_2 = AIAirport.IsHangarTile(m_airportTo) ? AIMap.GetTileIndex(AIMap.GetTileX(m_airportTo), AIMap.GetTileY(m_airportTo) + 1) : m_airportTo;
			if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					local load_mode = AIController.GetSetting("air_load_mode");
					if (AIOrder.AppendOrder(new_vehicle, order_1, (load_mode == 0 ? AIOrder.OF_FULL_LOAD_ANY : AIOrder.OF_NONE)) &&
							AIOrder.AppendOrder(new_vehicle, order_2, (load_mode == 0 ? AIOrder.OF_FULL_LOAD_ANY : AIOrder.OF_NONE))) {
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
				if (AIMap.DistanceSquare(best_hangar, m_airportFrom) > AIMap.DistanceSquare(best_hangar, m_airportTo)) {
					AIOrder.SkipToOrder(new_vehicle, 1);
				}
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
	local count_interval = WrightAI.GetEngineRealFakeDist(m_engine, AirBuildManager.DAYS_INTERVAL);
		local fakedist = WrightAI.DistanceRealFake(m_airportFrom, m_airportTo);
		local airport1_type = AIAirport.GetAirportType(m_airportFrom);
		local airport2_type = AIAirport.GetAirportType(m_airportTo);
		local aircraft_type = AIEngine.GetPlaneType(m_engine);
		return (count_interval > 0 ? (fakedist / count_interval) : 0) + WrightAI.GetNumTerminals(aircraft_type, airport1_type) + WrightAI.GetNumTerminals(aircraft_type, airport2_type);
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

		local fakedist = WrightAI.DistanceRealFake(m_airportFrom, m_airportTo);
		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		local buyVehicleCount = max(0, (infrastructure ? 7 : 2) - numvehicles);

		if (buyVehicleCount > optimalVehicleCount - numvehicles) {
			buyVehicleCount = optimalVehicleCount - numvehicles;
		}

		for (local i = 0; i < buyVehicleCount; ++i) {
			local old_lastVehicleAdded = -m_lastVehicleAdded;
			if (!infrastructure && (old_lastVehicleAdded > 0 && AIDate.GetCurrentDate() - old_lastVehicleAdded <= 3)) {
				break;
			}
			m_lastVehicleAdded = 0;
			local added_vehicle = addVehicle(true, (numvehicles % 2) == 1);
			if (added_vehicle != null) {
				local nameFrom = AIBaseStation.GetName(AIStation.GetStationID(m_airportFrom));
				local nameTo = AIBaseStation.GetName(AIStation.GetStationID(m_airportTo));
				numvehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on new route from " + (numvehicles % 2 == 1 ? nameTo : nameFrom) + " to " + (numvehicles % 2 == 1 ? nameFrom : nameTo) + "! (" + numvehicles + "/" + optimalVehicleCount + " aircraft, " + fakedist + " realfake tiles)");
				if (buyVehicleCount > 1) {
					m_lastVehicleAdded *= -1;
					if (!infrastructure) break;
				}
			} else {
				break;
			}
		}
		if (numvehicles < optimalVehicleCount && buyVehicleCount > 1 && m_lastVehicleAdded >= 0) {
			m_lastVehicleAdded = 0;
		}
		return numvehicles - numvehicles_before;
	}

	function sendVehicleToDepot(vehicle_id) {
		if (AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotAirGroup[0] && AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotAirGroup[1] && AIVehicle.GetState(vehicle_id) != AIVehicle.VS_CRASHED) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			local airport1_hangars = AIAirport.GetNumHangars(m_airportFrom) != 0;
			local airport2_hangars = AIAirport.GetNumHangars(m_airportTo) != 0;
			if (!(airport1_hangars && airport2_hangars)) {
				if (airport1_hangars) {
					AIOrder.SkipToOrder(vehicle_id, 0);
				} else {
					AIOrder.SkipToOrder(vehicle_id, 1);
				}
			}
			if (!AIVehicle.IsStoppedInDepot(vehicle_id) && !AIVehicle.SendVehicleToDepot(vehicle_id)) {
				AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
				return 0;
			}
			m_lastVehicleRemoved = AIDate.GetCurrentDate();

			AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_airportFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_airportTo)) + " has been sent to its depot!");

			return 1;
		}

		return 0;
	}

	function sendNegativeProfitVehiclesToDepot() {
		if (m_lastVehicleAdded <= 0 || AIDate.GetCurrentDate() - m_lastVehicleAdded <= 30) return;
//		AILog.Info("sendNegativeProfitVehiclesToDepot . m_lastVehicleAdded = " + m_lastVehicleAdded + "; " + AIDate.GetCurrentDate() + " - " + m_lastVehicleAdded + " = " + (AIDate.GetCurrentDate() - m_lastVehicleAdded) + " < 45" + " - " + AIBaseStation.GetName(AIStation.GetStationID(m_airportFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_airportTo)));

//		if (AIDate.GetCurrentDate() - m_lastVehicleRemoved <= 30) return;

		ValidateVehicleList();

		foreach (vehicle, _ in m_vehicleList) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (sendVehicleToDepot(vehicle)) {
					if (!AIGroup.MoveVehicle(m_sentToDepotAirGroup[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotAirGroup[0]);
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
		local station1 = AIStation.GetStationID(m_airportFrom);
		local station2 = AIStation.GetStationID(m_airportTo);
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
						if (!AIGroup.MoveVehicle(m_sentToDepotAirGroup[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotAirGroup[0]);
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

				AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_airportFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_airportTo)) + " has been sold!");
			}
		}

		sentToDepotList = this.sentToDepotList(1);

		for (local vehicle = sentToDepotList.Begin(); !sentToDepotList.IsEnd(); vehicle = sentToDepotList.Next()) {
			if (m_vehicleList.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local skip_to_order = AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT);
				sellVehicle(vehicle);

				local renewed_vehicle = addVehicle(true, skip_to_order);
				if (renewed_vehicle != null) {
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(skip_to_order < 1 ? m_airportFrom : m_airportTo)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(skip_to_order < 1 ? m_airportTo : m_airportFrom)) + " has been renewed!");
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

		if (AIDate.GetCurrentDate() - m_lastVehicleAdded < 90) {
			return 0;
		}

		ValidateVehicleList();
		local numvehicles = m_vehicleList.len();
		local numvehicles_before = numvehicles;

		local optimalVehicleCount = optimalVehicleCount();
		if (numvehicles >= optimalVehicleCount && maxed_out_num_vehs) {
			return 0;
		}

		local best_route_profit = null;
		local youngest_route_aircraft = null;
		foreach (v, _ in m_vehicleList) {
			local age = AIVehicle.GetAge(v);
			if (youngest_route_aircraft == null || age < youngest_route_aircraft) {
				youngest_route_aircraft = age;
			}
			local profit = AIVehicle.GetProfitLastYear(v) + AIVehicle.GetProfitThisYear(v);
			if (best_route_profit == null || profit > best_route_profit) {
				best_route_profit = profit;
			}
		}

		/* This route doesn't seem to be profitable. Stop adding more aircraft */
		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		local airport1_type = AIAirport.GetAirportType(m_airportFrom);
		local airport2_type = AIAirport.GetAirportType(m_airportTo);
		if (best_route_profit != null && best_route_profit - infrastructure * (AIAirport.GetMonthlyMaintenanceCost(airport1_type) + AIAirport.GetMonthlyMaintenanceCost(airport2_type)) * 12 / optimalVehicleCount < 10000) {
//			AILog.Info("This route doesn't seem to be profitable. Stop adding more aircraft " + (best_route_profit - infrastructure * (AIAirport.GetMonthlyMaintenanceCost(airport1_type) + AIAirport.GetMonthlyMaintenanceCost(airport2_type)) * 12 / optimalVehicleCount) + " youngest_route_aircraft = " + youngest_route_aircraft);

			if (youngest_route_aircraft > 730 && numvehicles > 2) {
				/* Send the vehicles to depot if we didn't do so yet */
				local airport1_hangars = AIAirport.GetNumHangars(m_airportFrom) != 0;
				local airport2_hangars = AIAirport.GetNumHangars(m_airportTo) != 0;
				foreach (vehicle, _ in m_vehicleList) {
					if (AIVehicle.GetGroupID(vehicle) != m_sentToDepotAirGroup[0] && AIVehicle.GetState(vehicle) != AIVehicle.VS_CRASHED) {
						if (AIVehicle.GetGroupID(vehicle) != m_sentToDepotAirGroup[1]) {
							if (!(airport1_hangars && airport2_hangars)) {
								if (airport1_hangars) {
									AIOrder.SkipToOrder(vehicle, 0);
								} else {
									AIOrder.SkipToOrder(vehicle, 1);
								}
							}
							if (AIVehicle.SendVehicleToDepot(vehicle)) {
								AILog.Info("Sending " + AIVehicle.GetName(vehicle) + " to hangar to close unprofitable route.");
								if (!AIGroup.MoveVehicle(m_sentToDepotAirGroup[0], vehicle)) {
									AILog.Error("Failed to move vehicle " + AIVehicle.GetName(vehicle) + " to group " + m_sentToDepotAirGroup[0]);
								} else {
									m_vehicleList.rawset(vehicle, 0);
								}
							}
						} else {
							AILog.Info("Sending " + AIVehicle.GetName(vehicle) + " to hangar to close unprofitable route.");
							if (!AIGroup.MoveVehicle(m_sentToDepotAirGroup[0], vehicle)) {
								AILog.Error("Failed to move vehicle " + AIVehicle.GetName(vehicle) + " to group " + m_sentToDepotAirGroup[0]);
							} else {
								m_vehicleList.rawset(vehicle, 0);
							}
						}
					}
				}
			}
			return 0;
		}

		/* Do not build a new vehicle once one of the airports becomes unavailable (small airport) */
		if (!infrastructure && (!AIAirport.IsValidAirportType(airport1_type) || !AIAirport.IsValidAirportType(airport2_type))) {
			return 0;
		}

		/* Do not build a new vehicle anymore once helidepots become available for routes where one of the airports isn't dedicated for helicopters */
		if (AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) || AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT)) {
			if (airport1_type == AIAirport.AT_HELIPORT && airport2_type != AIAirport.AT_HELISTATION && airport2_type != AIAirport.AT_HELIDEPOT ||
					airport2_type == AIAirport.AT_HELIPORT && airport1_type != AIAirport.AT_HELISTATION && airport1_type != AIAirport.AT_HELIDEPOT) {
				return 0;
			}
		}

		local cargoId = Utils.getCargoId(m_cargoClass);
		local station1 = AIStation.GetStationID(m_airportFrom);
		local station2 = AIStation.GetStationID(m_airportTo);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargoId);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargoId);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargoId);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargoId);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

		local engine_capacity = Utils.GetCapacity(m_engine, cargoId);
		local capacity_check = infrastructure ? min(engine_capacity, 100) : engine_capacity;

		if (cargoWaiting1 < capacity_check && cargoWaiting2 < capacity_check) {
			return 0;
		}

		local number_to_add = max (1, (cargoWaiting1 > cargoWaiting2 ? cargoWaiting1 : cargoWaiting2) / engine_capacity);
		local fakedist = WrightAI.DistanceRealFake(m_airportFrom, m_airportTo);
		while(number_to_add) {
			number_to_add--;
			local added_vehicle = addVehicle(true, cargoWaiting1 <= cargoWaiting2);
			if (added_vehicle != null) {
				numvehicles++;
				local skipped_order = false;
				if (cargoWaiting1 > cargoWaiting2) {
					cargoWaiting1 -= engine_capacity;
				} else {
					cargoWaiting2 -= engine_capacity;
					skipped_order = true;
				}
				AILog.Info("Added " + AIEngine.GetName(m_engine) + " on existing route from " + AIBaseStation.GetName(skipped_order ? station2 : station1) + " to " + AIBaseStation.GetName(skipped_order ? station1 : station2) + "! (" + numvehicles + "/" + optimalVehicleCount + " aircraft" + (numvehicles != 1 ? "s" : "") + ", " + fakedist + " fakedist tiles)");
				if (numvehicles >= optimalVehicleCount) {
					number_to_add = 0;
				}
			}
		}
		return numvehicles - numvehicles_before;
	}

	function renewVehicles() {
		ValidateVehicleList();
		local engine_price = AIEngine.GetPrice(this.m_engine);
		local count = 1 + AIGroup.GetNumVehicles(m_sentToDepotAirGroup[1], AIVehicle.VT_AIR);

		foreach (vehicle, _ in this.m_vehicleList) {
			if (AIVehicle.GetAgeLeft(vehicle) <= 365 || AIVehicle.GetEngineType(vehicle) != this.m_engine && Utils.HasMoney(2 * engine_price * count)) {
				if (sendVehicleToDepot(vehicle)) {
					count++;
					if (!AIGroup.MoveVehicle(m_sentToDepotAirGroup[1], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotAirGroup[1]);
					} else {
						m_vehicleList.rawset(vehicle, 1);
					}
				}
			}
		}
	}

	function removeIfUnserviced() {
		ValidateVehicleList();
		if (this.m_vehicleList.len() == 0 && (((!AIEngine.IsValidEngine(m_engine) || !AIEngine.IsBuildable(m_engine)) && m_lastVehicleAdded == 0) ||
				(AIDate.GetCurrentDate() - m_lastVehicleAdded >= 90) && m_lastVehicleAdded > 0)) {
			m_activeRoute = false;

			local stationFrom_name = AIBaseStation.GetName(AIStation.GetStationID(m_airportFrom));
			local fromTiles = AITileList_StationType(AIStation.GetStationID(m_airportFrom), AIStation.STATION_AIRPORT);
			for (local tile = fromTiles.Begin(); !fromTiles.IsEnd(); tile = fromTiles.Next()) {
				LuDiAIAfterFix().scheduledRemovals.AddItem(tile, 0);
				break;
			}

			local stationTo_name = AIBaseStation.GetName(AIStation.GetStationID(m_airportTo));
			local toTiles = AITileList_StationType(AIStation.GetStationID(m_airportTo), AIStation.STATION_AIRPORT);
			for (local tile = toTiles.Begin(); !toTiles.IsEnd(); tile = toTiles.Next()) {
				LuDiAIAfterFix().scheduledRemovals.AddItem(tile, 0);
				break;
			}

			if (AIGroup.IsValidGroup(m_group)) {
				AIGroup.DeleteGroup(m_group);
			}
			AILog.Warning("Removing unserviced air route from " + stationFrom_name + " to " + stationTo_name);
			return true;
		}
		return false;
	}

	function GroupVehicles() {
		foreach (vehicle, _ in this.m_vehicleList) {
			if (AIVehicle.GetGroupID(vehicle) != AIGroup.GROUP_DEFAULT && AIVehicle.GetGroupID(vehicle) != m_sentToDepotAirGroup[0] && AIVehicle.GetGroupID(vehicle) != m_sentToDepotAirGroup[1]) {
				if (!AIGroup.IsValidGroup(m_group)) {
					m_group = AIVehicle.GetGroupID(vehicle);
					break;
				}
			}
		}

		if (!AIGroup.IsValidGroup(m_group)) {
			m_group = AIGroup.CreateGroup(AIVehicle.VT_AIR, AIGroup.GROUP_INVALID);
			if (AIGroup.IsValidGroup(m_group)) {
				local a1 = AIAirport.GetAirportType(m_airportFrom);
				local a2 = AIAirport.GetAirportType(m_airportTo);
				local a = "L";
				if (a1 == AIAirport.AT_COMMUTER || a1 == AIAirport.AT_SMALL || a2 == AIAirport.AT_COMMUTER || a2 == AIAirport.AT_SMALL) {
					a = "S";
				}
				if (a1 == AIAirport.AT_HELISTATION || a1 == AIAirport.AT_HELIDEPOT || a1 == AIAirport.AT_HELIPORT || a2 == AIAirport.AT_HELISTATION || a2 == AIAirport.AT_HELIDEPOT || a2 == AIAirport.AT_HELIPORT) {
					a = "H";
				}
				AIGroup.SetName(m_group, a + WrightAI.DistanceRealFake(m_airportFrom, m_airportTo) + ": " + m_airportFrom + " - " + m_airportTo);
				AILog.Info("Created " + AIGroup.GetName(m_group) + " for air route from " + AIStation.GetName(AIStation.GetStationID(m_airportFrom)) + " to " + AIStation.GetName(AIStation.GetStationID(m_airportTo)));
			}
		}

		return m_group;
	}

	function saveRoute() {
		return [m_cityFrom, m_cityTo, m_airportFrom, m_airportTo, m_cargoClass, m_lastVehicleAdded, m_lastVehicleRemoved, m_activeRoute, m_sentToDepotAirGroup, m_group];
	}

	function loadRoute(data) {
		local cityFrom = data[0];
		local cityTo = data[1];
		local airportFrom = data[2];
		local airportTo = data[3];

		local cargoClass = data[4];

		local sentToDepotAirGroup = data[8];

		local route = AirRoute(cityFrom, cityTo, airportFrom, airportTo, cargoClass, sentToDepotAirGroup, 1);

		route.m_lastVehicleAdded = data[5];
		route.m_lastVehicleRemoved = data[6];
		route.m_activeRoute = data[7];
		route.m_group = data[9];

		local vehicleList = AIVehicleList_Station(AIStation.GetStationID(route.m_airportFrom));
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_AIR) {
				route.m_vehicleList.rawset(v, 2);
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotAirGroup[0]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_AIR) {
				if (route.m_vehicleList.rawin(v)) {
					route.m_vehicleList.rawset(v, 0);
				}
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotAirGroup[1]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_AIR) {
				if (route.m_vehicleList.rawin(v)) {
					route.m_vehicleList.rawset(v, 1);
				}
			}
		}

		return route;
	}
}
