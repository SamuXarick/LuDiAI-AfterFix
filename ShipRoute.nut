require("ShipRouteManager.nut");

class ShipRoute extends ShipRouteManager {
	MAX_VEHICLE_COUNT_MODE = AIController.GetSetting("water_cap_mode");
	COUNT_INTERVAL = 20;
	STATION_RATING_INTERVAL = 40;

	m_cityFrom = null;
	m_cityTo = null;
	m_dockFrom = null;
	m_dockTo = null;
	m_depotTile = null;
	m_buoyTiles = null;
	m_cargoClass = null;

	m_engine = null;
	m_group = null;

	m_lastVehicleAdded = null;
	m_lastVehicleRemoved = null;

	m_sentToDepotWaterGroup = null;

	m_activeRoute = null;

	m_vehicleList = null;


	constructor(cityFrom, cityTo, dockFrom, dockTo, depotTile, buoyTiles, cargoClass, sentToDepotWaterGroup, isLoaded = 0) {
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_dockFrom = dockFrom;
		m_dockTo = dockTo;
		m_depotTile = depotTile;
		m_buoyTiles = buoyTiles;
		m_cargoClass = cargoClass;

		m_engine = GetShipEngine(cargoClass);
		m_group = AIGroup.GROUP_INVALID;
		m_sentToDepotWaterGroup = sentToDepotWaterGroup;

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
	function GetEngineList(cargoClass);
	function GetShipEngine(cargoClass);
	function addremoveVehicleToRoute();

	function ValidateVehicleList() {
		local stationFrom = AIStation.GetStationID(m_dockFrom);
		local stationTo = AIStation.GetStationID(m_dockTo);

		local removelist = AIList();
		foreach (v, _ in m_vehicleList) {
			if (AIVehicle.IsValidVehicle(v)) {
				if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
					local num_orders = AIOrder.GetOrderCount(v);
					if (num_orders >= 2) {
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

	function GetEngineList(cargoClass) {
		local cargo = Utils.getCargoId(cargoClass);

		local tempList = AIEngineList(AIVehicle.VT_WATER);
		local engineList = AIList();
		for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
			if (AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, cargo)) {
				engineList.AddItem(engine, 0);
			}
		}

		return engineList;
	}

	function GetShipEngine(cargoClass) {
		local engineList = GetEngineList(cargoClass);
		if (engineList.Count() == 0) return m_engine == null ? -1 : m_engine;

		local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
		local cargo = Utils.getCargoId(cargoClass);

		local distance = AIMap.DistanceManhattan(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo));
		local best_income = null;
		local best_engine = null;
		for (local engine = engineList.Begin(); !engineList.IsEnd(); engine = engineList.Next()) {
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
			local max_speed = AIEngine.GetMaxSpeed(engine);
			local days_in_transit = (distance * 256 * 16) / (2 * 74 * max_speed);
			local running_cost = AIEngine.GetRunningCost(engine);
			local capacity = ::caches.GetBuildWithRefitCapacity(m_depotTile, engine, cargo);
			local income = ((capacity * AICargo.GetCargoIncome(cargo, distance, days_in_transit) - running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
//			AILog.Info("Engine: " + AIEngine.GetName(engine) + "; Capacity: " + capacity + "; Max Speed: " + max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + running_cost + "; Distance: " + distance + "; Income: " + income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_engine = engine;
			}
		}

		return best_engine == null ? -1 : best_engine;
	}

	function updateEngine() {
		if (!m_activeRoute) return;

		m_engine = GetShipEngine(m_cargoClass);
	}

	function AppendBuoyOrders(vehicle, reverse = false, start_from_depot = true) {
		if (m_buoyTiles.len() == 1) return true; // only ship depot is included

		local depot = start_from_depot;
		if (!reverse) {
			for (local i = 0; i < m_buoyTiles.len(); i++) {
				local tile = m_buoyTiles[i];
				assert(AIMarine.IsBuoyTile(tile) || AIMarine.IsWaterDepotTile(tile));

				if (depot && tile != m_depotTile) continue;
				if (tile == m_depotTile) {
					depot = !depot;
					continue;
				}
				if (!AIOrder.AppendOrder(vehicle, tile, AIOrder.OF_NONE)) {
					return false;
				}
			}
		} else {
			for (local i = m_buoyTiles.len() - 1; i >= 0; i--) {
				local tile = m_buoyTiles[i];
				assert(AIMarine.IsBuoyTile(tile) || AIMarine.IsWaterDepotTile(tile))

				if (depot && tile != m_depotTile) continue;
				if (tile == m_depotTile) {
					depot = !depot;
					continue;
				}
				if (!AIOrder.AppendOrder(vehicle, tile, AIOrder.OF_NONE)) {
					return false;
				}
			}
		}

		return true;
	}

	function sellVehicle(vehicle) {
		m_vehicleList.rawdelete(vehicle);
		AIVehicle.SellVehicle(vehicle);
		Utils.RepayLoan();
	}

	function addVehicle(return_vehicle = false) {
		ValidateVehicleList();
		if (MAX_VEHICLE_COUNT_MODE != 2 && m_vehicleList.len() >= optimalVehicleCount()) {
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

		local new_vehicle = AIVehicle.VEHICLE_INVALID;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			new_vehicle = TestBuildVehicleWithRefit().TryBuild(this.m_depotTile, this.m_engine, Utils.getCargoId(m_cargoClass));
		} else {
			new_vehicle = TestCloneVehicle().TryClone(this.m_depotTile, clone_vehicle_id, (AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id) ? true : false);
		}

		if (AIVehicle.IsValidVehicle(new_vehicle)) {
			m_vehicleList.rawset(new_vehicle, 2);
			local vehicle_ready_to_start = false;
			local depot_order_flags = AIOrder.OF_SERVICE_IF_NEEDED;
			local load_mode = AIController.GetSetting("water_load_mode");
			if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					if (AIOrder.AppendOrder(new_vehicle, m_depotTile, depot_order_flags) &&
							AppendBuoyOrders(new_vehicle, true, true) &&
							AIOrder.AppendOrder(new_vehicle, m_dockFrom, AIOrder.OF_NONE) &&
							(load_mode == 0 && AIOrder.AppendConditionalOrder(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 1) && AIOrder.SetOrderCondition(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.OC_LOAD_PERCENTAGE) && AIOrder.SetOrderCompareFunction(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.CF_EQUALS) && AIOrder.SetOrderCompareValue(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, 0) || true) &&
							AppendBuoyOrders(new_vehicle, false, false) &&
							AIOrder.AppendOrder(new_vehicle, m_depotTile, depot_order_flags) &&
							AppendBuoyOrders(new_vehicle, false, true) &&
							AIOrder.AppendOrder(new_vehicle, m_dockTo, AIOrder.OF_NONE) &&
							(load_mode == 0 && AIOrder.AppendConditionalOrder(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 1) && AIOrder.SetOrderCondition(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.OC_LOAD_PERCENTAGE) && AIOrder.SetOrderCompareFunction(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.CF_EQUALS) && AIOrder.SetOrderCompareValue(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, 0) || true) &&
							AppendBuoyOrders(new_vehicle, true, false)) {
						vehicle_ready_to_start = true;
					} else {
						sellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						local new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
						local new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle));
						if (new_vehicle_order_depot1_flags != depot_order_flags || new_vehicle_order_depot2_flags != depot_order_flags) {
							AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_depot1_flags + "/" + new_vehicle_order_depot2_flags + " != " + depot_order_flags + "/" + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
							sellVehicle(new_vehicle);
							return null;
						} else {
							vehicle_ready_to_start = true;
						}
					} else {
						AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						sellVehicle(new_vehicle);
						return null;
					}
				}
			} else {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					local new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					local new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle));
					if (new_vehicle_order_depot1_flags != depot_order_flags) {
						if (!AIOrder.SetOrderFlags(new_vehicle, 0, depot_order_flags)) {
							sellVehicle(new_vehicle);
							return null;
						}
					}
					new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					if (new_vehicle_order_depot2_flags != depot_order_flags) {
						if (!AIOrder.SetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle), depot_order_flags)) {
							sellVehicle(new_vehicle);
							return null;
						}
					}
					new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle));
					if (new_vehicle_order_depot1_flags == depot_order_flags && new_vehicle_order_depot2_flags == depot_order_flags) {
						if (load_mode == 0 && !HasConditionalOrders(new_vehicle)) {
							if (!AddConditionalOrders(new_vehicle)) {
								AILog.Error("Failed to add conditional orders to " + AIVehicle.GetName(new_vehicle));
								sellVehicle(new_vehicle);
								return null;
							}
						}
						vehicle_ready_to_start = true;
					} else {
						AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_depot1_flags + "/" + new_vehicle_order_depot2_flags + " != " + depot_order_flags + "/" + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
						sellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (clone_vehicle_id != share_orders_vid) {
						if (!AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
							AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
							sellVehicle(new_vehicle);
							return null;
						}
					}
					local new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					local new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle));
					if (new_vehicle_order_depot1_flags != depot_order_flags || new_vehicle_order_depot2_flags != depot_order_flags) {
						AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_depot1_flags + "/" + new_vehicle_order_depot2_flags + " != " + depot_order_flags + "/" + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
						sellVehicle(new_vehicle);
						return null;
					} else {
						vehicle_ready_to_start = true;
					}
				}
			}
			if (vehicle_ready_to_start) {
				if (!return_vehicle) AIVehicle.StartStopVehicle(new_vehicle);
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
		if (MAX_VEHICLE_COUNT_MODE == 0) return 10;

		local dockDistance = AITile.GetDistanceManhattanToTile(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo));
//		AILog.Info("dockDistance = " + dockDistance);
		local count_interval = (AIEngine.GetMaxSpeed(this.m_engine) * 2 * 74 * STATION_RATING_INTERVAL) / (256 * 16);
//		AILog.Info("count_interval = " + count_interval + "; MaxSpeed = " + AIEngine.GetMaxSpeed(this.m_engine));
		local vehicleCount = 1 + (count_interval > 0 ? (2 * dockDistance / count_interval) : 0);
//		AILog.Info("vehicleCount = " + vehicleCount);

		return vehicleCount;
	}

	function GetSecondDepotOrderIndex(vehicle) {
		local order_count = AIOrder.GetOrderCount(vehicle);

		local depot_order_count = 0;
		for (local i = 0; i < order_count; i++) {
			if (AIOrder.IsGotoDepotOrder(vehicle, i)) {
				depot_order_count++;
			}
			if (depot_order_count == 2) {
				return i;
			}
		}
		AILog.Error(AIVehicle.GetName(vehicle_id) + " doesn't have a second ship depot order.");
		return 0;
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

		local routedist = AITile.GetDistanceManhattanToTile(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo));

		local buyVehicleCount = max((((numvehicles + 1) * 2) >= optimalVehicleCount ? 1 : 2), (optimalVehicleCount / 2 - numvehicles))

		if (buyVehicleCount > optimalVehicleCount - numvehicles) {
			buyVehicleCount = optimalVehicleCount - numvehicles;
		}

		for (local i = 0; i < buyVehicleCount; ++i) {
			local old_lastVehicleAdded = -m_lastVehicleAdded;
			if (old_lastVehicleAdded > 0 && AIDate.GetCurrentDate() - old_lastVehicleAdded <= COUNT_INTERVAL) {
				break;
			}
			m_lastVehicleAdded = 0;
			local added_vehicle = addVehicle(true);
			if (added_vehicle != null) {
				local nameFrom = AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom));
				local nameTo = AIBaseStation.GetName(AIStation.GetStationID(m_dockTo));
				if (numvehicles % 2 == 1) {
					AIOrder.SkipToOrder(added_vehicle, GetSecondDepotOrderIndex(added_vehicle));
				}
				AIVehicle.StartStopVehicle(added_vehicle);
				numvehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on new route from " + (numvehicles % 2 == 1 ? nameTo : nameFrom) + " to " + (numvehicles % 2 == 1 ? nameFrom : nameTo) + "! (" + numvehicles + "/" + optimalVehicleCount + " ship" + (numvehicles != 1 ? "s" : "") + ", " + routedist + " manhattan tiles)");
				if (buyVehicleCount > 1) {
					m_lastVehicleAdded *= -1;
					break;
				}
			} else {
				break;
			}
		}
		if (numvehicles * 2 < (MAX_VEHICLE_COUNT_MODE == 0 ? 1 : optimalVehicleCount) && m_lastVehicleAdded >= 0) {
			m_lastVehicleAdded = 0;
		}
		return numvehicles - numvehicles_before;
	}

	function RemoveConditionalOrders(vehicle) {
		local order_count = AIOrder.GetOrderCount(vehicle);
		if (order_count == 0) return true;

		local interrupted;
		do {
			interrupted = false;
			order_count = AIOrder.GetOrderCount(vehicle);
			for (local i = 0; i < order_count; i++) {
				if (AIOrder.IsConditionalOrder(vehicle, i)) {
					if (AIOrder.RemoveOrder(vehicle, i)) {
						interrupted = true;
						break;
					} else {
						return false;
					}
				}
			}
		} while(interrupted);

		return true;
	}

	function AddConditionalOrders(vehicle) {
		assert(!HasConditionalOrders(vehicle));
		local order_count = AIOrder.GetOrderCount(vehicle);
		if (order_count == 0) return false;

		local interrupted;
		do {
			interrupted = false;
			order_count = AIOrder.GetOrderCount(vehicle);
			for (local i = 0; i < order_count; i++) {
				if (AIOrder.IsGotoStationOrder(vehicle, i) && !AIOrder.IsConditionalOrder(vehicle, i + 1)) {
					if (AIOrder.InsertConditionalOrder(vehicle, i + 1, i) &&
							AIOrder.SetOrderCondition(vehicle, i + 1, AIOrder.OC_LOAD_PERCENTAGE) &&
							AIOrder.SetOrderCompareFunction(vehicle, i + 1, AIOrder.CF_EQUALS) &&
							AIOrder.SetOrderCompareValue(vehicle, i + 1, 0)) {
						interrupted = true;
						break;
					} else {
						return false;
					}
				}
			}
		} while(interrupted);

		return true;
	}

	function HasConditionalOrders(vehicle) {
		local order_count = AIOrder.GetOrderCount(vehicle);
		if (order_count == 0) return false;

		for (local i = 0; i < order_count; i++) {
			if (AIOrder.IsConditionalOrder(vehicle, i)) {
				return true;
			}
		}
		return false;
	}

	function sendVehicleToDepot(vehicle_id) {
		if (AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotWaterGroup[0] && AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotWaterGroup[1]) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			if (!AIVehicle.IsStoppedInDepot(vehicle_id)) {
				local depot_order_flags = AIOrder.OF_STOP_IN_DEPOT;
				if (!AIVehicle.HasSharedOrders(vehicle_id)) {
					/* Remove conditional orders */
					if (!RemoveConditionalOrders(vehicle_id)) {
						AILog.Info("Failed to remove conditional orders from " + vehicle_name + " when preparing to send it to depot.");
//						AIController.Break(" ");
						return 0;
					} else {
						/* Make the ship stop at depot when executing depot orders. */
						local depotstop1 = AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags);
						local depotstop2 = AIOrder.SetOrderFlags(vehicle_id, GetSecondDepotOrderIndex(vehicle_id), depot_order_flags);
						if (!depotstop1 && !depotstop2) {
							AILog.Error("Failed to send " + vehicle_name + " to depot.");
//							AIController.Break(" ");
							return 0;
						}
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
							/* Remove conditional orders */
							if (!RemoveConditionalOrders(vehicle_id)) {
								AILog.Info("Failed to remove conditional orders from " + vehicle_name + " when preparing to send it to depot.");
//								AIController.Break(" ");
								return 0;
							} else {
								/* Make the ship stop at depot when executing depot orders. */
								local depotstop1 = AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags);
								local depotstop2 = AIOrder.SetOrderFlags(vehicle_id, GetSecondDepotOrderIndex(vehicle_id), depot_order_flags);
								if (!depotstop1 && !depotstop2) {
									AILog.Error("Failed to send " + vehicle_name + " to depot.");
//									AIController.Break(" ");
									return 0;
								}
							}
						} else {
							AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
//							AIController.Break(" ");
							return 0;
						}
					} else {
						AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
//						AIController.Break(" ");
						return 0;
					}
				}
			}
			m_lastVehicleRemoved = AIDate.GetCurrentDate();

			AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)) + " has been sent to its depot!");

			return 1;
		}

		return 0;
	}

	function sendNegativeProfitVehiclesToDepot() {
		if (m_lastVehicleAdded <= 0 || AIDate.GetCurrentDate() - m_lastVehicleAdded <= 30) return;
//		AILog.Info("sendNegativeProfitVehiclesToDepot . m_lastVehicleAdded = " + m_lastVehicleAdded + "; " + AIDate.GetCurrentDate() + " - " + m_lastVehicleAdded + " = " + (AIDate.GetCurrentDate() - m_lastVehicleAdded) + " < 45" + " - " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)));

//		if (AIDate.GetCurrentDate() - m_lastVehicleRemoved <= 30) return;

		ValidateVehicleList();

		foreach (vehicle, _ in m_vehicleList) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (sendVehicleToDepot(vehicle)) {
					if (!AIGroup.MoveVehicle(m_sentToDepotWaterGroup[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotWaterGroup[0]);
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
		local station1 = AIStation.GetStationID(m_dockFrom);
		local station2 = AIStation.GetStationID(m_dockTo);
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
						if (!AIGroup.MoveVehicle(m_sentToDepotWaterGroup[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotWaterGroup[0]);
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

				AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)) + " has been sold!");
			}
		}

		sentToDepotList = this.sentToDepotList(1);

		for (local vehicle = sentToDepotList.Begin(); !sentToDepotList.IsEnd(); vehicle = sentToDepotList.Next()) {
			if (m_vehicleList.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local skip_to_order = AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT);
				sellVehicle(vehicle);

				local renewed_vehicle = addVehicle(true);
				if (renewed_vehicle != null) {
					AIOrder.SkipToOrder(renewed_vehicle, skip_to_order);
					AIVehicle.StartStopVehicle(renewed_vehicle);
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)) + " has been renewed!");
				}
			}
		}
	}

	function GetGroupUsage() {
		local max_capacity = 0;
		local used_capacity = 0;
		local cargoId = Utils.getCargoId(m_cargoClass);
		foreach (v, _ in m_vehicleList) {
			if (AIVehicle.GetGroupID(v) == m_group) {
				max_capacity += AIVehicle.GetCapacity(v, cargoId);
				used_capacity += AIVehicle.GetCargoLoad(v, cargoId);
			}
		}
		if (max_capacity == 0) return 0;
		return 100 * used_capacity / max_capacity;
	}

	function addremoveVehicleToRoute(maxed_out_num_vehs) {
		if (!m_activeRoute) {
			return 0;
		}

		if (m_lastVehicleAdded <= 0) {
			return addVehiclesToNewRoute(m_cargoClass);
		}

		if (MAX_VEHICLE_COUNT_MODE != AIController.GetSetting("water_cap_mode")) {
			MAX_VEHICLE_COUNT_MODE = AIController.GetSetting("water_cap_mode");
//			AILog.Info("MAX_VEHICLE_COUNT_MODE = " + MAX_VEHICLE_COUNT_MODE);
		}

		if (AIDate.GetCurrentDate() - m_lastVehicleAdded < 90) {
			return 0;
		}

		local optimalVehicleCount = optimalVehicleCount();
		ValidateVehicleList();
		local numvehicles = m_vehicleList.len();
		local numvehicles_before = numvehicles;

		if (MAX_VEHICLE_COUNT_MODE != 2 && numvehicles >= optimalVehicleCount && maxed_out_num_vehs) {
			return 0;
		}

		local cargoId = Utils.getCargoId(m_cargoClass);
		local station1 = AIStation.GetStationID(m_dockFrom);
		local station2 = AIStation.GetStationID(m_dockTo);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargoId);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargoId);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargoId);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargoId);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

		local engine_capacity = ::caches.GetCapacity(this.m_engine, cargoId);
		local group_usage = GetGroupUsage();
//		AILog.Info(AIGroup.GetName(this.m_group) + ": usage = " + group_usage + "; engine_capacity = " + engine_capacity + "; cargoWaiting1 = " + cargoWaiting1 + "; cargoWaiting2 = " + cargoWaiting2);

		if ((cargoWaiting1 > engine_capacity || cargoWaiting2 > engine_capacity) && group_usage > 66) {
			local number_to_add = max(1, (cargoWaiting1 > cargoWaiting2 ? cargoWaiting1 : cargoWaiting2) / engine_capacity);
			local routedist = AITile.GetDistanceManhattanToTile(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo));
			while(number_to_add) {
				number_to_add--;
				local added_vehicle = addVehicle(true);
				if (added_vehicle != null) {
					numvehicles++;
					local skipped_order = false;
					if (cargoWaiting1 > cargoWaiting2) {
						cargoWaiting1 -= engine_capacity;
					} else {
						cargoWaiting2 -= engine_capacity;
						AIOrder.SkipToOrder(added_vehicle, GetSecondDepotOrderIndex(added_vehicle));
						skipped_order = true;
					}
					AIVehicle.StartStopVehicle(added_vehicle);
					AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on existing route from " + AIBaseStation.GetName(skipped_order ? station2 : station1) + " to " + AIBaseStation.GetName(skipped_order ? station1 : station2) + "! (" + numvehicles + (MAX_VEHICLE_COUNT_MODE != 2 ? "/" + optimalVehicleCount : "") + " ship" + (numvehicles != 1 ? "s" : "") + ", " + routedist + " manhattan tiles)");
					if (numvehicles >= MAX_VEHICLE_COUNT_MODE != 2 ? 1 : optimalVehicleCount) {
						number_to_add = 0;
					}
				}
			}
		}
		return numvehicles - numvehicles_before;
	}

	function renewVehicles() {
		ValidateVehicleList();
		local engine_price = AIEngine.GetPrice(this.m_engine);
		local count = 1 + AIGroup.GetNumVehicles(m_sentToDepotWaterGroup[1], AIVehicle.VT_WATER);

		foreach (vehicle, _ in this.m_vehicleList) {
//			local vehicle_engine = AIVehicle.GetEngineType(vehicle);
//			if (AIGroup.GetEngineReplacement(m_group, vehicle_engine) != m_engine) {
//				AIGroup.SetAutoReplace(m_group, vehicle_engine, m_engine);
//			}
			if (AIVehicle.GetAgeLeft(vehicle) <= 365 || AIVehicle.GetEngineType(vehicle) != this.m_engine && Utils.HasMoney(2 * engine_price * count)) {
				if (sendVehicleToDepot(vehicle)) {
					count++;
					if (!AIGroup.MoveVehicle(m_sentToDepotWaterGroup[1], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotWaterGroup[1]);
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

			local dockFrom_name = AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom));
			::scheduledRemovalsTable.Ship.rawset(m_dockFrom, 0);

			local dockTo_name = AIBaseStation.GetName(AIStation.GetStationID(m_dockTo));
			::scheduledRemovalsTable.Ship.rawset(m_dockTo, 0);

			::scheduledRemovalsTable.Ship.rawset(m_depotTile, 0);

			for (local i = 0; i < m_buoyTiles.len(); i++) {
				if (AIMarine.IsBuoyTile(m_buoyTiles[i])) {
					::scheduledRemovalsTable.Ship.rawset(m_buoyTiles[i], 0);
				}
			}

			if (AIGroup.IsValidGroup(m_group)) {
				AIGroup.DeleteGroup(m_group);
			}
			AILog.Warning("Removing unserviced water route from " + dockFrom_name + " to " + dockTo_name);
			return true;
		}
		return false;
	}

	function GroupVehicles() {
		foreach (vehicle, _ in this.m_vehicleList) {
			if (AIVehicle.GetGroupID(vehicle) != AIGroup.GROUP_DEFAULT && AIVehicle.GetGroupID(vehicle) != m_sentToDepotWaterGroup[0] && AIVehicle.GetGroupID(vehicle) != m_sentToDepotWaterGroup[1]) {
				if (!AIGroup.IsValidGroup(m_group)) {
					m_group = AIVehicle.GetGroupID(vehicle);
					break;
				}
			}
		}

		if (!AIGroup.IsValidGroup(m_group)) {
			m_group = AIGroup.CreateGroup(AIVehicle.VT_WATER, AIGroup.GROUP_INVALID);
			if (AIGroup.IsValidGroup(m_group)) {
				AIGroup.SetName(m_group, (m_cargoClass == AICargo.CC_PASSENGERS ? "P" : "M") + AIMap.DistanceManhattan(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo)) + ": " + m_dockFrom + " - " + m_dockTo);
				AILog.Info("Created " + AIGroup.GetName(m_group) + " for water route from " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)));
			}
		}

		return m_group;
	}

	function saveRoute() {
		return [m_cityFrom, m_cityTo, m_dockFrom, m_dockTo, m_depotTile, m_buoyTiles, m_cargoClass, m_lastVehicleAdded, m_lastVehicleRemoved, m_activeRoute, m_sentToDepotWaterGroup, m_group/*, m_vehicleList*/];
	}

	function loadRoute(data) {
		local cityFrom = data[0];
		local cityTo = data[1];
		local dockFrom = data[2];
		local dockTo = data[3];
		local depotTile = data[4];
//		AILog.Info("cityFrom = " + AITown.GetName(cityFrom) + "; cityTo = " + AITown.GetName(cityTo) + "; dockFrom = " + AIBaseStation.GetName(AIStation.GetStationID(dockFrom)) + " (" + dockFrom + "); dockTo = " + AIBaseStation.GetName(AIStation.GetStationID(dockTo)) + " (" + dockTo + "); depotTile = " + depotTile);
//		AILog.Info("distFromdepot = " + AIMap.DistanceManhattan(depotTile, Utils.GetDockDockingTile(dockFrom)) + "; distTodepot = " + AIMap.DistanceManhattan(depotTile, Utils.GetDockDockingTile(dockTo)) + "; route dist = " + AIMap.DistanceManhattan(Utils.GetDockDockingTile(dockFrom), Utils.GetDockDockingTile(dockTo)));

		local buoyTiles = data[5];

		local cargoClass = data[6];

		local sentToDepotWaterGroup = data[10];

		local route = ShipRoute(cityFrom, cityTo, dockFrom, dockTo, depotTile, buoyTiles, cargoClass, sentToDepotWaterGroup, 1);

		route.m_lastVehicleAdded = data[7];
		route.m_lastVehicleRemoved = data[8];
		route.m_activeRoute = data[9];
		route.m_group = data[11];

		local vehicleList = AIVehicleList_Station(AIStation.GetStationID(route.m_dockFrom));
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
				route.m_vehicleList.rawset(v, 2);
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotWaterGroup[0]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
				if (route.m_vehicleList.rawin(v)) {
					route.m_vehicleList.rawset(v, 0);
				}
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotWaterGroup[1]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
				if (route.m_vehicleList.rawin(v)) {
					route.m_vehicleList.rawset(v, 1);
				}
			}
		}
//		route.m_vehicleList = data[12];

		return [route, buoyTiles.len()];
	}
}
