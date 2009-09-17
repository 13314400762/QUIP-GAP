"""
Simple example of molecular dynamics of 64 atoms of bulk silicon at 1000 K
James Kermode 2009
"""

from quippy import *

# Set up atomic configuation
s = supercell(diamond(5.44, 14), 3, 3, 3)

# Initialise potential from XML string
pot = Potential('IP SW', """<SW_params n_types="1">
<comment> Stillinger and Weber, Phys. Rev. B  31 p 5262 (1984)</comment>
<per_type_data type="1" atomic_num="14" />

<per_pair_data atnum_i="14" atnum_j="14" AA="7.049556277" BB="0.6022245584"
      p="4" q="0" a="1.80" sigma="2.0951" eps="2.1675" />

<per_triplet_data atnum_c="14" atnum_j="14" atnum_k="14"
      lambda="21.0" gamma="1.20" eps="2.1675" />
</SW_params>
""")

s.set_cutoff(pot.cutoff()+2.0)
s.calc_connect()

# Set up dynamical system at 1000K
ds = DynamicalSystem(s)
ds.rescale_velo(1000.0)
ds.zero_momentum()

outf = CInOutput('si-1000.xyz', OUTPUT)
traj = AtomsList(ds.run(pot, dt=1.0, n_steps=1000, save_interval=10, out=outf))
traj.loadall() # Run the dynamics
traj.show() # Display in AtomEye
outf.close()
raw_input('Press ENTER to terminate')

