import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

def build():
    recipe("structure.ae.forge_cannon", "str_defense_adv", params={"kit": "forge_cannon"},
           meta={"role": "advanced_defense", "doc": "AE Forge Cannon: rapid-cycling armoured turret, ammo drum, cyan cooling collars; AE dialect (pipes, scrap, jib crane, caged core) comes from the ae style slots front / extra."})
    recipe("structure.ae.horizon_mass_driver", "str_superweapon", params={"kit": "long_barrel"},
           meta={"role": "superweapon", "doc": "AE Horizon Mass Driver: 14 m rail barrel at 25 deg on a charcoal mount, six cyan capacitor rings, slews to the target azimuth."})

if __name__ == "__main__":
    build()
