LuDiAI AfterFix
===============

LuDiAI AfterFix is an AI that builds road routes and air routes,
transporting either mail or passengers.

It's an AI that is built upon the original work of lukin_'s LuDiAI.
Initial work was on fixing issues found on the original, but it became
something more of its own later on.


Main differences or improvements
--------------------------------

- Adds more configuration settings
- Randomizes most configuration settings when started as Random AI
- Can build more than 500 road vehicles
- Builds more airport types
- Builds helicopters
- Builds statues
- Builds the company HQ
- Sells old aircraft
- Is aware of cargo distribution setting
- Is aware of plane speed setting
- Is aware of aircraft max range
- Is aware of map size for route distances
- Matches aircraft type with airport type
- Plans optimal distances between airports
- May build more than one aircraft per route at once
- May add or remove more than one road vehicle at once during management
- Renews vehicles when better models become available
- Plans a maximum number of vehicles a route can support
- Attaches road stations to existing airports
- Removes unserviced road routes
- Use of customized road pathfinder
- Retries road construction if it finds an obstacle instead of giving up
- Is aware of articulated road vehicles' need of drivethrough stations
- Upgrades road bridges
- Retries construction of road stations instead of giving upon instantly
- Schedules removals of leftover road stations and depots on failure
- May also try to build road depots in the source or destination towns
- Founds towns
- Initiates advertising campaigns in towns
- Funds construction of buildings in towns
- Loans and repays on-the-go


Configuration Settings
----------------------

Town Cargo:
    Choses which cargo the AI will handle. If the AI started as Random AI,
    the choice will be randomized on startup.

    - Passengers:
    The AI creates Passenger only routes via road and/or air.

    - Mail:
    The AI creates Mail only routes via road and/or air.

    - Passengers and Mail:
    The AI creates both Passenger and Mail routes via road and/or air.


Cities only:
    When enabled, the AI will only service City status towns. When
    disabled, it will service both cities and towns. If the AI started as
    Random AI, the choice will be randomized on startup.


Town choice priority:
    Defines how the AI will pair two towns. If the AI Started as Random
    AI, one of the following options will be picked at random on startup.

    - Most cargo produced first:
    The AI choses the most productive towns first when creating a service.

    - None, pick at random:
    The AI choses the towns at random when creating a service.

    - Shorter routes first:
    The AI choses towns which are closer to each other first when creating
    a service.

    - Longer routes first:
    The AI choses towns which are further from each other first when
    creating a service.


Is friendly:
    When enabled, the AI tries to avoid building its stations near
    stations of other companies. When disabled, it is allowed to do so.
    If the AI started as Random AI, the decision will be randomized on
    startup.


Air support:
    Enables or disables the usage of air routes.


Road support:
    Enables or disables the usage of road routes.


Can station spread:
    When enabled, the AI expands its road stations by distantly joining
    new station pieces, to enlarge station coverage. It may also join road
    stations with airports and vice-versa whenever possible. If the AI
    started as Random AI, the decision will be randomized on startup.


Approximate number of days in transit for road routes:
    Lower values may help pathfinding faster, but at the cost of lesser
    profits. Higher values may slow pathfinding and may not necessarily
    yield the best profits, assuming the default engines are being used. AI
    random value of up to -5/+5 is added on startup, and the limit can
    never go below 10 or above 150.


Road pathfinder profile:
    Select the behaviour of the pathfinder when connecting two towns by
    roads. If the AI started as Random AI, the choice will be randomized
    on startup.

    - Custom:
    Tweaked for low construction costs when the AI is poor, by avoiding
    watered coast tiles, which may result in some weird bridges across
    two coasts. May try to avoid going through drivethrough stations.
    May build more bridges or tunnels in difficult terrain, especially
    when the slopes are too steep. If the AI is rich, it may build really
    long bridges and tunnels. Relatively slow, but overall, the better
    planner.

    - Default:
    Though the pathfinder interval cost values have been reworked and some
    of the logic regarding bridges and how are roads connected to each
    other, the default profile tries to mimic the behaviour of the
    original LuDiAI pathfinder. It is not cost conscious regarding coasts,
    slopes or bridges, doesn't avoid drivethrough stations and does not
    build too long bridges or tunnels.

    - Fastest:
    Optimized for fastest planning speed, at the cost of low road reuse.
    It prefers fewer curves, which could result in roads going through
    sharp landscapes, or be longer than necessary. Can only build small
    bridges, which may not be ideal for maps with lots of water. Cannot
    build tunnels.


Road route capacity mode:
    Determines how the AI will handle the capacity of a route by managing
    the number of vehicles when there's enough cargo waiting at the
    stations. If the AI started as Random AI, the choice will be
    randomized on startup.

    - Maximum of 25 road vehicles:
    Depending on the cargo waiting, the AI may decide to add road vehicles
    to the route, as long as it doesn't go over 25. It adds one at a time
    per management cycle.

    - Estimate maximum number of road vehicles:
    Same as above, but instead of 25 road vehicles, the maximum number is
    based on the distance between stations, maximum speed of the engine
    and the number of loading bays available at the stations. Stations may
    also spread to accomodate more loading bays, and thus more vehicles.
    It also adds one at a time per management cycle.

    - Adjust number of road vehicles dynamically:
    In this mode, the AI will keep adding vehicles to the route whenever
    there's cargo waiting, but will also remove road vehicles if it finds
    its vehicles unable to move. It will be constantly doing this all the
    time, which may slow down management. Contrary to the other modes, it
    can add or remove multiple vehicles at once per management cycle.


Road route load orders mode:
    Determines how road vehicles set up their orders. If the AI started as
    Random AI, the choice will be randomized on startup.

    - Full load before departing:
    The vehicles will use 'Full load any cargo' on their go-to orders.

    - Load something before departing:
    A conditional order is placed between their go-to orders that Jump to
    their respective go-to order when load percentage is equal to zero.

    - May load nothing before departing:
    The default 'Load if available' is used on their go-to orders.


AI-GS communication support:
    Allow communication between AI and Game Script SCP libraries.
    Currently supports Company Value GS, where the AI will think twice
    before spending money in town actions, just to maintain the lead or
    to maintain catch-up against the company ranked first.