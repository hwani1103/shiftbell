"""Canonical floor/puzzle identity for rotation, reflection and translation."""
def geometry(level, include_units=True):
    floor=[(x,y) for y,row in enumerate(level['rows']) for x,v in enumerate(row) if v=='.']
    variants=[]
    for swap in [False,True]:
        for sx in [-1,1]:
            for sy in [-1,1]:
                def rotate(p):
                    x,y=p
                    if swap:x,y=y,x
                    return x*sx,y*sy
                transformed=[rotate(c) for c in floor]
                left=min(x for x,y in transformed);top=min(y for x,y in transformed)
                def norm(p):
                    x,y=rotate(p);return x-left,y-top
                key=(tuple(sorted(norm(c) for c in floor)),)
                if include_units:key+=(norm(level['goal']),tuple(sorted(norm(u['start']) for u in level['units'])),level['maxCommands'])
                variants.append(key)
    return min(variants)

