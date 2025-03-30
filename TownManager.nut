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
}

class TownManager {
	m_townList = null;
	m_townCount = null;

	m_nearCityPairArray = null;
	m_usedCitiesPassTable = null;
	m_usedCitiesMailTable = null;

	constructor() {
		m_townList = AIList();
		m_townCount = 0;

		m_nearCityPairArray = [];
		m_usedCitiesPassTable = {};
		m_usedCitiesMailTable = {};
	}

	function GetUnusedCity(bestRoutesBuilt, cargoClass);
	function RemoveUsedCityPair(fromCity, toCity, usedCities);
	function FindNearCities(fromCity, minDistance, maxDistance, bestRoutesBuilt, cargoClass, fakedist);
	function BuildTownList();
	function HasArrayCargoClassPairs(cargoClass);
	function ClearCargoClassArray(cargoClass);

	function m_cityFrom(m_data) {
		return m_data[0];
	}

	function m_cityTo(m_data) {
		return m_data[1];
	}

	function m_cargoClass(m_data) {
		return m_data[2];
	}

	function hasCargoClass(m_data, cargoClass) {
		return m_cargoClass(m_data) == cargoClass;
	}

	function IsEqual(m_data, cityFrom, cityTo, cargoClass) {
		if (!hasCargoClass(m_data, cargoClass)) return false;

		if (m_cityFrom(m_data) == cityFrom && m_cityTo(m_data) == cityTo) {
			return true;
		}

		if (m_cityFrom(m_data) == cityTo && m_cityTo(m_data) == cityFrom) {
			return true;
		}

		return false;
	}

	function TownPair(cityFrom, cityTo, cargoClass) {
		return [cityFrom, cityTo, cargoClass];
	}

	function ClearCargoClassArray(cargoClass) {
		for (local i = m_nearCityPairArray.len() - 1; i >= 0; --i) {
			if (hasCargoClass(m_nearCityPairArray[i], cargoClass)) {
				m_nearCityPairArray.remove(i);
			}
		}
	}

	function HasArrayCargoClassPairs(cargoClass) {
		for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
			if (hasCargoClass(m_nearCityPairArray[i], cargoClass)) {
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
		local citiesOnly = AIController.GetSetting("cities_only");
		if (townCount == m_townCount) return;

		m_townCount = townCount;

		m_townList = AITownList();
	}

	function GetUnusedCity(bestRoutesBuilt, cargoClass) {
		BuildTownList();

		if (m_townList.Count() == (cargoClass == AICargo.CC_PASSENGERS ? m_usedCitiesPassTable.len() : m_usedCitiesMailTable.len())) {
			return null;
		}

		local localList = AIList();
		localList.AddList(m_townList);
		localList.RemoveList(cargoClass == AICargo.CC_PASSENGERS ? Utils.TableListToAIList(m_usedCitiesPassTable) : Utils.TableListToAIList(m_usedCitiesMailTable));

		local unusedTown = null;
		local pick_mode = AIController.GetSetting("pick_mode");
		if (pick_mode == 1) {
			local randomLocalListItemIndex = AIBase.RandRange(localList.Count());
			unusedTown = Utils.GetNthItem(localList, randomLocalListItemIndex);
			if (cargoClass == AICargo.CC_PASSENGERS) {
				m_usedCitiesPassTable.rawset(unusedTown, 0);
			} else {
				m_usedCitiesMailTable.rawset(unusedTown, 0);
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
					m_usedCitiesPassTable.rawset(unusedTown, 0);
				} else {
					m_usedCitiesMailTable.rawset(unusedTown, 0);
				}
			}
		}

		return unusedTown;
	}

	function RemoveUsedCityPair(fromCity, toCity, cargoClass, usedCities) {
//		AILog.Info(m_nearCityPairArray.len() + " found in the m_nearCityPairArray");
//		AILog.Info("Town pair " + AITown.GetName(fromCity) + " and " + AITown.GetName(toCity) + " (" + AICargo.GetCargoLabel(Utils.GetCargoID(cargoClass)) + ") are being removed...");
		for (local i = m_nearCityPairArray.len() - 1; i >= 0; --i) {
			if (IsEqual(m_nearCityPairArray[i], fromCity, toCity, cargoClass)) {
//				AILog.Info("Found pair " + AITown.GetName(m_cityFrom(m_nearCityPairArray[i])) + " and " + AITown.GetName(m_cityTo(m_nearCityPairArray[i])) + "( " + AICargo.GetCargoLabel(Utils.GetCargoID(m_cargoClass(m_nearCityPairArray[i]))) + ") in m_nearCityPairArray[" + i + "]");
				m_nearCityPairArray.remove(i);
				break;
			}
		}

		/* The following code is too slow */
//		if (usedCities) {
//			if (cargoClass == AICargo.CC_PASSENGERS) {
//				AILog.Info(m_usedCitiesPassTable.len() + " found in m_usedCitiesPassTable");
//				local removeList = AIList();
//				foreach (u, v in m_usedCitiesPassTable) {
//					local removeTown = true;
//					for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
//						if ((u == m_cityFrom(m_nearCityPairArray[i]) || u == m_cityTo(m_nearCityPairArray[i])) && m_cargoClass(m_nearCityPairArray[i]) == cargoClass) {
//							removeTown = false;
//						}
//					}
//					if (removeTown) {
//						AILog.Info("Town " + AITown.GetName(u) + " is being removed (RemoveUsedCityPair)");
//						removeList.AddItem(u, 0);
//					}
//				}
//
//				Utils.RemoveAIListFromTableList(removeList, m_usedCitiesPassTable);
//			} else {
//				AILog.Info(m_usedCitiesMailTable.len() + " found in m_usedCitiesMailTable");
//				local removeList = AIList();
//				foreach (u, v in m_usedCitiesMailTable) {
//					local removeTown = true;
//					for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
//						if ((u == m_cityFrom(m_nearCityPairArray[i]) || u == m_cityTo(m_nearCityPairArray[i])) && m_cargoClass(m_nearCityPairArray[i]) == cargoClass) {
//							removeTown = false;
//						}
//					}
//					if (removeTown) {
//						AILog.Info("Town " + AITown.GetName(u) + " is being removed (RemoveUsedCityPair)");
//						removeList.AddItem(u, 0);
//					}
//				}
//
//				Utils.RemoveAIListFromTableList(removeList, m_usedCitiesMailTable);
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
		localCityList.RemoveList(cargoClass == AICargo.CC_PASSENGERS ? Utils.TableListToAIList(m_usedCitiesPassTable) : Utils.TableListToAIList(m_usedCitiesMailTable));
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
				if (IsEqual(m_nearCityPairArray[i], fromCity, toCity, cargoClass)) {
					exists = true;
					break;
				}
			}

			if (!exists) {
				m_nearCityPairArray.append(this.TownPair(fromCity, toCity, cargoClass));
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
					if (IsEqual(m_nearCityPairArray[i], fromCity, localPairList.Begin(), cargoClass)) {
						exists = true;
						break;
					}
				}

				if (!exists) {
					m_nearCityPairArray.append(this.TownPair(fromCity, localPairList.Begin(), cargoClass));
					return;
				}
			} else {
//				local start_tick = AIController.GetTick();
//				AILog.Info("FindNearCities . bestRoutesBuilt . localPairList: " + localPairList.Count() + " items; m_nearCityPairArray: " + m_nearCityPairArray.len() + " items.");
				local count = 0;
				for (local toCity = localPairList.Begin(); !localPairList.IsEnd(); toCity = localPairList.Next()) {
					local exists = false;
					for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
						if (IsEqual(m_nearCityPairArray[i], fromCity, toCity, cargoClass)) {
							exists = true;
							break;
						}
					}

					if (!exists) {
						m_nearCityPairArray.append(this.TownPair(fromCity, toCity, cargoClass));
						count++;
						if (count == 10) break; // too many towns in localPairList will slow IsEqual down over time
					}
				}
//				local management_ticks = AIController.GetTick() - start_tick;
//				AILog.Info("FindNearCities " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
			}
		}

		return;
	}

	function SaveTownManager() {
		return [m_nearCityPairArray, m_usedCitiesPassTable, m_usedCitiesMailTable];
	}

	function LoadTownManager(data) {
		m_nearCityPairArray = data[0];
		AILog.Info("Loaded " + m_nearCityPairArray.len() + " near city pairs.");

		m_usedCitiesPassTable = data[1];
		AILog.Info("Loaded " + m_usedCitiesPassTable.len() + " used cities Pass.");

		m_usedCitiesMailTable = data[2];
		AILog.Info("Loaded " + m_usedCitiesMailTable.len() + " used cities Mail.");
	}

}
