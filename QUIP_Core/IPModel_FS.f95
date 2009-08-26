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
!X IPModel_FS module  
!X
!% Module for Finnis-Sinclair embedded-atom potential
!% (Ref. Philosophical Magazine A, {\bf 50}, 45 (1984)).
!%
!% The IPModel_FS object contains all the parameters read from a
!% 'FS_params' XML stanza.
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
module IPModel_FS_module

use libatoms_module

use mpi_context_module
use QUIP_Common_module

implicit none

private 

include 'IPModel_interface.h'

public :: IPModel_FS
type IPModel_FS
  integer :: n_types = 0                 !% Number of atomic types. 
  integer, allocatable :: atomic_num(:), type_of_atomic_num(:)  !% Atomic number dimensioned as \texttt{n_types} 

  real(dp) :: cutoff = 0.0_dp  !% Cutoff for computing connection.

  real(dp), allocatable :: c(:,:), c0(:,:), c1(:,:), c2(:,:)
  real(dp), allocatable :: A(:,:), beta(:,:), d(:,:)

  character(len=FIELD_LENGTH) :: label
  type(mpi_context) :: mpi

end type IPModel_FS

logical :: parse_in_ip, parse_matched_label
type(IPModel_FS), pointer :: parse_ip

interface Initialise
  module procedure IPModel_FS_Initialise_str
end interface Initialise

interface Finalise
  module procedure IPModel_FS_Finalise
end interface Finalise

interface Print
  module procedure IPModel_FS_Print
end interface Print

interface Calc
  module procedure IPModel_FS_Calc
end interface Calc

contains

subroutine IPModel_FS_Initialise_str(this, args_str, param_str, mpi)
  type(IPModel_FS), intent(inout) :: this
  character(len=*), intent(in) :: args_str, param_str
  type(mpi_context), intent(in), optional :: mpi

  type(Dictionary) :: params

  call Finalise(this)

  call initialise(params)
  this%label = ''
  call param_register(params, 'label', '', this%label)
  if (.not. param_read_line(params, args_str, ignore_unknown=.true.,task='IPModel_FS_Initialise_str args_str')) then
    call system_abort("IPModel_FS_Initialise_str failed to parse label from args_str="//trim(args_str))
  endif
  call finalise(params)

  call IPModel_FS_read_params_xml(this, param_str)

! Two cutoff radius: this%d > this%c
  this%cutoff = maxval(this%d)

  if (present(mpi)) this%mpi = mpi

end subroutine IPModel_FS_Initialise_str

subroutine IPModel_FS_Finalise(this)
  type(IPModel_FS), intent(inout) :: this

  if (allocated(this%atomic_num)) deallocate(this%atomic_num)
  if (allocated(this%type_of_atomic_num)) deallocate(this%type_of_atomic_num)

  if (allocated(this%c))  deallocate(this%c)
  if (allocated(this%c0)) deallocate(this%c0)
  if (allocated(this%c1)) deallocate(this%c1)
  if (allocated(this%c2)) deallocate(this%c2)
  if (allocated(this%A)) deallocate(this%A)
  if (allocated(this%beta)) deallocate(this%beta)
  if (allocated(this%d)) deallocate(this%d)

  this%n_types = 0
  this%label = ''
  
end subroutine IPModel_FS_Finalise

!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X 
!% The potential calculator: this routine computes energy, forces and the virial.
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

subroutine IPModel_FS_Calc(this, at, e, local_e, f, virial)
  type(IPModel_FS), intent(inout) :: this
  type(Atoms), intent(in) :: at
  real(dp), intent(out), optional :: e, local_e(:) !% \texttt{e} = System total energy, \texttt{local_e} = energy of each atom, vector dimensioned as \texttt{at%N}. 
  real(dp), intent(out), optional :: f(:,:)   !% Forces, dimensioned as \texttt{f(3,at%N)}
  real(dp), intent(out), optional :: virial(3,3)  !% Virial

  integer i, ji, j, ti, tj
  real(dp) :: rij(3), rij_mag, drij(3)
  real(dp) ::  phi_tot, sqrt_phi_tot
  real(dp) ::  Ui, dU

  ! private variables for open-mp 
  real(dp) :: private_virial(3,3), private_f(3,at%N), private_e

  if (present(e)) e = 0.0_dp
  if (present(local_e)) local_e = 0.0_dp
  if (present(virial)) virial = 0.0_dp
  if (present(f)) then 
     if(size(f,1) .ne. 3 .or. size(f,2) .ne. at%N) call system_abort('IPMOdel_FS_Calc: f is the wrong size')
     f = 0.0_dp
  end if

!$omp parallel private(i,ji,j,ti,tj,phi_tot,sqrt_phi_tot,dU,Ui,drij,rij_mag,private_virial,private_f,private_e)

  if (present(e)) private_e = 0.0_dp
  if (present(virial)) private_virial = 0.0_dp
  if (present(f)) private_f = 0.0_dp

!$omp do 
  do i=1, at%N
    if (this%mpi%active) then
      if (mod(i-1, this%mpi%n_procs) /= this%mpi%my_proc) cycle
    endif
     
     phi_tot = 0.0_dp
     
    do ji=1, atoms_n_neighbours(at, i)
      j = atoms_neighbour(at, i, ji, rij_mag)
      if (rij_mag .feq. 0.0_dp) cycle
 
      ti = get_type(this%type_of_atomic_num, at%Z(i))
      tj = get_type(this%type_of_atomic_num, at%Z(j))
 
      phi_tot = phi_tot + this%A(ti,tj) *  this%A(ti,tj) * phi_ij(this, ti, tj, rij_mag)
    enddo
 
    sqrt_phi_tot = dsqrt(phi_tot)
 
    if (present(e)) then
       private_e =  private_e - sqrt_phi_tot
    endif
    if (present(local_e)) then
      local_e(i) = local_e(i) - sqrt_phi_tot 
    endif

    do ji=1, atoms_n_neighbours(at, i)
       j = atoms_neighbour(at, i, ji, rij_mag, cosines = drij)
       if (rij_mag .feq. 0.0_dp) cycle

       ti = get_type(this%type_of_atomic_num, at%Z(i))
       tj = get_type(this%type_of_atomic_num, at%Z(j))

      if (present(e) .or. present(local_e)) then
	 Ui  = 0.5_dp * Vij(this, ti, tj, rij_mag)
	if (present(local_e)) then
	  local_e(i) = local_e(i) + Ui 
	endif
	if (present(e)) then
	  private_e = private_e + Ui 
	endif
      endif

      if (present(f) .or. present(virial)) then

        dU = 0.5_dp * dVij(this, ti, tj, rij_mag) - this%A(ti,tj) * this%A(ti,tj) * dphi_ij(this, ti, tj, rij_mag) / 2.0_dp /  sqrt_phi_tot 
  
        if (present(f)) then
          private_f(:,i) = private_f(:,i) + dU * drij(:)
          private_f(:,j) = private_f(:,j) - dU * drij(:)
        endif
        if (present(virial)) then
            private_virial = private_virial - dU*(drij .outer. drij)*rij_mag
        endif
      endif

   end do
   
  end do

!$omp critical
  if(present(e)) e = e+private_e
  if(present(virial)) virial = virial+private_virial
  if(present(f)) f = f+private_f
!$omp end critical

!$omp end parallel

  if (present(e)) e = sum(this%mpi, e)
  if (present(local_e)) call sum_in_place(this%mpi, local_e)
  if (present(f)) call sum_in_place(this%mpi, f)
  if (present(virial)) call sum_in_place(this%mpi, virial) 

end subroutine IPModel_FS_Calc

function Vij(this, ti, tj, r)
  type(IPModel_FS), intent(in) :: this
  integer, intent(in) :: ti, tj
  real(dp), intent(in) :: r
  real(dp) :: Vij 

  if ((r .feq. 0.0_dp) .or. (r > this%c(ti,tj))) then
    Vij = 0.0
    return
  endif

  Vij = (r - this%c(ti,tj))*(r - this%c(ti,tj))*(this%c0(ti,tj) + r * this%c1(ti,tj) + r * r * this%c2(ti,tj) ) 

end function Vij 


function dVij(this, ti, tj, r)
  type(IPModel_FS), intent(in) :: this
  integer, intent(in) :: ti, tj
  real(dp), intent(in) :: r
  real(dp) :: dVij 

  if ((r .feq. 0.0_dp) .or. (r > this%c(ti,tj))) then
    dVij = 0.0
    return
  endif

  dVij =  2.0_dp * (r - this%c(ti,tj))*(this%c0(ti,tj) + r * this%c1(ti,tj) + r * r * this%c2(ti,tj)) + &
           (r - this%c(ti,tj))*(r - this%c(ti,tj))*(this%c1(ti,tj) + 2.0_dp * r * this%c2(ti,tj)) 
end function dVij 


function phi_ij(this, ti, tj, r)
  type(IPModel_FS), intent(in) :: this
  integer, intent(in) :: ti, tj
  real(dp), intent(in) :: r
  real(dp) :: num 
  real(dp) :: phi_ij

  if ((r .feq. 0.0_dp) .or. (r > this%d(ti,tj))) then
    phi_ij = 0.0
    return
  endif

  num = r  - this%d(ti,tj)
  phi_ij = num * num  +  this%beta(ti,tj) * (num * num * num) / this%d(ti,tj)

end function  phi_ij 

function dphi_ij(this, ti, tj, r)
  type(IPModel_FS), intent(in) :: this
  integer, intent(in) :: ti, tj
  real(dp), intent(in) :: r
  real(dp) :: num
  real(dp) :: dphi_ij

  if ((r .feq. 0.0_dp) .or. (r > this%d(ti,tj))) then
    dphi_ij = 0.0
    return
  endif

  num = r  - this%d(ti,tj)
  dphi_ij = 2.0_dp * num  + 3.0_dp * this%beta(ti,tj) * (num * num) / this%d(ti,tj)

end function  dphi_ij


!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X 
!X XML param reader functions
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

subroutine IPModel_startElement_handler(URI, localname, name, attributes)
  character(len=*), intent(in)   :: URI  
  character(len=*), intent(in)   :: localname
  character(len=*), intent(in)   :: name 
  type(dictionary_t), intent(in) :: attributes

  integer :: status
  character(len=1024) :: value

  integer ti, tj

  if (name == 'FS_params') then ! new FS stanza

    if (parse_matched_label) return ! we already found an exact match for this label

    call QUIP_FoX_get_value(attributes, 'label', value, status)
    if (status /= 0) value = ''

    if (len(trim(parse_ip%label)) > 0) then ! we were passed in a label
      if (value == parse_ip%label) then ! exact match
	parse_matched_label = .true.
	parse_in_ip = .true.
      else ! no match
	parse_in_ip = .false.
      endif
    else ! no label passed in
      parse_in_ip = .true.
    endif

    if (parse_in_ip) then
      if (parse_ip%n_types /= 0) then
	call finalise(parse_ip)
      endif

      call QUIP_FoX_get_value(attributes, 'n_types', value, status)
      if (status == 0) then
	read (value, *), parse_ip%n_types
      else
	call system_abort("Can't find n_types in FS_params")
      endif

      allocate(parse_ip%atomic_num(parse_ip%n_types))
      parse_ip%atomic_num = 0
      allocate(parse_ip%c(parse_ip%n_types,parse_ip%n_types))
      parse_ip%c = 0.0_dp
      allocate(parse_ip%c0(parse_ip%n_types,parse_ip%n_types))
      parse_ip%c0 = 0.0_dp
      allocate(parse_ip%c1(parse_ip%n_types,parse_ip%n_types))
      parse_ip%c1 = 0.0_dp
      allocate(parse_ip%c2(parse_ip%n_types,parse_ip%n_types))
      parse_ip%c2 = 0.0_dp
      allocate(parse_ip%A(parse_ip%n_types,parse_ip%n_types))
      parse_ip%A = 0.0_dp
      allocate(parse_ip%beta(parse_ip%n_types,parse_ip%n_types))
      parse_ip%beta = 0.0_dp
      allocate(parse_ip%d(parse_ip%n_types,parse_ip%n_types))
      parse_ip%d = 0.0_dp
    endif

  elseif (parse_in_ip .and. name == 'per_type_data') then

    call QUIP_FoX_get_value(attributes, "type", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find type")
    read (value, *) ti

    call QUIP_FoX_get_value(attributes, "atomic_num", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find atomic_num")
    read (value, *) parse_ip%atomic_num(ti)

    if (allocated(parse_ip%type_of_atomic_num)) deallocate(parse_ip%type_of_atomic_num)
    allocate(parse_ip%type_of_atomic_num(maxval(parse_ip%atomic_num)))
    parse_ip%type_of_atomic_num = 0
    do ti=1, parse_ip%n_types
      if (parse_ip%atomic_num(ti) > 0) &
        parse_ip%type_of_atomic_num(parse_ip%atomic_num(ti)) = ti
    end do

  elseif (parse_in_ip .and. name == 'per_pair_data') then

    call QUIP_FoX_get_value(attributes, "type1", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find type1")
    read (value, *) ti
    call QUIP_FoX_get_value(attributes, "type2", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find type2")
    read (value, *) tj

    call QUIP_FoX_get_value(attributes, "c", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find c")
    read (value, *) parse_ip%c(ti,tj)
    call QUIP_FoX_get_value(attributes, "c0", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find c0")
    read (value, *) parse_ip%c0(ti,tj)
    call QUIP_FoX_get_value(attributes, "c1", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find c1")
    read (value, *) parse_ip%c1(ti,tj)
    call QUIP_FoX_get_value(attributes, "c2", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find c2")
    read (value, *) parse_ip%c2(ti,tj)
    call QUIP_FoX_get_value(attributes, "A", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find A")
    read (value, *) parse_ip%A(ti,tj) 
    call QUIP_FoX_get_value(attributes, "beta", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find beta")
    read (value, *) parse_ip%beta(ti,tj) 
    call QUIP_FoX_get_value(attributes, "d", value, status)
    if (status /= 0) call system_abort ("IPModel_FS_read_params_xml cannot find d")
    read (value, *) parse_ip%d(ti,tj) 

    if (ti /= tj) then
      parse_ip%c(tj,ti) = parse_ip%c(ti,tj)
      parse_ip%c0(tj,ti) = parse_ip%c0(ti,tj)
      parse_ip%c1(tj,ti) = parse_ip%c1(ti,tj)
      parse_ip%c2(tj,ti) = parse_ip%c2(ti,tj)
      parse_ip%A(tj,ti) = parse_ip%A(ti,tj)
      parse_ip%beta(tj,ti) = parse_ip%beta(ti,tj)
      parse_ip%d(tj,ti) = parse_ip%d(ti,tj)
    end if

  endif

end subroutine IPModel_startElement_handler

subroutine IPModel_endElement_handler(URI, localname, name)
  character(len=*), intent(in)   :: URI  
  character(len=*), intent(in)   :: localname
  character(len=*), intent(in)   :: name 

  if (parse_in_ip) then
    if (name == 'FS_params') then
      parse_in_ip = .false.
    end if
  endif

end subroutine IPModel_endElement_handler

subroutine IPModel_FS_read_params_xml(this, param_str)
  type(IPModel_FS), intent(inout), target :: this
  character(len=*), intent(in) :: param_str

  type(xml_t) :: fxml

  if (len(trim(param_str)) <= 0) return

  parse_in_ip = .false.
  parse_matched_label = .false.
  parse_ip => this

  call open_xml_string(fxml, param_str)
  call parse(fxml,  &
    startElement_handler = IPModel_startElement_handler, &
    endElement_handler = IPModel_endElement_handler)
  call close_xml_t(fxml)

  if (this%n_types == 0) then
    call system_abort("IPModel_FS_read_params_xml parsed file, but n_types = 0")
  endif

end subroutine IPModel_FS_read_params_xml


!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X 
!X printing
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

subroutine IPModel_FS_Print (this, file)
  type(IPModel_FS), intent(in) :: this
  type(Inoutput), intent(inout),optional :: file

  integer :: ti, tj

  call Print("IPModel_FS : Finnis-Sinclair", file=file)
  call Print("IPModel_FS : n_types = " // this%n_types // " cutoff = " // this%cutoff, file=file)

  do ti=1, this%n_types
    call Print ("IPModel_FS : type " // ti // " atomic_num " // this%atomic_num(ti), file=file)
    call verbosity_push_decrement()
    do tj=1, this%n_types
      call Print ("IPModel_FS : interaction " // ti // " " // tj // " c, c0, c1, c2 " // this%c(ti,tj) // " " // &
        this%c0(ti,tj) // " " //  this%c1(ti,tj) // " " // this%c2(ti,tj) // " " // &
         " d " // this%d(ti,tj) // " " // &
	" A " // this%a(ti,tj) // "  " // " beta " // &
	this%beta(ti,tj), file=file)
    end do
    call verbosity_pop()
  end do

end subroutine IPModel_FS_Print

end module IPModel_FS_module
