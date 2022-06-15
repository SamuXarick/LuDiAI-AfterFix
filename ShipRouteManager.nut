require("ShipBuildManager.nut");

class ShipRouteManager {
	m_townRouteArray = null;
	m_sentToDepotWaterGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	constructor(sentToDepotWaterGroup, best_routes_built) {
		m_townRouteArray = [];
		m_sentToDepotWaterGroup = sentToDepotWaterGroup;
		m_best_routes_built = best_routes_built;
	}

	function buildRoute(shipBuildManager, cityFrom, cityTo, cargoClass, cheaperRoute, best_routes_built) {
		local route = shipBuildManager.buildWaterRoute(cityFrom, cityTo, cargoClass, cheaperRoute, m_sentToDepotWaterGroup, best_routes_built);
		if (route != null && route != 0) {
			m_townRouteArray.append(route);
			shipBuildManager.setRouteFinish();
			return [1, route.m_dockFrom, route.m_dockTo];
		}

		return [route, null, null];
	}


	function getShipCount() {
		local list = AIVehicleList();
		local vehiclecount = 0;
		for (local vehicle = list.Begin(); !list.IsEnd(); vehicle = list.Next()) {
			if (AIVehicle.GetVehicleType(vehicle) == AIVehicle.VT_WATER) {
				vehiclecount++;
			}
		}

		return vehiclecount;
	}

	function townRouteExists(cityFrom, cityTo, cargoClass) {
		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			if (TownPair(cityFrom, cityTo, cargoClass).isEqual(m_townRouteArray[i].m_cityFrom, m_townRouteArray[i].m_cityTo, m_townRouteArray[i].m_cargoClass)) {
//				AILog.Info("townRouteExists from " + AITown.GetName(cityFrom) + " to " + AITown.GetName(cityTo));
				return 1;
			}
		}

		return 0;
	}

	//the highest last years profit out of all vehicles
	function highestProfitLastYear() {
		local maxAllRoutesProfit = null;

		for (local i = 0; i < this.m_townRouteArray.len(); ++i) {
			local maxRouteProfit = 0;
			foreach (vehicle, _ in this.m_townRouteArray[i].m_vehicleList) {
				local profit = AIVehicle.GetProfitLastYear(vehicle);
				if (maxRouteProfit < profit) {
					maxRouteProfit = profit;
				}
			}

			if (maxAllRoutesProfit == null || maxRouteProfit > maxAllRoutesProfit) {
				maxAllRoutesProfit = maxRouteProfit;
			}
		}

		return maxAllRoutesProfit;
	}

	//won't build any new stations if 1
	function hasMaxStationCount(cityFrom, cityTo, cargoClass) {
//		return 0;

		local maxTownStationFrom = (1 + AITown.GetPopulation(cityFrom) / 1000).tointeger();
		local maxTownStationTo = (1 + AITown.GetPopulation(cityTo) / 1000).tointeger();

		local cityFromCount = 0;
		local cityToCount = 0;

		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			if (m_townRouteArray[i].m_cityFrom == cityFrom || m_townRouteArray[i].m_cityFrom == cityTo) {
				if (m_townRouteArray[i].m_cargoClass == cargoClass) ++cityFromCount;
			}

			if (m_townRouteArray[i].m_cityTo == cityTo || m_townRouteArray[i].m_cityTo == cityFrom) {
				if (m_townRouteArray[i].m_cargoClass == cargoClass) ++cityToCount;
			}
		}
//		AILog.Info("cityFrom = " + AITown.GetName(cityFrom) + " ; cityFromCount = " + cityFromCount + " ; maxTownStationFrom = " + maxTownStationFrom + " ; cityTo = " + AITown.GetName(cityTo) + " ; cityToCount = " + cityToCount + " ; maxTownStationTo = " + maxTownStationTo);

		if ((cityFromCount >= maxTownStationFrom) || (cityToCount >= maxTownStationTo)) {
			return 1;
		}

		return 0;
	}

	function saveRouteManager() {
		local array = [];
		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			array.append(m_townRouteArray[i].saveRoute());
		}

		return [array, m_sentToDepotWaterGroup, m_best_routes_built];
	}

	function loadRouteManager(data) {
		if (m_townRouteArray == null) {
			m_townRouteArray = [];
		}

		local routearray = data[0];

		local buoys = 0;
		for (local i = 0; i < routearray.len(); i++) {
			local route = ShipRoute.loadRoute(routearray[i]);
			m_townRouteArray.append(route[0]);
			buoys += route[1];
		}
		AILog.Info("Loaded " + m_townRouteArray.len() + " water routes with " + buoys + " buoys.");

		m_sentToDepotWaterGroup = data[1];
		m_best_routes_built = data[2];
	}

}
