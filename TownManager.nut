class TownPair {
	m_city_from = null;
	m_city_to = null;
	m_cargo_class = null;

	constructor(cityFrom, cityTo, cargoClass = null) {
		m_city_from = cityFrom;
		m_city_to = cityTo;
		m_cargo_class = cargoClass;
	}

	function IsEqual(cityFrom, cityTo, cargoClass = null) {
		if (m_cargo_class != cargoClass) return false;

		if (m_city_from == cityFrom && m_city_to == cityTo) {
			return true;
		}

		if (m_city_from == cityTo && m_city_to == cityFrom) {
			return true;
		}
	}

	function IsTownPairDataEqual(town_pair_data) {
		return IsEqual(town_pair_data[0], town_pair_data[1]);
	}
}

class TownManager {
	m_townList = null;
	m_townCount = null;

	m_nearCityPairArray = null;
	m_usedCitiesList = null;

	constructor() {
		m_townList = AIList();
		m_townCount = 0;

		m_nearCityPairArray = {};
		m_nearCityPairArray.rawset(AICargo.CC_PASSENGERS, []);
		m_nearCityPairArray.rawset(AICargo.CC_MAIL, []);
		m_usedCitiesList = {};
		m_usedCitiesList.rawset(AICargo.CC_PASSENGERS, AIList());
		m_usedCitiesList.rawset(AICargo.CC_MAIL, AIList());
	}

	function GetUnusedCity(bestRoutesBuilt, cargoClass);
	function FindNearCities(fromCity, minDistance, maxDistance, bestRoutesBuilt, cargoClass, fakedist);
	function BuildTownList();

	function GetLastMonthProductionDiffRate(town, cargo) {
		return (AITown.GetLastMonthProduction(town, cargo) - AITown.GetLastMonthSupplied(town, cargo)) * (100 - AITown.GetLastMonthTransportedPercentage(town, cargo)) / 100;
	}

	function IsTownGrowing(town, cargo) {
//		return true;
		if (!AIGameSettings.GetValue("town_growth_rate")) return true; // no town grows, just work with it

		local cargoList = AICargoList();
		cargoList.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
		local cargoRequired = AIList();
		for (local cargo_type = cargoList.Begin(); !cargoList.IsEnd(); cargo_type = cargoList.Next()) {
			local town_effect = AICargo.GetTownEffect(cargo_type);

			if (town_effect != AICargo.TE_NONE) {
//				local effect_name;
//				switch(town_effect) {
//					case AICargo.TE_PASSENGERS: effect_name = "TE_PASSENGERS"; break;
//					case AICargo.TE_MAIL: effect_name = "TE_MAIL"; break;
//					case AICargo.TE_GOODS: effect_name = "TE_GOODS"; break;
//					case AICargo.TE_WATER: effect_name = "TE_WATER"; break;
//					case AICargo.TE_FOOD: effect_name = "TE_FOOD"; break;
//				}
//				AILog.Info(" - Effect of " + AICargo.GetCargoLabel(cargo_type) + " in " + AITown.GetName(town) + " is " + effect_name);
				local cargo_goal = AITown.GetCargoGoal(town, town_effect);
				if (cargo_goal != 0) {
//					AILog.Info(" - An amount of " + cargo_goal + " " + AICargo.GetCargoLabel(cargo_type) + " is required to grow " + AITown.GetName(town));
					cargoRequired.AddItem(cargo_type, cargo_goal);
				}
			}
		}
//		AILog.Info(" ");
		local num_cargo_types_required = cargoRequired.Count();
		local result = num_cargo_types_required == 0 || (cargoRequired.HasItem(cargo) && num_cargo_types_required == 1);

//		AILog.Info("-- Result for town " + AITown.GetName(town) + ": " + result + " - " + num_cargo_types_required + " --");
		return result;
	}

	function BuildTownList() {
		local townCount = AITown.GetTownCount();
		if (townCount == m_townCount) return;

		m_townCount = townCount;

		m_townList = AITownList();
	}

	function GetUnusedCity(bestRoutesBuilt, cargoClass) {
		BuildTownList();

		if (m_townList.Count() == m_usedCitiesList[cargoClass].Count()) {
			return null;
		}

		local localList = AIList();
		localList.AddList(m_townList);
		localList.RemoveList(m_usedCitiesList[cargoClass]);

		local unusedTown = null;
		local pick_mode = AIController.GetSetting("pick_mode");
		if (pick_mode == 1) {
			localList.RemoveTop(AIBase.RandRange(localList.Count()));
			unusedTown = localList.Begin();
			m_usedCitiesList[cargoClass].AddItem(unusedTown, 0);
		} else {
			local cargo = Utils.GetCargoType(cargoClass);
			for (local town = localList.Begin(); !localList.IsEnd(); town = localList.Next()) {
				localList.SetValue(town, (pick_mode == 0 ? GetLastMonthProductionDiffRate(town, cargo) : AITown.GetLastMonthProduction(town, cargo)));
			}
			localList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

			if (!bestRoutesBuilt) {
				local cargolimit = cargoClass == AICargo.CC_PASSENGERS ? 70 : 35;

				local templist = AIList();
				templist.AddList(localList);
				for (local town = localList.Begin(); !localList.IsEnd(); town = localList.Next()) {
					if (!IsTownGrowing(town, cargo)) {
						templist.RemoveItem(town);
						continue;
					}
					if (localList.GetValue(town) <= cargolimit) {
						templist.RemoveItem(town);
						continue;
					}
				}
				localList.KeepList(templist);
			}

			if (!localList.IsEmpty()) {
				unusedTown = localList.Begin();
				m_usedCitiesList[cargoClass].AddItem(unusedTown, 0);
			}
		}

		return unusedTown;
	}

	function RemoveUsedCityPair(fromCity, toCity, cargoClass, usedCities) {
//		AILog.Info(m_nearCityPairArray[cargoClass].len() + " found in the m_nearCityPairArray[" + AICargo.GetCargoLabel(Utils.GetCargoType(cargoClass)) + "]");
//		AILog.Info("Town pair " + AITown.GetName(fromCity) + " and " + AITown.GetName(toCity) + " (" + AICargo.GetCargoLabel(Utils.GetCargoType(cargoClass)) + ") are being removed...");
		for (local i = m_nearCityPairArray[cargoClass].len() - 1; i >= 0; --i) {
			if (TownPair(fromCity, toCity).IsTownPairDataEqual(m_nearCityPairArray[cargoClass][i])) {
//				AILog.Info("Found pair " + AITown.GetName(m_nearCityPairArray[cargoClass][i][0]) + " and " + AITown.GetName(m_nearCityPairArray[cargoClass][i][1]) + " in m_nearCityPairArray[" + AICargo.GetCargoLabel(Utils.GetCargoType(cargoClass)) + "][" + i + "]");
				m_nearCityPairArray[cargoClass].remove(i);
				break;
			}
		}

		/* The following code is too slow */
//		if (usedCities) {
//			AILog.Info(m_usedCitiesList[cargoClass].Count() + " found in m_usedCitiesList[" + cargoClass + "]");
//			for (local town = m_usedCitiesList[cargoClass].Begin(); !m_usedCitiesList[cargoClass].IsEnd(); town = m_usedCitiesList[cargoClass].Next()) {
//				local removeTown = true;
//				for (local i = 0; i < m_nearCityPairArray[cargoClass].len(); ++i) {
//					if (town == m_nearCityPairArray[cargoClass][i][0] || town == m_nearCityPairArray[cargoClass][i][1]) {
//						removeTown = false;
//						break;
//					}
//				}
//				if (removeTown) {
//					AILog.Info("Town " + AITown.GetName(town) + " is being removed (RemoveUsedCityPair)");
//					m_usedCitiesList[cargoClass].RemoveItem(town);
//				}
//			}
//		}
	}

	function DistanceFunction(fakedist, town, tile) {
		if (fakedist) return AITown.GetDistanceSquareToTile(town, tile);
		return AITown.GetDistanceManhattanToTile(town, tile);
	}

	function FindNearCities(fromCity, minDistance, maxDistance, bestRoutesBuilt, cargoClass, fakedist = 0) {
//		AILog.Info("fromCity = " + fromCity + "; minDistance = " + minDistance + "; maxDistance = " + maxDistance + "; bestRoutesBuilt = " + bestRoutesBuilt + "; cargoClass = " + cargoClass + "; fakedist = " + fakedist);
		BuildTownList();

		local localCityList = AIList();
		localCityList.AddList(m_townList);
		localCityList.RemoveList(m_usedCitiesList[cargoClass]);
		localCityList.RemoveItem(fromCity); // remove self

		local localPairList = AIList();

		for (local toCity = localCityList.Begin(); !localCityList.IsEnd(); toCity = localCityList.Next()) {

			local distance = DistanceFunction(fakedist, fromCity, AITown.GetLocation(toCity));
			local fake = WrightAI.DistanceRealFake(AITown.GetLocation(fromCity), AITown.GetLocation(toCity));
			if ((distance > maxDistance) || (distance < minDistance) || (fakedist != 0 && fake > fakedist)) {
//				AILog.Warning("findNearCity:: Distance too long between " + AITown.GetName(fromCity) + " and " + AITown.GetName(toCity)) ;
			}
			else {
//				AILog.Info("Added " + AITown.GetName(toCity) + " to localPairList, distance = " + distance + " tiles, " + fake + " fake tiles.");
				localPairList.AddItem(toCity, 0);
			}
		}

		if (localPairList.IsEmpty()) {
			return;
		}

		local pick_mode = AIController.GetSetting("pick_mode");
		if (pick_mode == 1) {
			localPairList.RemoveTop(AIBase.RandRange(localPairList.Count()));
			local toCity = localPairList.Begin();

			local exists = false;
			for (local i = 0; i < m_nearCityPairArray[cargoClass].len(); ++i) {
				if (TownPair(fromCity, toCity).IsTownPairDataEqual(m_nearCityPairArray[cargoClass][i])) {
					exists = true;
					break;
				}
			}

			if (!exists) {
				m_nearCityPairArray[cargoClass].append([fromCity, toCity]);
				return;
			}
		} else {
			local fromCity_tile = AITown.GetLocation(fromCity);
			local cargo = Utils.GetCargoType(cargoClass);
			local cargolimit = cargoClass == AICargo.CC_PASSENGERS ? 70 : 35;
			for (local town = localPairList.Begin(); !localPairList.IsEnd(); town = localPairList.Next()) {
				localPairList.SetValue(town, (pick_mode == 0 ? GetLastMonthProductionDiffRate(town, cargo) : AITown.GetLastMonthProduction(town, cargo)));
			}
			localPairList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

			if (!bestRoutesBuilt) {
				local templist = AIList();
				templist.AddList(localPairList);
				for (local town = localPairList.Begin(); !localPairList.IsEnd(); town = localPairList.Next()) {
					if (!IsTownGrowing(town, cargo)) {
						templist.RemoveItem(town);
						continue;
					}
					if (pick_mode >= 2 && localPairList.GetValue(town) <= cargolimit) {
						templist.RemoveItem(town);
						continue;
					}
				}
				localPairList.KeepList(templist);
			}

			if (localPairList.IsEmpty()) {
				return;
			}

			if (pick_mode >= 2) {
				for (local town = localPairList.Begin(); !localPairList.IsEnd(); town = localPairList.Next()) {
					localPairList.SetValue(town, DistanceFunction(fakedist, town, fromCity_tile));
				}
				localPairList.Sort(AIList.SORT_BY_VALUE, (pick_mode == 2 ? AIList.SORT_ASCENDING : AIList.SORT_DESCENDING));
			}

//			for (local toCity = localPairList.Begin(); !localPairList.IsEnd(); toCity = localPairList.Next()) {
//				AILog.Info("From " + AITown.GetName(fromCity) + " to " + AITown.GetName(toCity) + " (" + DistanceFunction(fakedist, toCity, fromCity_tile) + " tiles)");
//			}

			if (!bestRoutesBuilt) {
				local exists = false;
				for (local i = 0; i < m_nearCityPairArray[cargoClass].len(); ++i) {
					if (TownPair(fromCity, localPairList.Begin()).IsTownPairDataEqual(m_nearCityPairArray[cargoClass][i])) {
						exists = true;
						break;
					}
				}

				if (!exists) {
					m_nearCityPairArray[cargoClass].append([fromCity, localPairList.Begin()]);
					return;
				}
			} else {
//				local start_tick = AIController.GetTick();
//				AILog.Info("FindNearCities . bestRoutesBuilt . localPairList: " + localPairList.Count() + " items; m_nearCityPairArray[" + AICargo.GetCargoLabel(Utils.GetCargoType(cargoClass)) + "]: " + m_nearCityPairArray[cargoClass].len() + " items.");
				local count = 0;
				for (local toCity = localPairList.Begin(); !localPairList.IsEnd(); toCity = localPairList.Next()) {
					local exists = false;
					for (local i = 0; i < m_nearCityPairArray[cargoClass].len(); ++i) {
						if (TownPair(fromCity, toCity).IsTownPairDataEqual(m_nearCityPairArray[cargoClass][i])) {
							exists = true;
							break;
						}
					}

					if (!exists) {
						m_nearCityPairArray[cargoClass].append([fromCity, toCity]);
						count++;
						if (count == 10) break; // too many towns in localPairList will slow IsTownPairDataEqual down over time
					}
				}
//				local management_ticks = AIController.GetTick() - start_tick;
//				AILog.Info("FindNearCities " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
			}
		}
	}

	function SaveTownManager() {
		return [m_nearCityPairArray, m_usedCitiesList];
	}

	function LoadTownManager(data) {
		m_nearCityPairArray = data[0];
		AILog.Info("Loaded " + m_nearCityPairArray[AICargo.CC_PASSENGERS].len() + " near city pairs Pass.");
		AILog.Info("Loaded " + m_nearCityPairArray[AICargo.CC_MAIL].len() + " near city pairs Mail.");

		m_usedCitiesList = data[1];
		AILog.Info("Loaded " + m_usedCitiesList[AICargo.CC_PASSENGERS].Count() + " used cities Pass.");
		AILog.Info("Loaded " + m_usedCitiesList[AICargo.CC_MAIL].Count() + " used cities Mail.");
	}
}
