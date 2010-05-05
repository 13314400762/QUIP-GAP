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

module IPEwald_module

use Atoms_module
use linearalgebra_module
use functions_module

implicit none

real(dp), parameter :: reciprocal_time_by_real_time = 1.0_dp / 3.0_dp

private
public :: Ewald_calc, Ewald_corr_calc

contains

  ! Ewald routine
  ! input: atoms object, has to have charge property
  ! input, optional: error (controls speed and error)
  ! input, optional: use_ewald_cutoff (forces original cutoff to be used)
  ! output: energy, force, virial

  ! procedure to determine optimal Ewald parameters:
  ! Optimization of the Ewald sum for large systems, Mol. Simul. 13 (1994), no. 1, 1-9.

  subroutine Ewald_calc(at_in,e,f,virial,error,use_ewald_cutoff,charge)

    type(Atoms), intent(in), target    :: at_in

    real(dp), intent(out), optional                    :: e
    real(dp), dimension(:,:), intent(out), optional    :: f
    real(dp), dimension(3,3), intent(out), optional    :: virial
    real(dp), intent(in), optional                    :: error
    logical, intent(in), optional                     :: use_ewald_cutoff
    real(dp), dimension(:), intent(in), optional, target :: charge

    integer  :: i, j, k, n, n1, n2, n3, not_needed !for reciprocal force
    integer, dimension(3) :: nmax !how many reciprocal vectors are to be taken

    logical :: my_use_ewald_cutoff

    real(dp) :: r_ij, erfc_ar, arg, my_error, alpha, kmax, kmax2, prefac, infac, two_alpha_over_sqrt_pi, v, &
    & ewald_precision, ewald_cutoff, my_cutoff

    real(dp), dimension(3) :: force, u_ij, a, b, c, h
    real(dp), dimension(3,3) :: identity3x3, k3x3
    real(dp), dimension(:,:,:,:), allocatable :: coskr, sinkr 
    real(dp), dimension(:,:,:,:), allocatable :: k_vec   ! reciprocal vectors
    real(dp), dimension(:,:,:,:), allocatable :: force_factor
    real(dp), dimension(:,:,:), allocatable   :: energy_factor
    real(dp), dimension(:,:,:), allocatable   :: mod2_k  !square of length of reciprocal vectors

    real(dp), dimension(:), pointer :: my_charge

    type(Atoms), target :: my_at
    type(Atoms), pointer :: at

    identity3x3 = 0.0_dp
    call add_identity(identity3x3)

    ! Set up Ewald calculation
    my_error = optional_default(1e-06_dp,error) * 4.0_dp * PI * EPSILON_0 ! convert eV to internal units
    my_use_ewald_cutoff = optional_default(.TRUE.,use_ewald_cutoff) ! can choose between optimal Ewald 
                                                                    ! cutoff and original one

    a = at_in%lattice(:,1); b = at_in%lattice(:,2); c = at_in%lattice(:,3)
    v = cell_volume(at_in)

    h(1) = v / norm(b .cross. c)
    h(2) = v / norm(c .cross. a)
    h(3) = v / norm(a .cross. b)

    ewald_precision = -log(my_error)
    ewald_cutoff = sqrt(ewald_precision/PI) * reciprocal_time_by_real_time**(1.0_dp/6.0_dp) * &
    & minval(sqrt( sum(at_in%lattice(:,:)**2,dim=1) )) / at_in%N**(1.0_dp/6.0_dp)

    call print('Ewald cutoff = '//ewald_cutoff,ANAL)

    if( my_use_ewald_cutoff .and. (ewald_cutoff > at_in%cutoff) ) then
        my_at = at_in
        call atoms_set_cutoff(my_at,ewald_cutoff)
        call calc_connect(my_at)
        at => my_at
    else
        at => at_in
    endif

    if( my_use_ewald_cutoff ) then
        my_cutoff = ewald_cutoff
     else
        my_cutoff = at_in%cutoff
     endif

         
    alpha = sqrt(ewald_precision)/at%cutoff
    call print('Ewald alpha = '//alpha,ANAL)

    kmax = 2.0_dp * ewald_precision / at%cutoff
    kmax2 = kmax**2
    call print('Ewald kmax = '//kmax,ANAL)

    nmax = nint( kmax * h / 2.0_dp / PI )
    call print('Ewald nmax = '//nmax,ANAL)

    two_alpha_over_sqrt_pi = 2.0_dp * alpha / sqrt(PI)

    prefac = 4.0_dp * PI / v
    infac  = - 1.0_dp / (4.0_dp * alpha**2.0_dp) 

    if( present(charge) ) then
       call check_size('charge',charge,(/at%N/),'IPEwald')
       my_charge => charge
    elseif( .not. assign_pointer(at, 'charge', my_charge) ) then
       call system_abort('Ewald_calc: no charge property is present in atoms object and no charge argument has been given')
    endif

    allocate( k_vec(3,-nmax(3):nmax(3),-nmax(2):nmax(2),0:nmax(1)), &
            & mod2_k(-nmax(3):nmax(3),-nmax(2):nmax(2),0:nmax(1) ),  &
            & force_factor(-nmax(3):nmax(3),-nmax(2):nmax(2),0:nmax(1),3), & 
            & energy_factor(-nmax(3):nmax(3),-nmax(2):nmax(2),0:nmax(1) ) )

    allocate( coskr(-nmax(3):nmax(3),-nmax(2):nmax(2),0:nmax(1),at%N), &
            & sinkr(-nmax(3):nmax(3),-nmax(2):nmax(2),0:nmax(1),at%N) )

    k_vec = 0.0_dp
    mod2_k = 0.0_dp
    force_factor = 0.0_dp
    energy_factor = 0.0_dp

    coskr = 0.0_dp
    sinkr = 0.0_dp

    not_needed = ( 2*nmax(3) + 1 ) * nmax(2) + nmax(3) + 1 ! lot of symmetries for k and -k so count only
                                                           ! half of them, omit k = (0,0,0)

    n = 0
    do n1 = 0, nmax(1)
       do n2 = -nmax(2), nmax(2)
           do n3 = -nmax(3), nmax(3)

              n = n + 1

              if( n>not_needed ) then
                  k_vec(:,n3,n2,n1) = ( at%g(1,:)*n1 + at%g(2,:)*n2 + at%g(3,:)*n3 ) * 2.0_dp * PI
                  mod2_k(n3,n2,n1)  = norm2( k_vec(:,n3,n2,n1) )

                  force_factor(n3,n2,n1,:) = 1.0_dp/mod2_k(n3,n2,n1) * &
                  & exp(mod2_k(n3,n2,n1)*infac) * k_vec(:,n3,n2,n1)
                  energy_factor(n3,n2,n1)  = 1.0_dp/mod2_k(n3,n2,n1) * exp(infac*mod2_k(n3,n2,n1))
              endif

           enddo
       enddo
    enddo

    do i = 1, at%N
       n = 0
       do n1 = 0, nmax(1)
          do n2 = -nmax(2), nmax(2)
             do n3 = -nmax(3), nmax(3)
             
                n = n + 1

                if( (n>not_needed) .and. ( mod2_k(n3,n2,n1)<kmax2 ) ) then
                   arg = dot_product(at%pos(:,i), k_vec(:,n3,n2,n1))
                   coskr(n3,n2,n1,i) = cos(arg)*my_charge(i)
                   sinkr(n3,n2,n1,i) = sin(arg)*my_charge(i)

                endif
             enddo
          enddo
       enddo
    enddo

    if(present(e)) e = 0.0_dp
    if(present(f)) f  = 0.0_dp
    if(present(virial)) virial  = 0.0_dp

    do i=1,at%N
       !Loop over neighbours
       do n = 1, atoms_n_neighbours(at,i)
          j = atoms_neighbour(at,i,n,distance=r_ij,cosines=u_ij) ! nth neighbour of atom i
          if( r_ij > my_cutoff )  cycle
           
          erfc_ar = erfc(r_ij*alpha)/r_ij

          if( present(e) ) e = e + 0.5_dp * my_charge(i)*my_charge(j)*erfc_ar

          if( present(f) .or. present(virial) ) then
              force(:) = my_charge(i)*my_charge(j) * &
              & ( two_alpha_over_sqrt_pi * exp(-(r_ij*alpha)**2) + erfc_ar ) / r_ij * u_ij(:)

              if(present(f)) then
                 f(:,i) = f(:,i) - force(:) 
              endif

              if (present(virial)) virial = virial + 0.5_dp * (force .outer. u_ij) * r_ij
          endif
 
      enddo
    enddo
             
    ! reciprocal energy
    if(present(e)) e = e + sum((sum(coskr,dim=4)**2 + sum(sinkr,dim=4)**2)*energy_factor) * prefac &
    & - sum(my_charge**2) * alpha / sqrt(PI) - PI / ( 2.0_dp * alpha**2 * v ) * sum(my_charge)**2

    ! reciprocal force
    if( present(f) ) then
        do i = 1, at%N
           do j = 1, at%N

              if( i<=j ) cycle

              force = (/( sum(force_factor(:,:,:,k) * &
              & ( sinkr(:,:,:,j)*coskr(:,:,:,i) - sinkr(:,:,:,i)*coskr(:,:,:,j) ) ), k=1,3 )/) * prefac * 2.0_dp

              !force acting on atom j by atom i
              f(:,i) = f(:,i) - force(:)
              f(:,j) = f(:,j) + force(:)

           enddo
        enddo
    endif

    ! reciprocal contribution to virial
    if(present(virial)) then
       n = 0
       do n1 = 0, nmax(1)
          do n2 = -nmax(2), nmax(2)
             do n3 = -nmax(3), nmax(3)
             
                n = n + 1

                if( (n>not_needed) .and. ( mod2_k(n3,n2,n1)<kmax2 ) ) then
   
                   k3x3 = k_vec(:,n3,n2,n1) .outer. k_vec(:,n3,n2,n1)
                   virial = virial &
                   & + ( identity3x3 - 2*(-infac + 1.0_dp/mod2_k(n3,n2,n1))*k3x3 ) * &
                   & (sum(coskr(n3,n2,n1,:))**2 + sum(sinkr(n3,n2,n1,:))**2) * energy_factor(n3,n2,n1) * &
                   & prefac

                endif
             enddo
          enddo
       enddo
    endif

    if(present(virial)) virial = virial - identity3x3 * sum(my_charge)**2 * PI / v / alpha**2 / 2

   ! if(present(e)) e = e / ( 4.0_dp * PI * EPSILON_0 ) ! convert from internal units to eV
   ! if(present(f)) f = f / ( 4.0_dp * PI * EPSILON_0 ) ! convert from internal units to eV/A
   ! if(present(virial)) virial = virial / ( 4.0_dp * PI * EPSILON_0 )

    if(present(e)) e = e * HARTREE*BOHR ! convert from internal units to eV
    if(present(f)) f = f * HARTREE*BOHR ! convert from internal units to eV/A
    if(present(virial)) virial = virial * HARTREE*BOHR


    deallocate( coskr, sinkr )
    deallocate( k_vec, mod2_k, force_factor, energy_factor )
    if (associated(at,my_at)) call finalise(my_at)

  endsubroutine Ewald_calc

  subroutine Ewald_corr_calc(at_in,e,f,virial,cutoff,charge)

    type(Atoms), intent(in), target    :: at_in

    real(dp), intent(out), optional                    :: e
    real(dp), dimension(:,:), intent(out), optional    :: f
    real(dp), dimension(3,3), intent(out), optional    :: virial
    real(dp), intent(in), optional                    :: cutoff
    real(dp), dimension(:), intent(in), optional, target :: charge

    integer  :: i, j, n

    real(dp) :: my_cutoff, r_ij, de
    real(dp), dimension(3) :: force, u_ij

    real(dp), dimension(:), pointer :: my_charge

    type(Atoms), target :: my_at
    type(Atoms), pointer :: at

    my_cutoff = optional_default(at_in%cutoff,cutoff)

    if( present(cutoff) .and. (my_cutoff > at_in%cutoff) ) then
        my_at = at_in
        call atoms_set_cutoff(my_at,cutoff)
        call calc_connect(my_at)
        at => my_at
    else
        at => at_in
    endif
         
    if( present(charge) ) then
       call check_size('charge',charge,(/at%N/),'IPEwald')
       my_charge => charge
    elseif( .not. assign_pointer(at, 'charge', my_charge) ) then
       call system_abort('Ewald_calc: no charge property is present in atoms object and no charge argument has been given')
    endif

    if( present(e) ) e = 0.0_dp
    if( present(f) ) f = 0.0_dp
    if( present(virial) ) virial = 0.0_dp

    do i = 1, at%N
       !Loop over neighbours
       do n = 1, atoms_n_neighbours(at,i)
          j = atoms_neighbour(at,i,n,distance=r_ij,cosines=u_ij) ! nth neighbour of atom i
          if( r_ij > my_cutoff )  cycle
           
          de = 0.5_dp * ( cos(r_ij*PI/my_cutoff) + 1.0_dp ) / r_ij

          if( present(e) ) e = e + 0.5_dp * de * my_charge(i)*my_charge(j)

          if( present(f) .or. present(virial) ) then
              force = my_charge(i)*my_charge(j) * &
              & ( -de - 0.5*PI*sin(r_ij*PI/my_cutoff)/my_cutoff ) / r_ij * u_ij

              if(present(f)) then
                 f(:,i) = f(:,i) + force
              endif

              if (present(virial)) virial = virial - 0.5_dp * (force .outer. u_ij) * r_ij
          endif
 
      enddo
    enddo
             
    if(present(e)) e = 0.8_dp * e * HARTREE*BOHR ! convert from internal units to eV
    if(present(f)) f = 0.8_dp * f * HARTREE*BOHR ! convert from internal units to eV/A
    if(present(virial)) virial = 0.8_dp * virial * HARTREE*BOHR

    my_charge => null()
    if (associated(at,my_at)) call finalise(my_at)

  endsubroutine Ewald_corr_calc

endmodule IPEwald_module
