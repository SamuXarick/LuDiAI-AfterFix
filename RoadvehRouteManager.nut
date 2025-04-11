require("RoadvehBuildManager.nut");

class RoadRouteManager
{
	m_townRouteArray = null;
	m_sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	constructor(sentToDepotRoadGroup, best_routes_built)
	{
		m_townRouteArray = [];
		m_sentToDepotRoadGroup = sentToDepotRoadGroup;
		m_best_routes_built = best_routes_built;
	}

	function BuildRoute(roadBuildManager, cityFrom, cityTo, cargoClass, articulated, best_routes_built)
	{
		local route = roadBuildManager.BuildRoadRoute(cityFrom, cityTo, cargoClass, articulated, m_sentToDepotRoadGroup, best_routes_built);
		if (route != null && route != 0) {
			m_townRouteArray.append(route);
			roadBuildManager.SetRouteFinished();
			return [1, route.m_stationFrom, route.m_stationTo];
		}

		return [route, null, null];
	}


	function GetRoadVehicleCount()
	{
		return AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_ROAD);
	}

	function TownRouteExists(cityFrom, cityTo, cargoClass)
	{
		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			if (TownPair(cityFrom, cityTo, cargoClass).IsEqual(m_townRouteArray[i].m_city_from, m_townRouteArray[i].m_city_to, m_townRouteArray[i].m_cargo_class)) {
//				AILog.Info("TownRouteExists from " + AITown.GetName(cityFrom) + " to " + AITown.GetName(cityTo));
				return true;
			}
		}

		return false;
	}

	/* the highest last years profit out of all vehicles */
	function HighestProfitLastYear()
	{
		local maxAllRoutesProfit = null;

		for (local i = 0; i < this.m_townRouteArray.len(); ++i) {
			local maxRouteProfit = 0;
			foreach (vehicle, _ in this.m_townRouteArray[i].m_vehicle_list) {
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

	/* won't build any new stations if true */
	function HasMaxStationCount(cityFrom, cityTo, cargoClass)
	{
//		return false;

		local maxTownStationFrom = (1 + AITown.GetPopulation(cityFrom) / 1000).tointeger();
		local maxTownStationTo = (1 + AITown.GetPopulation(cityTo) / 1000).tointeger();

		local cityFromCount = 0;
		local cityToCount = 0;

		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			if (m_townRouteArray[i].m_city_from == cityFrom || m_townRouteArray[i].m_city_from == cityTo) {
				if (m_townRouteArray[i].m_cargo_class == cargoClass) ++cityFromCount;
			}

			if (m_townRouteArray[i].m_city_to == cityTo || m_townRouteArray[i].m_city_to == cityFrom) {
				if (m_townRouteArray[i].m_cargo_class == cargoClass) ++cityToCount;
			}
		}
//		AILog.Info("cityFrom = " + AITown.GetName(cityFrom) + " ; cityFromCount = " + cityFromCount + " ; maxTownStationFrom = " + maxTownStationFrom + " ; cityTo = " + AITown.GetName(cityTo) + " ; cityToCount = " + cityToCount + " ; maxTownStationTo = " + maxTownStationTo);

		if ((cityFromCount >= maxTownStationFrom) || (cityToCount >= maxTownStationTo)) {
			return true;
		}

		return false;
	}

	function SaveRouteManager()
	{
		local array = [];
		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			array.append(m_townRouteArray[i].SaveRoute());
		}

		return [array, m_sentToDepotRoadGroup, m_best_routes_built];
	}

	function LoadRouteManager(data)
	{
		if (m_townRouteArray == null) {
			m_townRouteArray = [];
		}

		local routearray = data[0];

		local bridges = 0;
		for (local i = 0; i < routearray.len(); i++) {
			local route = RoadRoute.LoadRoute(routearray[i]);
			m_townRouteArray.append(route[0]);
			bridges += route[1];
		}
		AILog.Info("Loaded " + m_townRouteArray.len() + " road routes with " + bridges + " bridges.");

		m_sentToDepotRoadGroup = data[1];
		m_best_routes_built = data[2];
	}
};
