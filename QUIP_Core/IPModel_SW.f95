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
!X IPModel_SW  module 
!X
!% Module for the Stillinger and Weber potential for silicon
!% (Ref. Phys. Rev. B {\bf 31},  5262, (1984)).
!% The IPModel_SW object contains all the parameters read 
!% from an 'SW_params' XML stanza.
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

module IPModel_SW_module

use libatoms_module

use mpi_context_module
use QUIP_Common_module

implicit none

private

include 'IPModel_interface.h'

public :: IPModel_SW
type IPModel_SW
  integer :: n_types = 0         !% Number of atomic types 
  integer, allocatable :: atomic_num(:), type_of_atomic_num(:)  !% Atomic number dimensioned as \texttt{n_types} 

  real(dp) :: cutoff = 0.0_dp

  real(dp), allocatable :: a(:,:), AA(:,:), BB(:,:), p(:,:), q(:,:), sigma(:,:), eps2(:,:) !% IP parameters
  real(dp), allocatable :: lambda(:,:,:), gamma(:,:,:), eps3(:,:,:) !% IP parameters

  character(len=FIELD_LENGTH) :: label
  type(mpi_context) :: mpi

end type IPModel_SW

logical :: parse_in_ip, parse_matched_label
type(IPModel_SW), pointer :: parse_ip

interface Initialise
  module procedure IPModel_SW_Initialise_str
end interface Initialise

interface Finalise
  module procedure IPModel_SW_Finalise
end interface Finalise

interface Print
  module procedure IPModel_SW_Print
end interface Print

interface Calc
  module procedure IPModel_SW_Calc
end interface Calc

contains

subroutine IPModel_SW_Initialise_str(this, args_str, param_str, mpi)
  type(IPModel_SW), intent(inout) :: this
  character(len=*), intent(in) :: args_str, param_str
  type(mpi_context), intent(in), optional :: mpi

  type(Dictionary) :: params

  call Finalise(this)

  call initialise(params)
  this%label=''
  call param_register(params, 'label', '', this%label)
  if (.not. param_read_line(params, args_str, ignore_unknown=.true.,task='IPModel_SW_Initialise_str args_str')) then
    call system_abort("IPModel_SW_Initialise_str failed to parse label from args_str="//trim(args_str))
  endif
  call finalise(params)

  if (present(mpi)) this%mpi = mpi

  call IPModel_SW_read_params_xml(this, param_str)

end subroutine IPModel_SW_Initialise_str

subroutine IPModel_SW_Finalise(this)
  type(IPModel_SW), intent(inout) :: this

  if (allocated(this%atomic_num)) deallocate(this%atomic_num)
  if (allocated(this%type_of_atomic_num)) deallocate(this%type_of_atomic_num)

  this%n_types = 0
  this%label = ''
end subroutine IPModel_SW_Finalise

!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X 
!% The potential calculator. It computes energy, forces and virial.
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

subroutine IPModel_SW_Calc(this, at, e, local_e, f, virial)
  type(IPModel_SW), intent(inout) :: this
  type(Atoms), intent(in) :: at
  real(dp), intent(out), optional :: e, local_e(:) !% \texttt{e} = System total energy, \texttt{local_e} = energy of each atom, vector dimensioned as \texttt{at%N}.  
  real(dp), intent(out), optional :: f(:,:)        !% Forces, dimensioned as \texttt{f(3,at%N)} 
  real(dp), intent(out), optional :: virial(3,3)   !% Virial

  real(dp), pointer :: w_e(:)
  integer i, ji, j, ki, k
  real(dp) :: drij(3), drij_mag, drik(3), drik_mag, drij_dot_drik
  real(dp) :: w_f

  integer ti, tj, tk

  real(dp) :: drij_dri(3), drij_drj(3), drik_dri(3), drik_drk(3)
  real(dp) :: dcos_ijk_dri(3), dcos_ijk_drj(3), dcos_ijk_drk(3)

  real(dp) :: de, de_dr, de_drij, de_drik, de_dcos_ijk
  real(dp) :: cur_cutoff

  integer :: n_neigh_i

#ifdef OPENMP
  real(dp) :: private_virial(3,3), private_e
  real(dp), allocatable :: private_f(:,:), private_local_e(:)
#endif

  call print("IPModel_SW_Calc starting ", ANAL)
  if (present(e)) e = 0.0_dp
  if (present(local_e)) local_e = 0.0_dp
  if (present(f)) f = 0.0_dp
  if (present(virial)) virial = 0.0_dp

  if (.not.assign_pointer(at,"weight", w_e)) nullify(w_e)

#ifdef OPENMP
!$omp parallel private(i, ji, j, ki, k, drij, drij_mag, drik, drik_mag, drij_dot_drik, w_f, ti, tj, tk, drij_dri, drij_drj, drik_dri, drik_drk, dcos_ijk_dri, dcos_ijk_drj, dcos_ijk_drk, de, de_dr, de_drij, de_drik, de_dcos_ijk, cur_cutoff, private_virial, private_e, private_f, private_local_e, n_neigh_i)

  if (present(e)) private_e = 0.0_dp
  if (present(local_e)) then
    allocate(private_local_e(at%N))
    private_local_e = 0.0_dp
  endif
  if (present(f)) then
    allocate(private_f(3,at%N))
    private_f = 0.0_dp
  endif
  if (present(virial)) private_virial = 0.0_dp

!$omp do
#endif
  do i=1, at%N
    if (this%mpi%active) then
      if (mod(i-1, this%mpi%n_procs) /= this%mpi%my_proc) cycle
    endif
    ti = get_type(this%type_of_atomic_num, at%Z(i))
    if (current_verbosity() >= ANAL) call print ("IPModel_SW_Calc i " // i // " " // atoms_n_neighbours(at,i), ANAL)
    cur_cutoff = maxval(this%a(ti,:)*this%sigma(ti,:))
    n_neigh_i = atoms_n_neighbours(at, i)
    do ji=1, n_neigh_i
      j = atoms_neighbour(at, i, ji, drij_mag, cosines = drij, max_dist = cur_cutoff)
      if (j <= 0) cycle
      if (drij_mag .feq. 0.0_dp) cycle

      tj = get_type(this%type_of_atomic_num, at%Z(j))

      if (drij_mag/this%sigma(ti,tj) > this%a(ti,tj)) cycle

      if (current_verbosity() >= ANAL) call print ("IPModel_SW_Calc i j " // i // " " // j, ANAL)

      if (associated(w_e)) then
	w_f = 0.5_dp*(w_e(i)+w_e(j))
      else
	w_f = 1.0_dp
      endif

      if (present(e) .or. present(local_e)) then
	! factor of 0.5 because SW definition goes over each pair only once
	de = 0.5_dp*this%eps2(ti,tj)*f2(this, drij_mag, ti, tj)
	if (present(local_e)) then
#ifdef OPENMP
	  private_local_e(i) = private_local_e(i) + 0.5_dp*de
	  private_local_e(j) = private_local_e(j) + 0.5_dp*de
#else
	  local_e(i) = local_e(i) + 0.5_dp*de
	  local_e(j) = local_e(j) + 0.5_dp*de
#endif
	endif
	if (present(e)) then
#ifdef OPENMP
	  private_e = private_e + de*w_f
#else
	  e = e + de*w_f
#endif
	endif
      endif

      if (present(f) .or. present(virial)) then
	de_dr = 0.5_dp*this%eps2(ti,tj)*df2_dr(this, drij_mag, ti, tj)
	if (present(f)) then
#ifdef OPENMP
	  private_f(:,i) = private_f(:,i) + de_dr*w_f*drij
	  private_f(:,j) = private_f(:,j) - de_dr*w_f*drij
#else
	  f(:,i) = f(:,i) + de_dr*w_f*drij
	  f(:,j) = f(:,j) - de_dr*w_f*drij
#endif
	endif
	if (present(virial)) then
#ifdef OPENMP
	  private_virial = private_virial - de_dr*w_f*(drij .outer. drij)*drij_mag
#else
	  virial = virial - de_dr*w_f*(drij .outer. drij)*drij_mag
#endif
	endif
      endif

      if (associated(w_e)) then
	w_f = w_e(i)
      else
	w_f = 1.0_dp
      endif

      do ki=1, n_neigh_i
	if (ki <= ji) cycle
	k = atoms_neighbour(at, i, ki, drik_mag, cosines = drik, max_dist=cur_cutoff)
	if (k <= 0) cycle
	if (drik_mag .feq. 0.0_dp) cycle

	tk = get_type(this%type_of_atomic_num, at%Z(k))

        if (drik_mag/this%sigma(ti,tk) > this%a(ti,tk)) cycle

	drij_dot_drik = sum(drij*drik)
	if (present(e) .or. present(local_e)) then
	  de = this%eps3(ti,tj,tk)*f3(this, drij_mag, drik_mag, drij_dot_drik, ti, tj, tk)
	  if (present(local_e)) then
#ifdef OPENMP
	    private_local_e(i) = private_local_e(i) + de
#else
	    local_e(i) = local_e(i) + de
#endif
	  endif
	  if (present(e)) then
#ifdef OPENMP
	    private_e = private_e + de*w_f
#else
	    e = e + de*w_f
#endif
	  endif
	endif
	if (present(f) .or. present(virial)) then
	  call df3_dr(this, drij_mag, drik_mag, drij_dot_drik, ti, tj, tk, de_drij, de_drik, de_dcos_ijk)
	  drij_dri = drij
	  drij_drj = -drij
	  drik_dri = drik
	  drik_drk = -drik

! dcos_ijk = drij_dot_drik
! (ri_x - rj_x)*(ri_x - rk_x) + (ri_y - rj_y)*(ri_y-rk_y) / (rij rik)
!
! d/dri
! 
! ((rij rik)(rij_x + rik_x) - (rij . rik)(rij rik_x / rik + rik rij_x/rij)) / (rij rik)^2
! 
! rij rik ( rij_x + rik_x) -  (rij.rik)(rij rik_x / rik + rik rij_x/rij)
! ---------------------------------------------------------------------
!                       rij^2 rik^2
!                       
! rij_x + rik_x     cos_ijk (rij rik_x / rik + rik rij_x /rij)
! -------------  - ------------------------------------------
! rij rik                    rij rik
! 
! rij_x + rik_x
! ------------- - cos_ijk (rik_x / rik^2 + rij_x / rij^2)
!    rij rik
!    
!    
! rhatij_x/rik + rhatik_x/rij - cos_ijk(rhatik_x/rik + rhatij_x/rij)
! 
! 
! d/drj
! 
! ((rij rik)(-rik_x) - (rij.rik)(rik (-rij_x)/rij)) / (rij rik)^2
! 
!  -rik_x     (rij.rik) ( rik rij_x/rij)
! -------  + ---------------------------
! rij rik           rij^2 rik^2
! 
! -rhatik_x/rij + cos_ijk rhatij_x/rij
!
! d/drij
!
! (ri_x - rj_x)*(ri_x - rk_x) + (ri_y - rj_y)*(ri_y-rk_y) / (rij rik)
!
! (rij rik) rik_x - (rij . rik) (rij_x/rij rik)
! ---------------------------------------------
!                    (rij rik)^2
!
! rik_x      (rij.rik) rij_x 
! ------   - ---------------
! rij rik    rij^3 rik
!
! rhatik_x      (rhatij . rhatik) rhatij_x
! --------   -  ------------------------
! rij           rij
!
! rhatik_x      cos_ijk * rhatij_x
! --------   -  ------------------
!   rij                 rij

	  dcos_ijk_dri = drij/drik_mag + drik/drij_mag - drij_dot_drik * (drik/drik_mag + drij/drij_mag)
	  dcos_ijk_drj = -drik/drij_mag + drij_dot_drik * drij/drij_mag
	  dcos_ijk_drk = -drij/drik_mag + drij_dot_drik * drik/drik_mag

	  if (present(f)) then
#ifdef OPENMP
	    private_f(:,i) = private_f(:,i) + w_f*this%eps3(ti,tj,tk)*(de_drij*drij_dri(:) + de_drik*drik_dri(:) + &
						       de_dcos_ijk * dcos_ijk_dri(:))
	    private_f(:,j) = private_f(:,j) + w_f*this%eps3(ti,tj,tk)*(de_drij*drij_drj(:) + de_dcos_ijk*dcos_ijk_drj(:))
	    private_f(:,k) = private_f(:,k) + w_f*this%eps3(ti,tj,tk)*(de_drik*drik_drk(:) + de_dcos_ijk*dcos_ijk_drk(:)) 
#else
	    f(:,i) = f(:,i) + w_f*this%eps3(ti,tj,tk)*(de_drij*drij_dri(:) + de_drik*drik_dri(:) + &
						       de_dcos_ijk * dcos_ijk_dri(:))
	    f(:,j) = f(:,j) + w_f*this%eps3(ti,tj,tk)*(de_drij*drij_drj(:) + de_dcos_ijk*dcos_ijk_drj(:))
	    f(:,k) = f(:,k) + w_f*this%eps3(ti,tj,tk)*(de_drik*drik_drk(:) + de_dcos_ijk*dcos_ijk_drk(:)) 
#endif
	  end if
	  if (present(virial)) then
#ifdef OPENMP
	    private_virial = private_virial - w_f*this%eps3(ti,tj,tk)*( &
	      de_drij*(drij .outer. drij)*drij_mag + de_drik*(drik .outer. drik)*drik_mag + &
	      de_dcos_ijk * ((drik .outer. drij) - drij_dot_drik * (drij .outer. drij)) + &
	      de_dcos_ijk * ((drij .outer. drik) - drij_dot_drik * (drik .outer. drik)) )
#else
	    virial = virial - w_f*this%eps3(ti,tj,tk)*( &
	      de_drij*(drij .outer. drij)*drij_mag + de_drik*(drik .outer. drik)*drik_mag + &
	      de_dcos_ijk * ((drik .outer. drij) - drij_dot_drik * (drij .outer. drij)) + &
	      de_dcos_ijk * ((drij .outer. drik) - drij_dot_drik * (drik .outer. drik)) )
#endif
	  end if
	endif

      end do ! ki

    end do
  end do

#ifdef OPENMP
!$omp critical
  if (present(e)) e = e + private_e
  if (present(f)) f = f + private_f
  if (present(local_e)) local_e = local_e + private_local_e
  if (present(virial)) virial = virial + private_virial
!$omp end critical 

!$omp end parallel
#endif

  if (present(e)) e = sum(this%mpi, e) 
  if (present(local_e)) call sum_in_place(this%mpi, local_e)
  if (present(f)) call sum_in_place(this%mpi, f)
  if (present(virial)) call sum_in_place(this%mpi, virial)

end subroutine IPModel_SW_Calc

function f3(this, rij_i, rik_i, cos_ijk, ti, tj, tk)
  type(IPModel_SW), intent(in) :: this
  real(dp), intent(in) :: rij_i, rik_i, cos_ijk
  integer, intent(in) :: ti, tj, tk
  real(dp) :: f3

  real(dp) :: rij, rik
  real(dp), parameter :: one_third = 1.0_dp/3.0_dp

  rij = rij_i/this%sigma(ti,tj)
  rik = rik_i/this%sigma(ti,tk)

  if (rij >= this%a(ti,tj) .or. rik >= this%a(ti,tk)) then
    f3 = 0.0_dp
    return
  endif

  f3 = this%lambda(ti,tj,tk)*exp( this%gamma(ti,tj,tk)/(rij-this%a(ti,tj)) + this%gamma(ti,tj,tk)/(rik-this%a(ti,tk)) )* &
    (cos_ijk + one_third)**2

end function f3

subroutine df3_dr(this, rij_i, rik_i, cos_ijk, ti, tj, tk, de_drij, de_drik, de_dcos_ijk)
  type(IPModel_SW), intent(in) :: this
  real(dp), intent(in) :: rij_i, rik_i, cos_ijk
  integer, intent(in) :: ti, tj, tk
  real(dp), intent(out) :: de_drij, de_drik, de_dcos_ijk

  real(dp) :: rij, rik, r_scale_ij, r_scale_ik
  real(dp) :: expf, cosf

  real(dp), parameter :: one_third = 1.0_dp/3.0_dp

  rij = rij_i/this%sigma(ti,tj)
  rik = rik_i/this%sigma(ti,tk)

  if (rij >= this%a(ti,tj) .or. rik >= this%a(ti,tk)) then
    de_drij = 0.0_dp
    de_drik = 0.0_dp
    de_dcos_ijk = 0.0_dp
    return
  endif

  r_scale_ij = 1.0_dp/this%sigma(ti,tj)
  r_scale_ik = 1.0_dp/this%sigma(ti,tk)

  expf = this%lambda(ti,tj,tk)*exp(this%gamma(ti,tj,tk)/(rij - this%a(ti,tj)) + this%gamma(ti,tj,tk)/(rik - this%a(ti,tk)))
  cosf = (cos_ijk + one_third)

  de_drij = -expf * this%gamma(ti,tj,tk)/(rij-this%a(ti,tj))**2 * cosf**2 * r_scale_ij
  de_drik = -expf * this%gamma(ti,tj,tk)/(rik-this%a(ti,tk))**2 * cosf**2 * r_scale_ik
  de_dcos_ijk = expf * 2.0_dp * cosf

end subroutine df3_dr


function f2(this, ri, ti, tj)
  type(IPModel_SW), intent(in) :: this
  real(dp), intent(in) :: ri
  integer, intent(in) :: ti, tj
  real(dp) :: f2

  real(dp) r

  r = ri/this%sigma(ti,tj)

  if (r >= this%a(ti,tj)) then
    f2 = 0.0_dp
    return
  endif

  f2 = this%AA(ti,tj)*(this%BB(ti,tj) * r**(-this%p(ti,tj)) - r**(-this%q(ti,tj))) * exp(1.0_dp/(r-this%a(ti,tj)))

end function f2

function df2_dr(this, ri, ti, tj)
  type(IPModel_SW), intent(in) :: this
  real(dp), intent(in) :: ri
  integer, intent(in) :: ti, tj
  real(dp) :: df2_dr

  real(dp) r, dr_dri
  real(dp) :: expf, dexpf_dr, powf, dpowf_dr

  r = ri/this%sigma(ti,tj)

  if (r >= this%a(ti,tj)) then
    df2_dr = 0.0_dp
    return
  endif

  dr_dri = 1.0_dp/this%sigma(ti,tj)

  expf = exp(1.0_dp/(r-this%a(ti,tj)))
  dexpf_dr = -expf/(r-this%a(ti,tj))**2

  powf = this%BB(ti,tj)*(r**(-this%p(ti,tj))) - r**(-this%q(ti,tj))
  dpowf_dr = -this%p(ti,tj)*this%BB(ti,tj)*(r**(-this%p(ti,tj)-1)) + this%q(ti,tj)*r**(-this%q(ti,tj)-1)

  df2_dr = this%AA(ti,tj)*(powf*dexpf_dr + dpowf_dr*expf)*dr_dri

end function df2_dr

!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X 
!% XML param reader functions.
!% An example for the input file.
!% First the general parameters and pair terms:
!%> <SW_params n_types="2" label="PRB_31_plus_H">
!%> <per_type_data type="1" atomic_num="1" />
!%> <per_type_data type="2" atomic_num="14" />
!%> <per_pair_data atnum_i="1" atnum_j="1" AA="0.0" BB="0.0"
!%>       p="0" q="0" a="5.0" sigma="1.0" eps="0.0" />
!%> <per_pair_data atnum_i="1" atnum_j="14" AA="8.581214" BB="0.0327827"
!%>       p="4" q="0" a="1.25" sigma="2.537884" eps="2.1672" />
!%> <per_pair_data atnum_i="14" atnum_j="14" AA="7.049556277" BB="0.6022245584"
!%>       p="4" q="0" a="1.80" sigma="2.0951" eps="2.1675" />
!% Now the triplet terms: atnum_c is the center atom, neighbours j and k
!%> <per_triplet_data atnum_c="1"  atnum_j="1"  atnum_k="1"
!%>       lambda="21.0" gamma="1.20" eps="2.1675" />
!%> <per_triplet_data atnum_c="1"  atnum_j="1"  atnum_k="14"
!%>       lambda="21.0" gamma="1.20" eps="2.1675" />
!%> <per_triplet_data atnum_c="1"  atnum_j="14" atnum_k="14"
!%>       lambda="21.0" gamma="1.20" eps="2.1675" />
!%> 
!%> <per_triplet_data atnum_c="14" atnum_j="1"  atnum_k="1"
!%>       lambda="21.0" gamma="1.20" eps="2.1675" />
!%> <per_triplet_data atnum_c="14" atnum_j="1"  atnum_k="14"
!%>       lambda="21.0" gamma="1.20" eps="2.1675" />
!%> <per_triplet_data atnum_c="14" atnum_j="14" atnum_k="14"
!%>       lambda="21.0" gamma="1.20" eps="2.1675" />
!%> </SW_params>
!% 
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

subroutine IPModel_startElement_handler(URI, localname, name, attributes)
  character(len=*), intent(in)   :: URI  
  character(len=*), intent(in)   :: localname
  character(len=*), intent(in)   :: name 
  type(dictionary_t), intent(in) :: attributes

  integer status
  character(len=1024) :: value
  integer ti, tj, tk, Zi, Zj, Zk

  if (name == 'SW_params') then ! new SW stanza
    call print("startElement_handler SW_params", NERD)
    if (parse_in_ip) &
      call system_abort("IPModel_startElement_handler entered SW_params with parse_in true. Probably a bug in FoX (4.0.1, e.g.)")

    if (parse_matched_label) then 
       call print("SW_params startElement_handler bailing because we already matched our label", NERD)
       return ! we already found an exact match for this label
    end if

    call QUIP_FoX_get_value(attributes, 'label', value, status)
    if (status /= 0) value = ''

    call print("SW_params startElement_handler found xml label '"//trim(value)//"'", NERD)

    if (len(trim(parse_ip%label)) > 0) then ! we were passed in a label
      call print("SW_params startElement_handler was passed in label '"//trim(parse_ip%label)//"'", NERD)
      if (value == parse_ip%label) then ! exact match
        parse_matched_label = .true.
        parse_in_ip = .true.
      else ! no match
	call print("SW_params startElement_handler got label didn't match", NERD)
        parse_in_ip = .false.
      endif
    else ! no label passed in
      call print("SW_params startElement_handler was not passed in a label", NERD)
      parse_in_ip = .true.
    endif

    if (parse_in_ip) then
      if (parse_ip%n_types /= 0) then
	call print("SW_params startElement_handler finalising old data, restarting to parse new section", NERD)
        call finalise(parse_ip)
      endif

      call QUIP_FoX_get_value(attributes, "n_types", value, status)
      if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find n_types")
      read (value, *) parse_ip%n_types

      allocate(parse_ip%atomic_num(parse_ip%n_types))
      parse_ip%atomic_num = 0
      allocate(parse_ip%a(parse_ip%n_types,parse_ip%n_types))
      parse_ip%a = 0.0_dp
      allocate(parse_ip%AA(parse_ip%n_types,parse_ip%n_types))
      allocate(parse_ip%BB(parse_ip%n_types,parse_ip%n_types))
      allocate(parse_ip%p(parse_ip%n_types,parse_ip%n_types))
      allocate(parse_ip%q(parse_ip%n_types,parse_ip%n_types))
      allocate(parse_ip%sigma(parse_ip%n_types,parse_ip%n_types))
      parse_ip%sigma = 0.0_dp
      allocate(parse_ip%eps2(parse_ip%n_types,parse_ip%n_types))

      allocate(parse_ip%lambda(parse_ip%n_types,parse_ip%n_types,parse_ip%n_types))
      allocate(parse_ip%gamma(parse_ip%n_types,parse_ip%n_types,parse_ip%n_types))
      allocate(parse_ip%eps3(parse_ip%n_types,parse_ip%n_types,parse_ip%n_types))
    endif

  elseif (parse_in_ip .and. name == 'per_type_data') then

    call QUIP_FoX_get_value(attributes, "type", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find type")
    read (value, *) ti

    call QUIP_FoX_get_value(attributes, "atomic_num", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find atomic_num")
    read (value, *) parse_ip%atomic_num(ti)

    if (allocated(parse_ip%type_of_atomic_num)) deallocate(parse_ip%type_of_atomic_num)
    allocate(parse_ip%type_of_atomic_num(maxval(parse_ip%atomic_num)))
    parse_ip%type_of_atomic_num = 0
    do ti=1, parse_ip%n_types
      if (parse_ip%atomic_num(ti) > 0) &
        parse_ip%type_of_atomic_num(parse_ip%atomic_num(ti)) = ti
    end do

  elseif (parse_in_ip .and. name == 'per_pair_data') then

    call QUIP_FoX_get_value(attributes, "atnum_i", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find atnum_i")
    read (value, *) Zi
    call QUIP_FoX_get_value(attributes, "atnum_j", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find atnum_j")
    read (value, *) Zj

    ti = get_type(parse_ip%type_of_atomic_num,Zi)
    tj = get_type(parse_ip%type_of_atomic_num,Zj)

    call QUIP_FoX_get_value(attributes, "AA", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find AA")
    read (value, *) parse_ip%AA(ti,tj)
    call QUIP_FoX_get_value(attributes, "BB", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find BB")
    read (value, *) parse_ip%BB(ti,tj)
    call QUIP_FoX_get_value(attributes, "p", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find p")
    read (value, *) parse_ip%p(ti,tj)
    call QUIP_FoX_get_value(attributes, "q", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find q")
    read (value, *) parse_ip%q(ti,tj)
    call QUIP_FoX_get_value(attributes, "a", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find a")
    read (value, *) parse_ip%a(ti,tj)
    call QUIP_FoX_get_value(attributes, "sigma", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find sigma")
    read (value, *) parse_ip%sigma(ti,tj)
    call QUIP_FoX_get_value(attributes, "eps", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find eps")
    read (value, *) parse_ip%eps2(ti,tj)

    if (ti /= tj) then
      parse_ip%AA(tj,ti) = parse_ip%AA(ti,tj)
      parse_ip%BB(tj,ti) = parse_ip%BB(ti,tj)
      parse_ip%p(tj,ti) = parse_ip%p(ti,tj)
      parse_ip%q(tj,ti) = parse_ip%q(ti,tj)
      parse_ip%a(tj,ti) = parse_ip%a(ti,tj)
      parse_ip%sigma(tj,ti) = parse_ip%sigma(ti,tj)
      parse_ip%eps2(tj,ti) = parse_ip%eps2(ti,tj)
    endif

    parse_ip%cutoff = maxval(parse_ip%a*parse_ip%sigma)

  elseif (parse_in_ip .and. name == 'per_triplet_data') then

    call QUIP_FoX_get_value(attributes, "atnum_c", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find atnum_c")
    read (value, *) Zi
    call QUIP_FoX_get_value(attributes, "atnum_j", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find atnum_j")
    read (value, *) Zj
    call QUIP_FoX_get_value(attributes, "atnum_k", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find atnum_k")
    read (value, *) Zk

    ti = get_type(parse_ip%type_of_atomic_num,Zi)
    tj = get_type(parse_ip%type_of_atomic_num,Zj)
    tk = get_type(parse_ip%type_of_atomic_num,Zk)

    call QUIP_FoX_get_value(attributes, "lambda", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find lambda")
    read (value, *) parse_ip%lambda(ti,tj,tk)
    call QUIP_FoX_get_value(attributes, "gamma", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find gamma")
    read (value, *) parse_ip%gamma(ti,tj,tk)
    call QUIP_FoX_get_value(attributes, "eps", value, status)
    if (status /= 0) call system_abort ("IPModel_SW_read_params_xml cannot find eps")
    read (value, *) parse_ip%eps3(ti,tj,tk)

    if (tj /= tk) then
      parse_ip%lambda(ti,tk,tj) = parse_ip%lambda(ti,tj,tk)
      parse_ip%gamma(ti,tk,tj) = parse_ip%gamma(ti,tj,tk)
      parse_ip%eps3(ti,tk,tj) = parse_ip%eps3(ti,tj,tk)
    endif
  endif

end subroutine IPModel_startElement_handler

subroutine IPModel_endElement_handler(URI, localname, name)
  character(len=*), intent(in)   :: URI  
  character(len=*), intent(in)   :: localname
  character(len=*), intent(in)   :: name 

  if (parse_in_ip) then
    if (name == 'SW_params') then
      call print("endElement_handler SW_params", NERD)
      parse_in_ip = .false.
    endif
  endif

end subroutine IPModel_endElement_handler

subroutine IPModel_SW_read_params_xml(this, param_str)
  type(IPModel_SW), intent(inout), target :: this
  character(len=*) :: param_str

  type (xml_t) :: fxml

  if (len(trim(param_str)) <= 0) return

  parse_ip => this
  parse_in_ip = .false.
  parse_matched_label = .false.

  call open_xml_string(fxml, param_str)

  call parse(fxml, &
    startElement_handler = IPModel_startElement_handler, &
    endElement_handler = IPModel_endElement_handler)

  call close_xml_t(fxml)

  if (this%n_types == 0) then
    call system_abort("IPModel_SW_read_params_xml parsed file, but n_types = 0")
  endif

end subroutine


!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X 
!X printing
!% Printing of SW parameters: number of different types, cutoff radius, atomic numbers, ect.
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


subroutine IPModel_SW_Print (this, file)
  type(IPModel_SW), intent(in) :: this
  type(Inoutput), intent(inout),optional :: file

  integer ti, tj, tk

  call Print("IPModel_SW : Stillinger-Weber", file=file)
  call Print("IPModel_SW : n_types = " // this%n_types // " cutoff = " // this%cutoff, file=file)

  do ti=1, this%n_types
    call Print ("IPModel_SW : type "// ti // " atomic_num " // this%atomic_num(ti), file=file)
    call verbosity_push_decrement()
    do tj=1, this%n_types
      call Print ("IPModel_SW : pair interaction ti tj " // ti // " " // tj // " Zi Zj " // this%atomic_num(ti) // &
	" " // this%atomic_num(tj), file=file)
      call Print ("IPModel_SW : pair " // this%AA(ti,tj) // " " // this%BB(ti,tj) // " " // this%p(ti,tj) // " " // &
	this%q(ti,tj) // " " // this%a(ti,tj), file=file)
      call Print ("IPModel_SW :      " // this%sigma(ti,tj) // " " // this%eps2(ti,tj), file=file)
      do tk=1, this%n_types
	call Print ("IPModel_SW : triplet interaction ti tj " // ti // " " // tj // " " // tk // &
	  " Zi Zj Zk " // this%atomic_num(ti) // " " // this%atomic_num(tj) // " " // this%atomic_num(tk), file=file)
	call Print ("IPModel_SW : triplet " // this%lambda(ti,tj,tk) // " " // this%gamma(ti,tj,tk) // " " // &
	  this%eps3(ti,tj,tk), file=file)
      end do
    end do
    call verbosity_pop()
  end do

end subroutine IPModel_SW_Print

end module IPModel_SW_module
