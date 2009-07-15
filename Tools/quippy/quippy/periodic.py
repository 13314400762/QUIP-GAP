# List of elements, in order of increasing atomic number
ElementName = [x.strip() for x in
               ["xx", "H  ","He ","Li ","Be ","B  ","C  ","N  ","O  ","F  ","Ne ","Na ","Mg ","Al ","Si ","P  ","S  ", 
                "Cl ","Ar ","K  ","Ca ","Sc ","Ti ","V  ","Cr ","Mn ","Fe ","Co ","Ni ","Cu ","Zn ","Ga ","Ge ",
                "As ","Se ","Br ","Kr ","Rb ","Sr ","Y  ","Zr ","Nb ","Mo ","Tc ","Ru ","Rh ","Pd ","Ag ","Cd ",
                "In ","Sn ","Sb ","Te ","I  ","Xe ","Cs ","Ba ","La ","Ce ","Pr ","Nd ","Pm ","Sm ","Eu ","Gd ",
                "Tb ","Dy ","Ho ","Er ","Tm ","Yb ","Lu ","Hf ","Ta ","W  ","Re ","Os ","Ir ","Pt ","Au ","Hg ",
                "Tl ","Pb ","Bi ","Po ","At ","Rn ","Fr ","Ra ","Ac ","Th ","Pa ","U  ","Np ","Pu ","Am ","Cm ",
                "Bk ","Cf ","Es ","Fm ","Md ","No ","Lr ","Rf ","Db ","Sg ","Bh ","Hs ","Mt ","Ds ","Rg ","Uub",
                "Uut","Uuq","Uup","Uuh"] ]

# Temp array to intialise ElementMass dictionary
mass = [ 0.0, 1.00794, 4.00260, 6.941, 9.012187, 10.811, 12.0107, 14.00674, 15.9994, 18.99840, 20.1797, 22.98977, 
         24.3050, 26.98154, 28.0855, 30.97376, 32.066, 35.4527, 39.948, 39.0983, 40.078, 44.95591, 47.867,     
         50.9415, 51.9961, 54.93805, 55.845, 58.93320, 58.6934, 63.546, 65.39, 69.723, 72.61, 74.92160, 78.96, 
         79.904, 83.80, 85.4678, 87.62, 88.90585, 91.224, 92.90638, 95.94, 98.0, 101.07, 102.90550, 106.42,    
         107.8682, 112.411, 114.818, 118.710, 121.760, 127.60, 126.90447, 131.29, 132.90545, 137.327, 138.9055,
         140.116, 140.90765, 144.24, 145.0, 150.36, 151.964, 157.25, 158.92534, 162.50, 164.93032, 167.26,     
         168.93421, 173.04, 174.967, 178.49, 180.9479, 183.84, 186.207, 190.23, 192.217, 195.078, 196.96655,   
         200.59, 204.3833, 207.2, 208.98038, 209.0, 210.0, 222.0, 223.0, 226.0, 227.0, 232.0381, 231.03588,    
         238.0289, 237.0, 244.0, 243.0, 247.0, 247.0, 251.0, 252.0, 257.0, 258.0, 259.0, 262.0, 261.0, 262.0,  
         263.0, 264.0, 265.0, 268.0, 271.0, 272.0, 285.0, 284.0, 289.0, 288.0, 292.0 ]

# Mapping of element name to mass
ElementMass = dict(zip(ElementName, mass))
del mass

covrad = [ 0.0, 0.320,0.310,1.630,0.900,0.820,0.770,0.750,0.730,0.720,0.710,1.540,1.360,1.180,1.110,1.060,1.020,     
           0.990,0.90,2.030,1.740,1.440,1.320,1.220,1.180,1.170,1.170,1.160,1.150,1.170,1.250,1.260,1.220,1.200, 
           1.160,1.140,1.120,2.160,1.910,1.620,1.450,1.340,1.300,1.270,1.250,1.250,1.280,1.340,1.480,1.440,1.410, 
           1.400,1.360,1.330,1.310,2.350,1.980,1.690,1.650,1.650,1.840,1.630,1.620,1.850,1.610,1.590,1.590,1.580, 
           1.570,1.560,2.000,1.560,1.440,1.340,1.300,1.280,1.260,1.270,1.300,1.340,1.490,1.480,1.470,1.460,1.460, 
           2.000,2.000,2.000,2.000,2.000,1.650,2.000,1.420,2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000, 
           2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000,2.000 ]

# Mapping of element name to covalent radii
ElementCovRad = dict(zip(ElementName, covrad))
del covrad

def atomic_number_from_symbol(atomic_symbol):
   """Return atomic number corresponding to atomic_symbol, or 0 on error"""

   try:
      atomic_num = int(atomic_symbol)
      if atomic_num < 1 or atomic_num > len(ElementName):
         atomic_num = 0
      return atomic_num
   except ValueError:
      try:
         return ElementName.index(atomic_symbol)
      except IndexError:
         return 0

def atomic_number_from_mass(atomic_mass, tol=0.01):
   """Return atomic number from mass in grams per mole, or 0 on error"""
   for sym, mass in ElementMass.iteritems():
      if abs(mass - atomic_mass) < tol:
         return sym
   return 0

