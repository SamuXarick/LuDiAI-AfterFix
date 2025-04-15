require("TrainBuildManager.nut");

class RailRouteManager {
	m_town_route_array = null;
	m_sentToDepotRailGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	constructor(sent_to_depot_rail_group, best_routes_built) {
		m_town_route_array = [];
		m_sentToDepotRailGroup = sent_to_depot_rail_group;
		m_best_routes_built = best_routes_built;
	}

	function BuildRoute(railBuildManager, city_from, city_to, cargo_class, best_routes_built, rail_type) {
		local route = railBuildManager.BuildRailRoute(city_from, city_to, cargo_class, m_sentToDepotRailGroup, best_routes_built, rail_type);
		if (route != null && route != 0) {
			m_town_route_array.append(route);
			railBuildManager.SetRouteFinished();
			return [1, route.m_station_from, route.m_station_to];
		}

		return [route, null, null];
	}


	function GetTrainCount() {
		return AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_RAIL);
	}

	function TownRouteExists(city_from, city_to, cargo_class) {
		for (local i = 0; i < m_town_route_array.len(); ++i) {
			if (TownPair(city_from, city_to, cargo_class).IsEqual(m_town_route_array[i].m_city_from, m_town_route_array[i].m_city_to, m_town_route_array[i].m_cargo_class)) {
//				AILog.Info("TownRouteExists from " + AITown.GetName(city_from) + " to " + AITown.GetName(city_to));
				return 1;
			}
		}

		return 0;
	}

	/* the highest last years profit out of all vehicles */
	function HighestProfitLastYear() {
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

	/* won't build any new stations if 1 */
	function HasMaxStationCount(city_from, city_to, cargo_class) {
//		return 0;

		local maxTownStationFrom = (1 + AITown.GetPopulation(city_from) / 1000).tointeger();
		local maxTownStationTo = (1 + AITown.GetPopulation(city_to) / 1000).tointeger();

		local cityFromCount = 0;
		local cityToCount = 0;

		for (local i = 0; i < m_town_route_array.len(); ++i) {
			if (m_town_route_array[i].m_city_from == city_from || m_town_route_array[i].m_city_from == city_to) {
				if (m_town_route_array[i].m_cargo_class == cargo_class) ++cityFromCount;
			}

			if (m_town_route_array[i].m_city_to == city_to || m_town_route_array[i].m_city_to == city_from) {
				if (m_town_route_array[i].m_cargo_class == cargo_class) ++cityToCount;
			}
		}
//		AILog.Info("city_from = " + AITown.GetName(city_from) + " ; cityFromCount = " + cityFromCount + " ; maxTownStationFrom = " + maxTownStationFrom + " ; city_to = " + AITown.GetName(city_to) + " ; cityToCount = " + cityToCount + " ; maxTownStationTo = " + maxTownStationTo);

		if ((cityFromCount >= maxTownStationFrom) || (cityToCount >= maxTownStationTo)) {
			return 1;
		}

		return 0;
	}

	function SaveRouteManager() {
		local array = [];
		for (local i = 0; i < m_town_route_array.len(); ++i) {
			array.append(m_town_route_array[i].SaveRoute());
		}

		return [array, m_sentToDepotRailGroup, m_best_routes_built];
	}

	function LoadRouteManager(data) {
		if (m_town_route_array == null) {
			m_town_route_array = [];
		}

		local routearray = data[0];

		local bridges = 0;
		for (local i = 0; i < routearray.len(); i++) {
			local route = RailRoute.LoadRoute(routearray[i]);
			m_town_route_array.append(route[0]);
			bridges += route[1];
		}
		AILog.Info("Loaded " + m_town_route_array.len() + " rail routes with " + bridges + " bridges.");

		m_sentToDepotRailGroup = data[1];
		m_best_routes_built = data[2];
	}

}
