!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X
!X     QUIP: quantum mechanical and interatomic potential simulation package
!X
!X     Portions written by Noam Bernstein, while working at the
!X     Naval Research Laboratory, Washington DC.
!X
!X     Portions written by Gabor Csanyi, Copyright 2006-2007.
!X
!X     When using this software,  please cite the following reference:
!X
!X     reference
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X
!X FilePot Module
!X
!% FilePot is a potential that computes things by writing atomic config to a
!% file, running a command, and reading its output
!%
!% it takes an argument string on initialization with one mandatory parameter
!%>   command=path_to_command
!% and two optional parameters
!%>   property_list=prop1:T1:N1:prop2:T2:N2...
!% which defaults to 'pos', and
!%>   min_cutoff=cutoff
!% which default to zero. If min_cutoff is non zero and the cell is narrower
!% than $2*min_cutoff$ in any direction then it will be replicated before
!% being written to the file. The forces are taken from the primitive cell
!% and the energy is reduced by a factor of the number of repeated copies.
!% 
!% The command takes 2 arguments, the names of the input and the output files.
!% command output is in extended xyz form.
!%
!% energy and virial (both optional) are passed via the comment, labeled as
!%     'energy=E' and 'virial="vxx vxy vxz vyx vyy vyz vzx vzy vzz"'.
!%
!%  per atoms data is at least atomic type and optionally 
!%     a local energy (labeled 'local_e:R:1') 
!%  and 
!%  forces (labeled 'force:R:3')
!%
!% right now (14/2/2008) the atoms_xyz reader requires the 1st 3 columns after
!%   the atomic type to be the position.
!% 
!% If you ask for some quantity from FilePot_Calc and it's not in the output file, it
!% returns an error status or crashes (if err isn't present).
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
! some day implement calculation queues
! how to do this? one possibility:
!  add args_str to FilePot_Calc, and indicate
!   queued_force=i to indicate this atoms structure should be queued for the calculation
!    of forces on atom i (or a list, or a range?)
! or
!   process_queue, which would process the queue and fill in all the forces
module FilePot_module

use libatoms_module
use mpi_context_module

implicit none
private


public :: FilePot_type
type FilePot_type
  character(len=1024) :: command
  character(len=1024) :: property_list
  real(dp)            :: min_cutoff

  character(len=1024) :: init_args_str
  type(MPI_context) :: mpi

end type FilePot_type

public :: Initialise
interface Initialise
  module procedure FilePot_Initialise
end interface Initialise

public :: Finalise
interface Finalise
  module procedure FilePot_Finalise
end interface Finalise

public :: cutoff
interface cutoff
   module procedure FilePot_cutoff
end interface

public :: Wipe
interface Wipe
  module procedure FilePot_Wipe
end interface Wipe

public :: Print
interface Print
  module procedure FilePot_Print
end interface Print

public :: calc
interface calc
  module procedure FilePot_Calc
end interface

contains


subroutine FilePot_Initialise(this, args_str, mpi)
  type(FilePot_type), intent(inout) :: this
  character(len=*), intent(in) :: args_str
  type(MPI_Context), intent(in), optional :: mpi

  type(Dictionary) ::  params
  character(len=STRING_LENGTH) :: command, property_list
  real(dp) :: min_cutoff

  this%init_args_str = args_str

  call initialise(params)
  command=''
  property_list='pos'
  call param_register(params, 'command', PARAM_MANDATORY, command)
  call param_register(params, 'property_list', 'pos', property_list)
  call param_register(params, 'min_cutoff', '0.0', min_cutoff)
  if (.not. param_read_line(params, args_str, ignore_unknown=.true.,task='filepot_initialise args_str')) then
    call system_abort("FilePot_initialise failed to parse args_str='"//trim(args_str)//"'")
  endif
  call finalise(params)

  this%command = command
  this%property_list = property_list
  this%min_cutoff = min_cutoff
  if (present(mpi)) this%mpi = mpi

end subroutine FilePot_Initialise

subroutine FilePot_Finalise(this)
  type(FilePot_type), intent(inout) :: this

  call wipe(this)

end subroutine FilePot_Finalise

subroutine FilePot_Wipe(this)
  type(FilePot_type), intent(inout) :: this

  this%command=""
  this%property_list=""
  this%min_cutoff = 0.0_dp

end subroutine FilePot_Wipe

function FilePot_cutoff(this)
  type(FilePot_type), intent(in) :: this
  real(dp) :: FilePot_cutoff
  FilePot_cutoff = 0.0_dp ! return zero, because FilePot does its own connection calculation
end function FilePot_cutoff

subroutine FilePot_Print(this, file)
  type(FilePot_type),    intent(in)           :: this
  type(Inoutput), intent(inout),optional,target:: file

  if (current_verbosity() < NORMAL) return

  call print("FilePot: command='"//trim(this%command)// &
       "' property_list='"//trim(this%property_list)//&
       "' min_cutoff="//this%min_cutoff,file=file)

end subroutine FilePot_Print

subroutine FilePot_Calc(this, at, energy, local_e, forces, virial, args_str, err)
  type(FilePot_type), intent(inout) :: this
  type(Atoms), intent(inout) :: at
  real(dp), intent(out), optional :: energy
  real(dp), intent(out), target, optional :: local_e(:)
  real(dp), intent(out), optional :: forces(:,:)
  real(dp), intent(out), optional :: virial(3,3)
  character(len=*), intent(in), optional :: args_str
  integer, intent(out), optional :: err

  character(len=1024) :: xyzfile, outfile, my_args_str
  type(inoutput) :: xyzio
  integer :: nx, ny, nz
  type(Atoms) :: sup
  integer :: my_err
  integer :: status

  if (present(energy)) energy = 0.0_dp
  if (present(local_e)) local_e = 0.0_dp
  if (present(forces)) forces = 0.0_dp
  if (present(virial)) virial = 0.0_dp
  if (present(err)) err = 0
  my_args_str = ''
  if (present(args_str)) my_args_str = args_str

  ! Run external command either if MPI object is not active, or if it is active and we're the
  ! master process. Function does not return on any node until external command is finished.

  if (.not. this%mpi%active .or. &
       (this%mpi%active .and. this%mpi%my_proc == 0)) then
     
     xyzfile="filepot."//this%mpi%my_proc//".xyz"
     outfile="filepot."//this%mpi%my_proc//".out"

     call initialise(xyzio, xyzfile, action=OUTPUT)

     ! Do we need to replicate cell to exceed min_cutoff ?
     if (this%min_cutoff .fne. 0.0_dp) then
        call fit_box_in_cell(this%min_cutoff, this%min_cutoff, this%min_cutoff, at%lattice, nx, ny, nz)
     else
        nx = 1; ny = 1; nz = 1
     end if

     if (nx /= 1 .or. ny /= 1 .or. nz /= 1) then
        call Print('FilePot: replicating cell '//nx//'x'//ny//'x'//nz//' times.')
        call supercell(sup, at, nx, ny, nz)
        call print_xyz(sup, xyzio, properties=trim(this%property_list),real_format='f17.10')
     else
        call print_xyz(at, xyzio, properties=trim(this%property_list),real_format='f17.10')
     end if
     call finalise(xyzio)

!     call print("FilePot: invoking external command "//trim(this%command)//" "//' '//trim(xyzfile)//" "// &
!          trim(outfile)//" on "//at%N//" atoms...")
     call print("FilePot: invoking external command "//trim(this%command)//' '//trim(xyzfile)//" "// &
          trim(outfile)//" "//trim(my_args_str)//" on "//at%N//" atoms...")

     ! call the external command here
!     call system_command(trim(this%command)//" "//trim(xyzfile)//" "//trim(outfile),status=status)
     call system_command(trim(this%command)//' '//trim(xyzfile)//" "//trim(outfile)//" "//trim(my_args_str),status=status)

     ! read back output from external command
     call filepot_read_output(outfile, at, nx, ny, nz, energy, local_e, forces, virial, my_err)
  end if

  if (this%mpi%active) then
     ! Share results with other nodes
     if (present(energy))  call bcast(this%mpi, energy)
     if (present(local_e)) call bcast(this%mpi, local_e)

     if (present(forces))  call bcast(this%mpi, forces)
     if (present(virial))  call bcast(this%mpi, virial)

     call bcast(this%mpi, my_err)
  end if

  if (present(err)) then
    err = my_err
  else if (my_err /= 0) then
    call system_abort("FilePot got err status " // my_err // " from filepot_read_output")
  end if

end subroutine FilePot_calc

subroutine filepot_read_output(outfile, at, nx, ny, nz, energy, local_e, forces, virial, err)
  character(len=*), intent(in) :: outfile
  type(Atoms), intent(inout) :: at
  integer, intent(in) :: nx, ny, nz
  real(dp), intent(out), optional :: energy
  real(dp), intent(out), target, optional :: local_e(:)
  real(dp), intent(out), optional :: forces(:,:)
  real(dp), intent(out), optional :: virial(3,3)
  integer, intent(out), optional :: err

  integer :: i
  type(inoutput) :: outio
  type(atoms) :: at_out, primitive
  integer, pointer :: Z_p(:)
  real(dp) :: virial_1d(9)
  real(dp), pointer :: local_e_p(:), forces_p(:,:)
  real(dp),dimension(3)          :: QM_cell

  call initialise(outio, outfile)
  call read_xyz(at_out, outio)
  call finalise(outio)

  if (present(err)) err = 0

  if (nx /= 1 .or. ny /= 1 .or. nz /= 1) then
     ! Discard atoms outside the primitive cell
     call select(primitive, at_out, list=(/ (i, i=1,at_out%N/(nx*ny*nz) ) /))
     at_out = primitive
     call finalise(primitive)
  end if

  if (at_out%N /= at%N) then
    if (present(err)) then
      call print("filepot_read_output in '"//trim(outfile)//"' got N="//at_out%N//" /= at%N="//at%N, ERROR)
      err = 1
      return
    else
      call system_abort("filepot_read_output in '"//trim(outfile)//"' got N="//at_out%N//" /= at%N="//at%N)
    endif
  endif

  if (.not. assign_pointer(at_out,'Z',Z_p)) then
    if (present(err)) then
      call print("filepot_read_output in '"//trim(outfile)//"' couldn't associated pointer for field Z", ERROR)
      err = 1
      return
    else
      call system_abort("filepot_read_output in '"//trim(outfile)//"' couldn't associated pointer for field Z")
    endif
  endif
  do i=1, at%N
    if (at%Z(i) /= Z_p(i)) then
      if (present(err)) then
	call print("filepot_read_output in '"//trim(outfile)//"' got Z("//i//")="// &
	  at_out%Z(i)//" /= at%Z("//i//")="// at%Z(i), ERROR)
	err = 1
	return
      else
	call system_abort("filepot_read_output in '"//trim(outfile)//"' got Z("//i//")="// &
	  at_out%Z(i)//" /= at%Z("//i//")="//at%Z(i))
      endif
    endif
  end do

  if (present(energy)) then
    if (.not. get_value(at_out%params,'energy',energy)) then
      if (present(err)) then
	call print("filepot_read_output needed energy, but couldn't find energy in '"//trim(outfile)//"'", ERROR)
	err = 1
	return
      else
	call system_abort("filepot_read_output needed energy, but couldn't find energy in '"//trim(outfile)//"'")
      endif
    endif
    ! If cell was repeated, reduce energy by appropriate factor
    ! to give energy of primitive cell.
    if (nx /= 1 .or. ny /= 1 .or. nz /= 1) &
         energy = energy/(nx*ny*nz)
  endif

  if (present(virial)) then
     if (nx /= 1 .or. ny /= 1 .or. nz /= 1) &
          call system_abort("filepot_read_output: don't know how to rescale virial for repicated system")

    if (.not. get_value(at_out%params,'virial',virial_1d)) then
      if (present(err)) then
	call print("filepot_read_output needed virial, but couldn't find virial in '"//trim(outfile)//"'", ERROR)
	err = 1
	return
      else
	call system_abort("filepot_read_output needed virial, but couldn't find virial in '"//trim(outfile)//"'")
      endif
    endif
    virial(:,1) = virial_1d(1:3)
    virial(:,2) = virial_1d(4:6)
    virial(:,3) = virial_1d(7:9)
  endif

  if (present(local_e)) then
    if (.not. assign_pointer(at_out, 'local_e', local_e_p)) then
      if (present(err)) then
	call print("filepot_read_output needed local_e, but couldn't find local_e in '"//trim(outfile)//"'", ERROR)
	err = 1
	return
      else
	call system_abort("filepot_read_output needed local_e, but couldn't find local_e in '"//trim(outfile)//"'")
      endif
    endif
    local_e = local_e_p
  endif

  if (present(forces)) then
    if (.not. assign_pointer(at_out, 'force', forces_p)) then
      if (present(err)) then
	call print("filepot_read_output needed forces, but couldn't find force in '"//trim(outfile)//"'", ERROR)
	err = 1
	return
      else
	call system_abort("filepot_read_output needed forces, but couldn't find force in '"//trim(outfile)//"'")
      endif
    endif
    forces = forces_p
  endif

  !for the CP2K driver. If the QM cell size is saved in *at_out*, save it in *at*
  if (get_value(at_out%params,'QM_cell',QM_cell)) then
     call set_value(at%params,'QM_cell',QM_cell)
  endif

  call finalise(at_out)

end subroutine filepot_read_output

end module FilePot_module
