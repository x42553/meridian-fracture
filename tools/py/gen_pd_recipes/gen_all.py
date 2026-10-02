import sys, os, importlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pdlib, gen_style
from pdlib import *
def main(only=None):
    gen_style.main() if hasattr(gen_style,'main') else dump(os.path.join(ROOT,'styles','pd.json'), gen_style.build_style())
    fns = []
    for mod in ('gen_ground','gen_air','gen_sea','gen_struct'):
        try:
            m = importlib.import_module(mod)
        except ModuleNotFoundError:
            continue
        for name in getattr(m,'RECIPES',[]):
            fns.append(getattr(m,name))
    n=0
    for f in fns:
        r=f()
        if only and not any(o in r['id'] for o in only): continue
        write_recipe(r); n+=1
    print("wrote",n,"recipes")
if __name__=='__main__':
    main(sys.argv[1:] or None)
