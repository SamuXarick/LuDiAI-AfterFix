require("ShipBuildManager.nut");

class ShipRouteManager
{
	m_town_route_array = null;
	m_sentToDepotWaterGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	constructor(sent_to_depot_water_group, best_routes_built)
	{
		m_town_route_array = [];
		m_sentToDepotWaterGroup = sent_to_depot_water_group;
		m_best_routes_built = best_routes_built;
	}

	function BuildRoute(ship_build_manager, city_from, city_to, cargo_class, cheaperRoute, best_routes_built)
	{
		local route = ship_build_manager.BuildWaterRoute(city_from, city_to, cargo_class, cheaperRoute, m_sentToDepotWaterGroup, best_routes_built);
		if (route != null && route != 0) {
			m_town_route_array.append(route);
			ship_build_manager.SetRouteFinished();
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
		for (local i = 0; i < m_town_route_array.len(); ++i) {
			if (TownPair(city_from, city_to, cargo_class).IsEqual(m_town_route_array[i].m_city_from, m_town_route_array[i].m_city_to, m_town_route_array[i].m_cargo_class)) {
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

		for (local i = 0; i < this.m_town_route_array.len(); ++i) {
			local maxRouteProfit = 0;
			foreach (vehicle, _ in this.m_town_route_array[i].m_vehicle_list) {
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

		local max_town_station_from = (1 + AITown.GetPopulation(city_from) / 1000).tointeger();
		local max_town_station_to = (1 + AITown.GetPopulation(city_to) / 1000).tointeger();

		local city_from_count = 0;
		local city_to_count = 0;

		for (local i = 0; i < m_town_route_array.len(); ++i) {
			if (m_town_route_array[i].m_city_from == city_from || m_town_route_array[i].m_city_from == city_to) {
				if (m_town_route_array[i].m_cargo_class == cargo_class) ++city_from_count;
			}

			if (m_town_route_array[i].m_city_to == city_to || m_town_route_array[i].m_city_to == city_from) {
				if (m_town_route_array[i].m_cargo_class == cargo_class) ++city_to_count;
			}
		}
//		AILog.Info("city_from = " + AITown.GetName(city_from) + " ; city_from_count = " + city_from_count + " ; max_town_station_from = " + max_town_station_from + " ; city_to = " + AITown.GetName(city_to) + " ; city_to_count = " + city_to_count + " ; max_town_station_to = " + max_town_station_to);

		if ((city_from_count >= max_town_station_from) || (city_to_count >= max_town_station_to)) {
			return true;
		}

		return false;
	}

	function SaveRouteManager()
	{
		local array = [];
		for (local i = 0; i < m_town_route_array.len(); ++i) {
			array.append(m_town_route_array[i].SaveRoute());
		}

		return [array, m_sentToDepotWaterGroup, m_best_routes_built];
	}

	function LoadRouteManager(data)
	{
		if (m_town_route_array == null) {
			m_town_route_array = [];
		}

		local routearray = data[0];

		for (local i = 0; i < routearray.len(); i++) {
			local route = ShipRoute.LoadRoute(routearray[i]);
			m_town_route_array.append(route);
		}
		AILog.Info("Loaded " + m_town_route_array.len() + " water routes.");

		m_sentToDepotWaterGroup = data[1];
		m_best_routes_built = data[2];
	}
};
