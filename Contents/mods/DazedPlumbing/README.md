# Dazed Utilities: Plumbing  (v0.17.0, Build 42)

Release 9 (0.15.0): **ice** with Dazed Utilities: Climate (frozen pipes and tanks, cracked tanks you weld shut), on top of release 8's drilled well, smoker and sprinkler schedule, release 7's biogas digester, release 6's fuel pump, release 5's water main and the Dazed Utilities core. Needs **Dazed Utilities: Core** (`DazedCore`), loaded first.
Works with *Dazed Utilities: Power* (generators and boilers on the pipes, the pump and purifier wired to a controller); needs nothing else.

## Main water panel (0.17.0)
A connected water main gets a **Water panel** (right-click the main -> Water main -> *Water panel*, the first row once a building is connected). It is one board, like Dazed Power's charge board: drag it by its body, close it with the X.
- **SUPPLY** and **DEMAND** dials (0-40 L/min, or up to the line rate when that is higher): what reached the house last minute and what its open fixtures want. The red arc on SUPPLY starts at the house's own rate.
- **LINE RATE**: click the left half of the strip for 1 L/min less, the right half for 1 L/min more (1 up to *Water main line rate*). The house never draws more than this.
- **Water tower**: every tank on the main's line together, with its percentage and litres (pale when frozen, olive when tainted). **TANKS ON LINE** lists up to three, the one feeding marked.
- **SOURCES ON LINE**: every pump, purifier, drilled well, downspout and rain barrel pushing into those tanks (and the pumps feeding a purifier), with its state and flow. The toggle switches an electric pump, purifier or well on or off; clicking the flow figure steps an electric pump or purifier through 25/50/75/100%.
- Lamps: **SUPPLY** (water on the line), **TAINTED**, **DRY**, **RATIONED** (the house wants more than its rate or the tanks hold), **PAUSED**.
- **FIXTURES**, in fill order: room, kind, level, litres, a **valve** toggle (a closed fixture gets nothing from the main) and up/down arrows that move it in the **fill order** (the first in line is filled first when water is short). Six rows show; the header arrows or the wheel scroll the rest. Fixtures with a tap of their own are listed last, without controls.
- **TODAY**: litres delivered since midnight on number wheels, with a bar for every hour.
- **CONNECT BUILDING** opens the Building Picker, as the menu does. **DRAIN FIXTURES ON SHUT-OFF**: when the main is shut off, every fixture it feeds is emptied once.
- **MAIN SHUT-OFF**: click the wheel, then click again within two seconds. It reads OPEN or PAUSED. It is the same switch as the main line's pause in the pipe menu: either one turns both.
- Who can use it: a player within the main's reach plus two squares, as for the picker. Every switch is a command the server checks (range, the fixture or machine still on this main) and limits to four a second; the window never writes anything itself. Works on a dedicated server and in hosted games.
- **Controls are mouse only** (no keys): a click is a press that moves the mouse 4 px or less, so the board still drags by its body; the wheel scrolls the sources and fixtures lists; the X closes it.
- **The wall panel** (item `Base.DazedWaterPanel`, recipe `MakeDazedWaterPanel`: Welding 2, 2 small sheet metal, a shut-off valve, 4 screws and a screwdriver; 4 kg). Hang it **inside a building, against a wall** on the side it faces (one to a square). It binds by itself to the water main that serves that building, at once when placed or when a main connects, and within a minute otherwise; a panel in a house no main serves can still be hung, and its menu says *No water main serves this building* until one does. Right-click it -> **Water panel** opens the main's board from indoors, worked through the panel (you stand within 2 squares of it). CONNECT BUILDING is greyed there (that stays at the main). If the main's square is not loaded on the server, the board says *Main out of range* and shows the last figures; the rate, shut-off, drain and valves still work, the machine switches wait. Lifting a panel changes nothing on the main; disconnecting or lifting the main leaves its panels unbound. Tiles 256-259 (sheet grown to 8x33), placeholder art from `tools/panel_art.py`.
- **With Dazed Climate**, a frozen square on the main's own pipe run or a frozen feeding tank lights FROZEN and the PAUSED lamp, and the shut-off card reads *frozen: waits for the thaw*. **With Dazed Power**, a running source shows its watts; an electric pump, purifier or drilled well without power reads *no power*.
- The guide (Dazed guide -> Plumbing) has a *Water panel* page.
- Art: the board looks for each part in `media/ui/DazedPlumbing/Board/` first (its own tank column, LINE RATE knob and MAIN SHUT-OFF wheel), then in Dazed Power's board folder (gauge faces, needles, lamps, toggles, number wheels, card corners) when that mod is loaded, and draws plain shapes for anything neither has. The tank column's sight glass is the rect x 9, y 19, 42x140 of its 60x170 case (`Board.TANK_WINDOW`); the water is drawn into it.
- **Blender renders** (Blender 4.2+, on the PC; `ART` is the folder holding `dup_render.py` and `pz_sprite_forge.py`, `MOD` this mod's folder). From Blender's Python console:
  ```
  ART = r"C:\Users\<you>\Zomboid\dup_art"; FAMILIES = ["wallpanel", "icons:DazedWaterPanel"]; exec(open(ART + r"\dup_render.py").read())
  BOARD_OUT = ART + r"\out\board"; exec(open(r"<MOD>\tools\blender\board_render.py").read())
  ```
  or headless:
  ```
  blender -b -P "%ART%\dup_render.py" -- "%ART%" wallpanel icons:DazedWaterPanel
  blender -b -P "%MOD%\tools\blender\board_render.py" -- "%ART%\out\board"
  ```
  Then pack (from `%MOD%`): `python tools\pack_panel_renders.py --renders "%ART%\out"` (add `--dry-run` to see what it would do). It copies the board parts to `media/ui/DazedPlumbing/Board/`, packs sprites 256-259 (E S W N; the panel faces the wall it hangs on, like the downspout) and the 32 px icon, re-checks the tile sheet, and writes `media/ui/DazedPlumbing/Board/.rendered`, after which `panel_art.py` will not overwrite the renders without `--force`.
- Saves: nothing to migrate. A main nobody opens the panel on behaves exactly as before; the new fields (`rate`, `shut`, `drain`, `valves`, `prio`, figures) are added only when used. A main whose line was paused before 0.17.0 reads as shut.

## Ice (0.15.0)
With **Dazed Utilities: Climate** loaded, water freezes. A frozen pipe square passes nothing, like a closed valve, until
it thaws; a frozen water tank gives and takes nothing (its Fluid menu shows it empty). A tank that freezes while over
80% full may **crack**: once thawed it leaks 2% of its capacity an hour until the crack is welded (*Tank -> Weld the
crack*: a blowtorch with 2 uses, a welding mask, Welding 2). The tank menu and gauge show **FROZEN** and **CRACKED**.
Climate decides when things freeze and handles pipe insulation; Plumbing only honours the `frozen` and `cracked`
fields, so it needs nothing new without Climate.

## The drilled well (0.14.0)
An electric borehole pump for clean water. Stand it on **bare natural ground in the open** (grass or dirt, the water pump's rule), one to a square, and pipe it to a water tank like a pump (*Well line -> Pipe to: <tank>*).
- **Power:** a **400 W** Dazed Power load (LOADS label WELL, load kind `well`). Like the electric fuel pump it runs **only when wired to a powered Dazed Power controller**; the town grid or a generator's square does not count. Without Dazed Power installed it is simply unpowered. It has the same on/off switch as the electric pumps and counts as working (billed) only while it is pumping.
- **Water:** about **15 L a minute of clean water** while powered and the tank has room. It draws from deep ground, so it does not use or dry out the square's ground water the hand and electric pumps share. When the tanks are full it waits and draws nothing.
- The menu and its tooltip show whether it is wired, its status (pumping, tanks full, switched off, no power, not piped, line broken or paused) and its output.
- **Build:** recipe `MakeDazedDrilledWell`, **Welding 3 and Mechanics 2**: 4 metal pipes, 2 sheet metal, a shut-off valve, 6 screws; a blowtorch, a welding mask and a wrench (or pipe wrench). **27 kg**, so one piece. Tiles 248-251, placeholder art (`tools/well_art.py`, which also grew the sheet to 8x32).
- Dazed Power's priority table has no entry for `well` yet, so it sheds at Normal priority. The LOADS label key `IGUI_DazedPower_Load_well` lives in this mod's EN `IG_UI.json` (the game merges every mod's translations).

## The smoker (0.14.0)
A propane-fired smoke box. Pipe it to a **propane tank** like any machine (*Smoker gas line -> Pipe to: <tank>*), put **raw meat or fish** in its container (it is a container like a crate: open it in the loot window, 15 capacity), then right-click it -> **Smoker -> Light**.
- **Gas:** it burns **0.05 kg of propane an hour** while lit (0.4 kg for a full batch), drawn from the tanks on its line, fullest first. It lights only with gas on the line, and **goes out** by itself when the gas runs out or the line is closed or paused (light it again once there is gas). **Extinguish** puts it out.
- **Smoking:** every raw meat or fish item inside that has had **8 in-game hours** of smoke becomes smoked: marked `dazedSmoked` in its ModData, cooked, its freshness (`offAge` and `offAgeMax`) **six times longer**, and its name gains **(Smoked)**. Vanilla B42 has no smoked variants of its meats, so the item is changed in place instead of replaced.
- **What counts:** a Food with FoodType Meat, Fish, Game, Seafood or Poultry, any Dazed Butchery cut (`Base.DB_*`) and anything that answers `isMeat`/`isFish`; not food that is already cooked, burnt, rotten or smoked. An item taken out loses its smoke so far.
- **While you are away:** it works while its square is loaded and catches up the hours away when it loads again, **at most 48 h** (and only as long as the gas lasts).
- The menu and its tooltip show the propane on the line, whether it is lit (smoking, lit with nothing raw, not lit, went out) and how many items are smoking and the hours to go.
- **Build:** recipe `MakeDazedSmoker`, **Welding 2 and Cooking 3**: a metal drum, 2 sheet metal, a metal pipe, a shut-off valve, 4 screws; a blowtorch, a welding mask and a screwdriver. **26 kg**, so one piece. One to a square; like any vanilla container it can only be lifted empty. Tiles 252-255 with a `smoker` container, placeholder art (`tools/smoker_art.py`). No sandbox options: the numbers are constants at the top of `DUP_Smokers.lua`.
- Multiplayer: the server settles and changes everything; "Light / Extinguish" sends only the smoker and on/off. A smoked item is re-sent to the clients whole (removed and added again) so its new name and freshness show.

## Sprinkler schedule (0.14.0)
Each sprinkler has a **watering window** and a **Skip when raining** toggle (right-click -> Sprinkler -> **Schedule**).
- Window presets: **Always** (the default, as before), **Dawn** 05:00-08:00, **Evening** 18:00-21:00, **Night** 22:00-04:00. The start hour counts and the end hour does not; a window that ends before it starts runs over midnight.
- **Skip when raining** (on by default): while the rain intensity is above 0.05 the sprinkler waits. Snow does not count as rain.
- Outside its window, or in the rain, it asks the line for nothing and stops spraying within a minute (at once when you change the setting).
- The menu and the Sprinkler row's tooltip show the schedule and why it is waiting. Settings live in the sprinkler's ModData (`dazedSprinkler.from`, `.to`, `.rainSkip`) and are changed only on the authority, by a timed action. Lifting a sprinkler resets its schedule to the defaults.

### Patch notes 0.14.0
- New: **drilled well** (item `Base.DazedDrilledWell`, recipe `MakeDazedDrilledWell`, sprites 248-251, files `DUP_DrilledWells.lua`, `DUP_WellMenu.lua`, `tools/well_art.py`). A new `DazedCore.Power` load kind, `well` (400 W).
- New: **smoker** (item `Base.DazedSmoker`, recipe `MakeDazedSmoker`, sprites 252-255 with a `smoker` container, files `DUP_Smokers.lua`, `DUP_SmokerActions.lua`, `DUP_SmokerMenu.lua`, `DUP_SmokerWorld.lua`, `tools/smoker_art.py`).
- New: **sprinkler schedule** (window presets and the rain skip; new action `DUP_SprinklerSchedule`).
- The power switch now also works on the well; placement refuses a well off bare natural ground or outdoors.
- Boot line is now `252/252 tiles, 32/32 items`; 32 recipes. Tile sheet grown to 8x32 (now full).
- Tests: new `sprinkler_test.lua`, `well_test.lua` and `smoker_test.lua` in `run_all.sh`; `fuel_test.lua` and `digester_test.lua` expect the new counts. The version constant and `mod.info` still read 0.13.0 until the release bump.
- No sandbox options, no save migration: existing sprinklers keep watering at any hour, and now skip rain by default.
- Performance: pipe keys are parsed once (`DazedPlumb.Net.split` remembers), which the minute pipe and port ticks do
  for every pipe; the sprite-name pattern is built once instead of on every object a scan looks at. Tests: new checks
  in `net_test.lua`.

## The biogas digester (0.12.0)
A drum you feed rotten food and manure; it slowly makes propane for a **propane tank** you pipe it to (*Digester gas line -> Pipe to: <tank>*, same pipes and valves as any machine). It needs no power.
- **Add waste** (right-click the digester): a **rotten (or spoiled) food** item is 1 unit; a **manure item** (`Base.Dung_*`: cow, pig, sheep, chicken, turkey...) or a **use of a compost bag** (`Base.CompostBag`) is 2 units. The drum holds **40 units**; an item that does not fit stays in your pack. One timed action per item (the menu offers "everything suitable" or a single item).
- **Gas:** each unit makes **0.05 kg of propane** in all. A unit's mean digestion time is **24 in-game hours**, so the slurry shrinks by a fixed share per hour (about 63% of it in the first day, the same whether worked out each minute or all at once); 24 units make about 0.05 kg an hour.
- **Weather:** the air at the digester counts. **Below 10 C** it runs at half speed, **below 0 C** it stops (the waste waits).
- **Buffer and full tanks:** gas waits in a **2 kg buffer** and flows into the tank at up to 1 kg a minute. When the tank is full (or it is not piped, or the line is paused) the buffer fills and digestion **pauses** with the waste kept; a full drum of waste is exactly 2 kg of gas.
- **While you are away:** it works while its square is loaded; when it loads again it catches up the hours away, **at most 48 h**.
- The menu and its tooltip show **waste units, gas buffer in kg and status** (digesting, digesting slowly (cold), frozen, gas buffer full, idle) and the hourly output.
- **Build:** **Welding 2**: a metal drum, 2 metal pipes, 1 sheet metal, a shut-off valve, 4 screws, a blowtorch, welding mask and a screwdriver. **28 kg**, so one piece. One to a square. Lifting it empties it (waste and buffer are lost, like the purifier's buffer). Tiles 244-247, placeholder art (`tools/digester_art.py`). No sandbox options: the numbers are constants at the top of `DUP_Digesters.lua`.
- Multiplayer: the server settles and moves everything; "Add waste" sends only the digester and the item, and the server re-checks both.

### Patch notes 0.13.0

- Follows DazedCore's sandbox presets (`NeedWrench`, `MainReach`, `MainFlow`). The electric fuel pump has its Dazed Power
  load priority (Low by default).

### Patch notes 0.12.0
- New: biogas digester (item `Base.DazedDigester`, recipe `MakeDazedDigester`, sprites 244-247, files `DUP_Digesters.lua`, `DUP_DigesterActions.lua`, `DUP_DigesterMenu.lua`, `DUP_DigesterWorld.lua`).
- Tests: new `digester_test.lua` in `run_all.sh`; `fuel_test.lua` now expects 244 tiles, 30 items and 0.12.0.
- Boot line is now `244/244 tiles, 30/30 items`.
- Nothing existing changed in behaviour; the pump, tank and pipe files only gained the digester in their placement and boot lists.

## The fuel pump (0.11.0)
A pump for refuelling at the base. Pipe it to a **petrol tank** like any machine (*Fuel pump line -> Pipe to: <tank>*), then right-click it:
- **Refuel: <vehicle>** for a **parked vehicle (engine off) within 2 squares**: pick 10 / 25 / 50 L or *Until full*. It fills the vehicle's GasTank from the piped tank(s) (the fullest first).
- **Fill gas can: <can>** for a petrol can or other fuel container you carry (an empty petrol can works too).
- The menu shows the petrol on the line in litres, and how fast the pump moves it.
- **Hand fuel pump:** you crank it, 2 L a minute (a 2 L chunk per action), no power. **Welding 2**: 3 metal pipes, 2 sheet metal, a shut-off valve, 4 screws, screwdriver.
- **Electric fuel pump:** about 10 L a minute, a **200 W** load that counts as working only while it is moving fuel. It runs **only when wired to a powered Dazed Power controller** (not off the town grid or a generator's square) and has the same on/off switch as the electric water pump. **Electricity 3 and Welding 2**: a hand fuel pump (consumed), 4 electronics scrap, 3 electric wire, 1 engine parts, screwdriver.
- Both weigh under 30 kg (16 and 22), so they are one piece, not parts. Tiles 236-243, placeholder art.
- Dazed Power needs the load name `IGUI_DazedPower_Load_fuelpump` ("FUEL PUMP") to show it on its LOADS page.

## The water main (0.10.0)
A house plumbed from the outside. Build a **Water Main** (Welding 4: 3 metal pipes, 2 sheet metal, a valve, 6 screws; welding mask, blowtorch and pipe wrench) or find one in plumbing and hardware stock. Stand it **outdoors** within **6 squares** of the house, pipe it to a water tank like any machine (*Main line -> Pipe to: <tank>*), then right-click it -> **Connect a building...**: the Building Picker shades the house under the cursor (yellow: a click connects it; red: out of reach or already served by another main). Map houses come with their basements; a structure you built yourself is picked the same way, on a dedicated server too.
Once the town water is off, **every sink, bath, shower, toilet, washer and dishwasher inside** is fed from the tank every minute, up to **30 L a minute for the whole house** (shared among what is running). A fixture with a tap of its own keeps its tap. Tank dry: dry taps. Tainted tank: tainted taps (a purifier upstream fixes that). One main serves one building and a building takes one main; lifting the main or cutting its pipe disconnects it.
Sandbox: *Water main reach* (squares, 6) and *Water main line rate* (L/min, 30).

## What you get
- 18 tanks: 3 sizes (small ~10, large ~30, extra-large ~100) x 3 contents (propane in kg, gas in L, water in L) x 2 tiers.
- **Salvaged** tier: 80% capacity, starts leaking below condition 60. Found in loot, or rigged from scrap (screwdriver, small sheet metal, screws, duct tape).
- **Crafted** tier: full capacity, leaks below condition 35. Welded (welding mask, blowtorch, sheet metal, pipe; XL also metal bars).
- Right-click a tank: **Pour in** / **Take out into** (propane tanks and lantern bottles, water containers, petrol cans) / **Patch the tank** (small sheet metal + screws, +30 condition).
- Dangers: propane and gas tanks explode and burn if fire is next to them; damaged tanks leak over time (also while you are away).
- XL tanks can only be placed outdoors, with nothing overhead.
- Contents and condition survive picking a tank up and putting it down.

## Pipe networks (0.7.0)
Right-click a machine (a Dazed Power propane or petrol generator or steam boiler, a pump, the purifier, or a **water fixture**) -> **Fuel line / Pipe to: <tank>**. The menu shows the length and how many pipe sections it costs.
- **One line, many machines.** A run that ends beside a pipe already serving that tank **joins it** automatically, so one line can feed several machines and tanks. Pipes only join where their art shows a join (a branch gets a T-shaped square).
- **One fluid per line, colour-coded.** Water is blue, propane white, petrol red (the same as the tank barrels). Different fluids never join, and cannot share a square.
- **Fair sharing.** Machines on the same tank split what it holds evenly (a machine that wants less leaves the rest to the others). Pumps fill the tanks on their line by free room. Lines that meet at the same tank share it too.
- **Shut-off valves.** Right-click a plain run of pipe -> **Fit a shut-off valve** (needs a valve and Welding 2), then **Close / Open the valve**. An open valve is a shade darker than its pipe; a closed valve is drawn near-black and stops the flow past it.
- **Costs (placeholders, easy to change).** One **pipe section** per square laid or mended; a metal pipe makes four (craft with a blowtorch and welding mask, Welding 1). **Welding 1** is needed to lay, mend or join pipe; a **valve** (metal pipe + 2 screws + blowtorch, Welding 2) to fit one. Disconnecting a machine lifts the dead-end pipe and hands half of its sound sections back (`Pipes.REFUND`).
- **Disconnect** takes a machine off its line and lifts any pipe left dead-ended; cut and mend work square by square (right-click a pipe). A machine standing right beside a tank needs no pipe.
- Indoors the pipe runs overhead, outdoors on the ground, and never blocks movement. Outdoor pipes wear under zombies and vehicles and break at 0 (a broken square stops the flow until mended).
- Old pipes and fuel lines from 0.4-0.6 are **not migrated**: start new worlds, or cut the old links.
- With *Dazed Utilities: Power*: **propane / petrol generators** burn straight from a tank on their line (drawn as fuel is used, even across a long time-skip; the generator is pointed at the fullest tank on its line). **Steam boilers** are topped up with water (20 L/min).
- Vanilla generators are not supported: Dazed Power turns every placed generator into its own battery controller.
Other mods register machines with `DazedPlumb.Links.register{...}` (see DUP_Links.lua); a sink may give its own `rate(obj)` (the water main does). Machines that need power are told to the core: `DazedCore.Power.registerLoad{...}` (see DUP_Power.lua).

## Taps (0.7.0)
Sinks, baths, showers, toilets and washing machines are **water sinks** like a boiler: pipe one to a water tank and the tank tops it up every minute (20 L/min, shared fairly). **Tainted in the tank means tainted at the tap.** While the town supply still runs, fixtures are left alone.
Console lines to check: `town water: WaterShutModifier=...` and `tap: addFluid on the fixture worked|did NOT raise it` (or `setWaterAmount ...`). If a fixture type does not take water, report which one.

## Rain collection (0.8.0)
- **Open-topped tanks catch rain.** A water tank with open sky over any of its squares fills while it rains: 10 L per open square per hour at full downpour (`Model.RAIN_PER_SQUARE_HOUR`), scaled by the rain's intensity. Rainwater is clean. Only while the tank is loaded: rain that fell while you were away is not counted. Indoor and roofed tanks catch nothing.
- **Barrel beside a building catches its roof.** A water tank standing outside with a building square touching it also takes the roof's runoff: 2 L per roof square per hour at full downpour (`Model.RUNOFF_PER_ROOF_SQUARE_HOUR`), at most 60 L/h per tank, split between the tanks beside that building. The roof is sized from the building's floor plan. The tank's status line shows CATCHING RAIN. This is the stand-in for real gutters and downspouts.
- **Vanilla rain barrels are water sources.** Right-click a rain collector barrel -> **Rain barrel line -> Pipe to: <tank>**. The tank draws the barrel down (up to 20 L/min), and the water is tainted if the barrel's is.
- Console lines to check: `rain barrel: adjustAmount worked|did NOT lower it` (or `setWaterAmount ...`). If barrels are not recognised, tell me the name the tile shows.
- **Water dispensers** now count as tap fixtures (pipe one to a tank like a sink).
- **Downspouts (0.9.0).** Craft one (Welding 1: welding mask, blowtorch, sheet metal, metal pipe, 2 screws) and place it on an outdoor square with a building wall against the side it faces (the sprite faces its wall; rotate to choose). While it rains it takes its share of that building's **whole roof** into a 20 L buffer, up to **80 L/h** (`Model.DOWNSPOUT_MAX_PER_HOUR`). It is a water source like a pump: right-click it -> **Downspout line -> Pipe to: <tank>**, or stand it beside a tank. Its water is clean. The roof is shared equally between every downspout and every barrel beside the same building (a barrel is capped at 60 L/h), so a big roof wants several downspouts: a house of 8x10 squares (160 L/h at full rain) fills two.

## Multiplayer
Every change to pipes, tanks, wells and links is made by the **authority** (single player, or the server): timed actions run their `complete()` there, and the once-a-minute ticks do nothing on a client. Pipes and wells live in global ModData that the server transmits when something changes (and a client asks for on joining). Dedicated servers are a design target; this has not been run on one yet.

## Install
Drop the `DazedPlumbing` folder into `Zomboid/Workshop/<anything>/Contents/mods/` (or `Zomboid/mods/`), enable "Dazed Utilities: Plumbing". Art is hand-built from simple shaded boxes (placeholder quality, but aligned).

## First-test checklist (things I could not verify outside the game)
Console lines to look for (`Zomboid/console.txt`):
- `DazedCore: ready -- 1.0.0, heavy parts v2, ...` then `DazedPlumbing: ready -- 252/252 tiles, 32/32 items`
- `DazedPlumbing: tank loot in N lists (...)` and `water main loot in N lists (...)`, and which lists were skipped (list names are guesses).
- `DazedPlumbing: adding water/gas to an empty container: worked|failed` (taking out into an EMPTY bottle/can).
Fuel-line test: link a Dazed Power propane generator to a propane tank, run it, and watch the tank drop as it burns.
Fuel pump test (0.11.0): pipe a hand fuel pump to a petrol tank, park a car beside it with the engine off and refuel it, then fill a petrol can. Check the console for `vehicle tank set ok, read back N` and, for an empty can, `raising an empty container with gas: addFluid worked`. Wire an electric fuel pump to a Dazed Power controller: it should refuse until wired and powered, then move about 10 L a minute.
Digester test (0.12.0): build one, pipe it to a propane tank, add a rotten food item and a manure item (the items must disappear and the menu show 3 units), and watch the tank rise by about 0.1 kg in the first day (0.15 kg in all). Check the manure and compost item names match the game (`Base.Dung_*`, `Base.CompostBag`), that the metal drum (`Base.MetalDrum`) is accepted by the recipe, and that "Add waste" works from a server client. Try it below 10 C and below 0 C, and with a full tank (the buffer should stop at 2.00 kg).
Drilled well test (0.14.0): build one (check the recipe accepts a plain `Base.Wrench` or a pipe wrench), place it on grass outdoors (a floor or indoors should be refused), pipe it to a water tank and wire it to a Dazed Power controller: it should refuse until wired and powered, then add about 15 L a minute of clean water, show WELL at 400 W on the LOADS page and stop drawing when the tank is full.
Smoker test (0.14.0): place one, check it opens as a container titled "Smoker" (the tile property `container = smoker` with `ContainerCapacity = 15`) and refuses to be lifted while full. Pipe it to a propane tank, put a raw steak and a raw fish in, light it, and after 8 in-game hours both should read "(Smoked)", be cooked and keep much longer; the tank should drop about 0.4 kg. Check the names and freshness also show on a server client (the item is re-sent), that it goes out when the tank is empty or its valve is shut, and that a Dazed Butchery cut is accepted.
Sprinkler schedule test (0.14.0): set Dawn, check it waters only from 05:00 to 08:00 and the menu says it is waiting otherwise; set Night and check it waters after midnight; with the rain skip on it should stop spraying in the rain and the console should not complain about `getTimeOfDay` or `getRainIntensity`.
Water main test: pipe a main to a full water tank, connect a house, run a sink inside: the tank should drop and the main's menu should count the fixtures it feeds.
Try: craft a small tank, place it, pour water in from a bottle, take it back out, lift and re-place (amount kept), light a fire next to a gas tank.

## Known limitations
- Not yet tested in multiplayer or on a dedicated server (the code keeps every change on the server, but nothing has been run there).
- Rain that falls while a tank's area is not loaded is not counted.
- A sprinkler only waters crops on its own floor. Its schedule follows the game clock's hour; there is no custom hour entry, only the presets.

License: CC BY-NC-SA 4.0 (same as the core and Dazed Power).

## Irrigation: the garden sprinkler (0.9.7)
- Craft a **Garden Sprinkler** (Welding 1: welding mask, blowtorch, metal pipe, scrap metal, 2 screws) and stand it among your crops; one to a square.
- Pipe it to a water tank like a tap: right-click -> **Sprinkler line -> Pipe to: <tank>**.
- Every minute it waters the **thirsty crops within 3 squares** (`Sprinklers.RADIUS`). Each crop is topped up to the middle of its own good range (between its waterNeeded and waterNeededMax), never over it, so it cannot drown a field. Crops already in range, including beds the rain keeps wet, are left alone.
- Water use: 0.1 L per point of a crop's water level (a dry bed to 70 takes 7 L), at most 10 L a minute per sprinkler. It shows its spray while it waters.
- Its menu shows how many crops are in reach and how many are thirsty, and has an on/off switch.
- Crops are watered on the server (the farming system lives there). Untested in game.

## Water pumps (0.5.0)
- **Hand Pump** and **Electric Water Pump** (craft: hand = 3 metal pipes, 2 sheet metal, 4 screws, Welding 2; electric = a hand pump + electronics scrap, wire, engine parts, Electricity 3).
- Place them only on **bare natural ground (grass/dirt) in the open**; the menu says why if refused.
- They draw from **the ground under them**, which can **run dry**: 800 L (1600 near open water), refills 30 L/hour (3x in rain). The water level belongs to the square -- lifting a pump and replacing it does not reset it.
- **Pipe it to a water tank** (right-click the pump -> Pump line -> Pipe to ...). Pipes work as for machines, but water flows *into* the tank.
- **Hand pump:** right-click -> *Work the handle* (5 L a stroke into the tank). **Electric:** pushes 8 L/min by itself while the square has mains power (a generator or Dazed Power system). It stops without power, and with Dazed Power it is a **real load**: 400 W on the controller's LOADS page (as WATER PUMP) only while it is actually working (piped, tank has room, ground has water).
- Both can **fill a carried container** straight from the ground.
- Placeholder art; untested in game.

## Water quality and the purifier (0.6.0)
- **Water tanks now track clean vs tainted water.** Ground water from a pump is **tainted**; so is tainted water you pour in. A tank counts as tainted once 10% or more of what it holds is dirty, and gives tainted water when you take it out (into a container that holds no clean water). The tank menu shows [clean]/[tainted].
- **Water Purifier** (craft: sheet metal, metal pipes, electronics scrap, wire, screws; Electricity 3): place it between a pump and a tank: **pump -> pipe -> purifier -> pipe -> tank** (right-click the pump -> *Pipe to: Water purifier*; right-click the purifier -> *Pipe to: <tank>*).
- It needs **power** and is a real **Dazed Power load** (150 W while working, listed as PURIFIER). Both can also be **wired** to a Dazed Power controller instead of standing on a powered square.
- **Filter cartridge** (craft from 4 water-purifying tablets + 2 ripped sheets): fit it from the purifier's menu for **20 L/min**; it treats ~500 litres, shows its remaining condition, comes back out if you remove it, and travels with a lifted purifier. **Without a filter** it still purifies, but only **2 L/min**.
- A purifier buffers 20 L and cannot feed another purifier. Placeholder art; untested in game.

## First-test checklist for 0.7.0 (new, not yet run in game)
1. `DazedPlumbing: ready -- 208/208 tiles, 26/26 items`.
2. Craft pipe sections (Welding 1), pipe a boiler or generator to a tank: the pipe should show **tinted** (blue for water). If it is grey, the tint did not apply (`setCustomColor`); tell me and I will switch to separate sprites.
3. Pipe a second machine to the same tank: its run should end at the first pipe (a T), costing fewer sections, and both machines should draw.
4. Fit a valve, close it, check the branch goes quiet; open it again.
5. Cut a pipe and mend it. Disconnect a machine and check some sections come back.
6. Pipe a sink to a water tank and run the tap; check the two console lines above.
7. On a server: do 2-5 as a client, and check the second player sees the pipes and the menu counts without relogging.

## Art and tile tools (`tools/`)
All world sprites and inventory icons are Blender renders (0.9.4), made with the pz-sprite-forge camera and light rig (`tools/blender/`, MIT):

1. In Blender 4.2+, run `tools/blender/dup_render.py` from the Python console with `ART` set to a folder holding it and `pz_sprite_forge.py`, and `FAMILIES` set to any of `tanks` (or `tanks:water` and so on), `pipes`, `pumps`, `purifier`, `downspout`, `wallpanel`, `icons` (or `icons:DazedWaterPanel` and so on). The cells land in `ART/out/<family>/<sprite index>.png` at 2x.
2. Large and XL tanks span 2 or 3 squares. Each piece is rendered with its own square under the camera, plus an `<index>_m.png` mask of what stands on that square.
3. `python3 tools/pack_art.py <out dirs...>` cuts the pieces with their masks, shrinks the cells to 128x256, sharpens them and repacks `dazedplumbing.pack`.
4. `python3 tools/make_icons.py <out>/icons` writes the 32x32 icons.
5. `python3 tools/scene_preview.py` lays cells out the way the game draws them, for checking.

The pipes are rendered light grey on purpose: the game tints them per fluid.

`pack_tiles.py check` confirms the tile definitions, the pack and the item scripts agree (and that the `.tiles` file round-trips byte for byte). `pack_tiles.py grow --rows N` adds room for new sprites without moving any existing index. `pzformat/` holds the pack and tile readers and writers from pz-sprite-forge (MIT). Saved worlds remember sprite names, so only ever append.

`panel_art.py` draws the wall water panel's placeholders (sprites 256-259 and its icon), grows the sheet to 33 rows and gives the tiles their properties; once `pack_panel_renders.py` has packed the Blender renders it refuses to run without `--force`. `blender/board_render.py` renders the panel board's own parts (see *Blender renders* under the Main Water Panel). `fuelpump_art.py` draws the fuel pump stand-ins (sprites 236-243, two icons, tile properties); run `pack_tiles.py grow --rows 31` first. `digester_art.py` (244-247), `well_art.py` (248-251, grows the sheet to 32 rows itself) and `smoker_art.py` (252-255, the last free row) do the same for the digester, the drilled well and the smoker. Row 33 holds the panel and has 4 free tiles (260-263); after them the next sprite needs `pack_tiles.py grow --rows 34`.

`pipe_art.py`, `machine_art.py` and `icon_art.py` are the older flat drawings, kept for reference only. Running them would overwrite the renders.

## Tests (outside the game)
`tools/tests/` runs the real Lua on a stand-in engine (Lua 5.1-compatible code; any Lua 5.1-5.4 will do):
```
cd tools/tests
lua net_test.lua                               # the pure network code
lua plumbing_test.lua                          # links, actions, ticks, sync, taps, valves, flow
lua place_test.lua                             # a large tank picked up is one item
lua mains_test.lua                             # the water main: picking a house, reach, feeding, taps kept
lua panel_test.lua                             # the main water panel: fill order, valves, throttle, shut-off, drain, figures, commands, the window
lua board_test.lua                             # the panel's face: controls, scrolling, scaling, drawn stand-ins without textures
lua wallpanel_test.lua                         # the wall panel: placement, binding, working the main through it, the board by key
lua fuel_test.lua                              # the fuel pumps: litres per action, limits, hand vs electric, power, cans, vehicles, sprite and item counts
lua digester_test.lua                          # the biogas digester
lua sprinkler_test.lua                         # the sprinkler schedule: windows (over midnight too), rain skip, the action, the tick
lua well_test.lua                              # the drilled well: output per minute, power by wire only, clean water, full tanks, the load
lua smoker_test.lua                            # the smoker: burn rate, smoking timer, 48 h catch-up, no gas or a shut line, the smoked-food change
./run_all.sh                                   # every test above that run_all.sh lists
# each takes <lua root> [<core lua root>]; the defaults expect DazedCore checked out beside this folder
```

## Changes
- **0.17.0.** **Main water panel** (see its section): a board for a connected water main with supply and demand dials, the house's line rate, the tanks and sources on the line, per-fixture valves and fill order, today's litres and a main shut-off with an optional drain, and a **wall panel** item that opens it from inside the house. No save migration.
  - *Patch notes:*
    - New files: `DUP_MainPanel.lua` (server commands `mainValve`, `mainPrio`, `mainRate`, `mainShut`, `mainDrain`, `mainMachine`, `mainInfo` through `DazedCore.Net`, 250 ms / 500 ms limits), `DUP_BoardLayout.lua` (the face as draw ops), `DUP_Board.lua` (the window); tests `panel_test.lua` and `board_test.lua`.
    - Water main: optional entry fields `rate`, `shut`, `drain`, `drained`, `valves`, `prio`, `lpm`, `today`, `hist`, `histDay`, `used`. `W.put` fills in priority order and skips closed valves; the minute tick runs `W.beforeFlow` / `W.afterFlow` around the link tick for the figures, use detection and the drain. Figures alone are synced at most every 5 game minutes.
    - The main line's pause and the panel's shut-off are one switch (new optional adapter hook `onSource` in `L.setSource`).
    - The main's fixture list is no longer rescanned when the mains table changes, only when the pipes or the footprint do.
    - Fixtures: `X.kindOf`, `X.amount`, `X.tainted`, `X.selfFed`, `X.empty`.
    - Wall panel: `DUP_WallPanels.lua` (placement rule, binding, the server-only `DazedPlumbPanels` list and its minute tick), `DUP_PanelMenu.lua` (menu and guide page), item, recipe, tiles 256-259 (`tools/panel_art.py`, sheet 8x33). Boot line `256/256 tiles, 33/33 items`; 33 recipes.
    - The board opens by key: `DUP_Board.open(player, mainOrKey, { via = {x, y, z}, readOnly })`; `mainInfo` answers `waiting = true` while the main's square is unloaded on the server. Climate's frozen pipes count in `W.status`.
    - Tests: new `wallpanel_test.lua`; `fuel_test.lua` and `digester_test.lua` expect the new counts.
- **0.16.0.** Optimization pass: graph caches keyed on the pipe table's own version, batched ModData sends from the minute ticks, cached port squares and fixture lists, memoized sprite lookups, and water-main picker commands through `DazedCore.Net`. No save migration.
  - *Fixes:*
    - **Gauge on a digester-fed tank (MP):** opening the gauge on a client no longer settles the digester there (it advanced the clock, digested waste and sent ModData from the client). A client's `available()` returns `Dg.preview`, the same figure worked out without writing; `settle`/`publish`/`refresh` on digesters and smokers are authority-only.
    - **Memory:** the digester, smoker, tank and downspout tables no longer rely on weak keys (the game's Lua ignores them). Each minute tick forgets a machine that is gone along with what it last showed clients; the tank roof memo empties every in-game hour.
    - **Wells table:** a well with no pump on its loaded square is forgotten once it has refilled (every ten game minutes), so the synced wells table stops growing. A drained well keeps its level, so lifting and re-placing a pump still finds it; unloaded squares are kept.
    - **Ports:** a device swapped for another within a minute with no object event now gets the right port (the re-check compares sprite names as well as the object count).
- **0.11.0.** **Fuel pump** (see its section): hand (2 L/min) and electric (10 L/min, 200 W, Dazed Power wire only). Refuels a parked vehicle within 2 squares and fills petrol cans from the piped petrol tank. New: `DUP_FuelPumps.lua` (model, sprites, link adapter), `DUP_FuelActions.lua` (`DUP_FuelVehicle`, `DUP_FuelCan`), `DUP_FuelMenu.lua`, 2 items, 2 recipes, 8 sprites (236-243, tile sheet grown to 8x31), EN text, `fuel_test.lua` and `run_all.sh`. The electric pump is a new `DazedCore.Power` load (`fuelpump`).
  - *Patch notes:* the power switch now also works on fuel pumps; placing a fuel pump is limited to one per square; boot check counts 240 sprites and 29 items. No sandbox options, no save migration. The vehicle tank calls are untested in game (see the checklist).
- **0.10.0.** **Needs Dazed Utilities: Core.** What both Dazed mods shared moves there: heavy parts (now v2, both engine argument orders), sync, notes, the Building Picker and the power registry. `DU_HeavyParts` and the old power shim are gone from this mod; the pump and purifier are registered as loads with `DazedCore.Power` (DUP_Power.lua), and Dazed Power bills them; original Dazed Power is no longer supported. Server notes travel through the core's command. **Water main** (see its section): item, recipe, loot, 4 sprites (232-235, placeholder art), two sandbox options, the `DazedPlumbMains` synced table. Link sinks may give a `rate` of their own. Tests take the core's Lua root as a second argument; `tools/pzformat` now lives in the core (the tools look there).
- **0.9.12.** Heavy tanks come apart into parts, like a bed or shelving: anything over 30 kg is carried as 2-4 parts named "(1/2)", "(2/2)" and so on, each 30 kg or less. Placing it needs every part in your inventory, and the other parts are used up when it goes down. Large and XL tanks must be emptied before they can be picked up; the tank menu says so. Crafted or looted heavy tanks split the same way within a minute of reaching your inventory.
- **0.9.11.** From the full test pass:
  - **Fluid menu on LG/XL tanks:** clicking any square of a long tank now gives the Fluid menu (the game only adds its own on the tank's first square).
  - **Tank to tank:** right-click a tank > *Pipe to another tank* to run a line to another tank of the same type. Tanks on one line even out like connected barrels (up to the line's flow a minute; a shut valve stops it).
  - **Rename tanks:** *Rename tank* in the tank menu; the name shows in the menu title, the gauge window and the *Pipe to* lists.
  - **Admin fill:** admins (or debug mode in single player) get *[Admin] Fill tank* on every tank, propane included.
  - **Hand pump:** a stroke takes half as long again, so the lever and handle move 50% slower.
  - **Pipes over farm plots:** crops, grass and other ground cover no longer push a run around them. In debug mode, right-clicking a square shows whether a pipe may cross it and, if not, why.
  - **Indoor runs keep to the walls:** an overhead run prefers squares beside a wall, so it hugs the walls and drops down on the wall side of what it feeds.
  - **Downspouts (and any device next to a run):** the last pipe square now always reaches into the device's square and gets its port fitting, even for lines laid before 0.9.10.
  - **Shutoff valve redrawn:** a slimmer brass valve threaded onto the pipe, with the pipe visibly running through it (8 Blender sprites).
- **0.9.10.** Pipes now visibly join what they feed: where a pipe meets a tank, pump, purifier, sprinkler, downspout or tap, a fitting on the device's own square carries it in. For a large or XL tank it runs underneath and rises into the belly with a flange; for anything else it runs in to the foot. An overhead (indoor) pipe drops to the ground first instead of meeting the tank wall at head height. Fittings come and go with the pipe and the device (within a minute when a device is placed or lifted) and are tinted like the pipe. 16 new Blender sprites (`ports` family in `dup_render.py`).
- **0.9.9.** Fixes from play:
  - **Fluid menu on tanks:** water and petrol tanks now carry a real fluid container that mirrors what they hold, so the game's own *Fluid* menu (info, transfer, empty), drinking, washing and filling work on them. Whatever the game takes out or pours in comes off or goes onto the tank within a minute (at once for pours and pick-ups). Propane tanks are unchanged. A full LG/XL tank still can't be rotated in place.
  - **Sinks, tubs and showers:** every plumbable fixture is found now, including industrial sinks and anything set on a counter or worktop, since the menus look at every object on the clicked square. Piped fixtures get water in their own fluid container, so baths, showers and sinks offer washing and filling once the town water is off. Tainted tank water stays tainted at the tap.
  - **Sprinkler piping:** the sprinkler's *Pipe to* rows show up (the menu was only looking at the object under the mouse).
  - **On/off switch:** electric pumps and purifiers have *Turn on* / *Turn off*. Switched off, they move no water and draw no power.
  - **Hand pump animation:** the character works the lever (the game's hand-press animation), and the handle goes down twice a stroke with water running from the spout (4 new Blender frames). Filling a container at the hand pump does the same. Only the player pumping sees the handle move.
  - Fixed the flow lines showing a formatting error instead of the percentage.
- **0.9.8.** Polish and speed:
  - **Pipe wrench:** laying, mending and cutting pipe and fitting valves need a pipe wrench in your inventory. Turning a valve by hand does not. A sandbox option (*Dazed Plumbing > Pipe work needs a pipe wrench*) turns this off.
  - **Sounds:** the game's own sounds for pumping, pouring water, and wrench work on pipes, valves, filters, flow settings and patching.
  - **Faster ticks:**
    - The pipe networks are worked out once and reused until a pipe changes, instead of rebuilt from every pipe each minute.
    - Which device an object is gets remembered by its sprite.
    - A tank's roof lookup is kept for an in-game hour.
  - The Known limitations list is brought up to date.
- **0.9.7.** Irrigation: the garden sprinkler (see its section), with Blender sprites (idle and spraying, 204 to 211) and an icon. **Tank gauge window:** a tank's menu has *Open gauge*. It shows a live gauge in the fluid's colour, the amount, condition, water quality, leaking or catching rain, the trend in and out per hour (with time to full or empty), a graph of the level while it is open, and every device feeding or drawing from it and what each is doing. The boot line now counts every sprite block, gaps included: expect `DazedPlumbing: ready -- 208/208 tiles, 26/26 items`.
- **0.9.6.** Tank sizes reviewed to match the new art (`Model.NOMINAL`, now per type; salvaged tanks hold 80%):

  | | Small | Large | XL |
  |---|---|---|---|
  | Water, petrol | 200 L (a 55-gallon drum) | 1000 L (a 275-gallon basement tank) | 2000 L |
  | Propane | 45 kg (a 100 lb cylinder) | 200 kg | 400 kg |

  The old sizes were 10 / 30 / 100. Propane stays below a real tank's fill so it remains scarce (a vanilla propane tank is 9 kg). To keep up with the bigger tanks:
  - a well holds 800 L (was 300) and refills 30 L/h (was 20)
  - a filter cartridge treats 500 L (was 200)
  - the hand pump adds a 250 L choice

  Tanks in existing saves keep what they hold and simply have more room.
- **0.9.5.** Fixes and controls from the in-game check:
  - **Tanks:** picking up a large or XL tank gives back ONE tank (tile property `ForceSingleItem`), still carrying its water and condition.
  - **Downspout lag:** the right-click no longer stalls the game. The pipe routes it previews remember each square's answer for a moment, a search gives up after 2500 squares, tanks beyond the longest run are not searched, and at most the 8 nearest are planned.
  - **Hand pump:** *Work the handle* now asks how much: 5, 25, 50, 100 or 250 L, or until the tanks are full. It stops by itself when the tanks fill or the well runs dry.
  - **Flow setting:** the electric pump and the purifier have a *Set flow* choice (25, 50, 75 or 100%). Their menus show the flow in L/min and whether water is moving. Power draw scales with the flow.
  - **Visible valves:** a shut-off valve is now a brass ball valve on the pipe, its red lever along the pipe when open and across it when closed (8 new Blender sprites, 196 to 203). Valves fitted in older saves get theirs when their chunk loads.
  - **Counter sinks:** sinks set into kitchen counters can be piped. They are recognised by the engine's `waterPiped` flag, or as a fixtures tile that holds water.
- **0.9.4.** All art redone as Blender renders to match Project Zomboid's look: tanks, pipes, both pumps, the purifier, the downspout and all 25 inventory icons. Large and XL tanks are now tall basement-oil-tank style: a flat-sided oval body on four steel legs, about 1.4 to 1.5 squares high. Salvaged ones are faded and rusty and stand on bricks. Each fluid keeps its colour (water blue, propane white, petrol red) and gets its own fittings. Small tanks: a 100 lb propane cylinder, a red steel drum (the crafted one carries a drum pump) and a blue plastic drum with a spigot. Pipes are threaded steel with couplings, sitting on small blocks outdoors and hung from rods overhead. Sprite indices are unchanged, so existing saves keep working.
- **0.9.3.** The electric pump and the purifier can be **wired to an Dazed Power controller** when *Dazed Power* 0.9.0+ is installed (a power hook, `DazedPlumb.externalPower`, that Dazed Power fills in). A wired machine runs while that controller's output is on and is billed by it, not by the radius sweep. On the LOADS page they now read WATER PUMP and PURIFIER instead of the fuel pump's label.
- **0.9.2.** Fixes from the first in-game check: the hand pump's menu crashed and never saw the tank's room (it used the pre-0.7 single-tank link); shut-off valves can now go on any sound pipe square (short lines next to machines had nowhere to fit one) and the option always shows, greyed with the reason; sinks, rain barrels and the town-water check read tile properties through Build 42's get/has as well as the old Val/Is.
- **0.9.1.** New inventory icons for the pipe section, valve, hand and electric pumps, purifier, filter cartridge and downspout, drawn in the same style as the world sprites (`tools/icon_art.py`). Tank icons unchanged.
- **0.9.0.** Downspouts: a wall-mounted rain source that takes a share of the whole roof (80 L/h each) and feeds a tank by pipe or adjacency. New tiles 192-195, item, recipe and icon; tile sheet grown to 8x25. Untested in game.
- **0.8.1 art.** Pump (hand, electric) and purifier sprites redrawn centred on the tile, so pipes meet them (the old ones sat about 20 px low and clipped at the bottom of the tile). Regenerate with `python3 tools/machine_art.py` (the same Pillow tool chain as `tools/pipe_art.py`). Inventory icons are unchanged. Untested in game.
- **0.8.0.** Rain collection (open water tanks catch rain, and ones beside a building catch its roof; vanilla rain barrels pipe to tanks), water dispensers as taps, pipe colours now match the barrels (water blue, propane white, petrol red; an open valve is a shade darker). Untested in game.
- **0.7.0 art fix.** Pipe sprites redrawn edge to edge and centred on the tile (the old ground art was clipped and off-centre, so pipes showed gaps). Regenerate with `python3 tools/pipe_art.py` (needs Pillow; `tools/pzformat/` is MIT, from pz-sprite-forge). Untested in game.
- **0.7.0.** Shared pipe networks (auto-merge, one fluid per line, colour tint, fair sharing, valves); taps for water fixtures; pipe sections and valve costs gated by Welding; MP hardening (authority-only ticks, synced pipe and well tables, client reads never write). Pipe records moved to the `DazedPlumbNet` table; older pipes are not migrated.
