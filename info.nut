class LuDiAIAfterFix extends AIInfo {
  function GetAuthor() {
	return "lukin_, Samu";
  }
  function GetName() {
	return "LuDiAI AfterFix";
  }
  function GetDescription() {
	return "Transports passengers or mail with trucks, buses, airplanes and helicopters";
  }
  function GetVersion() {
	return 11;
  }
  function MinVersionToLoad() {
	return 8;
  }
  function GetDate() {
	return "01-04-2019";
  }
  function CreateInstance() {
	return "LuDiAIAfterFix";
  }
  function GetShortName() {
	return "LDAF";
  }
  function GetAPIVersion() {
	return "1.4";
  }
  function GetURL() {
	return "https://www.tt-forums.net/viewtopic.php?f=65&t=83806";
  }

  function GetSettings() {
	AddSetting({
	  name = "select_town_cargo",
	  description = "Town cargo",
	  easy_value = 0,
	  medium_value = 0,
	  hard_value = 0,
	  custom_value = 0,
	  flags = CONFIG_RANDOM,
	  min_value = 0,
	  max_value = 1
	});

	AddLabels("select_town_cargo", {
	  _0 = "Passengers",
	  _1 = "Mail"
	});

	AddSetting({
	  name = "cities_only",
	  description = "Cities only",
	  easy_value = 1,
	  medium_value = 0,
	  hard_value = 0,
	  custom_value = 0,
	  flags = CONFIG_BOOLEAN | CONFIG_RANDOM
	});

	AddSetting({
	  name = "pick_mode",
	  description = "Town choice priority",
	  easy_value = 1,
	  medium_value = 0,
	  hard_value = 2,
	  custom_value = 0,
	  flags =  CONFIG_RANDOM,
	  min_value = 0,
	  max_value = 3
	});

	AddLabels("pick_mode", {
	  _0 = "Most cargo produced first",
	  _1 = "None, pick at random",
	  _2 = "Shorter routes first",
	  _3 = "Longer routes first"
	});

	AddSetting({
	  name = "is_friendly",
	  description = "Is friendly",
	  easy_value = 1,
	  medium_value = 1,
	  hard_value = 0,
	  custom_value = 1,
	  flags = CONFIG_BOOLEAN | CONFIG_RANDOM | CONFIG_INGAME
	});

	AddSetting({
	  name = "air_support",
	  description = "Air support",
	  easy_value = 1,
	  medium_value = 1,
	  hard_value = 1,
	  custom_value = 1,
	  flags = CONFIG_BOOLEAN | CONFIG_INGAME
	});

	AddSetting({
	  name = "road_support",
	  description = "Road support",
	  easy_value = 1,
	  medium_value = 1,
	  hard_value = 1,
	  custom_value = 1,
	  flags = CONFIG_BOOLEAN | CONFIG_INGAME
	});

	AddSetting({
	  name = "station_spread",
	  description = "Can station spread",
	  easy_value = 0,
	  medium_value = 1,
	  hard_value = 1,
	  custom_value = 1,
	  flags = CONFIG_BOOLEAN | CONFIG_RANDOM | CONFIG_INGAME
	});

	AddSetting({
	  name = "road_min_dist",
	  description = "Minimum distance between towns for road routes",
	  min_value = 20,
	  max_value = 130,
	  easy_value = 40,
	  medium_value = 60,
	  hard_value = 85,
	  custom_value = 40,
	  step_size = 15,
	  flags = CONFIG_RANDOM
	});

	AddSetting({
	  name = "pf_profile",
	  description = "Road pathfinder profile",
	  easy_value = 0,
	  medium_value = 1,
	  hard_value = 2,
	  custom_value = 0,
	  flags = CONFIG_RANDOM | CONFIG_INGAME,
	  min_value = 0,
	  max_value = 2
	});

	AddLabels("pf_profile", {
	  _0 = "Custom",
	  _1 = "Default",
	  _2 = "Fastest"
	});

	AddSetting({
	  name = "road_cap_mode",
	  description = "Road route capacity mode",
	  easy_value = 1,
	  medium_value = 0,
	  hard_value = 2,
	  custom_value = 1,
	  flags = CONFIG_RANDOM | CONFIG_INGAME,
	  min_value = 0,
	  max_value = 2
	});

	AddLabels("road_cap_mode", {
	  _0 = "Maximum of 25 road vehicles",
	  _1 = "Estimate maximum number of road vehicles",
	  _2 = "Adjust number of road vehicles dynamically"
	});

	AddSetting({
	  name = "scp_support",
	  description = "AI-GS communication support",
	  easy_value = 1,
	  medium_value = 1,
	  hard_value = 1,
	  custom_value = 0,
	  flags = CONFIG_BOOLEAN | CONFIG_RANDOM
	});
  }
}

RegisterAI(LuDiAIAfterFix());


