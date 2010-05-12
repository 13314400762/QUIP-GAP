! H0 XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
! H0 X
! H0 X   libAtoms+QUIP: atomistic simulation library
! H0 X
! H0 X   Portions of this code were written by
! H0 X     Albert Bartok-Partay, Silvia Cereda, Gabor Csanyi, James Kermode,
! H0 X     Ivan Solt, Wojciech Szlachta, Csilla Varnai, Steven Winfield.
! H0 X
! H0 X   Copyright 2006-2010.
! H0 X
! H0 X   These portions of the source code are released under the GNU General
! H0 X   Public License, version 2, http://www.gnu.org/copyleft/gpl.html
! H0 X
! H0 X   If you would like to license the source code under different terms,
! H0 X   please contact Gabor Csanyi, gabor@csanyi.net
! H0 X
! H0 X   Portions of this code were written by Noam Bernstein as part of
! H0 X   his employment for the U.S. Government, and are not subject
! H0 X   to copyright in the USA.
! H0 X
! H0 X
! H0 X   When using this software, please cite the following reference:
! H0 X
! H0 X   http://www.libatoms.org
! H0 X
! H0 X  Additional contributions by
! H0 X    Alessio Comisso, Chiara Gattinoni, and Gianpietro Moras
! H0 X
! H0 XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X
!X gap_wrapper subroutine
!X
!% wrapper to make it nicer for non-QUIP programs to use GAP potential
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

subroutine gap_wrapper(N,lattice,symbol,coord,energy,force,stress)
  use libatoms_module
  use quip_module

  implicit none

  integer, intent(in) :: N
  real(dp), dimension(3,3), intent(in) :: lattice
  character(len=8), dimension(N), intent(in) :: symbol
  real(dp), dimension(3,N), intent(in) :: coord
  real(dp), intent(out) :: energy
  real(dp), dimension(3,N), intent(out) :: force
  real(dp), dimension(3,3), intent(out) :: stress
  
  type(atoms), save     :: at
  type(Potential), save :: pot

  integer :: i
  real(dp), dimension(:), pointer :: charge

  logical, save :: first_run = .true.

  call system_initialise(verbosity=SILENT)

  if( first_run ) then
     call Initialise(pot, "IP GAP", "" )
     call initialise(at,N,transpose(lattice)*BOHR)
  endif
  
  if( .not. first_run .and. (N /= at%N) ) then
     call finalise(at)
     call initialise(at,N,transpose(lattice)*BOHR)
  endif

  call set_lattice(at,transpose(lattice)*BOHR, keep_fractional=.false.)
  
  do i = 1, at%N
     at%Z(i) = atomic_number_from_symbol(symbol(i))
  enddo 
  at%pos = coord*BOHR

  call atoms_set_cutoff(at,cutoff(pot)+0.5_dp)
  call calc_connect(at)

  call calc(pot,at,e=energy,f=force,virial=stress)

  energy = energy / HARTREE
  force = force / HARTREE * BOHR
  stress = stress / HARTREE

  first_run = .false.
  call system_finalise()

endsubroutine gap_wrapper
