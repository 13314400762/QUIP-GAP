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

! IR intensities from K. Jackson, M. R. Pederson, and D. Porezag,
! Z. Hajnal, and T. Frauenheim, Phys. Rev. B v. 55, 2549 (1997).
module phonons_module
use libatoms_module
use quip_module
use libatoms_misc_utils_module
implicit none
private

public phonons, phonons_fine, eval_frozen_phonon

contains

function eval_frozen_phonon(metapot, at, dx, evec, calc_args)
  type(MetaPotential), intent(inout) :: metapot
  type(Atoms), intent(inout) :: at
  real(dp), intent(in) :: dx
  real(dp), intent(in) :: evec(:)
  character(len=*), intent(in), optional :: calc_args
  real(dp) :: eval_frozen_phonon ! result

  real(dp) :: Ep, E0, Em
  real(dp), allocatable :: pos0(:,:), dpos(:,:)

  allocate(pos0(3,at%N))
  allocate(dpos(3,at%N))

  pos0 = at%pos

  dpos = reshape(evec, (/ 3, at%N /) )
  dpos = dpos / sqrt(sum(dpos**2))

  call calc_dists(at)
  call calc(metapot, at, E=E0, args_str=calc_args)
  mainlog%prefix="FROZ_E0"
  call print_xyz(at, mainlog, real_format='f14.10', properties="pos:phonon")
  mainlog%prefix=""

  at%pos = pos0 + dx*dpos

  call calc_dists(at)
  call calc(metapot, at, E=Ep, args_str=calc_args)
  mainlog%prefix="FROZ_EP"
  call print_xyz(at, mainlog, real_format='f14.10', properties="pos:phonon")
  mainlog%prefix=""

  at%pos = pos0 - dx*dpos

  call calc_dists(at)
  call calc(metapot, at, E=Em, args_str=calc_args)
  mainlog%prefix="FROZ_EM"
  call print_xyz(at, mainlog, real_format='f14.10', properties="pos:phonon")
  mainlog%prefix=""

  call print("Em " // Em // " E0 " // E0 // " Ep " // Ep, VERBOSE)

  eval_frozen_phonon = ((Ep-E0)/dx - (E0-Em)/dx)/dx

  at%pos = pos0
  call calc_dists(at)

  deallocate(dpos)
  deallocate(pos0)

end function eval_frozen_phonon

subroutine phonons(metapot, at, dx, evals, evecs, effective_masses, calc_args, IR_intensities, do_parallel, &
		   zero_translation, zero_rotation, force_const_mat)
  type(MetaPotential), intent(inout) :: metapot
  type(Atoms), intent(inout) :: at
  real(dp), intent(in) :: dx
  real(dp), intent(out) :: evals(at%N*3)
  real(dp), intent(out), optional :: evecs(at%N*3,at%N*3)
  real(dp), intent(out), optional :: effective_masses(at%N*3)
  character(len=*), intent(in), optional :: calc_args
  real(dp), intent(out), optional :: IR_intensities(:)
  logical, intent(in), optional :: do_parallel
  logical, intent(in), optional :: zero_translation, zero_rotation
  real(dp), intent(out), optional :: force_const_mat(:,:)

  integer i, j, alpha, beta
  integer err
  real(dp), allocatable :: pos0(:,:), fp(:,:), fm(:,:)
  real(dp), allocatable :: dm(:,:)

  logical :: override_zero_freq_phonons = .true.
  real(dp) :: phonon_norm, CoM(3), axis(3), dr_proj(3)
  real(dp), allocatable :: zero_overlap_inv(:,:)
  real(dp), allocatable :: phonon(:,:), zero_phonon(:,:), zero_phonon_p(:,:), P(:,:), dm_t(:,:)
  real(dp) :: mu_m(3), mu_p(3), dmu_dq(3)
  real(dp), allocatable :: dmu_dr(:,:,:)
  real(dp), pointer :: local_dn(:), mass(:)

  integer :: n_zero
  logical :: do_zero_translation, do_zero_rotation

  integer :: ind
  logical :: my_do_parallel
  type(MPI_context) :: mpi_glob

  my_do_parallel = optional_default(.false., do_parallel)

  if (my_do_parallel) then
    call initialise(mpi_glob)
  endif

  do_zero_translation = optional_default(zero_translation, .true.)
  do_zero_rotation = optional_default(zero_rotation, .false.)

  allocate(pos0(3,at%N))
  allocate(fp(3,at%N))
  allocate(fm(3,at%N))
  allocate(dm(at%N*3,at%N*3))
  allocate(dmu_dr(3, at%N, 3))

  if (present(force_const_mat)) then
    if (size(force_const_mat,1) /= size(dm,1) .or. size(force_const_mat,2) /= size(dm,2)) &
      call system_abort("phonons received force_const_mat, shape="//shape(force_const_mat) // &
			" which doesn't match shape(dm)="//shape(dm))
  endif

  if (present(IR_intensities)) then
    if (.not. assign_pointer(at, 'local_dn', local_dn)) then
      call add_property(at, 'local_dn', 0.0_dp, 1)
    endif
  endif

  if (dx == 0.0_dp) &
    call system_abort("phonons called with dx == 0.0")

  if (my_do_parallel) then
    dm = 0.0_dp
    dmu_dr = 0.0_dp
  endif

  call set_cutoff(at, cutoff(metapot))
  call calc_connect(at)
  
  pos0 = at%pos

  ! calculate dynamical matrix with finite differences
  ind = -1
  do i=1, at%N
    do alpha=1,3
      ind = ind + 1
      if (my_do_parallel) then
	if (mod(ind, mpi_glob%n_procs) /= mpi_glob%my_proc) cycle
      endif

      at%pos = pos0
      at%pos(alpha,i) = at%pos(alpha,i) + dx
      call calc_dists(at)
      call calc(metapot, at, f=fp, args_str=calc_args)
      if (present(IR_intensities)) then
	if (.not. assign_pointer(at, 'local_dn', local_dn)) &
	  call system_abort("phonons impossible failure to assign pointer for local_dn")
	mu_p = dipole_moment(at%pos, local_dn)
      endif

      at%pos = pos0
      at%pos(alpha,i) = at%pos(alpha,i) - dx
      call calc_dists(at)
      call calc(metapot, at, f=fm, args_str=calc_args)
      if (present(IR_intensities)) then
	if (.not. assign_pointer(at, 'local_dn', local_dn)) &
	  call system_abort("phonons impossible failure to assign pointer for local_dn")
	mu_m = dipole_moment(at%pos, local_dn)
      endif

      dmu_dr(alpha, i, :) = (mu_p-mu_m)/(2.0_dp*dx)

      do j=1, at%N
	do beta=1,3
	  dm((i-1)*3+alpha,(j-1)*3+beta) = -((fp(beta,j)-fm(beta,j))/(2.0_dp*dx))
	end do
      end do

    end do
  end do

  at%pos = pos0
  call calc_dists(at)

  if (my_do_parallel) then
    call sum_in_place(mpi_glob, dm)
    call sum_in_place(mpi_glob, dmu_dr)
  endif

  if (.not. assign_pointer(at, 'mass', mass)) &
    call add_property(at, 'mass', 0.0_dp, 1)
  if (.not. assign_pointer(at, 'mass', mass)) &
    call system_abort("impossible failure to assign pointer for mass")
  do i=1, at%N
    mass(i) = ElementMass(at%Z(i))
  end do

  if (present(force_const_mat)) then
    force_const_mat = dm
  endif

  ! transform from generalized eigenproblem to regular eigenproblem
  do i=1, at%N
    do j=1, at%N
      dm((i-1)*3+1:(i-1)*3+3,(j-1)*3+1:(j-1)*3+3) = dm((i-1)*3+1:(i-1)*3+3,(j-1)*3+1:(j-1)*3+3) / &
					sqrt(ElementMass(at%Z(i))*ElementMass(at%Z(j)))
    end do
  end do

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  n_zero = 0
  if (do_zero_translation) n_zero = n_zero + 3
  if (do_zero_rotation) n_zero = n_zero + 3

  if (n_zero > 0) then

    allocate(zero_phonon(at%N*3,n_zero))
    allocate(zero_phonon_p(at%N*3,n_zero))
    allocate(phonon(3,at%N))
    do i=1, n_zero
      if (do_zero_translation .and. i <= 3) then ! translation
	beta = i
	phonon = 0.0_dp
	phonon(beta,:) = 1.0_dp
      else ! rotation
	beta = i-3
	CoM = centre_of_mass(at)
	axis = 0.0_dp; axis(beta) = 1.0_dp
	do j=1, at%N
	  dr_proj = at%pos(:,j)-CoM
	  dr_proj(beta) = 0.0_dp
	  phonon(:,j) = dr_proj .cross. axis
	end do
      endif
      phonon_norm=sqrt(sum(ElementMass(at%Z)*sum(phonon**2,1)))
      zero_phonon(:,i) = reshape(phonon/phonon_norm, (/ 3*at%N /) )
    end do ! i
    deallocate(phonon)

    ! transform from generalized eigenproblem to regular eigenproblem
    do i=1, at%N
      zero_phonon((i-1)*3+1:(i-1)*3+3,:) = zero_phonon((i-1)*3+1:(i-1)*3+3,:)*sqrt(ElementMass(at%Z(i)))
    end do

    allocate(zero_overlap_inv(n_zero,n_zero))
    ! project out zero frequency modes
    do i=1, n_zero
      do j=1, n_zero
	zero_overlap_inv(i,j) = sum(zero_phonon(:,i)*zero_phonon(:,j))
      end do
    end do
    call inverse(zero_overlap_inv)

    zero_phonon_p = 0.0_dp; call matrix_product_sub(zero_phonon_p, zero_phonon, zero_overlap_inv)
    deallocate(zero_overlap_inv)

    allocate(dm_t(at%N*3,at%N*3))
    allocate(P(at%N*3,at%N*3))
    P = 0.0_dp; call matrix_product_sub(P, zero_phonon_p, zero_phonon, .false., .true.)
    deallocate(zero_phonon_p)
    P = -P
    call add_identity(P)

    dm_t = 0.0_dp; call matrix_product_sub(dm_t, dm, P)
    dm = 0.0_dp; call matrix_product_sub(dm, P, dm_t)
    deallocate(dm_t)
    deallocate(P)
  end if

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  ! symmetrize dynamical matrix exactly
  do i=1, 3*at%N
    do j=i+1, 3*at%N
      dm(i,j) = dm(j,i)
    end do
  end do

  call print("dm", NERD)
  call print(dm, NERD)

  ! diagonalise dynamical matrix
  call diagonalise(dm, evals, evecs, err)
  if (err /= 0) then
    call system_abort("calc_phonons got error " // err // " in diagonalise")
  endif

  if (override_zero_freq_phonons .and. do_zero_rotation) then
    zero_phonon(:,n_zero-1) = zero_phonon(:,n_zero-1)-zero_phonon(:,n_zero-2)*sum(zero_phonon(:,n_zero-1)*zero_phonon(:,n_zero-2))
    zero_phonon(:,n_zero-1) = zero_phonon(:,n_zero-1)/sqrt(sum(zero_phonon(:,n_zero-1)**2))
    zero_phonon(:,n_zero) = zero_phonon(:,n_zero)-zero_phonon(:,n_zero-2)*sum(zero_phonon(:,n_zero)*zero_phonon(:,n_zero-2))
    zero_phonon(:,n_zero) = zero_phonon(:,n_zero)-zero_phonon(:,n_zero-1)*sum(zero_phonon(:,n_zero)*zero_phonon(:,n_zero-1))
    zero_phonon(:,n_zero) = zero_phonon(:,n_zero)/sqrt(sum(zero_phonon(:,n_zero)**2))
    evecs(:,1:n_zero) = zero_phonon
  endif
  deallocate(zero_phonon)

  ! transform from evecs of regular eigenproblem to evecs of original generalized eigenproblem
  if (present(evecs)) then
    do i=1, at%N
      evecs((i-1)*3+1:(i-1)*3+3,:) = evecs((i-1)*3+1:(i-1)*3+3,:) / sqrt(ElementMass(at%Z(i))) 
    end do
  endif

  ! calculate effective masses
  if (present(effective_masses)) then
    do i=1, 3*at%N
      effective_masses(i) = 0.0_dp
      do j=1, at%N
	effective_masses(i) = 1.0_dp/sum(evecs(:,i)**2)
      end do
    end do
  endif

  if (present(IR_intensities)) then
    do i=1, at%N*3
      dmu_dq(1) = sum(dmu_dr(:,:,1)*reshape(evecs(:,i), (/ 3, at%N /) ) )
      dmu_dq(2) = sum(dmu_dr(:,:,2)*reshape(evecs(:,i), (/ 3, at%N /) ) )
      dmu_dq(3) = sum(dmu_dr(:,:,3)*reshape(evecs(:,i), (/ 3, at%N /) ) )
      IR_intensities(i) = 3.0_dp/(PI*3.0*10**3)*sum(dmu_dq**2)
    end do
  endif

  call print("evals", VERBOSE)
  call print(evals, VERBOSE)
  if (present(evecs)) then
    call print("evecs", NERD)
    call print(evecs, NERD)
  endif
  if (present(effective_masses)) then
    call print("effective masses", VERBOSE)
    call print(effective_masses, VERBOSE)
  endif
  if (present(IR_intensities)) then
    call print("IR intensities", VERBOSE)
    call print(IR_intensities, VERBOSE)
  endif

  deallocate(dmu_dr)
  deallocate(pos0)
  deallocate(fp)
  deallocate(fm)
  deallocate(dm)

end subroutine phonons

subroutine phonons_fine(metapot, at_in, dx, phonon_supercell, calc_args, do_parallel)

  type(MetaPotential), intent(inout) :: metapot
  type(Atoms), intent(inout) :: at_in
  real(dp), intent(in) :: dx
  character(len=*), intent(in), optional :: calc_args
  logical, intent(in), optional :: do_parallel
  integer, dimension(3), intent(in), optional :: phonon_supercell

  type(Atoms) :: at
  integer :: i, ii, j, k, l, alpha, beta, nk, n1, n2, n3, jn, ni, nj, nj_orig, &
  & ni1, ni2, ni3, nj1, nj2, nj3
  integer, dimension(3) :: do_phonon_supercell, shift

  real(dp), dimension(3) :: pp, diff_ij, diff_1k, diff_i1, diff_jk
  real(dp), dimension(:,:), allocatable :: evals
  real(dp), dimension(:,:), allocatable :: dm, q, pos0
  real(dp), dimension(:,:,:,:), allocatable :: fp0, fm0
  complex(dp), dimension(:,:), allocatable :: dmft
  complex(dp), dimension(:,:,:), allocatable :: evecs


  do_phonon_supercell = optional_default((/2,2,2/),phonon_supercell)

  call supercell(at,at_in,do_phonon_supercell(1),do_phonon_supercell(2),do_phonon_supercell(3))

  nk = product(do_phonon_supercell)
  allocate(q(3,nk)) 

  i = 0
  do n1 = 0, do_phonon_supercell(1)-1
     do n2 = 0, do_phonon_supercell(2)-1
        do n3 = 0, do_phonon_supercell(3)-1
           i = i + 1

           q(:,i) = 2*PI*matmul( ( (/real(n1,dp),real(n2,dp),real(n3,dp)/) / do_phonon_supercell ), at_in%g )
        enddo
     enddo
  enddo

  allocate(evals(at_in%N*3,nk), evecs(at_in%N*3,at_in%N*3,nk)) !, dm(at%N*3,at%N*3))
  allocate(pos0(3,at%N))

  if (dx == 0.0_dp) &
    call system_abort("phonons called with dx == 0.0")

  call set_cutoff(at, cutoff(metapot)+0.5_dp)
  call calc_connect(at)
  pos0 = at%pos

  ! calculate dynamical matrix with finite differences
!  do i=1, at%N
!    do alpha=1,3
!
!      at%pos = pos0
!      at%pos(alpha,i) = at%pos(alpha,i) + dx
!      call calc_dists(at)
!      call calc(metapot, at, f=fp, args_str=calc_args)
!
!      at%pos = pos0
!      at%pos(alpha,i) = at%pos(alpha,i) - dx
!      call calc_dists(at)
!      call calc(metapot, at, f=fm, args_str=calc_args)
!
!      do j=1, at%N
!	do beta=1,3
!	  dm((i-1)*3+alpha,(j-1)*3+beta) = -((fp(beta,j)-fm(beta,j))/(2.0_dp*dx))
!	end do
!      end do
!
!    end do
!  end do

  ! that works for perfect diamond cells only
  allocate(fp0(3,at%N,3,at_in%N),fm0(3,at%N,3,at_in%N))

  do i = 1, at_in%N
     do alpha = 1, 3
        at%pos = pos0
        at%pos(alpha,i) = at%pos(alpha,i) + dx
        call calc_dists(at)
        call calc(metapot, at, f=fp0(:,:,alpha,i), args_str=calc_args)

        at%pos = pos0
        at%pos(alpha,i) = at%pos(alpha,i) - dx
        call calc_dists(at)
        call calc(metapot, at, f=fm0(:,:,alpha,i), args_str=calc_args)
     enddo
  enddo

  at%pos = pos0
  call calc_dists(at)

!  do i = 1, at_in%N  ! move atom i
!
!     do ni1 = 0, do_phonon_supercell(1)-1
!        do ni2 = 0, do_phonon_supercell(2)-1
!           do ni3= 0, do_phonon_supercell(3)-1
!              ni = ((ni1*do_phonon_supercell(2)+ni2)*do_phonon_supercell(3)+ni3)*at_in%N+i
!           
!              do alpha = 1, 3
!                 do j = 1, at_in%N  ! force on atom j
!                    do nj1 = 0, do_phonon_supercell(1)-1
!                       do nj2 = 0, do_phonon_supercell(2)-1
!                          do nj3= 0, do_phonon_supercell(3)-1
!                             shift = (/nj1,nj2,nj3/) - (/ni1,ni2,ni3/) + do_phonon_supercell
!                             shift(1) = mod(shift(1),do_phonon_supercell(1))
!                             shift(2) = mod(shift(2),do_phonon_supercell(2))
!                             shift(3) = mod(shift(3),do_phonon_supercell(3))
!                             nj = ((nj1*do_phonon_supercell(2)+nj2)*do_phonon_supercell(3)+nj3)*at_in%N+j
!                             nj_orig = ((shift(1)*do_phonon_supercell(2)+shift(2))*do_phonon_supercell(3)+shift(3))*at_in%N+j
!	                     do beta = 1, 3
!                                dm((ni-1)*3+alpha,(nj-1)*3+beta) = &
!                                & -((fp0(beta,nj_orig,alpha,i)-fm0(beta,nj_orig,alpha,i))/(2.0_dp*dx))
!                             enddo
!                          enddo
!                       enddo
!                    enddo
!                 enddo
!              enddo
!           enddo
!        enddo
!     enddo
!  enddo
              
!  deallocate(fp0,fm0)

  at%pos = pos0
  call calc_dists(at)
  deallocate(pos0)

  ! transform from generalized eigenproblem to regular eigenproblem
!  do i = 1, at%N
!    do j = 1, at%N
!      dm((i-1)*3+1:(i-1)*3+3,(j-1)*3+1:(j-1)*3+3) = dm((i-1)*3+1:(i-1)*3+3,(j-1)*3+1:(j-1)*3+3) / &
!					sqrt(ElementMass(at%Z(i))*ElementMass(at%Z(j)))
!    enddo
!  enddo

  ! symmetrize dynamical matrix exactly
!  do i = 1, 3*at%N
!    do j = i+1, 3*at%N
!      dm(i,j) = dm(j,i)
!    enddo
!  enddo

!$omp parallel private(dmft)
  allocate(dmft(at_in%N*3,at_in%N*3))
!$omp do private(k,i,j,alpha,beta,diff_ij,n1,n2,n3,pp,jn)
  do k = 1, nk
     dmft = CPLX_ZERO
     do i = 1, at_in%N
        do alpha = 1, 3
           do j = 1, at_in%N
              diff_ij = at_in%pos(:,j) - at_in%pos(:,i) 
              do beta = 1, 3
  
                 do n1 = 0, do_phonon_supercell(1)-1
                    do n2 = 0, do_phonon_supercell(2)-1
                       do n3= 0, do_phonon_supercell(3)-1

                          pp = at_in%lattice .mult. (/n1,n2,n3/)
                          jn = ((n1*do_phonon_supercell(2)+n2)*do_phonon_supercell(3)+n3)*at_in%N+j

                          dmft((i-1)*3+alpha,(j-1)*3+beta) = dmft((i-1)*3+alpha,(j-1)*3+beta) &
                          & - ((fp0(beta,jn,alpha,i)-fm0(beta,jn,alpha,i))/(2.0_dp*dx)) / &
                          & sqrt(ElementMass(at_in%Z(i))*ElementMass(at_in%Z(j))) &
                          & * exp( CPLX_IMAG * dot_product(q(:,k),(diff_ij+pp)) )

                       enddo
                    enddo
                 enddo
              enddo
           enddo
        enddo
     enddo
     do i = 1, 3*at_in%N
       dmft(i,i) = CPLX_ONE*real(dmft(i,i))
       do j = i+1, 3*at_in%N
         dmft(i,j) = conjg(dmft(j,i))
       enddo
     enddo
     call diagonalise(dmft, evals(:,k), evecs(:,:,k))
  enddo
!$omp end do
deallocate(dmft)
!$omp end parallel  
  
  do k = 1, nk
!     call print('q: '//q(:,k)*a/(2*PI))
     print'(a,3f10.5)','q: ',q(:,k)
     !call print(evecs(:,:,k))
     print'('//at_in%N*3//'f15.9)',sign(sqrt(abs(evals(:,k))),evals(:,k))/2.0_dp/PI*1000.0_dp
  enddo

  deallocate(q, evals, evecs)
  call finalise(at)

endsubroutine phonons_fine
endmodule phonons_module
