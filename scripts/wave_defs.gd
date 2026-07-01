class_name WaveDefs

# UnitType values: 0=ALPHA, 1=BRAVO, 2=CHARLIE
# Each wave has arrays per side: north, south, east, west
# Each entry: {"type": int, "count": int}

const WAVES: Array = [
	{
		"north": [{"type": 0, "count": 2}, {"type": 1, "count": 1}],
		"south": [{"type": 1, "count": 2}],
		"east":  [{"type": 2, "count": 1}],
		"west":  [{"type": 0, "count": 1}],
	},
	{
		"north": [{"type": 0, "count": 2}, {"type": 1, "count": 2}],
		"south": [{"type": 1, "count": 2}, {"type": 2, "count": 1}],
		"east":  [{"type": 2, "count": 2}, {"type": 0, "count": 1}],
		"west":  [{"type": 0, "count": 2}, {"type": 1, "count": 1}],
	},
	{
		"north": [{"type": 0, "count": 3}, {"type": 1, "count": 2}],
		"south": [{"type": 1, "count": 3}, {"type": 2, "count": 2}],
		"east":  [{"type": 2, "count": 3}, {"type": 0, "count": 2}],
		"west":  [{"type": 0, "count": 3}, {"type": 1, "count": 2}],
	},
	{
		"north": [{"type": 0, "count": 3}, {"type": 1, "count": 3}, {"type": 2, "count": 1}],
		"south": [{"type": 1, "count": 3}, {"type": 2, "count": 3}],
		"east":  [{"type": 2, "count": 3}, {"type": 0, "count": 3}],
		"west":  [{"type": 0, "count": 3}, {"type": 1, "count": 2}, {"type": 2, "count": 2}],
	},
	{
		"north": [{"type": 0, "count": 4}, {"type": 1, "count": 4}, {"type": 2, "count": 3}],
		"south": [{"type": 1, "count": 4}, {"type": 2, "count": 4}, {"type": 0, "count": 3}],
		"east":  [{"type": 2, "count": 4}, {"type": 0, "count": 4}, {"type": 1, "count": 3}],
		"west":  [{"type": 0, "count": 4}, {"type": 1, "count": 4}, {"type": 2, "count": 3}],
	},
]
