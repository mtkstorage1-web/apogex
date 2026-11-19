"""Build APOGEX's original equirectangular coastline and lunar relief maps."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUTPUT = Path(__file__).resolve().parents[1] / "assets/textures/planets"
WIDTH, HEIGHT = 1024, 512

# Simplified coastlines sketched in longitude and latitude.
COASTS = [
    [(-168,66),(-155,71),(-130,70),(-112,75),(-91,72),(-83,67),(-94,58),
     (-80,52),(-80,62),(-65,60),(-59,52),(-69,47),(-76,43),(-81,32),
     (-80,25),(-89,30),(-97,26),(-90,20),(-86,21),(-83,15),(-77,8),
     (-83,8),(-96,17),(-105,21),(-115,32),(-124,42),(-126,52),(-139,59),
     (-154,57),(-167,54),(-159,62)],
    [(-81,9),(-72,12),(-60,9),(-52,5),(-48,-1),(-35,-6),(-40,-19),
     (-49,-28),(-54,-34),(-62,-41),(-67,-55),(-74,-51),(-74,-39),
     (-72,-28),(-70,-18),(-77,-11),(-81,-4)],
    [(-73,78),(-57,83),(-29,82),(-19,76),(-22,69),(-44,60),(-53,63),(-61,71)],
    [(-10,36),(-9,44),(0,47),(5,54),(12,56),(6,61),(19,71),(34,70),
     (37,65),(56,69),(68,73),(95,76),(113,73),(135,73),(155,70),(176,66),
     (179,59),(163,57),(157,50),(140,50),(142,43),(131,44),(125,37),
     (121,31),(119,23),(109,19),(106,8),(101,3),(99,8),(98,17),(91,22),
     (86,20),(78,8),(73,12),(68,23),(59,26),(50,30),(55,25),(50,16),
     (43,12),(40,19),(34,28),(31,31),(35,35),(27,38),(25,35),(17,39),
     (13,38),(8,44),(1,42),(-4,36)],
    [(-6,36),(10,37),(24,34),(33,31),(38,18),(44,11),(51,12),(46,4),
     (40,-4),(39,-13),(34,-23),(24,-34),(18,-34),(11,-19),(12,-7),
     (8,4),(-5,5),(-16,12),(-17,22)],
    [(112,-23),(115,-33),(126,-34),(136,-32),(142,-39),(151,-36),
     (154,-27),(147,-18),(143,-11),(136,-16),(130,-12),(122,-17),(114,-21)],
    [(95,5),(106,-6),(104,-8),(99,-3)], [(106,-6),(116,-8),(113,-9)],
    [(109,1),(117,7),(119,1),(115,-4),(110,-3)],
    [(131,-1),(141,-2),(151,-7),(146,-10),(139,-7),(132,-6)],
    [(131,32),(137,36),(141,42),(145,44),(144,38),(139,34)],
    [(166,-46),(176,-41),(179,-37),(174,-36),(169,-43)],
    [(48,-12),(50,-16),(46,-25),(43,-24),(44,-18)],
    [(-10,50),(-5,59),(0,58),(2,51)], [(-25,63),(-14,67),(-13,64)],
    [(-180,-72),(-145,-76),(-115,-73),(-80,-73),(-63,-64),(-55,-67),
     (-56,-75),(-31,-79),(0,-71),(45,-67),(80,-68),(118,-67),(153,-71),
     (174,-78),(180,-72),(180,-90),(-180,-90)],
]


def earth():
    mask = Image.new("L", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(mask)
    for coast in COASTS:
        draw.polygon([((lon + 180) / 360 * WIDTH, (90 - lat) / 180 * HEIGHT)
                      for lon, lat in coast], fill=255)
    # A soft ramp around coastlines gives the shader shelf depth and room to erode edges.
    Image.blend(mask.filter(ImageFilter.GaussianBlur(3)),
                mask.filter(ImageFilter.GaussianBlur(15)), 0.48).save(OUTPUT / "earth_coasts.png")


def moon():
    rng = np.random.default_rng(421)
    lon, lat = np.meshgrid(np.linspace(-np.pi, np.pi, WIDTH, endpoint=False),
                           np.linspace(np.pi / 2, -np.pi / 2, HEIGHT))
    normals = np.stack((np.cos(lat) * np.cos(lon), np.sin(lat),
                        np.cos(lat) * np.sin(lon)), axis=-1).astype(np.float32)
    relief = np.zeros((HEIGHT, WIDTH), dtype=np.float32)
    rays = np.zeros_like(relief)
    maria = np.zeros_like(relief)
    for x, y, radius in [(-19,31,21),(-40,29,19),(-52,20,26),(-49,4,22),(-42,-16,15),
                         (-23,-13,10),(28,16,17),(35,32,11),(42,10,11),
                         (52,-8,10),(58,2,12),(64,17,9), (116,-30,10)]:
        x, y = np.radians([x, y])
        center = [np.cos(y) * np.cos(x), np.sin(y), np.cos(y) * np.sin(x)]
        dot = normals @ center
        r = np.arccos(np.clip(dot,-1,1)) / np.radians(radius)
        folded = np.sin(lon * 15 + lat * 9) * np.cos(lat * 18 - lon * 7)
        irregular = r + folded * 0.19 + np.sin(lat * 34 + lon * 25) * 0.055
        basin = np.clip((1.11 - irregular) * 2.9, 0, 1)
        maria = np.maximum(maria, basin)
    craters = [(rng.uniform(-180,180), np.degrees(np.arcsin(rng.uniform(-1,1))),
                rng.uniform(0.9, 2.4)) for _ in range(620)]
    craters += [(rng.uniform(-180,180), rng.uniform(-78,78),
                 rng.uniform(3, 8)) for _ in range(75)]
    craters += [(-11,-43,3.7), (-20,9,3.4), (-48,24,3.6), (143,-30,5)]
    for i, (x, y, radius) in enumerate(craters):
        x, y, radius = np.radians([x,y,radius])
        center = np.array([np.cos(y) * np.cos(x), np.sin(y), np.cos(y) * np.sin(x)])
        extent = 7 if i >= len(craters) - 4 else 1.45
        dot = normals @ center
        active = dot > np.cos(radius * extent)
        distance = np.arccos(np.clip(dot[active], -1, 1)) / radius
        bowl = -0.27 * np.maximum(0, 1 - distance**2)
        rim = 0.19 * np.exp(-((distance - 0.96) / 0.18)**2)
        relief[active] += (bowl + rim) * min(1.2, radius * 32)
        if extent > 2:
            east = np.array([-np.sin(x), 0, np.cos(x)])
            north = np.array([-np.sin(y)*np.cos(x), np.cos(y), -np.sin(y)*np.sin(x)])
            vectors = normals[active]
            angle = np.arctan2(vectors @ north, vectors @ east)
            streak = np.clip(np.sin(angle*17 + 1.3) + .55*np.sin(angle*31), 0, 1)**4
            rays[active] += streak * np.maximum(0, 1-distance/extent)**1.4
    bitmap = np.stack((maria, relief + 0.53, rays), axis=-1)
    Image.fromarray(np.uint8(np.clip(bitmap, 0, 1)*255)).save(OUTPUT / "moon_relief.png")


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    earth()
    moon()
