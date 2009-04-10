#!/usr/bin/env python

from numpy import *
from pyatoms import *

import sys

selection_edge_tol = 10.0

if len(sys.argv) != 3:
   print 'Usage: %s <old file.xyz> <new file.xyz>' % sys.argv[0]
   sys.exit(1)

at = Atoms(sys.argv[1])

print 'Found properties: %r' % at.properties.keys()

# Rename some properties and convert some from real to int
try:
   kill_list = []
   for p in at.properties.keys():
      if p in 'Embed_Mask:Changed_NN:Move_Mask:Select_Mask:Fit_Mask:NN'.split(':'):
         newname = p.lower()
         if p in 'Embed_Mask:Fit_Mask:Select_Mask':
            newname = newname[:newname.index('_mask')]
         at.add_property(newname, getattr(at,p).astype(int))
         kill_list.append(p)
      else:
         at.properties.rename(p,p.lower())

   for p in kill_list:
      del at.properties[p]

   at.properties.rename('embed','hybrid')
         
   at.repoint()
except ValueError, message:
   print message
   sys.exit(1)

## # Negate move_mask since constrain_mask was other way round
## at.move_mask[:] = 1 - at.move_mask[:]

print 'Fixing %d atoms' % count(at.move_mask == 0)

print at.properties

at.add_property('old_nn',at.nn)
at.add_property('md_old_changed_nn',at.changed_nn)
at.add_property('edge_mask',0)
at.add_property('load',0.0,ncols=3)
at.add_property('hybrid_mark',0)

# Set edge_mask to 1 for atoms closer than edge_mask_tol to an edge

minx = at.pos[:,0].min() + selection_edge_tol
maxx = at.pos[:,0].max() - selection_edge_tol
miny = at.pos[:,1].min() + selection_edge_tol
maxy = at.pos[:,1].max() - selection_edge_tol

at.edge_mask[at.pos[:,0] < minx] = 1
at.edge_mask[at.pos[:,0] > maxx] = 1
at.edge_mask[at.pos[:,1] < miny] = 1
at.edge_mask[at.pos[:,1] > maxy] = 1

at.params['State'] = 'MD'

print 'Setting edge_mask=1 for %d atoms' % count(at.edge_mask == 1)

required_properties = 'pos:hybrid:fit:nn:changed_nn:old_nn:md_old_changed_nn:edge_mask:load'.split(':')

for p in required_properties:
   if not p in at.properties.keys():
      print '%s missing' % p

at.write(sys.argv[2])
