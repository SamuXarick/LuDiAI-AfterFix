class TownPair {
	m_cityFrom = null;
	m_cityTo = null;
	m_cargoClass = null;

	constructor(cityFrom, cityTo, cargoClass) {
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_cargoClass = cargoClass;
	}

	function IsEqual(cityFrom, cityTo, cargoClass) {
		if (m_cargoClass != cargoClass) return false;

		if (m_cityFrom == cityFrom && m_cityTo == cityTo) {
			return true;
		}

		if (m_cityFrom == cityTo && m_cityTo == cityFrom) {
			return true;
		}
	}

	function IsTownPairDataEqual(town_pair_data) {
		return IsEqual(town_pair_data[0], town_pair_data[1], town_pair_data[2]);
	}
}

class TownManager {
	m_townList = null;
	m_townCount = null;

	m_nearCityPairArray = null;
	m_usedCitiesPassList = null;
	m_usedCitiesMailList = null;

	constructor() {
		m_townList = AIList();
		m_townCount = 0;

		m_nearCityPairArray = [];
		m_usedCitiesPassList = AIList();
		m_usedCitiesMailList = AIList();
	}

	function GetUnusedCity(bestRoutesBuilt, cargoClass);
	function RemoveUsedCityPair(fromCity, toCity, usedCities);
	function FindNearCities(fromCity, minDistance, maxDistance, bestRoutesBuilt, cargoClass, fakedist);
	function BuildTownList();
	function HasArrayCargoClassPairs(cargoClass);
	function ClearCargoClassArray(cargoClass);

	function ClearCargoClassArray(cargoClass) {
		for (local i = m_nearCityPairArray.len() - 1; i >= 0; --i) {
			if (m_nearCityPairArray[i][2] == cargoClass) {
				m_nearCityPairArray.remove(i);
			}
		}
	}

	function HasArrayCargoClassPairs(cargoClass) {
		for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
			if (m_nearCityPairArray[i][2] == cargoClass) {
				return true;
			}
		}
		return false;
	}

	function GetLastMonthProductionDiffRate(town, cargo) {
		return (AITown.GetLastMonthProduction(town, cargo) - AITown.GetLastMonthSupplied(town, cargo)) * (100 - AITown.GetLastMonthTransportedPercentage(town, cargo)) / 100;
	}

	function BuildTownList() {
		local townCount = AITown.GetTownCount();
		if (townCount == m_townCount) return;

		m_townCount = townCount;

		m_townList = AITownList();
	}

	function GetUnusedCity(bestRoutesBuilt, cargoClass) {
		BuildTownList();

		if (m_townList.Count() == (cargoClass == AICargo.CC_PASSENGERS ? m_usedCitiesPassList.Count() : m_usedCitiesMailList.Count())) {
			return null;
		}

		local localList = AIList();
		localList.AddList(m_townList);
		localList.RemoveList(cargoClass == AICargo.CC_PASSENGERS ? m_usedCitiesPassList : m_usedCitiesMailList);

		local unusedTown = null;
		local pick_mode = AIController.GetSetting("pick_mode");
		if (pick_mode == 1) {
			local randomLocalListItemIndex = AIBase.RandRange(localList.Count());
			unusedTown = Utils.GetNthItem(localList, randomLocalListItemIndex);
			if (cargoClass == AICargo.CC_PASSENGERS) {
				m_usedCitiesPassList.AddItem(unusedTown, 0);
			} else {
				m_usedCitiesMailList.AddItem(unusedTown, 0);
			}
		} else {
			local cargo = Utils.GetCargoID(cargoClass);
			for (local town = localList.Begin(); !localList.IsEnd(); town = localList.Next()) {
				localList.SetValue(town, (pick_mode == 0 ? TownManager.GetLastMonthProductionDiffRate(town, cargo) : AITown.GetLastMonthProduction(town, cargo)));
			}
			localList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

			if (!bestRoutesBuilt) {
				local cargolimit = cargoClass == AICargo.CC_PASSENGERS ? 70 : 35;

				local templist = AIList();
				templist.AddList(localList);
				for (local town = localList.Begin(); !localList.IsEnd(); town = localList.Next()) {
					if (!Utils.IsTownGrowing(town, cargo)) {
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

			if (localList.Count()) {
				unusedTown = localList.Begin();
				if (cargoClass == AICargo.CC_PASSENGERS) {
					m_usedCitiesPassList.AddItem(unusedTown, 0);
				} else {
					m_usedCitiesMailList.AddItem(unusedTown, 0);
				}
			}
		}

		return unusedTown;
	}

	function RemoveUsedCityPair(fromCity, toCity, cargoClass, usedCities) {
//		AILog.Info(m_nearCityPairArray.len() + " found in the m_nearCityPairArray");
//		AILog.Info("Town pair " + AITown.GetName(fromCity) + " and " + AITown.GetName(toCity) + " (" + AICargo.GetCargoLabel(Utils.GetCargoID(cargoClass)) + ") are being removed...");
		for (local i = m_nearCityPairArray.len() - 1; i >= 0; --i) {
			if (TownPair(fromCity, toCity, cargoClass).IsTownPairDataEqual(m_nearCityPairArray[i])) {
//				AILog.Info("Found pair " + AITown.GetName(m_nearCityPairArray[i][0]) + " and " + AITown.GetName(m_nearCityPairArray[i][1]) + "( " + AICargo.GetCargoLabel(Utils.GetCargoID(m_nearCityPairArray[i][2])) + ") in m_nearCityPairArray[" + i + "]");
				m_nearCityPairArray.remove(i);
				break;
			}
		}

		/* The following code is too slow */
//		if (usedCities) {
//			if (cargoClass == AICargo.CC_PASSENGERS) {
//				AILog.Info(m_usedCitiesPassList.Count() + " found in m_usedCitiesPassList");
//				local removeList = AIList();
//				foreach (u, v in m_usedCitiesPassList) {
//					local removeTown = true;
//					for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
//						if ((u == m_nearCityPairArray[i][0] || u == m_nearCityPairArray[i][1]) && m_nearCityPairArray[i][2] == cargoClass) {
//							removeTown = false;
//						}
//					}
//					if (removeTown) {
//						AILog.Info("Town " + AITown.GetName(u) + " is being removed (RemoveUsedCityPair)");
//						removeList.AddItem(u, 0);
//					}
//				}
//
//				m_usedCitiesPassList.RemoveList(removeList);
//			} else {
//				AILog.Info(m_usedCitiesMailList.Count() + " found in m_usedCitiesMailList");
//				local removeList = AIList();
//				foreach (u, v in m_usedCitiesMailList) {
//					local removeTown = true;
//					for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
//						if ((u == m_nearCityPairArray[i][0] || u == m_nearCityPairArray[i][1]) && m_nearCityPairArray[i][2] == cargoClass) {
//							removeTown = false;
//						}
//					}
//					if (removeTown) {
//						AILog.Info("Town " + AITown.GetName(u) + " is being removed (RemoveUsedCityPair)");
//						removeList.AddItem(u, 0);
//					}
//				}
//
//				m_usedCitiesMailList.RemoveList(removeList);
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
		localCityList.RemoveList(cargoClass == AICargo.CC_PASSENGERS ? m_usedCitiesPassList : m_usedCitiesMailList);
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

		if (!localPairList.Count()) {
			return;
		}

		local pick_mode = AIController.GetSetting("pick_mode");
		if (pick_mode == 1) {
			local randomLocalListItemIndex = AIBase.RandRange(localPairList.Count());
			local toCity = Utils.GetNthItem(localPairList, randomLocalListItemIndex);

			local exists = false;
			for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
				if (TownPair(fromCity, toCity, cargoClass).IsTownPairDataEqual(m_nearCityPairArray[i])) {
					exists = true;
					break;
				}
			}

			if (!exists) {
				m_nearCityPairArray.append([fromCity, toCity, cargoClass]);
				return;
			}
		}
		else {
			local fromCity_tile = AITown.GetLocation(fromCity);
			local cargo = Utils.GetCargoID(cargoClass);
			local cargolimit = cargoClass == AICargo.CC_PASSENGERS ? 70 : 35;
			for (local town = localPairList.Begin(); !localPairList.IsEnd(); town = localPairList.Next()) {
				localPairList.SetValue(town, (pick_mode == 0 ? TownManager.GetLastMonthProductionDiffRate(town, cargo) : AITown.GetLastMonthProduction(town, cargo)));
			}
			localPairList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

			if (!bestRoutesBuilt) {
				local templist = AIList();
				templist.AddList(localPairList);
				for (local town = localPairList.Begin(); !localPairList.IsEnd(); town = localPairList.Next()) {
					if (pick_mode != 1 && !Utils.IsTownGrowing(town, cargo)) {
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

			if (!localPairList.Count()) {
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
				for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
					if (TownPair(fromCity, localPairList.Begin(), cargoClass).IsTownPairDataEqual(m_nearCityPairArray[i])) {
						exists = true;
						break;
					}
				}

				if (!exists) {
					m_nearCityPairArray.append([fromCity, localPairList.Begin(), cargoClass]);
					return;
				}
			} else {
//				local start_tick = AIController.GetTick();
//				AILog.Info("FindNearCities . bestRoutesBuilt . localPairList: " + localPairList.Count() + " items; m_nearCityPairArray: " + m_nearCityPairArray.len() + " items.");
				local count = 0;
				for (local toCity = localPairList.Begin(); !localPairList.IsEnd(); toCity = localPairList.Next()) {
					local exists = false;
					for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
						if (TownPair(fromCity, toCity, cargoClass).IsTownPairDataEqual(m_nearCityPairArray[i])) {
							exists = true;
							break;
						}
					}

					if (!exists) {
						m_nearCityPairArray.append([fromCity, toCity, cargoClass]);
						count++;
						if (count == 10) break; // too many towns in localPairList will slow IsTownPairDataEqual down over time
					}
				}
//				local management_ticks = AIController.GetTick() - start_tick;
//				AILog.Info("FindNearCities " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
			}
		}

		return;
	}

	function SaveTownManager() {
		return [m_nearCityPairArray, m_usedCitiesPassList, m_usedCitiesMailList];
	}

	function LoadTownManager(data) {
		m_nearCityPairArray = data[0];
		AILog.Info("Loaded " + m_nearCityPairArray.len() + " near city pairs.");

		m_usedCitiesPassList = data[1];
		AILog.Info("Loaded " + m_usedCitiesPassList.Count() + " used cities Pass.");

		m_usedCitiesMailList = data[2];
		AILog.Info("Loaded " + m_usedCitiesMailList.Count() + " used cities Mail.");
	}

}
