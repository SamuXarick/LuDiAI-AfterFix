require("AirBuildManager.nut");

class AirRouteManager {
	m_townRouteArray = null;
	m_sentToDepotAirGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	constructor(sentToDepotAirGroup, best_routes_built) {
		m_townRouteArray = [];
		m_sentToDepotAirGroup = sentToDepotAirGroup;
		m_best_routes_built = best_routes_built;
	}

	function BuildRoute(airRouteManager, airBuildManager, airTownManager, cityFrom, cityTo, cargoClass, best_routes_built, all_routes_built) {
		local route = airBuildManager.BuildAirRoute(airRouteManager, airTownManager, cityFrom, cityTo, cargoClass, m_sentToDepotAirGroup, best_routes_built, all_routes_built);
		if (route != null && route != 0) {
			m_townRouteArray.append(route);
			airBuildManager.SetRouteFinished();
			return [1, route.m_airportFrom, route.m_airportTo];
		}

		return [route, null, null];
	}


	function GetAircraftCount() {
		return AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_AIR);
	}

	function TownRouteExists(cityFrom, cityTo, cargoClass) {
		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			if (TownPair(cityFrom, cityTo, cargoClass).IsEqual(m_townRouteArray[i].m_cityFrom, m_townRouteArray[i].m_cityTo, m_townRouteArray[i].m_cargoClass)) {
//				AILog.Info("TownRouteExists from " + AITown.GetName(cityFrom) + " to " + AITown.GetName(cityTo));
				return 1;
			}
		}

		return 0;
	}

	/* the highest last years profit out of all vehicles */
	function HighestProfitLastYear() {
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

	/* won't build any new stations if 1 */
	function HasMaxStationCount(cityFrom, cityTo, cargoClass) {
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

	function SaveRouteManager() {
		local array = [];
		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			array.append(m_townRouteArray[i].SaveRoute());
		}

		return [array, m_sentToDepotAirGroup, m_best_routes_built];
	}

	function LoadRouteManager(data) {
		if (m_townRouteArray == null) {
			m_townRouteArray = [];
		}

		local routearray = data[0];

		for (local i = 0; i < routearray.len(); i++) {
			local route = AirRoute.LoadRoute(routearray[i]);
			m_townRouteArray.append(route);
		}
		AILog.Info("Loaded " + m_townRouteArray.len() + " air routes.");

		m_sentToDepotAirGroup = data[1];
		m_best_routes_built = data[2];
	}

}
