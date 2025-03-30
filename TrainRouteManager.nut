require("TrainBuildManager.nut");

class RailRouteManager {
	m_townRouteArray = null;
	m_sentToDepotRailGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	constructor(sentToDepotRailGroup, best_routes_built) {
		m_townRouteArray = [];
		m_sentToDepotRailGroup = sentToDepotRailGroup;
		m_best_routes_built = best_routes_built;
	}

	function BuildRoute(railBuildManager, cityFrom, cityTo, cargoClass, best_routes_built, railtype) {
		local route = railBuildManager.BuildRailRoute(cityFrom, cityTo, cargoClass, m_sentToDepotRailGroup, best_routes_built, railtype);
		if (route != null && route != 0) {
			m_townRouteArray.append(route);
			railBuildManager.SetRouteFinished();
			return [1, route.m_stationFrom, route.m_stationTo];
		}

		return [route, null, null];
	}


	function GetTrainCount() {
		return AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_RAIL);
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

		return [array, m_sentToDepotRailGroup, m_best_routes_built];
	}

	function LoadRouteManager(data) {
		if (m_townRouteArray == null) {
			m_townRouteArray = [];
		}

		local routearray = data[0];

		local bridges = 0;
		for (local i = 0; i < routearray.len(); i++) {
			local route = RailRoute.LoadRoute(routearray[i]);
			m_townRouteArray.append(route[0]);
			bridges += route[1];
		}
		AILog.Info("Loaded " + m_townRouteArray.len() + " rail routes with " + bridges + " bridges.");

		m_sentToDepotRailGroup = data[1];
		m_best_routes_built = data[2];
	}

}
