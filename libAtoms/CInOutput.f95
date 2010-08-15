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

#include "error.inc"

module CInOutput_module

  !% Interface to C routines for reading and writing Atoms objects to and from XYZ and NetCDF files.

  use iso_c_binding
  use error_module
  use System_module, only: dp, optional_default, s2a, a2s, parse_string, print, PRINT_VERBOSE, PRINT_ALWAYS, INPUT, OUTPUT, INOUT
  use Atoms_module, only: Atoms, initialise, finalise, add_property, bcast, has_property, set_lattice, atoms_repoint
  use PeriodicTable_module, only: atomic_number_from_symbol, ElementName
  use Extendable_str_module, only: Extendable_str, operator(//), string, c_extendable_str_initialise
  use Dictionary_module, only: Dictionary, has_key, get_value, set_value, print, subset, swap, lookup_entry_i, lower_case, &
       T_INTEGER, T_CHAR, T_REAL, T_LOGICAL, T_INTEGER_A, T_REAL_A, T_INTEGER_A2, T_REAL_A2, T_LOGICAL_A, T_CHAR_A, &
       print_keys, c_dictionary_ptr_type, c_dictionary_initialise, assignment(=)
  use Table_module, only: Table, allocate, append, TABLE_STRING_LENGTH
  use MPI_Context_module, only: MPI_context

  implicit none

  private

  interface

     subroutine read_netcdf(filename, params, properties, selected_properties, lattice, n_atom, frame, zero, irep, rrep, error) bind(c)
       use iso_c_binding, only: C_CHAR, C_INT, C_PTR, C_DOUBLE
       character(kind=C_CHAR,len=1), dimension(*), intent(in) :: filename
       integer(kind=C_INT), dimension(12), intent(in) :: params, properties, selected_properties
       real(kind=C_DOUBLE), dimension(3,3), intent(out) :: lattice
       integer(kind=C_INT), intent(out) :: n_atom
       integer(kind=C_INT), intent(in), value :: frame, zero, irep
       real(kind=C_DOUBLE), intent(in), value :: rrep
       integer(kind=C_INT), intent(out) :: error
     end subroutine read_netcdf

     subroutine write_netcdf(filename, params, properties, selected_properties, lattice, n_atom, n_label, n_string, frame, netcdf4, append, &
          shuffle, deflate, deflate_level, error) bind(c)
       use iso_c_binding, only: C_CHAR, C_INT, C_PTR, C_DOUBLE
       character(kind=C_CHAR,len=1), dimension(*), intent(in) :: filename
       integer(kind=C_INT), dimension(12), intent(in) :: params, properties, selected_properties
       real(kind=C_DOUBLE), dimension(3,3), intent(in) :: lattice
       integer(kind=C_INT), intent(in), value :: n_atom, n_label, n_string, frame, netcdf4, append, shuffle, deflate, deflate_level
       integer(kind=C_INT), intent(out) :: error
     end subroutine write_netcdf

     subroutine query_netcdf(filename, n_frame, n_atom, n_label, n_string, error) bind(c)
       use iso_c_binding, only: C_CHAR, C_INT, C_PTR, C_DOUBLE
       character(kind=C_CHAR,len=1), dimension(*), intent(in) :: filename
       integer(kind=C_INT), intent(out) :: n_frame, n_atom, n_label, n_string
       integer(kind=C_INT), intent(out) :: error
     end subroutine query_netcdf

     subroutine read_xyz(filename, params, properties, selected_properties, lattice, n_atom, compute_index, frame, string, string_length, error) bind(c)
       use iso_c_binding, only: C_CHAR, C_INT, C_PTR, C_DOUBLE
       character(kind=C_CHAR,len=1), dimension(*), intent(in) :: filename
       integer(kind=C_INT), dimension(12), intent(in) :: params, properties, selected_properties
       real(kind=C_DOUBLE), dimension(3,3), intent(out) :: lattice
       integer(kind=C_INT), intent(out) :: n_atom
       integer(kind=C_INT), intent(in), value :: compute_index, frame, string, string_length
       integer(kind=C_INT), intent(out) :: error
     end subroutine read_xyz

     subroutine write_xyz(filename, params, properties, selected_properties, lattice, n_atom, append, prefix, &
       int_format, real_format, str_format, logical_format, string, estr, error) bind(c)
       use iso_c_binding, only: C_CHAR, C_INT, C_PTR, C_DOUBLE
       character(kind=C_CHAR,len=1), dimension(*), intent(in) :: filename
       integer(kind=C_INT), dimension(12), intent(in) :: params, properties, selected_properties, estr
       real(kind=C_DOUBLE), dimension(3,3), intent(in) :: lattice
       integer(kind=C_INT), intent(in), value :: n_atom, append
       character(kind=C_CHAR,len=1), dimension(*), intent(in) :: prefix, int_format, real_format, str_format, logical_format
       integer(kind=C_INT), intent(in), value :: string
       integer(kind=C_INT), intent(out) :: error
     end subroutine write_xyz

     subroutine query_xyz(filename, compute_index, frame, n_frame, n_atom, error) bind(c)
       use iso_c_binding, only: C_CHAR, C_INT
       character(kind=C_CHAR,len=1), dimension(*), intent(in) :: filename
       integer(kind=C_INT), intent(in), value :: compute_index, frame
       integer(kind=C_INT), intent(out) :: n_frame, n_atom
       integer(kind=C_INT), intent(out) :: error
     end subroutine query_xyz

  end interface

  integer, parameter :: XYZ_FORMAT = 1
  integer, parameter :: NETCDF_FORMAT = 2

  type CInOutput
     logical :: initialised = .false.
     character(len=1024) :: filename
     integer :: action
     integer :: format
     logical :: got_index
     logical :: netcdf4
     logical :: append
     integer :: current_frame
     integer :: n_frame
     integer :: n_atom
     integer :: n_label
     integer :: n_string
     type(MPI_Context) :: mpi
  end type CInOutput

  interface initialise
     !% Open a file for reading or writing. File type (Extended XYZ or NetCDF) is guessed from
     !% filename extension. Filename 'stdout' with action 'OUTPUT' to write XYZ to stdout.
     module procedure CInOutput_initialise
  end interface

  interface finalise
     !% Close file and free memory. Calls close() interface.
     module procedure CInOutput_finalise
  end interface

  interface close
     !% Close file. After a call to close(), you can can call initialise() again
     !% to reopen a new file.
     module procedure CInOutput_close
  end interface

  interface read
     !% Read an Atoms object from this CInOutput stream.
     !%
     !% Important properties which may be present (non-exhaustive list)
     !% \begin{itemize}
     !% \item {\bf species}, str, 1 col -- atomic species, e.g. Si or H
     !% \item {\bf pos}, real, 3 cols -- cartesian positions, in A
     !% \item {\bf Z}, int, 1 col -- atomic numbers
     !% \item {\bf mass}, real, 1 col -- atomic masses, in A,eV,fs units system
     !% \item {\bf velo}, real, 3 cols -- velocities, in A/fs
     !% \item {\bf acc}, real, 3 cols -- accelerations, in A/fs$^2$
     !% \item {\bf hybrid}, int, 1 col -- one for QM atoms and zero for hybrid atoms
     !% \item {\bf frac_pos}, real, 3 cols -- fractional positions of atoms
     !% \end{itemize}

     module procedure CInOutput_read
     module procedure atoms_read
     module procedure atoms_read_cinoutput
  end interface

  interface write
     !% Write an Atoms object to this CInOutput stream.
     module procedure CInOutput_write
     module procedure atoms_write
     module procedure atoms_write_cinoutput
  end interface

  public :: CInOutput, initialise, finalise, close, read, write

contains

  subroutine cinoutput_initialise(this, filename, action, append, netcdf4, no_compute_index, mpi, error)
    use iso_c_binding, only: C_INT
    type(CInOutput), intent(inout)  :: this
    character(*), intent(in), optional :: filename
    integer, intent(in), optional :: action
    logical, intent(in), optional :: append
    logical, optional, intent(in) :: netcdf4
    logical, optional, intent(in) :: no_compute_index
    type(MPI_context), optional, intent(in) :: mpi
    integer, intent(out), optional :: error

    integer :: compute_index
    logical :: file_exists

    INIT_ERROR(error)

    ! Make sure function pointers are set up to allow C to call dictionary, error, and extendable_str
    call c_dictionary_initialise()
    call c_error_initialise()
    call c_extendable_str_initialise()

    this%action = optional_default(INPUT, action)
    this%append = optional_default(.false., append)
    this%netcdf4 = optional_default(.true., netcdf4)
    this%filename = optional_default('', filename)

    compute_index = 1
    if (present(no_compute_index)) then
       if (no_compute_index) compute_index = 0
    end if
    if (present(mpi)) this%mpi = mpi

    ! Guess format from file extension
    if (trim(filename) == '') then
       this%format = XYZ_FORMAT
    else
       if (filename(len_trim(filename)-2:) == '.nc') then
          this%format = NETCDF_FORMAT
       else
          this%format = XYZ_FORMAT
       end if
    end if

    this%n_frame = 0
    this%n_atom = 0
    this%n_label = 0
    this%n_string = 0
    this%current_frame = 0
    this%got_index = .false.

    ! Should we do an initial query to count number of frames/atoms?
    if (.not. this%mpi%active .or. (this%mpi%active .and. this%mpi%my_proc == 0)) then
       inquire(file=this%filename, exist=file_exists)
       if (file_exists) then
          if (this%format == NETCDF_FORMAT) then
             call query_netcdf(trim(this%filename)//C_NULL_CHAR, this%n_frame, this%n_atom, this%n_label, this%n_string, error)
             BCAST_PASS_ERROR(error, this%mpi)
             this%got_index = .true.
          else
             if (trim(this%filename) /= 'stdin' .and. trim(this%filename) /= 'stdout') then
                call query_xyz(trim(this%filename)//C_NULL_CHAR, compute_index, this%current_frame, this%n_frame, this%n_atom, error)
                BCAST_PASS_ERROR(error, this%mpi)
                this%got_index = .false.
                if (compute_index == 1) this%got_index = .true.
             else
                this%got_index = .false.
             end if
          end if
       end if
    end if

    if (this%mpi%active) then
       BCAST_CHECK_ERROR(error, this%mpi)
       call bcast(this%mpi, this%n_frame)
       call bcast(this%mpi, this%n_atom)
       call bcast(this%mpi, this%n_label)
       call bcast(this%mpi, this%n_string)
    end if

    if (this%action /= INPUT .and. this%append) this%current_frame = this%n_frame

    this%initialised = .true.

  end subroutine cinoutput_initialise

  subroutine cinoutput_close(this)
    type(CInOutput), intent(inout) :: this

    this%initialised = .false.

  end subroutine cinoutput_close

  subroutine cinoutput_finalise(this)
    type(CInOutput), intent(inout) :: this

    call cinoutput_close(this)

  end subroutine cinoutput_finalise


  subroutine cinoutput_read(this, at, properties, properties_array, frame, zero, str, estr, error)
    use iso_c_binding, only: C_INT
    type(CInOutput), intent(inout) :: this
    type(Atoms), target, intent(out) :: at
    character(*), intent(in), optional :: properties
    character(*), intent(in), optional :: properties_array(:)
    integer, optional, intent(in) :: frame
    logical, optional, intent(in) :: zero
    character(*), intent(in), optional :: str
    type(extendable_str), intent(in), optional :: estr
    integer, intent(out), optional :: error

    type(Dictionary) :: empty_dictionary
    type(Dictionary), target :: selected_properties, tmp_params
    integer :: i, j, k, n_properties
    integer(C_INT) :: do_zero, do_compute_index, do_frame, i_rep
    real(C_DOUBLE) :: r_rep
    real(dp) :: lattice(3,3), maxlen(3), sep(3)
    type(c_dictionary_ptr_type) :: params_ptr, properties_ptr, selected_properties_ptr
    integer, dimension(12) :: params_ptr_i, properties_ptr_i, selected_properties_ptr_i
    integer n_atom
    character(len=100) :: tmp_properties_array(100)
    type(Extendable_Str), dimension(:), allocatable :: filtered_keys

    real, parameter :: vacuum = 10.0_dp ! amount of vacuum to add if no lattice found in file

    INIT_ERROR(error)

    if (.not. this%initialised) then
       RAISE_ERROR_WITH_KIND(ERROR_IO,"This CInOutput object is not initialised", error)
    endif
    if (this%action /= INPUT .and. this%action /= INOUT) then
       RAISE_ERROR_WITH_KIND(ERROR_IO,"Cannot read from action=OUTPUT CInOutput object", error)
    endif

    if (present(str) .and. present(estr)) then
       RAISE_ERROR('CInOutput_read: only one of "str" and "estr" may be present, not both', error)
    end if

    call finalise(at)

    if (.not. this%mpi%active .or. (this%mpi%active .and. this%mpi%my_proc == 0)) then

       call print('cinoutput_read: doing read on proc '//this%mpi%my_proc, PRINT_VERBOSE)

       do_frame = optional_default(this%current_frame, frame)

       if (this%got_index) then
          if (do_frame < 0) do_frame = this%n_frame + do_frame ! negative frames count backwards from end
          if (do_frame < 0 .or. do_frame >= this%n_frame) then
             BCAST_RAISE_ERROR_WITH_KIND(ERROR_IO_EOF,"cinoutput_read: frame "//int(do_frame)//" out of range 0 <= frame < "//int(this%n_frame), error, this%mpi)
          end if
       end if

       do_zero = 0
       if (present(zero)) then
          if (zero) do_zero = 1
       end if

       call initialise(selected_properties)
       if (present(properties) .or. present(properties_array)) then
          if (present(properties_array)) then
             do i=1,size(properties_array)
                call set_value(selected_properties, properties_array(i), 1)
             end do
             PASS_ERROR(error)
          else ! we've got a colon-separated string
             call parse_string(properties, ':', tmp_properties_array, n_properties, error=error)
             PASS_ERROR(error)
             if (n_properties > size(tmp_properties_array)) then
                RAISE_ERROR('cinoutput_read: too many properties given in "properties" argument', error)
             end if
             do i=1,n_properties
                call set_value(selected_properties, tmp_properties_array(i), 1)
             end do
          end if
       end if

       lattice = 0.0_dp
       call initialise(empty_dictionary) ! pass an empty dictionary to prevent pos, species, z properties being created
       call initialise(at, 0, lattice, properties=empty_dictionary)
       call finalise(empty_dictionary)

       call initialise(tmp_params)
       params_ptr%p => tmp_params
       properties_ptr%p => at%properties
       selected_properties_ptr%p => selected_properties
       params_ptr_i = transfer(params_ptr, params_ptr_i)
       properties_ptr_i = transfer(properties_ptr, properties_ptr_i)
       selected_properties_ptr_i = transfer(selected_properties_ptr, selected_properties_ptr_i)

       if (this%format == NETCDF_FORMAT) then
          i_rep = 0
          r_rep = 0.0_dp
          call read_netcdf(trim(this%filename)//C_NULL_CHAR, params_ptr_i, properties_ptr_i, selected_properties_ptr_i, &
               at%lattice, n_atom, do_frame, do_zero, i_rep, r_rep, error)
       else
          do_compute_index = 1
          if (.not. this%got_index) do_compute_index = 0
          if (present(str)) then
             call print('len_trim(str) = '//len_trim(str))
             call read_xyz(str, params_ptr_i, properties_ptr_i, selected_properties_ptr_i, &
                  at%lattice, n_atom, do_compute_index, do_frame, 1, len_trim(str), error)
          else if(present(estr)) then
	     call print('estr%len = '//estr%len)
             call read_xyz(estr%s, params_ptr_i, properties_ptr_i, selected_properties_ptr_i, &
                  at%lattice, n_atom, do_compute_index, do_frame, 1, estr%len, error)
          else
             call read_xyz(trim(this%filename)//C_NULL_CHAR, params_ptr_i, properties_ptr_i, selected_properties_ptr_i, &
                  at%lattice, n_atom, do_compute_index, do_frame, 0, 0, error)
          end if
       end if
       BCAST_PASS_ERROR(error, this%mpi)
       call finalise(selected_properties)

       ! Copy tmp_params into at%params, removing "Lattice" and "Properties" entries
       allocate(filtered_keys(tmp_params%N))
       j = 1
       do i=1,tmp_params%N
          if (string(tmp_params%keys(i)) == 'Lattice' .or. &
              string(tmp_params%keys(i)) == 'Properties') cycle

          call initialise(filtered_keys(j), tmp_params%keys(i))
          j = j + 1
       end do

       call subset(tmp_params, filtered_keys(1:j-1), at%params)
       call finalise(tmp_params)
       do i=1,size(filtered_keys)
          call finalise(filtered_keys(i))
       end do
       deallocate(filtered_keys)

       at%N = n_atom
       at%Nbuffer = at%N
       at%Ndomain = at%N
       at%initialised = .true.
       call atoms_repoint(at)

       if (all(abs(at%lattice) < 1e-5_dp)) then
          ! read_xyz() sets all lattice components to 0.0 if no lattice was present
          at%lattice(:,:) = 0.0_dp

          maxlen = 0.0_dp
          do i=1,at%N
             do j=1,at%N
                sep = at%pos(:,i)-at%pos(:,j)
                do k=1,3
                   if (abs(sep(k)) > maxlen(k)) maxlen(k) = abs(sep(k))
                end do
             end do
          end do

          do k=1,3
             at%lattice(k,k) = maxlen(k) + vacuum
          end do
          call print('set lattice to ')
          call print(at%lattice)
       end if
       call set_lattice(at, at%lattice, scale_positions=.false.)

       if (.not. has_property(at,"Z") .and. .not. has_property(at, "species")) then
          call print ("at%properties keys", PRINT_ALWAYS)
          call print_keys(at%properties, PRINT_ALWAYS)
          BCAST_RAISE_ERROR('cinoutput_read: atoms object read from file has neither Z nor species', error, this%mpi)
       else if (.not. has_property(at,"species") .and. has_property(at,"Z")) then
          call add_property(at, "species", repeat(" ",TABLE_STRING_LENGTH))
          call atoms_repoint(at)
          do i=1,at%N
             at%species(:,i) = s2a(ElementName(at%Z(i)))
          end do
       else if (.not. has_property(at,"Z") .and. has_property(at, "species")) then
          call add_property(at, "Z", 0)
          call atoms_repoint(at)
          do i=1,at%n
             at%Z(i) = atomic_number_from_symbol(a2s(at%species(:,i)))
          end do
       end if

       this%current_frame = this%current_frame + 1

    end if

    if (this%mpi%active) then
       BCAST_CHECK_ERROR(error,this%mpi)
       call bcast(this%mpi, at)
    end if

  end subroutine cinoutput_read


  subroutine cinoutput_write(this, at, properties, properties_array, prefix, int_format, real_format, frame, &
       shuffle, deflate, deflate_level, estr, error)
    type c_extendable_str_ptr_type
       type(Extendable_str), pointer :: p
    end type c_extendable_str_ptr_type
    type(CInOutput), intent(inout) :: this
    type(Atoms), target, intent(in) :: at
    character(*), intent(in), optional :: properties
    character(*), intent(in), optional :: properties_array(:)
    character(*), intent(in), optional :: prefix
    character(*), intent(in), optional :: int_format, real_format
    integer, intent(in), optional :: frame
    logical, intent(in), optional :: shuffle, deflate
    integer, intent(in), optional :: deflate_level
    type(Extendable_Str), intent(inout), optional, target :: estr
    integer, intent(out), optional :: error

    logical :: file_exists
    integer :: i
    integer(C_INT) :: do_frame, n_label, n_string, do_netcdf4
    type(Dictionary), target :: selected_properties, tmp_params
    character(len=100) :: do_prefix, do_int_format, do_real_format, do_str_format, do_logical_format
    integer(C_INT) :: do_shuffle, do_deflate, do_deflate_level, append
    character(len=100) :: tmp_properties_array(at%properties%n)
    integer n_properties
    type(c_dictionary_ptr_type) :: params_ptr, properties_ptr, selected_properties_ptr
    integer, dimension(12) :: params_ptr_i, properties_ptr_i, selected_properties_ptr_i, estr_ptr_i
    type(c_extendable_str_ptr_type) :: estr_ptr


    INIT_ERROR(error)

    if (.not. this%initialised) then
       RAISE_ERROR("cinoutput_write: this CInOutput object is not initialised", error)
    endif
    if (this%action /= OUTPUT .and. this%action /= INOUT) then
       RAISE_ERROR("cinoutput_write: cannot write to action=INPUT CInOutput object", error)
    endif
    if (.not. at%initialised) then
       RAISE_ERROR("cinoutput_write: atoms object not initialised", error)
    end if

    if (this%mpi%active .and. this%mpi%my_proc /= 0) return

    ! These are C-strings and thus must be terminated with '\0'
    do_prefix = optional_default(C_NULL_CHAR, prefix)
    do_int_format = trim(optional_default('%8d', int_format))//C_NULL_CHAR
    do_real_format = trim(optional_default('%16.8f', real_format))//C_NULL_CHAR
    do_str_format = '%.10s'//C_NULL_CHAR
    do_logical_format = '%5c'//C_NULL_CHAR

    do_frame = optional_default(this%current_frame, frame)

    do_shuffle = transfer(optional_default(.true., shuffle),do_shuffle)
    do_deflate = transfer(optional_default(.true., deflate),do_shuffle)
    do_deflate_level = optional_default(6, deflate_level)

    append = 0
    inquire(file=this%filename, exist=file_exists)
    if (file_exists .and. this%append .or. this%current_frame /= 0) append = 1

    do_netcdf4 = 0
    if (this%netcdf4) do_netcdf4 = 1

    if (present(properties) .and. present(properties_array)) then
       RAISE_ERROR('cinoutput_write: "properties" and "properties_array" cannot both be present.', error)
    end if

    call initialise(selected_properties)
    if (.not. present(properties) .and. .not. present(properties_array)) then
       do i=1,at%properties%N
          call set_value(selected_properties, string(at%properties%keys(i)), 1)
       end do
    else
       if (present(properties_array)) then
          do i=1,size(properties_array)
             call set_value(selected_properties, properties_array(i), 1)
          end do
       else ! we've got a colon-separated string
          call parse_string(properties, ':', tmp_properties_array, n_properties, error=error)
          PASS_ERROR(error)
          do i=1,n_properties
             call set_value(selected_properties, tmp_properties_array(i), 1)
          end do
       end if
    end if

    tmp_params = at%params
    !call subset(at%params, at%params%keys(1:at%params%n), tmp_params)  ! Make a copy since write_xyz() adds "Lattice" and "Properties" keys
    params_ptr%p => tmp_params
    properties_ptr%p => at%properties
    selected_properties_ptr%p => selected_properties
    params_ptr_i = transfer(params_ptr, params_ptr_i)
    properties_ptr_i = transfer(properties_ptr, properties_ptr_i)
    selected_properties_ptr_i = transfer(selected_properties_ptr, selected_properties_ptr_i)
    if (present(estr)) then
       estr_ptr%p => estr
       estr_ptr_i = transfer(estr_ptr, estr_ptr_i)
    end if

    n_label = 10
    n_string = 1024

    if (this%format == NETCDF_FORMAT) then
       call write_netcdf(trim(this%filename)//C_NULL_CHAR, params_ptr_i, properties_ptr_i, selected_properties_ptr_i, &
            at%lattice, at%n, n_label, n_string, do_frame, &
            do_netcdf4, append, do_shuffle, do_deflate, do_deflate_level, error)
       PASS_ERROR(error)
    else
       ! Put "species" in first column and "pos" in second
       if (has_key(selected_properties, 'species')) &
            call swap(selected_properties, 'species', string(selected_properties%keys(1)))
       if (has_key(selected_properties, 'pos')) &
            call swap(selected_properties, 'pos', string(selected_properties%keys(2)))

       if (present(estr)) then
          call write_xyz(C_NULL_CHAR, params_ptr_i, properties_ptr_i, selected_properties_ptr_i, &
               at%lattice, at%n, append, do_prefix, do_int_format, do_real_format, do_str_format, do_logical_format, 1, estr_ptr_i, error)
       else
          call write_xyz(trim(this%filename)//C_NULL_CHAR, params_ptr_i, properties_ptr_i, selected_properties_ptr_i, &
               at%lattice, at%n, append, do_prefix, do_int_format, do_real_format, do_str_format, do_logical_format, 0, estr_ptr_i, error)
       end if
       PASS_ERROR(error)
    end if

    call finalise(selected_properties)
    call finalise(tmp_params)
    this%current_frame = this%current_frame + 1

  end subroutine cinoutput_write

  subroutine atoms_read(this, filename, properties, properties_array, frame, zero, str, estr, no_compute_index, mpi, error)
    !% Read Atoms object from XYZ or NetCDF file.
    type(Atoms), intent(inout) :: this
    character(len=*), intent(in), optional :: filename
    character(*), intent(in), optional :: properties
    character(*), intent(in), optional :: properties_array(:)
    integer, optional, intent(in) :: frame
    logical, optional, intent(in) :: zero
    character(len=*), intent(in), optional :: str
    type(extendable_str), intent(in), optional :: estr
    logical, optional, intent(in) :: no_compute_index
    type(MPI_context), optional, intent(inout) :: mpi
    integer, intent(out), optional :: error

    type(CInOutput) :: cio

    INIT_ERROR(error)

    call initialise(cio, filename, INPUT, no_compute_index=no_compute_index, mpi=mpi, error=error)
    PASS_ERROR_WITH_INFO('While reading "' // filename // '".', error)
    call read(cio, this, properties, properties_array, frame, zero, str, estr, error=error)
    PASS_ERROR_WITH_INFO('While reading "' // filename // '".', error)
    call finalise(cio)

  end subroutine atoms_read

  subroutine atoms_read_cinoutput(this, cio, properties, properties_array, frame, zero, str, estr, error)
    type(Atoms), target, intent(inout) :: this
    type(CInOutput), intent(inout) :: cio
    character(*), intent(in), optional :: properties
    character(*), intent(in), optional :: properties_array(:)
    integer, optional, intent(in) :: frame
    logical, optional, intent(in) :: zero
    character(len=*), intent(in), optional :: str
    type(extendable_str), intent(in), optional :: estr
    integer, intent(out), optional :: error

    INIT_ERROR(error)
    call cinoutput_read(cio, this, properties, properties_array, frame, zero, str, estr, error=error)
    PASS_ERROR(error)

  end subroutine atoms_read_cinoutput

  subroutine atoms_write(this, filename, append, properties, properties_array, prefix, int_format, real_format, estr, error)
    !% Write Atoms object to XYZ or NetCDF file. Use filename "stdout" to write to terminal.
    use iso_fortran_env
    type(Atoms), intent(in) :: this
    character(len=*), intent(in), optional :: filename
    logical, optional, intent(in) :: append
    character(*), intent(in), optional :: properties
    character(*), intent(in), optional :: properties_array(:)
    character(*), intent(in), optional :: prefix
    character(*), intent(in), optional :: int_format, real_format
    type(extendable_str), intent(inout), optional :: estr
    integer, intent(out), optional :: error

    type(CInOutput) :: cio
    type(MPI_context) :: mpi

    if (trim(filename) == 'stdout') then
       call initialise(mpi)
       if (mpi%active .and. mpi%my_proc /= 0) return
       flush(output_unit)
    end if

    INIT_ERROR(error)
    call initialise(cio, filename, OUTPUT, append, error=error)
    PASS_ERROR_WITH_INFO('While writing "' // filename // '".', error)
    call write(cio, this, properties, properties_array, prefix, int_format, real_format, error=error)
    PASS_ERROR_WITH_INFO('While writing "' // filename // '".', error)
    call finalise(cio)

  end subroutine atoms_write

  subroutine atoms_write_cinoutput(this, cio, properties, properties_array, prefix, int_format, real_format, frame, shuffle, deflate, deflate_level, estr, error)
    type(Atoms), target, intent(inout) :: this
    type(CInOutput), intent(inout) :: cio
    character(*), intent(in), optional :: properties
    character(*), intent(in), optional :: properties_array(:)
    character(*), intent(in), optional :: prefix, int_format, real_format
    integer, intent(in), optional :: frame
    logical, intent(in), optional :: shuffle, deflate
    integer, intent(in), optional :: deflate_level
    type(extendable_str), intent(inout), optional :: estr
    integer, intent(out), optional :: error

    INIT_ERROR(error)
    call cinoutput_write(cio, this, properties, properties_array, prefix, int_format, real_format, frame, shuffle, deflate, deflate_level, estr, error=error)
    PASS_ERROR(error)

  end subroutine atoms_write_cinoutput

end module CInOutput_module
