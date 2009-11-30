#!/usr/bin/env python

from quippy import *
import sys

def oxygenate(at, edge_only=False):
   """Add oxygen atoms to undercoorindated silicons to complete tetrahedra."""
   
   saved_cutoff, saved_use_uniform_cutoff = at.cutoff, at.use_uniform_cutoff
   at.set_cutoff_factor(1.2)
   at.calc_connect()

   add_pos = []
   add_i = []
   rem_list = []
   
   for i in frange(at.n):
      if at.z[i] != 14: continue # Only consider silicon atoms
      if edge_only and at.edge_mask[i] != 1: continue  
	
      neighb = at.neighbours[i]
      
      if len(neighb) == 4:
         continue
      
      elif len(neighb) == 3:
         # add single O atom to complete SiO4 tetrahedron
         
         p1 = neighb[1].diff - neighb[2].diff
         p2 = neighb[1].diff - neighb[3].diff

         length = (neighb[1].distance + neighb[2].distance + neighb[3].distance)/3.0

         n = cross(p1, p2)
         n = n/sqrt(dot(n,n))

         if dot(n,neighb[1].diff) > 0.0: n = -n

         add_pos.append(at.pos[:,i]+length*n)
         add_i.append(i)
         at.move_mask[at.n] = at.move_mask[i]
         
      elif len(neighb) == 2:
         # add two O atoms to complete SiO4 tetrahedron

         length = (neighb[1].distance + neighb[2].distance)/2.0

         n1 = cross(neighb[1].diff, neighb[2].diff)
         n1 = n1/sqrt(dot(n1,n1))

         n2 = neighb[2].diff - neighb[1].diff
         n2 = n2/sqrt(dot(n2,n2))

         n3 = cross(n1,n2)

         o1 = at.pos[:,i] + length*( n1*sqrt(2./3)+n3*sqrt(1./3))
         o2 = at.pos[:,i] + length*(-n1*sqrt(2./3)+n3*sqrt(1./3))

         add_pos.append(o1)
         add_pos.append(o2)
         add_i.append(i)
         add_i.append(i)
      elif len(neighb) <= 1:
         rem_list.append(i)
         

   if len(add_pos) > 0:
      add_z = [8]*len(add_pos)
      add_pos = farray(add_pos)

      nat = at.n
      at.add_atoms(add_pos, add_z)

      for i in frange(nat+1, nat+add_pos.shape[1]):
         source = add_i.pop(0)
         at.move_mask[i] = at.move_mask[source]
         at.edge_mask[i] = at.edge_mask[source]

   if len(rem_list) > 0:
      at.remove_atoms(rem_list)

   # Now check if any of the new oxygens are too close to one another
   at.calc_connect()

   rem_list = []
   for i in frange(at.n):
      if at.z[i] != 8: continue
      if edge_only and at.edge_mask[i] != 1: continue

      neighb = at.neighbours[i]
      oxy_neighb = [pair.j for pair in neighb if at.z[pair.j] == 8]

      if len(oxy_neighb) != 0:
         print i, oxy_neighb
         for j in oxy_neighb:
            if i < j: rem_list.append(j)
         print i, rem_list

   if len(rem_list) > 0:
      print 'Removing %r' % rem_list
      at.remove_atoms(rem_list)
      
   at.cutoff, at.use_uniform_cutoff = saved_cutoff, saved_use_uniform_cutoff


if __name__ == '__main__':

   import optparse
   p = optparse.OptionParser(usage='%prog [-e|--edge-only] <infile> <outfile>')
   p.add_option('-e', '--edge-only', action='store_true', help='Only add oxygens in region where edge-mask == 1')
   p.add_option('-r', '--remove', action='store', help='Also remove the given property (e.g. load)')
   opt, args = p.parse_args()

   if len(args) != 2:
      p.error()
      
   a = Atoms(args[0])
   oxygenate(a, edge_only=opt.edge_only)

   if opt.remove is not None:
      a.remove_property(opt.remove)

   a.write(args[1])
