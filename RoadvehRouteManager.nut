require("RoadvehBuildManager.nut");

class RoadRouteManager
{
	m_town_route_array = null;
	m_sent_to_depot_road_group = null;
	m_best_routes_built = null;

	constructor(sent_to_depot_road_group, best_routes_built)
	{
		this.m_town_route_array = [];
		this.m_sent_to_depot_road_group = sent_to_depot_road_group;
		this.m_best_routes_built = best_routes_built;
	}

	function BuildRoute(road_build_manager, city_from, city_to, cargo_class, articulated, best_routes_built)
	{
		local route = road_build_manager.BuildRoadRoute(city_from, city_to, cargo_class, articulated, this.m_sent_to_depot_road_group, best_routes_built);
		if (route != null && route != 0) {
			this.m_town_route_array.append(route);
			road_build_manager.SetRouteFinished();
			return [1, route.m_station_from, route.m_station_to];
		}

		return [route, null, null];
	}


	function GetRoadVehicleCount()
	{
		return AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_ROAD);
	}

	function TownRouteExists(city_from, city_to, cargo_class)
	{
		for (local i = 0; i < this.m_town_route_array.len(); ++i) {
			if (TownPair(city_from, city_to, cargo_class).IsEqual(this.m_town_route_array[i].m_city_from, this.m_town_route_array[i].m_city_to, this.m_town_route_array[i].m_cargo_class)) {
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

		local maxTownStationFrom = (1 + AITown.GetPopulation(city_from) / 1000).tointeger();
		local maxTownStationTo = (1 + AITown.GetPopulation(city_to) / 1000).tointeger();

		local cityFromCount = 0;
		local cityToCount = 0;

		for (local i = 0; i < this.m_town_route_array.len(); ++i) {
			if (this.m_town_route_array[i].m_city_from == city_from || this.m_town_route_array[i].m_city_from == city_to) {
				if (this.m_town_route_array[i].m_cargo_class == cargo_class) ++cityFromCount;
			}

			if (this.m_town_route_array[i].m_city_to == city_to || this.m_town_route_array[i].m_city_to == city_from) {
				if (this.m_town_route_array[i].m_cargo_class == cargo_class) ++cityToCount;
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
		for (local i = 0; i < this.m_town_route_array.len(); ++i) {
			array.append(this.m_town_route_array[i].SaveRoute());
		}

		return [array, this.m_sent_to_depot_road_group, this.m_best_routes_built];
	}

	function LoadRouteManager(data)
	{
		if (this.m_town_route_array == null) {
			this.m_town_route_array = [];
		}

		local routearray = data[0];

		local bridges = 0;
		for (local i = 0; i < routearray.len(); i++) {
			local route = RoadRoute.LoadRoute(routearray[i]);
			this.m_town_route_array.append(route[0]);
			bridges += route[1];
		}
		AILog.Info("Loaded " + this.m_town_route_array.len() + " road routes with " + bridges + " bridges.");

		this.m_sent_to_depot_road_group = data[1];
		this.m_best_routes_built = data[2];
	}
};
