require("ShipBuildManager.nut");

class ShipRouteManager
{
	m_townRouteArray = null;
	m_sentToDepotWaterGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	constructor(sentToDepotWaterGroup, best_routes_built)
	{
		m_townRouteArray = [];
		m_sentToDepotWaterGroup = sentToDepotWaterGroup;
		m_best_routes_built = best_routes_built;
	}

	function BuildRoute(shipBuildManager, city_from, city_to, cargo_class, cheaperRoute, best_routes_built)
	{
		local route = shipBuildManager.BuildWaterRoute(city_from, city_to, cargo_class, cheaperRoute, m_sentToDepotWaterGroup, best_routes_built);
		if (route != null && route != 0) {
			m_townRouteArray.append(route);
			shipBuildManager.SetRouteFinished();
			return [1, route.m_dockFrom, route.m_dockTo];
		}

		return [route, null, null];
	}


	function GetShipCount()
	{
		return AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_WATER);
	}

	function TownRouteExists(city_from, city_to, cargo_class)
	{
		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			if (TownPair(city_from, city_to, cargo_class).IsEqual(m_townRouteArray[i].m_city_from, m_townRouteArray[i].m_city_to, m_townRouteArray[i].m_cargo_class)) {
//				AILog.Info("TownRouteExists from " + AITown.GetName(city_from) + " to " + AITown.GetName(city_to));
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
	function HasMaxStationCount(city_from, city_to, cargo_class)
	{
//		return false;

		local maxTownStationFrom = (1 + AITown.GetPopulation(city_from) / 1000).tointeger();
		local maxTownStationTo = (1 + AITown.GetPopulation(city_to) / 1000).tointeger();

		local cityFromCount = 0;
		local cityToCount = 0;

		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			if (m_townRouteArray[i].m_city_from == city_from || m_townRouteArray[i].m_city_from == city_to) {
				if (m_townRouteArray[i].m_cargo_class == cargo_class) ++cityFromCount;
			}

			if (m_townRouteArray[i].m_city_to == city_to || m_townRouteArray[i].m_city_to == city_from) {
				if (m_townRouteArray[i].m_cargo_class == cargo_class) ++cityToCount;
			}
		}
//		AILog.Info("city_from = " + AITown.GetName(city_from) + " ; cityFromCount = " + cityFromCount + " ; maxTownStationFrom = " + maxTownStationFrom + " ; city_to = " + AITown.GetName(city_to) + " ; cityToCount = " + cityToCount + " ; maxTownStationTo = " + maxTownStationTo);

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

		return [array, m_sentToDepotWaterGroup, m_best_routes_built];
	}

	function LoadRouteManager(data)
	{
		if (m_townRouteArray == null) {
			m_townRouteArray = [];
		}

		local routearray = data[0];

		for (local i = 0; i < routearray.len(); i++) {
			local route = ShipRoute.LoadRoute(routearray[i]);
			m_townRouteArray.append(route);
		}
		AILog.Info("Loaded " + m_townRouteArray.len() + " water routes.");

		m_sentToDepotWaterGroup = data[1];
		m_best_routes_built = data[2];
	}
};
