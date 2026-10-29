local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local Safe = ns.Safe -- (Util.lua)
local QD = ns.QuestieData
local function QDB() return QD.DB() end
local AddOnVersion, WaypointLink = I._.AddOnVersion, I._.WaypointLink
local ZoneName = I.ZoneName

----------------------------------------------------------------------
-- Game objects found by what they are: "nearest mailbox", "nearest anvil" (QuestieDB's objects: name, spawns)
----------------------------------------------------------------------

-- words -> the kind of object (its list's id)
I.OBJECT_KINDS = { mailbox = "mailbox", mailboxes = "mailbox", mail = "mailbox", post = "mailbox",
	forge = "forge", forges = "forge", anvil = "anvil", anvils = "anvil",
	["cooking fire"] = "cookingfire", ["cooking fires"] = "cookingfire", cookingfire = "cookingfire", cookingfires = "cookingfire",
	moonwell = "moonwell", moonwells = "moonwell" }
-- each kind's object names, lowercase: every object of one of these exact names counts (0.67.10, the player: forges and
-- anvils for blacksmiths and engineers; WoW Forever's QuestieDB has 70 forge and 193 anvil spots, Ironforge's own forge
-- named The Great Forge. 0.68.1, the player: cooking fires and moonwells, only objects of exactly that name, 12 Cooking
-- Fire and 31 Moonwell spots: no campfires or bonfires, no moonwell with a name of its own)
I.OBJECT_NAMES = { mailbox = { "mailbox" }, forge = { "forge", "the great forge" }, anvil = { "anvil" },
	moonwell = { "moonwell" } }
-- kinds that are a list of object ids, not names (0.68.10, the player: every fire you can cook at, not only those named
-- Cooking Fire): the server decides which objects count, and some campfires are only scenery, so a name can't tell
-- generated: tests/gen_data.py cookingfires (do not edit by hand)
-- 2231 objects, Mangos Zero's gameobject_template: type 8 (spell focus), focus 4 (Cooking Fire)
I.COOKING_FIRE_IDS = {
	1766, 1798, 1799, 1801, 1802, 1803, 1804, 1805, 1806, 1807, 1808, 1809, 1810, 1811, 1812, 1813,
	1814, 1815, 1816, 1817, 1818, 1819, 1820, 1821, 1822, 1824, 1825, 1826, 1827, 1828, 1829, 1830,
	1831, 1832, 1833, 1834, 1835, 1836, 1837, 1838, 1839, 1840, 1841, 1842, 1843, 1844, 1845, 1846,
	1847, 1848, 1849, 1850, 1851, 1852, 1853, 1854, 1855, 1856, 1857, 1858, 1859, 1860, 1864, 1865,
	1866, 1867, 1868, 1869, 1870, 1871, 1872, 1873, 1874, 1875, 1876, 1877, 1878, 1879, 1880, 1881,
	1882, 1883, 1884, 1885, 1886, 1887, 1888, 1889, 1890, 1891, 1892, 1893, 1894, 1895, 1898, 1901,
	1902, 1903, 1904, 1905, 1906, 1908, 1909, 1912, 1914, 1915, 1916, 1917, 1921, 1922, 1923, 1926,
	1928, 1930, 1931, 1932, 1936, 1937, 1938, 1939, 1940, 1941, 1943, 1944, 1945, 1946, 1947, 1948,
	1949, 1950, 1951, 1952, 1953, 1954, 1957, 1958, 1959, 1960, 1961, 1962, 1964, 1967, 1969, 1970,
	1971, 1972, 1973, 1975, 1976, 1977, 1979, 1981, 1984, 1985, 1986, 1987, 1988, 1989, 1990, 1991,
	1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007,
	2056, 2057, 2062, 2334, 2335, 2336, 2658, 2661, 2663, 2664, 2665, 2666, 2667, 2719, 2732, 3084,
	3085, 3089, 3200, 3201, 3220, 3246, 3249, 3251, 3252, 3253, 3254, 3256, 3258, 3260, 3262, 3264,
	3265, 3266, 3270, 3286, 3296, 3298, 3301, 3303, 3306, 3307, 3308, 3310, 3311, 3315, 3636, 3637,
	3638, 3639, 3656, 3716, 3717, 3718, 3722, 3723, 3760, 3761, 3769, 3770, 3771, 3772, 3797, 3798,
	3799, 3800, 3801, 3802, 3803, 3804, 3815, 3816, 3817, 3818, 3819, 3832, 3833, 3834, 3835, 3836,
	3837, 3838, 3839, 3840, 3841, 3842, 3843, 3844, 3845, 3847, 3848, 3849, 3850, 3851, 3852, 3853,
	3855, 3856, 3857, 3864, 3865, 3866, 3867, 3869, 3870, 3871, 3872, 3873, 3874, 3875, 3876, 3877,
	3878, 3879, 3880, 3881, 3882, 3883, 3884, 3885, 3886, 3888, 3890, 3891, 3892, 3893, 3894, 3895,
	3896, 3897, 3898, 3899, 3900, 3901, 3902, 3903, 3904, 3905, 3906, 3907, 3908, 3909, 3910, 3911,
	3912, 3913, 3914, 3915, 3916, 3917, 3918, 3919, 3920, 3921, 3922, 3923, 3924, 3925, 3926, 3927,
	3928, 3929, 3930, 3931, 3932, 3933, 3934, 3937, 3943, 3945, 3951, 3960, 3962, 3963, 3964, 3967,
	3968, 6286, 6287, 6288, 6289, 6290, 6291, 6292, 9847, 10388, 12665, 15068, 15069, 17284, 18035, 18043,
	18045, 18046, 18047, 18048, 18049, 18050, 18051, 18052, 18053, 18054, 18055, 18056, 18057, 18058, 18059, 18060,
	18061, 18062, 18063, 18064, 18065, 18066, 18067, 18068, 18069, 18070, 18071, 18072, 18073, 18074, 18075, 18076,
	18077, 18079, 18083, 18084, 18085, 18087, 18089, 18090, 18340, 18341, 18342, 18343, 18344, 18345, 18596, 18643,
	18644, 18645, 18930, 19536, 20356, 20692, 20693, 20694, 20810, 20829, 20830, 20831, 20849, 20850, 20869, 20870,
	20871, 20872, 20873, 20874, 20875, 20876, 20877, 20878, 20879, 20881, 20898, 20918, 20921, 20922, 20924, 20926,
	20981, 20982, 20983, 20989, 20990, 20991, 21007, 21008, 21009, 21127, 21282, 21308, 21327, 21459, 22205, 22207,
	22208, 22216, 22217, 22218, 22219, 22220, 22221, 22222, 22223, 22229, 22230, 22231, 22563, 22564, 22565, 22566,
	22567, 22602, 22603, 22604, 22605, 22606, 22670, 22671, 22672, 22673, 22674, 22707, 22708, 22709, 22710, 22711,
	22712, 22772, 22773, 22774, 22775, 22776, 22777, 22831, 22832, 22833, 22834, 22835, 22836, 22882, 22883, 22884,
	22885, 22886, 22887, 23570, 23571, 23572, 23573, 23574, 23575, 23577, 23879, 23880, 23881, 24723, 24724, 24725,
	24726, 24727, 24728, 24729, 24758, 24759, 24760, 24761, 24762, 24763, 24764, 24765, 26494, 26495, 26496, 26499,
	29150, 29151, 29784, 31407, 31408, 31409, 31410, 31411, 31511, 31572, 31573, 31574, 31575, 31576, 31577, 31578,
	31579, 31580, 32107, 32109, 32110, 32358, 32389, 32391, 32404, 32416, 32425, 32429, 32878, 32879, 32880, 32881,
	32882, 32883, 32884, 32885, 34360, 35593, 35594, 35595, 35596, 35597, 35598, 35844, 36396, 36645, 37089, 37090,
	37091, 37092, 37093, 37094, 37095, 37096, 38019, 38028, 38029, 38030, 40197, 40198, 40201, 40298, 40299, 40301,
	41185, 41186, 41187, 41188, 41189, 41190, 41191, 41192, 41193, 41194, 43116, 43117, 43118, 43119, 43120, 43121,
	43122, 48404, 48411, 48414, 48419, 48429, 48431, 48432, 48437, 48443, 48444, 48451, 48455, 48460, 48463, 48466,
	48471, 48472, 48476, 48480, 48487, 48490, 48492, 48493, 48494, 48495, 48496, 48497, 48508, 48512, 48517, 48518,
	48519, 48526, 48531, 48532, 48535, 48537, 48543, 48544, 48547, 48552, 48554, 48555, 48556, 48557, 48558, 48559,
	48570, 48576, 49485, 49486, 49487, 50445, 50446, 50447, 50448, 50449, 50450, 50547, 50548, 50549, 50803, 50804,
	50805, 50910, 50986, 50987, 50988, 50989, 51950, 55250, 55535, 55615, 55616, 56809, 56810, 56818, 56819, 56820,
	56821, 57708, 57748, 58388, 58389, 59529, 59530, 59853, 59854, 59855, 59856, 59857, 59858, 59859, 59860, 59861,
	59862, 59863, 59864, 59865, 59990, 60393, 60394, 61037, 61038, 61039, 61927, 61928, 61929, 61952, 61953, 63196,
	67234, 69282, 69421, 69422, 69423, 69424, 69425, 69426, 69427, 69428, 69429, 69430, 69431, 69432, 69433, 69434,
	69435, 69436, 69437, 69438, 70517, 74075, 74076, 74078, 74135, 74138, 74146, 74439, 74440, 74441, 74442, 74443,
	74444, 74445, 74446, 74727, 74728, 74729, 74730, 82136, 82137, 82138, 82139, 82140, 88496, 88497, 88498, 91673,
	91706, 91738, 92065, 92066, 92067, 92098, 92099, 92140, 92141, 92142, 92143, 92424, 92425, 92426, 92427, 92458,
	94183, 94184, 94185, 94186, 94187, 94188, 94189, 94190, 94191, 102990, 102993, 103003, 103011, 103663, 103687, 103694,
	103695, 103727, 103728, 103729, 103748, 103749, 103750, 103751, 103770, 103771, 103772, 103773, 105173, 106325, 106326, 106327,
	106335, 106336, 110230, 110231, 110232, 110233, 110234, 110235, 110236, 111149, 111202, 111203, 111204, 111205, 111206, 111207,
	111254, 111255, 111256, 111257, 111258, 111259, 111839, 112879, 112881, 113540, 120584, 123328, 125475, 126312, 126313, 126314,
	126335, 126337, 126338, 126339, 126340, 126341, 126342, 126345, 129206, 136922, 136923, 136925, 136926, 136927, 136928, 136947,
	136948, 136949, 136950, 136951, 136952, 136954, 136955, 136957, 136959, 136961, 136962, 136963, 136964, 136965, 136966, 137647,
	138318, 140105, 140106, 140109, 140110, 140111, 140112, 140113, 140211, 140212, 140213, 140214, 140357, 140358, 140359, 140360,
	140931, 141069, 141610, 141611, 141813, 141843, 141844, 141845, 141851, 141852, 141870, 141871, 141971, 141972, 142018, 142019,
	142020, 142021, 142073, 142079, 142090, 142091, 142101, 142118, 142121, 142123, 142124, 142131, 142139, 142196, 142197, 142198,
	142340, 142342, 142689, 142690, 142691, 142692, 142693, 142694, 142695, 142837, 142871, 142872, 142965, 142966, 142967, 142968,
	142969, 142970, 142971, 142972, 142973, 142974, 142976, 142977, 142978, 142979, 142980, 143242, 143243, 143244, 143245, 143246,
	143247, 143250, 143273, 143295, 143296, 143301, 143314, 143318, 143319, 143320, 143323, 143325, 143326, 143328, 143337, 143342,
	143345, 143346, 143347, 143348, 143349, 143362, 143363, 143397, 143398, 143991, 144055, 144159, 144180, 146088, 146089, 146090,
	146091, 147065, 147536, 147742, 147743, 147744, 147745, 147746, 147747, 147748, 147749, 147750, 147751, 147752, 147753, 147754,
	147755, 147756, 147757, 147758, 147759, 147760, 147761, 147762, 147763, 147764, 147765, 147766, 147767, 147768, 147769, 147770,
	147771, 148436, 148437, 148511, 148840, 148841, 148846, 148847, 148851, 148865, 148876, 148877, 148878, 148879, 148880, 149026,
	149027, 149028, 149029, 149038, 149412, 149413, 149417, 149418, 149419, 150713, 151951, 152035, 152036, 152037, 152038, 152039,
	152040, 152043, 152044, 152324, 152325, 152326, 152327, 152328, 152329, 152330, 152331, 152332, 152619, 153124, 153125, 153126,
	153220, 153221, 153241, 153242, 153350, 153399, 153400, 153402, 153482, 153516, 153576, 153577, 153579, 153580, 153581, 153582,
	153583, 153584, 153695, 153723, 157636, 157968, 157969, 160411, 160420, 160421, 160426, 160470, 161488, 164699, 164704, 164728,
	164890, 164891, 165587, 165637, 165740, 165741, 165742, 165743, 165744, 165745, 165746, 165747, 165748, 165749, 165750, 165751,
	167284, 167285, 167286, 167287, 167288, 167289, 167290, 167291, 171535, 171536, 171537, 171538, 171539, 171540, 171541, 171542,
	171543, 171544, 171545, 171546, 171547, 171548, 171549, 171550, 171551, 171552, 171553, 171554, 171555, 171557, 171558, 171559,
	171560, 171561, 171562, 171563, 171564, 171565, 171566, 171623, 171624, 171625, 171626, 171627, 171628, 171633, 171634, 171635,
	171636, 171638, 171639, 171640, 171641, 171642, 171643, 171644, 171645, 171692, 171693, 171694, 171695, 171696, 171697, 171698,
	171700, 171701, 171702, 171703, 171705, 171706, 171707, 171742, 171743, 171750, 171751, 171753, 171754, 171755, 171756, 171757,
	171758, 171759, 171760, 171761, 171762, 171763, 171764, 171765, 171767, 171768, 171769, 172941, 172942, 172943, 172944, 172945,
	172946, 172947, 172948, 172949, 172950, 172951, 172952, 172953, 172954, 172955, 172956, 172998, 173000, 173007, 173008, 173009,
	173010, 173011, 173012, 173013, 173014, 173015, 173019, 173023, 173026, 173027, 173028, 173029, 173030, 173031, 173032, 173033,
	173034, 173035, 173036, 173037, 173038, 173039, 173040, 173041, 173042, 173043, 173045, 173046, 173048, 173049, 173050, 173051,
	173052, 173053, 173054, 173055, 173057, 173058, 173059, 173060, 173061, 173062, 173067, 173068, 173069, 173070, 173071, 173072,
	173073, 173074, 173075, 173076, 173077, 173087, 173088, 173089, 173090, 173091, 173092, 173093, 173096, 173097, 173098, 173099,
	173100, 173101, 173102, 173103, 173104, 173105, 173106, 173107, 173108, 173109, 173110, 173111, 173112, 173113, 173114, 173115,
	173116, 173117, 173118, 173119, 173120, 173121, 173122, 173123, 173124, 173125, 173127, 173128, 173129, 173130, 173131, 173132,
	173133, 173134, 173135, 173136, 173137, 173138, 173139, 173140, 173141, 173142, 173143, 173144, 173145, 173146, 173147, 173148,
	173149, 173150, 173151, 173152, 173153, 173154, 173155, 173156, 173158, 173159, 173163, 173164, 173165, 173166, 173167, 173171,
	173172, 173175, 173176, 173178, 173179, 173180, 173181, 173182, 173183, 173184, 173185, 173186, 173187, 173188, 173189, 173190,
	173191, 173192, 173193, 173194, 173195, 173196, 173197, 173198, 173199, 173200, 173201, 173204, 173205, 173206, 173207, 173208,
	173209, 173210, 173211, 173212, 173213, 173214, 173223, 173224, 173225, 173226, 174729, 174730, 174859, 174862, 174953, 175075,
	175076, 175104, 175146, 175179, 175180, 175181, 175284, 175285, 175286, 175312, 175313, 175314, 175315, 175316, 175317, 175318,
	175335, 175406, 175424, 175545, 175591, 175592, 175593, 175594, 175595, 175596, 175597, 175598, 175599, 175600, 175601, 175602,
	175603, 175604, 175605, 175630, 175631, 175632, 175669, 175670, 175671, 175672, 175673, 175674, 175675, 175707, 175764, 175765,
	175766, 175767, 175797, 175798, 175799, 175800, 175801, 175811, 175844, 175845, 175846, 175847, 175848, 175849, 175850, 175853,
	175929, 175930, 175931, 175932, 176113, 176186, 176187, 176200, 176201, 176202, 176203, 176204, 176226, 176227, 176228, 176229,
	176230, 176264, 176265, 176266, 176267, 176268, 176269, 176270, 176271, 176272, 176273, 176274, 176275, 176276, 176277, 176278,
	176279, 176280, 176281, 176282, 176283, 176284, 176285, 176286, 176287, 176288, 176289, 176290, 176291, 176292, 176293, 176294,
	176318, 176389, 176390, 176425, 176426, 176427, 176428, 176429, 176430, 176431, 176432, 176433, 176434, 176435, 176436, 176437,
	176438, 176439, 176440, 176441, 176442, 176443, 176444, 176445, 176446, 176447, 176448, 176449, 176450, 176451, 176452, 176454,
	176455, 176456, 176457, 176458, 176459, 176460, 176461, 176462, 176463, 176464, 176488, 176489, 176490, 176491, 176492, 176493,
	176496, 176504, 176506, 176507, 176549, 176550, 176551, 176552, 176553, 176554, 176555, 176556, 176558, 176559, 176560, 176567,
	176568, 176569, 176570, 176571, 176572, 176574, 176604, 176605, 176606, 176607, 176608, 176609, 176610, 176611, 176612, 176617,
	176618, 176619, 176624, 176625, 176626, 176627, 176628, 176629, 176705, 176768, 176784, 176787, 176789, 176790, 176791, 176792,
	176804, 176805, 176806, 176807, 176808, 176863, 176885, 176886, 176887, 176888, 176889, 176890, 176891, 176892, 176896, 176897,
	176898, 176899, 176904, 176905, 176906, 176998, 176999, 177002, 177003, 177004, 177005, 177006, 177007, 177008, 177009, 177010,
	177011, 177012, 177013, 177014, 177015, 177016, 177017, 177018, 177019, 177020, 177021, 177022, 177023, 177024, 177025, 177026,
	177084, 177194, 177195, 177196, 177197, 177225, 177244, 177261, 177262, 177263, 177284, 177285, 177286, 177288, 177290, 177292,
	177293, 177326, 177378, 177379, 177380, 177381, 177382, 177383, 177384, 177405, 177406, 177408, 177409, 177410, 177411, 177412,
	177413, 178524, 178525, 178572, 178573, 179084, 179085, 179086, 179119, 179120, 179121, 179122, 179147, 179344, 179419, 179500,
	179700, 179704, 179846, 179885, 179945, 179984, 180053, 180417, 180438, 180439, 180440, 180441, 180442, 180443, 180444, 180688,
	180689, 180915, 181099, 181220, 181311, 181312, 181313, 181314, 181315, 181316, 181317, 181318, 181320, 181321, 181322, 181323,
	181324, 181325, 181326, 181327, 181328, 181329, 181350, 181351, 181352, 181362, 181387, 181427, 181445, 181446, 181450, 181451,
	181452, 181453, 181455, 181456, 181480, 181481, 181483, 181484, 181485, 181486, 181487, 181489, 181490, 181491, 181493, 181494,
	181495, 181595, 181608, 181633, 181634, 181635, 181655, 181656, 181657, 181658, 181659, 181660, 181711, 181712, 181734, 181735,
	181736, 181737, 181738, 181767, 181773, 181775, 181787, 181788, 181789, 181829, 181851, 181863, 181864, 181865, 181866, 181867,
	181868, 181869, 181870, 181887, 181888, 181920, 181954, 182013, 182015, 182016, 182017, 182019, 182027, 182147, 182148, 182149,
	182150, 182151, 182152, 182153, 182154, 182155, 182156, 182157, 182158, 182159, 182160, 182161, 182162, 182205, 182206, 182209,
	182215, 182216, 182217, 182218, 182219, 182220, 182221, 182261, 182262, 182264, 182271, 182343, 182344, 182345, 182346, 182376,
	182377, 182378, 182400, 182401, 182402, 182534, 182535, 182536, 182537, 182538, 182561, 182568, 182569, 182570, 182575, 182577,
	182578, 182579, 182605, 182788, 182811, 182828, 182829, 182830, 182834, 182835, 182836, 182864, 182865, 182866, 182944, 182994,
	183005, 183006, 183007, 183008, 183009, 183010, 183099, 183111, 183112, 183113, 183114, 183116, 183117, 183118, 183119, 183124,
	183125, 183126, 183127, 183129, 183132, 183134, 183136, 183137, 183139, 183141, 183143, 183151, 183152, 183153, 183154, 183155,
	183159, 183160, 183161, 183162, 183166, 183168, 183189, 183190, 183191, 183192, 183193, 183194, 183195, 183196, 183197, 183198,
	183204, 183265, 183270, 183274, 183275, 183276, 183277, 183305, 183313, 183349, 183368, 183369, 183370, 183371, 183372, 183373,
	183374, 183375, 183376, 183377, 183378, 183379, 183380, 183381, 183382, 183383, 183393, 183418, 183419, 183420, 183421, 183422,
	183423, 183424, 183425, 183427, 183428, 183429, 183430, 183432, 183433, 183465, 183467, 183497, 183498, 183499, 183500, 183501,
	183502, 183821, 183824, 183827, 183828, 183882, 183883, 183894, 183895, 183896, 183897, 183898, 183899, 183900, 183901, 183902,
	183903, 183904, 183905, 183906, 183907, 183908, 183909, 183910, 183911, 183912, 183913, 183914, 183915, 183916, 183917, 183918,
	183919, 183920, 183922, 183923, 183924, 183925, 183926, 183927, 183930, 183931, 183946, 183984, 183985, 183986, 184003, 184009,
	184010, 184011, 184012, 184015, 184016, 184017, 184018, 184021, 184022, 184023, 184024, 184025, 184026, 184027, 184028, 184029,
	184030, 184032, 184033, 184034, 184114, 184145, 184287, 184314, 184316, 184317, 184339, 184340, 184341, 184342, 184346, 184347,
	184355, 184357, 184360, 184364, 184368, 184369, 184370, 184373, 184376, 184377, 184384, 184385, 184386, 184387, 184388, 184389,
	184390, 184391, 184392, 184395, 184396, 184398, 184399, 184400, 184401, 184416, 184442, 184448, 184467, 184470, 184471, 184472,
	184474, 184475, 184494, 184495, 184507, 184508, 184509, 184511, 184512, 184513, 184514, 184515, 184554, 184563, 184564, 184565,
	184579, 184580, 184581, 184582, 184583, 184584, 184585, 184618, 184644, 184645, 184646, 184647, 184648, 184649, 184650, 184651,
	184683, 184688, 184724, 184816, 184818, 184836, 184837, 184838, 184852, 184853, 184982, 184985, 184988, 184989, 184991, 184993,
	184994, 184995, 185023, 185024, 185025, 185026, 185027, 185028, 185029, 185030, 185031, 185104, 185105, 185111, 185112, 185113,
	185153, 185154, 185157, 185158, 185159, 185160, 185161, 185162, 185163, 185164, 185181, 185267, 185268, 185269, 185270, 185283,
	185284, 185286, 185288, 185289, 185290, 185325, 185498, 185529, 185530, 185531, 185532, 185533, 185534, 185535, 185536, 185537,
	185538, 185539, 185571, 185572, 185573, 186023, 186035, 186130, 186131, 186132, 186174, 186175, 186176, 186177, 186178, 186180,
	186233, 186243, 186406, 186407, 186451, 187252, 187370,
}
-- end of generated: cookingfires
I.OBJECT_ID_LISTS = { cookingfire = I.COOKING_FIRE_IDS }
-- each kind's rows: their name and icon
I.OBJECT_LOOK = {
	mailbox = { label = L["Mailbox"], icon = "Interface\\Icons\\INV_Letter_15" },
	forge = { label = L["Forge"], icon = "Interface\\Icons\\Trade_Mining" },
	anvil = { label = L["Anvil"], icon = "Interface\\Icons\\Trade_BlackSmithing" },
	cookingfire = { label = L["Cooking Fire"], icon = "Interface\\Icons\\INV_Misc_Food_15" },
	moonwell = { label = L["Moonwell"], icon = "Interface\\Icons\\Spell_Nature_StarFall" },
}
I.OBJECTS_NEAR = 8 -- (the nearest this many are listed)

-- instance entrances: their own lists (@dungeon, @raid), not QuestieDB objects
I.ENTRANCE_KINDS = { dungeon = "dungeon", dungeons = "dungeon", instance = "dungeon", instances = "dungeon", raid = "raid", raids = "raid" }
--- The kind of thing the search words name ("mailbox", "dungeon", "cooking fire"), or nil. Only when that's all they name.
function I.ObjectKind(tokens)
	if not tokens then return nil end
	if #tokens == 2 then return I.OBJECT_KINDS[tokens[1] .. " " .. tokens[2]] end
	if #tokens ~= 1 then return nil end
	return I.OBJECT_KINDS[tokens[1]] or I.ENTRANCE_KINDS[tokens[1]]
end

-- the object ids of each kind: one pass over QuestieDB's objects (13k names) the first time, kept in the saved
-- variables until QuestieDB changes (`db.objectIndex = { key, ids = { mailbox = "1,2,3" } }`)
local objectIds

--- The saved index's ids into out (kind -> list of ids).
local function SavedObjectIds(out, saved)
	for k, list in pairs(saved.ids) do
		local t = {}
		for id in tostring(list):gmatch("%d+") do t[#t + 1] = tonumber(id) end
		out[k] = t
	end
end

--- Every object's name read once (all = QuestieDB's object ids): the ids of each kind looked for go into out,
--- and the index is saved under key. kindOf: lowercase object name -> its kind.
local function ReadObjectIds(out, DB, all, kindOf, key)
	for _, kind in pairs(kindOf) do out[kind] = {} end
	local t0 = debugprofilestop and debugprofilestop()
	for _, id in ipairs(all) do
		local name = ns.Str(Safe(DB.QueryObjectSingle, id, "name")) -- (Util.lua: a string, not secret; "" names no kind)
		if name then
			local kind = kindOf[ns.Lower(name)]
			if kind then local t = out[kind]; t[#t + 1] = id end
		end
	end
	local ids = {}
	for k, t in pairs(out) do ids[k] = table.concat(t, ",") end
	if ns.db then ns.db.objectIndex = { key = key, ids = ids } end
	ns:Trace(("objects: %d read for their names%s"):format(#all, t0 and (", %.0f ms"):format(debugprofilestop() - t0) or ""))
end

local function ObjectIds(kind)
	local DB = QDB()
	if not (DB and DB.QueryObjectSingle and DB.ObjectIds) then return nil end
	if I.OBJECT_ID_LISTS[kind] then return I.OBJECT_ID_LISTS[kind] end -- (QuestieDB gives their spawns: no names read)
	if not objectIds then
		local all = DB.ObjectIds() or {}
		if #all == 0 then return nil end -- (not readable yet: asked again next time, nothing kept)
		-- (the names looked for are in the key: a kind or name added later reads every name again)
		local kindOf, names = {}, {}
		for kind, list in pairs(I.OBJECT_NAMES) do
			for _, name in ipairs(list) do kindOf[name] = kind; names[#names + 1] = name end
		end
		table.sort(names)
		local key = AddOnVersion("QuestieDB") .. "/" .. #all .. "/" .. table.concat(names, ",")
		local saved = ns.db and ns.db.objectIndex
		objectIds = {}
		if type(saved) == "table" and saved.key == key and type(saved.ids) == "table" then
			SavedObjectIds(objectIds, saved)
		else
			ReadObjectIds(objectIds, DB, all, kindOf, key)
		end
	end
	return objectIds[kind]
end
I.ResetObjectsForTests = function() objectIds = nil end

-- Shift+Enter on a spot row (a mailbox, an entrance, a vein): the map pin on it (a C API), no map opened; also Enter's
-- fallback when the game can't be handed the press (combat)
local function PinObject(e)
	local M = ns.Maps
	-- (a row with no place known, a TrainerSpells trainer without one: said, not an error; review, 0.57.7)
	local x, y = tonumber(e.px), tonumber(e.py)
	local pin = e.ui and x and y and M and M.Place and M.Place({ name = e.name, mapID = e.ui, pos = { x = x / 100, y = y / 100 } })
	if pin then
		ns:Print(M.PinLine(pin, e.pinName or e.name, e.zone))
	else
		ns:Print(L["Can't set a waypoint there."])
	end
end
I.PinObject = PinObject

--- After the game opened the map on a spot row's zone (Maps.SECURE): the pin on the spot, pointed at.
function I.SpotAfter(e)
	ns.Maps.ShowAfter({ name = e.pinName or e.name, mapID = e.ui, pos = { x = e.px / 100, y = e.py / 100 } })
end

-- what every mailbox row does (shared, not on each of thousands of rows): Enter opens the map on it with the pin, as an
-- entrance's does; Shift+Enter only pins it
local SPOT = { icon = "Interface\\Icons\\INV_Letter_15", generic = true, secure = ns.Maps.SECURE, isOpen = ns.Maps.IsOpenFor,
	after = I.SpotAfter, activate = PinObject, secondary = PinObject }
local SPOT_META = { __index = function(t, k)
	if k == "mapID" then return rawget(t, "ui") end -- (the map the press opens: Maps.Target)
	return SPOT[k]
end }
--- A mailbox's row: its own fields, what it does shared (SPOT).
function I.SpotRow(t) return setmetatable(t, SPOT_META) end

--- The nearest spawn of any of these objects (ids) to `here` on your continent, else the first known anywhere: { ui, px,
--- py, wcont, wx, wy, zone, d (yards, when near you) }; nil when QuestieDB knows none.
function I.NearestSpawn(oids, here)
	local DB = QDB()
	if not (DB and DB.QueryObjectSingle) then return nil end
	-- (the nearest and the first kept as their numbers: a vein can have thousands of spawns, one table each was garbage)
	local bUi, bc, bCont, bX, bY, bestD
	local fUi, fc, fCont, fX, fY
	local function Spot(cont, x, y, ui, c)
		if not fUi then fUi, fc, fCont, fX, fY = ui, c, cont, x, y end
		if here and x and cont == here.cont then
			local d = math.sqrt((x - here.x) ^ 2 + (y - here.y) ^ 2)
			if not bestD or d < bestD then bUi, bc, bCont, bX, bY, bestD = ui, c, cont, x, y, d end
		end
	end
	for _, oid in ipairs(oids) do I._.EachSpot(Safe(DB.QueryObjectSingle, oid, "spawns"), Spot, true) end
	if bUi then
		return { ui = bUi, px = bc[1], py = bc[2], wcont = bCont, wx = bX, wy = bY, zone = ZoneName(bUi), d = bestD }
	end
	if fUi then return { ui = fUi, px = fc[1], py = fc[2], wcont = fCont, wx = fX, wy = fY, zone = ZoneName(fUi) } end
	return nil
end

--- The rows of a kind of object (@mailbox): one per spawn, "Mailbox  Stormwind City", each with its map spot and its
--- place in world yards (for sort:distance, near:, in: and the direction arrow). {} when QuestieDB has none to read.
function I.ObjectRows(kind)
	local ids = ObjectIds(kind)
	local DB = QDB()
	local rows = {}
	if not (ids and DB) then return rows end
	local look = I.OBJECT_LOOK[kind] or {}
	local label = look.label or (kind:gsub("^%l", string.upper))
	local icon = look.icon ~= SPOT.icon and look.icon or nil -- (a mailbox's is every spot row's)
	-- (a kind listed by ids has objects of many names: each row says its own, "Campfire", and the kind's name is in
	-- its text, so "@cookingfire cooking" still finds every one)
	local listed = I.OBJECT_ID_LISTS[kind]
	for _, id in ipairs(ids) do
		local n = 0
		local name = label
		I._.EachSpot(Safe(DB.QueryObjectSingle, id, "spawns"), function(cont, x, y, ui, c, _, area)
			n = n + 1
			if listed and n == 1 then
				local own = ns.Str(Safe(DB.QueryObjectSingle, id, "name"))
				name = own and own ~= "" and own or label
			end
			local zone = ZoneName(ui)
			rows[#rows + 1] = I.SpotRow({
				name = name, key = id .. "-" .. n, kind = kind, icon = icon, detail = zone, zone = zone,
				text = listed and (zone and label .. "  " .. zone or label) or zone, ui = ui, px = c[1], py = c[2], area = area,
				wcont = cont, wx = x, wy = y,
			})
		end, true)
	end
	return rows
end

--- A map pin link for a row with a spot of its own (an entrance, a mailbox): the waypoint is set there (a C API).
function I.SpotPinLink(e)
	if not (e and e.ui and e.px and ns.Maps and ns.Maps.Place) then return nil end
	if not ns.Maps.Place({ name = e.name, mapID = e.ui, pos = { x = e.px / 100, y = e.py / 100 } }) then return nil end
	return WaypointLink()
end

--- "nearest mailbox" (Simple mode): the nearest rows of that kind's list (those `keep` keeps: a place said), closest
--- first, "N yd  Zone" (or what the row says after a distance, `distNote`: a flight path not checked yet says so).
--- nil when there's no such list; an empty list when none is on your continent.
function I.NearestObjectRows(kind, here, keep, far)
	local p = ns.providers[kind]
	if not p then return nil end
	local found, far_ = {}, {}
	for _, e in ipairs(ns:GetEntries(p)) do
		local ok = not keep or keep(e)
		local d = ok and I.RowYards(e, here) or nil -- (the yards alone: no spot table per row)
		if d then found[#found + 1] = { e = e, d = d }
		elseif ok and far then far_[#far_ + 1] = e end -- (the farthest first: those with no distance known before them,
		-- as if infinitely far, as @mailbox sort:-distance lists them; 0.65.x review)
	end
	-- (far: the farthest first, "farthest mailbox"; 0.65.7)
	if far then table.sort(found, function(a, b) return a.d > b.d end) else table.sort(found, function(a, b) return a.d < b.d end) end
	local rows = {}
	for i = 1, math.min(#far_, I.OBJECTS_NEAR) do rows[i] = setmetatable({ _score = 1e6 - i }, { __index = far_[i] }) end
	if #rows > 0 then
		local n = #rows
		for i = 1, math.min(#found, I.OBJECTS_NEAR - n) do
			local f = found[i]
			rows[n + i] = I.NearView(f.e, f.d, rawget(f.e, "distNote") or f.e.zone, far)
		end
		return rows
	end
	for i = 1, math.min(#found, I.OBJECTS_NEAR) do
		local f = found[i]
		local rest = rawget(f.e, "distNote") or f.e.zone
		rows[i] = I.NearView(f.e, f.d, rest, far)
	end
	return rows
end
