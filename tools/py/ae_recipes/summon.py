import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

def repair_drone():
    ops = [
        # underslung repair arm with a cyan work-light head, charcoal + ochre patch plates
        ["brush", "sec"], ["box", [0, 0.42, 0.25], [0.30, 0.16, 0.5], 0.02],
        ["brush", "metal", "metal"], ["cyl", [0, 0.40, -0.05], [0, 0.22, -0.55], 0.03, 5, 0.0],
        ["brush", "acc", "emissive"], ["box", [0, 0.20, -0.58], [0.10, 0.08, 0.10], 0.0],
        ["brush", "base*0.82"], ["box", [0.0, 0.64, 0.5], [0.34, 0.03, 0.4], 0.0],
        ["meta", "hover", 3.5],
    ]
    recipe("summon.ae.repair_drone", "sum_uav", scale=0.55, ops_after=ops)

if __name__ == "__main__":
    repair_drone()
