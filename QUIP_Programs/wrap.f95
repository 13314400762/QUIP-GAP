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

! FrameTools like wrapper for coalesce_in_one_periodic_image()
! moves all atoms so that no bonds occur across a periodic image
program wrap_prog
use libatoms_module
implicit none
  type(Atoms) :: at
  type(Dictionary) :: cli_params
  integer :: seed
  real(dp) :: cutoff_factor

  call system_initialise()

  call initialise(cli_params)
  call param_register(cli_params, 'seed', '1', seed)
  call param_register(cli_params, 'cutoff_factor', '1.0', cutoff_factor)
  if (.not. param_read_args(cli_params, do_check = .true.)) then
    call print("Usage: wrap [seed=1] [cutoff_factor=1.0]", PRINT_ALWAYS)
    call system_abort("Confused by CLI parameters")
  endif
  call finalise(cli_params)

  call read_xyz(at, "stdin")

  call set_cutoff_factor(at, cutoff_factor)
  call calc_connect(at)

  call coalesce_in_one_periodic_image(at, seed)

  mainlog%prefix="WRAPPED"
  call print_xyz(at, mainlog, properties="pos")
  mainlog%prefix=""

  call system_finalise()
end program

