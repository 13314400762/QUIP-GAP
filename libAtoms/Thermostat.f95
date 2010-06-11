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

!X
!X  Thermostat module
!X
!% This module contains the implementations for all the thermostats available
!% in libAtoms: Langevin, Nose-Hoover and Nose-Hoover-Langevin. 
!% Each thermostat has its own section in the 'thermostat1-4' subroutines,
!% which interleave the usual velocity verlet steps.
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

module thermostat_module

  use system_module
  use atoms_module
  use units_module

  implicit none

  real(dp), dimension(3,3), parameter :: matrix_one = reshape( (/ 1.0_dp, 0.0_dp, 0.0_dp, &
                                                                & 0.0_dp, 1.0_dp, 0.0_dp, &
                                                                & 0.0_dp, 0.0_dp, 1.0_dp/), (/3,3/) )

  real(dp), parameter :: MIN_TEMP = 1.0_dp ! K

  integer, parameter :: NONE                 = 0, &
                        LANGEVIN             = 1, &
                        NOSE_HOOVER          = 2, &
                        NOSE_HOOVER_LANGEVIN = 3, &
                        LANGEVIN_NPT         = 4, &
                        LANGEVIN_PR          = 5, &
                        NPH_ANDERSEN         = 6, &
                        NPH_PR               = 7

  !% Nose-Hoover thermostat ---
  !% Hoover, W.G., \emph{Phys. Rev.}, {\bfseries A31}, 1695 (1985)
  
  !% Langevin thermostat - fluctuation/dissipation ---
  !% Quigley, D. and Probert, M.I.J., \emph{J. Chem. Phys.}, 
  !% {\bfseries 120} 11432

  !% Nose-Hoover-Langevin thermostat --- me!

  type thermostat

     integer  :: type  = NONE     !% One of the types listed above
     real(dp) :: gamma = 0.0_dp   !% Friction coefficient in Langevin and Nose-Hoover-Langevin
     real(dp) :: eta   = 0.0_dp   !% $\eta$ variable in Nose-Hoover
     real(dp) :: p_eta = 0.0_dp   !% $p_\eta$ variable in Nose-Hoover and Nose-Hoover-Langevin 
     real(dp) :: f_eta = 0.0_dp   !% The force on the Nose-Hoover(-Langevin) conjugate momentum
     real(dp) :: Q     = 0.0_dp   !% Thermostat mass in Nose-Hoover and Nose-Hoover-Langevin
     real(dp) :: T     = 0.0_dp   !% Target temperature
     real(dp) :: Ndof  = 0.0_dp   !% The number of degrees of freedom of atoms attached to this thermostat
     real(dp) :: work  = 0.0_dp   !% Work done by this thermostat
     real(dp) :: p = 0.0_dp       !% External pressure
     real(dp) :: gamma_p = 0.0_dp !% Friction coefficient for cell in Langevin NPT
     real(dp) :: W_p = 0.0_dp     !% Fictious cell mass in Langevin NPT
     real(dp) :: epsilon_r = 0.0_dp !% Position of barostat variable
     real(dp) :: epsilon_v = 0.0_dp !% Velocity of barostat variable
     real(dp) :: epsilon_f = 0.0_dp !% Force on barostat variable
     real(dp) :: epsilon_f1 = 0.0_dp !% Force on barostat variable
     real(dp) :: epsilon_f2 = 0.0_dp !% Force on barostat variable
     real(dp) :: volume_0 = 0.0_dp !% Reference volume
     real(dp), dimension(3,3) :: lattice_v = 0.0_dp
     real(dp), dimension(3,3) :: lattice_f = 0.0_dp

  end type thermostat

  interface initialise
     module procedure thermostat_initialise
  end interface initialise

  interface finalise
     module procedure thermostat_finalise, thermostats_finalise
  end interface finalise

  interface assignment(=)
     module procedure thermostat_assignment, thermostat_array_assignment
  end interface assignment(=)

  interface print
     module procedure thermostat_print, thermostats_print
  end interface

  interface add_thermostat
     module procedure thermostats_add_thermostat
  end interface add_thermostat

  interface set_degrees_of_freedom
     module procedure set_degrees_of_freedom_int, set_degrees_of_freedom_real
  end interface set_degrees_of_freedom

  interface nose_hoover_mass
     module procedure nose_hoover_mass_int, nose_hoover_mass_real
  end interface nose_hoover_mass

  interface write_binary
     module procedure thermostat_file_write, thermostats_file_write
  end interface write_binary

  interface read_binary
     module procedure thermostat_file_read, thermostats_file_read
  end interface read_binary

contains

  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  !X
  !X INITIALISE / FINALISE
  !X
  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

  subroutine thermostat_initialise(this,type,T,gamma,Q,p,gamma_p,W_p,volume_0)

    type(thermostat),   intent(inout) :: this
    integer,            intent(in)    :: type
    real(dp), optional, intent(in)    :: T
    real(dp), optional, intent(in)    :: gamma
    real(dp), optional, intent(in)    :: Q
    real(dp), optional, intent(in)    :: p
    real(dp), optional, intent(in)    :: gamma_p
    real(dp), optional, intent(in)    :: W_p
    real(dp), optional, intent(in)    :: volume_0

    if (present(T)) then
       if (T < 0.0_dp) call system_abort('initialise: Temperature must be >= 0')
    end if

    if (type /= NONE .and. .not.present(T)) &
         call system_abort('initialise: T must be specified when turning on a thermostat')

    this%type = type
    this%work = 0.0_dp
    this%eta = 0.0_dp
    this%p_eta = 0.0_dp
    this%f_eta = 0.0_dp
    this%epsilon_r = 0.0_dp
    this%epsilon_v = 0.0_dp
    this%epsilon_f = 0.0_dp
    this%epsilon_f1 = 0.0_dp
    this%epsilon_f2 = 0.0_dp
    this%volume_0 = 0.0_dp
    this%p = 0.0_dp
    this%lattice_v = 0.0_dp
    this%lattice_f = 0.0_dp

    select case(this%type)

    case(NONE) 

       this%T = 0.0_dp
       this%gamma = 0.0_dp
       this%Q = 0.0_dp
       
    case(LANGEVIN)
       
       if (.not.present(gamma)) call system_abort('thermostat initialise: gamma is required for Langevin thermostat')
       this%T = T
       this%gamma = gamma
       this%Q = 0.0_dp
       
    case(NOSE_HOOVER)
       
       if (.not.present(Q)) call system_abort('thermostat initialise: Q is required for Nose-Hoover thermostat')
       if (Q <= 0.0_dp) call system_abort('thermostat initialise: Q must be > 0')
       this%T = T      
       this%gamma = 0.0_dp
       this%Q = Q
       
    case(NOSE_HOOVER_LANGEVIN)
       
       if (.not.present(gamma)) &
            call system_abort('thermostat initialise: gamma is required for Nose-Hoover-Langevin thermostat')
       if (gamma < 0.0_dp) call system_abort('thermostat initialise: gamma must be >= 0')
       if (.not.present(Q)) call system_abort('thermostat initialise: Q is required for Nose-Hoover-Langevin thermostat')
       if (Q <= 0.0_dp) call system_abort('thermostat initialise: Q must be > 0')
       this%T = T       
       this%gamma = gamma
       this%Q = Q
       
    case(LANGEVIN_NPT)
       
       if (.not.present(gamma) .or. .not.present(p) .or. .not.present(gamma_p) .or. .not.present(W_p) .or. .not.present(volume_0) ) &
       & call system_abort('thermostat initialise: p, gamma, gamma_p, W_p and volume_0 are required for Langevin NPT baro-thermostat')
       this%T = T
       this%gamma = gamma
       this%Q = 0.0_dp
       this%p = p
       this%gamma_p = gamma_p
       this%W_p = W_p
       this%volume_0 = volume_0
       
    case(LANGEVIN_PR)
       
       if (.not.present(gamma) .or. .not.present(p) .or. .not.present(W_p) ) &
       & call system_abort('initialise: p, gamma, W_p are required for Langevin Parrinello-Rahman baro-thermostat')
       this%T = T
       this%gamma = gamma
       this%Q = 0.0_dp
       this%p = p
       this%gamma_p = 0.0_dp
       this%W_p = W_p
       
    case(NPH_ANDERSEN)
       
       if (.not.present(W_p) .or. .not.present(p) .or. .not.present(volume_0) ) &
       & call system_abort('thermostat initialise: p, W_p and volume_0 are required for Andersen NPH barostat')
       this%T = 0.0_dp
       this%gamma = 0.0_dp
       this%Q = 0.0_dp
       this%p = p
       this%gamma_p = 0.0_dp
       this%W_p = W_p
       this%volume_0 = volume_0
       
    case(NPH_PR)
       
       if (.not.present(p) .or. .not.present(W_p) ) &
       & call system_abort('initialise: p and W_p are required for NPH Parrinello-Rahman barostat')
       this%T = 0.0_dp
       this%gamma = 0.0_dp
       this%Q = 0.0_dp
       this%p = p
       this%gamma_p = 0.0_dp
       this%W_p = W_p
       
    end select
    
  end subroutine thermostat_initialise

  subroutine thermostat_finalise(this)

    type(thermostat), intent(inout) :: this

    this%type  = NONE  
    this%gamma = 0.0_dp
    this%eta   = 0.0_dp
    this%p_eta = 0.0_dp 
    this%f_eta = 0.0_dp
    this%Q     = 0.0_dp
    this%T     = 0.0_dp
    this%Ndof  = 0.0_dp
    this%work  = 0.0_dp
    this%p     = 0.0_dp
    this%gamma_p = 0.0_dp
    this%W_p = 0.0_dp
    this%epsilon_r = 0.0_dp
    this%epsilon_v = 0.0_dp
    this%epsilon_f = 0.0_dp
    this%epsilon_f1 = 0.0_dp
    this%epsilon_f2 = 0.0_dp
    this%lattice_v = 0.0_dp
    this%lattice_f = 0.0_dp
    
  end subroutine thermostat_finalise

  subroutine thermostat_assignment(to,from)

    type(thermostat), intent(out) :: to
    type(thermostat), intent(in)  :: from

    to%type  = from%type      
    to%gamma = from%gamma 
    to%eta   = from%eta   
    to%p_eta = from%p_eta 
    to%Q     = from%Q     
    to%T     = from%T     
    to%Ndof  = from%Ndof
    to%work  = from%work  
    to%p     = from%p
    to%gamma_p = from%gamma_p
    to%W_p = from%W_p
    to%epsilon_r = from%epsilon_r
    to%epsilon_v = from%epsilon_v
    to%epsilon_f = from%epsilon_f
    to%epsilon_f1 = from%epsilon_f1
    to%epsilon_f2 = from%epsilon_f2
    to%volume_0 = from%volume_0
    to%lattice_v = from%lattice_v
    to%lattice_f = from%lattice_f

  end subroutine thermostat_assignment

  !% Copy an array of thermostats
  subroutine thermostat_array_assignment(to, from)
    type(thermostat), allocatable, intent(inout) :: to(:)
    type(thermostat), allocatable, intent(in) :: from(:)
    
    integer :: u(1), l(1), i

    if (allocated(to)) deallocate(to)
    u = ubound(from)
    l = lbound(from)
    allocate(to(l(1):u(1)))
    do i=l(1),u(1)
       to(i) = from(i)
    end do

  end subroutine thermostat_array_assignment

  !% Finalise an array of thermostats
  subroutine thermostats_finalise(this)

    type(thermostat), allocatable, intent(inout) :: this(:)

    integer :: i, ua(1), la(1), u, l
    
    if (allocated(this)) then
       ua = ubound(this); u = ua(1)
       la = lbound(this); l = la(1)
       do i = l, u
          call finalise(this(i))
       end do
       deallocate(this)
    end if

  end subroutine thermostats_finalise

  subroutine thermostats_add_thermostat(this,type,T,gamma,Q,p,gamma_p,W_p,volume_0)

    type(thermostat), allocatable, intent(inout) :: this(:)
    integer,                       intent(in)    :: type
    real(dp), optional,            intent(in)    :: T
    real(dp), optional,            intent(in)    :: gamma
    real(dp), optional,            intent(in)    :: Q
    real(dp), optional,            intent(in)    :: p
    real(dp), optional,            intent(in)    :: gamma_p
    real(dp), optional,            intent(in)    :: W_p
    real(dp), optional,            intent(in)    :: volume_0

    type(thermostat), allocatable                :: temp(:)
    integer                                      :: i, l, u, la(1), ua(1)

    if (allocated(this)) then
       la = lbound(this); l=la(1)
       ua = ubound(this); u=ua(1)
       allocate(temp(l:u))
       do i = l,u
          temp(i) = this(i)
       end do
       call finalise(this)
    else
       l=1
       u=0
    end if
    
    allocate(this(l:u+1))

    if (allocated(temp)) then
       do i = l,u
          this(i) = temp(i)
       end do
       call finalise(temp)
    end if

    call initialise(this(u+1),type,T,gamma,Q,p,gamma_p,W_p,volume_0)

  end subroutine thermostats_add_thermostat

  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  !X
  !X PRINTING
  !X
  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

  subroutine thermostat_print(this,file)

    type(thermostat),         intent(in) :: this
    type(inoutput), optional, intent(in) :: file
    select case(this%type)

    case(NONE)
       call print('Thermostat off',file=file)

    case(LANGEVIN)
       call print('Langevin, T = '//round(this%T,2)//' K, gamma = '//round(this%gamma,5)//' fs^-1, work = '//&
            round(this%work,5)//' eV, Ndof = '// round(this%Ndof,1),file=file)

    case(NOSE_HOOVER)
       call print('Nose-Hoover, T = '//round(this%T,2)//' K, Q = '//round(this%Q,5)//' eV fs^2, eta = '//&
            round(this%eta,5)//' (#), p_eta = '//round(this%p_eta,5)//' eV fs, work = '//round(this%work,5)//' eV, Ndof = ' // round(this%Ndof,1),file=file)

    case(NOSE_HOOVER_LANGEVIN)
       call print('Nose-Hoover-Langevin, T = '//round(this%T,2)//' K, Q = '//round(this%Q,5)//&
            ' eV fs^2, gamma = '//round(this%gamma,5)//' fs^-1, eta = '//round(this%eta,5)//&
            ' , p_eta = '//round(this%p_eta,5)//' eV fs, work = '//round(this%work,5)//' eV, Ndof = ' // round(this%Ndof,1),file=file)
       
    case(LANGEVIN_NPT)
       call print('Langevin NPT, T = '//round(this%T,2)//' K, gamma = '//round(this%gamma,5)//' fs^-1, work = '// &
            & round(this%work,5)//' eV, p = '//round(this%p,5)//' eV/A^3, gamma_p = '// &
            & round(this%gamma_p,5)//' fs^-1, W_p = '//round(this%W_p,5)//' au, Ndof = ' // round(this%Ndof,1),file=file)

    case(LANGEVIN_PR)
       call print('Langevin PR, T = '//round(this%T,2)//' K, gamma = '//round(this%gamma,5)//' fs^-1, work = '// &
            & round(this%work,5)//' eV, p = '//round(this%p,5)//' eV/A^3, gamma_p = '// &
            & round(this%gamma_p,5)//' fs^-1, W_p = '//round(this%W_p,5)//' au',file=file)

    case(NPH_ANDERSEN)
       call print('Andersen NPH, work = '// round(this%work,5)//' eV, p = '//round(this%p,5)//' eV/A^3, W_p = '//round(this%W_p,5)//' au, Ndof = ' // round(this%Ndof,1),file=file)

    case(NPH_PR)
       call print('Parrinello-Rahman NPH, work = '// round(this%work,5)//' eV, p = '//round(this%p,5)//' eV/A^3, W_p = '//round(this%W_p,5)//' au, Ndof = ' // round(this%Ndof,1),file=file)

    end select
    
  end subroutine thermostat_print

  subroutine thermostats_print(this,file)
    
    type(thermostat), allocatable, intent(in) :: this(:)
    type(inoutput), optional,      intent(in) :: file

    integer :: u, l, i, ua(1), la(1)

    la=lbound(this); l=la(1)
    ua=ubound(this); u=ua(1)

    do i = l,u
       call print('Thermostat '//i//':',file=file)
       call print(this(i),file)
    end do

  end subroutine thermostats_print

  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  !X
  !X SETTING Ndof
  !X
  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

  subroutine set_degrees_of_freedom_int(this,Ndof)

    type(thermostat), intent(inout) :: this
    integer,          intent(in)    :: Ndof

    this%Ndof = real(Ndof,dp)

  end subroutine set_degrees_of_freedom_int

  subroutine set_degrees_of_freedom_real(this,Ndof)

    type(thermostat), intent(inout) :: this
    real(dp),         intent(in)    :: Ndof

    this%Ndof = Ndof

  end subroutine set_degrees_of_freedom_real

  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  !X
  !X CHOOSING NOSE-HOOVER(-LANGEVIN) MASS
  !X
  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

  pure function nose_hoover_mass_int(Ndof,T,tau) result(Q)

    integer,  intent(in) :: Ndof
    real(dp), intent(in) :: T, tau
    real(dp)             :: Q

    Q = real(Ndof,dp)*BOLTZMANN_K*T*tau*tau/(4.0_dp*PI*PI)

  end function nose_hoover_mass_int
    
  pure function nose_hoover_mass_real(Ndof,T,tau) result(Q)

    real(dp), intent(in) :: Ndof, T, tau
    real(dp)             :: Q

    Q = Ndof*BOLTZMANN_K*T*tau*tau/(4.0_dp*PI*PI)

  end function nose_hoover_mass_real

  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  !X
  !X THERMOSTAT ROUTINES
  !X
  !X These routines interleave the usual velocity Verlet steps and should modify 
  !X the velocities and accelerations as required:
  !X
  !X (thermostat1)
  !X v(t+dt/2) = v(t) + a(t)dt/2
  !X (thermostat2)
  !X r(t+dt) = r(t) + v(t+dt/2)dt
  !X (thermostat3)
  !X v(t+dt) = v(t+dt/2) + a(t+dt)dt/2
  !X (thermostat4)
  !X
  !X A thermostat can be applied to part of the atomic system by passing an integer
  !X atomic property and the value it must have.
  !X
  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  
  subroutine thermostat1(this,at,f,dt,property,value,virial)

    type(thermostat), intent(inout) :: this
    type(atoms),      intent(inout) :: at
    real(dp),         intent(in)    :: f(:,:)
    real(dp),         intent(in)    :: dt
    character(*),     intent(in)    :: property
    integer,          intent(in)    :: value
    real(dp), dimension(3,3), intent(in), optional :: virial

    real(dp) :: decay, K, volume_p
    real(dp), dimension(3,3) :: lattice_p, ke_virial, decay_matrix, decay_matrix_eigenvectors, exp_decay_matrix
    real(dp), dimension(3) :: decay_matrix_eigenvalues
    integer  :: i, prop_index, pos_indices(3)

    if (get_value(at%properties,property,pos_indices)) then
       prop_index = pos_indices(2)
    else
       call system_abort('thermostat1: cannot find property '//property)
    end if
 
    select case(this%type)

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X LANGEVIN
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(LANGEVIN)
              
       !Decay the velocity for dt/2. The random force will have been added to acc during the
       !previous timestep.

       decay = exp(-0.5_dp*this%gamma*dt)
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = at%velo(:,i)*decay
       end do

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NOSE-HOOVER
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(NOSE_HOOVER)
       
       !Propagate eta for dt (this saves doing it twice, for dt/2)
       this%eta = this%eta + this%p_eta*dt/this%Q

       !Decay the velocities using p_eta for dt/2. Also, accumulate the (pre-decay)
       !kinetic energy (x2) and use to integrate the 'work' value
       K = 0.0_dp
       decay = exp(-0.5_dp*this%p_eta*dt/this%Q)

       do i=1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          K = K + at%mass(i)*norm2(at%velo(:,i))
          at%velo(:,i) = at%velo(:,i)*decay
       end do

       !Propagate the work for dt/2
       this%work = this%work + 0.5_dp*this%p_eta*K*dt/this%Q

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NOSE-HOOVER-LANGEVIN
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(NOSE_HOOVER_LANGEVIN)
       
       !Decay p_eta for dt/2 and propagate it for dt/2
       this%p_eta = this%p_eta*exp(-0.5_dp*this%gamma*dt) + 0.5_dp*this%f_eta*dt
       !Propagate eta for dt (this saves doing it twice, for dt/2)
       this%eta = this%eta + this%p_eta*dt/this%Q

       !Decay the velocities using p_eta for dt/2 and accumulate Ek (as in NH) for
       !work integration
       decay = exp(-0.5_dp*this%p_eta*dt/this%Q)
       K = 0.0_dp

       do i = 1, at%N
          if(at%data%int(prop_index,i) /= value) cycle
          K = K + at%mass(i)*norm2(at%velo(:,i))
          at%velo(:,i) = at%velo(:,i)*decay
       end do

       !Propagate work
       this%work = this%work + 0.5_dp*this%p_eta*K*dt/this%Q

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X LANGEVIN NPT, Andersen barostat
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(LANGEVIN_NPT)
              
       if( .not. present(virial) ) call system_abort('thermostat1: NPT &
       & simulation, but virial has not been passed')

       this%epsilon_r = this%epsilon_r + 0.5_dp*this%epsilon_v*dt
       volume_p = exp(3.0_dp*this%epsilon_r)*this%volume_0
       lattice_p = at%lattice * (volume_p/cell_volume(at))**(1.0_dp/3.0_dp)
       call set_lattice(at,lattice_p, scale_positions=.false.)

       this%epsilon_f1 = (1.0_dp + 3.0_dp/this%Ndof)*sum(at%mass*sum(at%velo**2,dim=1)) + trace(virial) &
       & - 3.0_dp * volume_p * this%p

       this%epsilon_f = this%epsilon_f1 + this%epsilon_f2
       this%epsilon_v = this%epsilon_v + 0.5_dp * dt * this%epsilon_f / this%W_p

       !Decay the velocity for dt/2. The random force will have been added to acc during the
       !previous timestep.

       decay = exp(-0.5_dp*dt*(this%gamma+(1.0_dp + 3.0_dp/this%Ndof)*this%epsilon_v))
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = at%velo(:,i)*decay
          at%pos(:,i) = at%pos(:,i)*( 1.0_dp + this%epsilon_v * dt )
       end do
       !at%pos = at%pos*exp(this%epsilon_vp * dt) ????

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X LANGEVIN NPT, Parrinello-Rahman barostat
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(LANGEVIN_PR)
              
       if( .not. present(virial) ) call system_abort('thermostat1: NPT &
       & simulation, but virial has not been passed')

       lattice_p = at%lattice + 0.5_dp * dt * matmul(this%lattice_v,at%lattice)

       call set_lattice(at,lattice_p, scale_positions=.false.)
       volume_p = cell_volume(at)

       ke_virial = matmul(at%velo*spread(at%mass,dim=1,ncopies=3),transpose(at%velo))

       this%lattice_f = ke_virial + virial - this%p*volume_p*matrix_one + trace(ke_virial)*matrix_one/this%Ndof
       this%lattice_v = this%lattice_v + 0.5_dp*dt*this%lattice_f / this%W_p
       
       !Decay the velocity for dt/2. The random force will have been added to acc during the
       !previous timestep.

       decay_matrix = -0.5_dp*dt*( this%gamma*matrix_one + this%lattice_v + trace(this%lattice_v)*matrix_one/this%Ndof )
       decay_matrix = ( decay_matrix + transpose(decay_matrix) ) / 2.0_dp ! Making sure the matrix is exactly symmetric
       call diagonalise(decay_matrix,decay_matrix_eigenvalues,decay_matrix_eigenvectors)
       exp_decay_matrix = matmul( decay_matrix_eigenvectors, matmul( diag(exp(decay_matrix_eigenvalues)), transpose(decay_matrix_eigenvectors) ) )
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = matmul(exp_decay_matrix,at%velo(:,i))
          !at%velo(:,i) = at%velo(:,i) + matmul(decay_matrix,at%velo(:,i))
          at%pos(:,i) = at%pos(:,i) + matmul(this%lattice_v,at%pos(:,i))*dt
       end do
       !at%pos = at%pos*exp(this%epsilon_vp * dt) ????

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NPH, Andersen barostat
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(NPH_ANDERSEN)
              
       if( .not. present(virial) ) call system_abort('thermostat1: NPH &
       & simulation, but virial has not been passed')

       this%epsilon_r = this%epsilon_r + 0.5_dp*this%epsilon_v*dt
       volume_p = exp(3.0_dp*this%epsilon_r)*this%volume_0
       lattice_p = at%lattice * (volume_p/cell_volume(at))**(1.0_dp/3.0_dp)
       call set_lattice(at,lattice_p, scale_positions=.false.)

       this%epsilon_f = (1.0_dp + 3.0_dp/this%Ndof)*sum(at%mass*sum(at%velo**2,dim=1)) + trace(virial) &
       & - 3.0_dp * volume_p * this%p

       this%epsilon_v = this%epsilon_v + 0.5_dp * dt * this%epsilon_f / this%W_p

       !Decay the velocity for dt/2. The random force will have been added to acc during the
       !previous timestep.

       decay = exp(-0.5_dp*dt*(1.0_dp + 3.0_dp/this%Ndof)*this%epsilon_v)
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = at%velo(:,i)*decay
          at%pos(:,i) = at%pos(:,i)*( 1.0_dp + this%epsilon_v * dt )
       end do

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NPH, Parrinello-Rahman barostat
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(NPH_PR)
              
       if( .not. present(virial) ) call system_abort('thermostat1: NPH &
       & simulation, but virial has not been passed')

       lattice_p = at%lattice + 0.5_dp * dt * matmul(this%lattice_v,at%lattice)

       call set_lattice(at,lattice_p, scale_positions=.false.)
       volume_p = cell_volume(at)

       ke_virial = matmul(at%velo*spread(at%mass,dim=1,ncopies=3),transpose(at%velo))

       this%lattice_f = ke_virial + virial - this%p*volume_p*matrix_one + trace(ke_virial)*matrix_one/this%Ndof
       this%lattice_v = this%lattice_v + 0.5_dp*dt*this%lattice_f / this%W_p
       
       !Decay the velocity for dt/2. 

       decay_matrix = -0.5_dp*dt*( this%lattice_v + trace(this%lattice_v)*matrix_one/this%Ndof )
       decay_matrix = ( decay_matrix + transpose(decay_matrix) ) / 2.0_dp ! Making sure the matrix is exactly symmetric
       call diagonalise(decay_matrix,decay_matrix_eigenvalues,decay_matrix_eigenvectors)
       exp_decay_matrix = matmul( decay_matrix_eigenvectors, matmul( diag(exp(decay_matrix_eigenvalues)), transpose(decay_matrix_eigenvectors) ) )
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = matmul(exp_decay_matrix,at%velo(:,i))
          !at%velo(:,i) = at%velo(:,i) + matmul(decay_matrix,at%velo(:,i))
          at%pos(:,i) = at%pos(:,i) + matmul(this%lattice_v,at%pos(:,i))*dt
       end do

    end select

  end subroutine thermostat1
  
  subroutine thermostat2(this,at,f,dt,property,value)

    type(thermostat), intent(inout) :: this
    type(atoms),      intent(inout) :: at
    real(dp),         intent(in)    :: dt
    real(dp),         intent(in)    :: f(:,:)
    character(*),     intent(in)    :: property
    integer,          intent(in)    :: value

    integer  :: prop_index, pos_indices(3)
    
    if (get_value(at%properties,property,pos_indices)) then
       prop_index = pos_indices(2)
    else
       call system_abort('thermostat2: cannot find property '//property)
    end if
    
!    select case(this%type)

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X LANGEVIN
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    !case(LANGEVIN)
       
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NOSE-HOOVER
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    !case(NOSE_HOOVER)

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NOSE-HOOVER-LANGEVIN
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       
    !case(NOSE_HOOVER_LANGEVIN)


       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       
!    end select

  end subroutine thermostat2

  subroutine thermostat3(this,at,f,dt,property,value)
    
    type(thermostat), intent(inout) :: this
    type(atoms),      intent(inout) :: at
    real(dp),         intent(in)    :: f(:,:)
    real(dp),         intent(in)    :: dt
    character(*),     intent(in)    :: property
    integer,          intent(in)    :: value

    real(dp) :: R, a(3)
    integer  :: i, prop_index, pos_indices(3)

    if (get_value(at%properties,property,pos_indices)) then
       prop_index = pos_indices(2)
    else
       call system_abort('thermostat3: cannot find property '//property)
    end if
    
    select case(this%type)

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X LANGEVIN
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(LANGEVIN,LANGEVIN_NPT,LANGEVIN_PR)
     
       ! Add the random acceleration
       R = 2.0_dp*this%gamma*BOLTZMANN_K*this%T/dt

       ! Random numbers may have been used at different rates on different MPI processes:
       ! we must resync the random number if we want the same numbers on each process.
       call system_resync_rng()

       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          a = sqrt(R/at%mass(i))*ran_normal3()
          at%acc(:,i) = at%acc(:,i) + a
       end do

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NOSE-HOOVER
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    !case(NOSE_HOOVER)

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NOSE-HOOVER-LANGEVIN
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    !case(NOSE_HOOVER_LANGEVIN) nothing to be done
       
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    end select

  end subroutine thermostat3
  
  subroutine thermostat4(this,at,f,dt,property,value,virial)

    type(thermostat), intent(inout) :: this
    type(atoms),      intent(inout) :: at
    real(dp),         intent(in)    :: f(:,:)
    real(dp),         intent(in)    :: dt
    character(*),     intent(in)    :: property
    integer,          intent(in)    :: value
    real(dp), dimension(3,3), intent(in), optional :: virial

    real(dp) :: decay, K, volume_p, f_cell
    real(dp), dimension(3,3) :: lattice_p, ke_virial, decay_matrix, decay_matrix_eigenvectors, exp_decay_matrix
    real(dp), dimension(3) :: decay_matrix_eigenvalues
    integer  :: i, prop_index, pos_indices(3)

    if (get_value(at%properties,property,pos_indices)) then
       prop_index = pos_indices(2)
    else
       call system_abort('thermostat4: cannot find property '//property)
    end if
    
    select case(this%type)

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X LANGEVIN
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(LANGEVIN)

       !Decay the velocities for dt/2 again
       decay = exp(-0.5_dp*this%gamma*dt)
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = at%velo(:,i)*decay
       end do
       
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NOSE-HOOVER
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(NOSE_HOOVER)

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

       !Decay the velocities again using p_eta for dt/2, and accumulate the (post-decay)
       !kinetic energy (x2) to integrate the 'work' value.
       decay = exp(-0.5_dp*this%p_eta*dt/this%Q)
       K = 0.0_dp
       do i=1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = at%velo(:,i)*decay
          K = K + at%mass(i)*norm2(at%velo(:,i))
       end do

       !Calculate new f_eta...
       this%f_eta = 0.0_dp
       do i = 1, at%N
          if (at%data%int(prop_index,i) == value) this%f_eta = this%f_eta + at%mass(i)*norm2(at%velo(:,i))
       end do
       this%f_eta = this%f_eta - this%Ndof*BOLTZMANN_K*this%T

       !Propagate p_eta for dt/2
       this%p_eta = this%p_eta + 0.5_dp*this%f_eta*dt

       !Propagate the work for dt/2
       this%work = this%work + 0.5_dp*this%p_eta*K*dt/this%Q

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       !X
       !X NOSE-HOOVER-LANGEVIN
       !X
       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       
    case(NOSE_HOOVER_LANGEVIN)
       
       !Decay the velocities again using p_eta for dt/2, and accumulate Ek for work integration
       decay = exp(-0.5_dp*this%p_eta*dt/this%Q)
       K = 0.0_dp
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = at%velo(:,i)*decay
          K = K + at%mass(i)*norm2(at%velo(:,i))
       end do

       !Propagate work
       this%work = this%work + 0.5_dp*this%p_eta*K*dt/this%Q

       !Calculate new f_eta...
       this%f_eta = 0.0_dp
       !Deterministic part:
        do i = 1, at%N
           if (at%data%int(prop_index,i) == value) this%f_eta = this%f_eta + at%mass(i)*norm2(at%velo(:,i))
        end do
       this%f_eta = this%f_eta - this%Ndof*BOLTZMANN_K*this%T
       !Stochastic part: 
       this%f_eta = this%f_eta + sqrt(2.0_dp*this%gamma*this%Q*BOLTZMANN_K*this%T/dt)*ran_normal()

       !Propagate p_eta for dt/2 then decay it for dt/2
       this%p_eta = this%p_eta + 0.5_dp*this%f_eta*dt
       this%p_eta = this%p_eta*exp(-0.5_dp*this%gamma*dt)

       !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    case(LANGEVIN_NPT)

       if( .not. present(virial) ) call system_abort('thermostat4: NPT &
       & simulation, but virial has not been passed')

       f_cell = sqrt(2.0_dp*BOLTZMANN_K*this%T*this%gamma_p*this%W_p/dt)*ran_normal()

       !Decay the velocities for dt/2 again
       decay = exp(-0.5_dp*dt*(this%gamma+(1.0_dp + 3.0_dp/this%Ndof)*this%epsilon_v))
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = at%velo(:,i)*decay
       end do
       
       volume_p = cell_volume(at)
       this%epsilon_f = (1.0_dp + 3.0_dp/this%Ndof)*sum(at%mass*sum(at%velo**2,dim=1)) + trace(virial) &
       & - 3.0_dp * volume_p * this%p + f_cell

       this%epsilon_v = ( this%epsilon_v + 0.5_dp * dt * this%epsilon_f / this%W_p ) / &
       & ( 1.0_dp + 0.5_dp * dt * this%gamma_p )

       this%epsilon_r = this%epsilon_r + 0.5_dp*this%epsilon_v*dt
       volume_p = exp(3.0_dp*this%epsilon_r)*this%volume_0
       lattice_p = at%lattice * (volume_p/cell_volume(at))**(1.0_dp/3.0_dp)
       call set_lattice(at,lattice_p, scale_positions=.false.)

       this%epsilon_f2 = f_cell - this%epsilon_v*this%W_p*this%gamma_p

    case(LANGEVIN_PR)

       if( .not. present(virial) ) call system_abort('thermostat4: NPT Parrinello-Rahman&
       & simulation, but virial has not been passed')

       !Decay the velocities for dt/2 again
       decay_matrix = -0.5_dp*dt*( this%gamma*matrix_one + this%lattice_v + trace(this%lattice_v)*matrix_one/this%Ndof )
       decay_matrix = ( decay_matrix + transpose(decay_matrix) ) / 2.0_dp ! Making sure the matrix is exactly symmetric
       call diagonalise(decay_matrix,decay_matrix_eigenvalues,decay_matrix_eigenvectors)
       exp_decay_matrix = matmul( decay_matrix_eigenvectors, matmul( diag(exp(decay_matrix_eigenvalues)), transpose(decay_matrix_eigenvectors) ) )
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = matmul(exp_decay_matrix,at%velo(:,i))
          !at%velo(:,i) = at%velo(:,i) + matmul(decay_matrix,at%velo(:,i))
       end do
       
       volume_p = cell_volume(at)
       ke_virial = matmul(at%velo*spread(at%mass,dim=1,ncopies=3),transpose(at%velo))
       this%lattice_f = ke_virial + virial - this%p*volume_p*matrix_one + trace(ke_virial)*matrix_one/this%Ndof

       this%lattice_v = this%lattice_v + 0.5_dp*dt*this%lattice_f / this%W_p
       lattice_p = at%lattice + 0.5_dp * dt * matmul(this%lattice_v,at%lattice)
       call set_lattice(at,lattice_p, scale_positions=.false.)

    case(NPH_ANDERSEN)

       if( .not. present(virial) ) call system_abort('thermostat4: NPH &
       & simulation, but virial has not been passed')

       !Decay the velocities for dt/2 again
       decay = exp(-0.5_dp*dt*(1.0_dp + 3.0_dp/this%Ndof)*this%epsilon_v)
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = at%velo(:,i)*decay
       end do
       
       volume_p = cell_volume(at)
       this%epsilon_f = (1.0_dp + 3.0_dp/this%Ndof)*sum(at%mass*sum(at%velo**2,dim=1)) + trace(virial) &
       & - 3.0_dp * volume_p * this%p

       this%epsilon_v = ( this%epsilon_v + 0.5_dp * dt * this%epsilon_f / this%W_p ) 

       this%epsilon_r = this%epsilon_r + 0.5_dp*this%epsilon_v*dt
       volume_p = exp(3.0_dp*this%epsilon_r)*this%volume_0
       lattice_p = at%lattice * (volume_p/cell_volume(at))**(1.0_dp/3.0_dp)
       call set_lattice(at,lattice_p, scale_positions=.false.)

    case(NPH_PR)

       if( .not. present(virial) ) call system_abort('thermostat4: NPH Parrinello-Rahman&
       & simulation, but virial has not been passed')

       !Decay the velocities for dt/2 again
       decay_matrix = -0.5_dp*dt*( this%lattice_v + trace(this%lattice_v)*matrix_one/this%Ndof )
       decay_matrix = ( decay_matrix + transpose(decay_matrix) ) / 2.0_dp ! Making sure the matrix is exactly symmetric
       call diagonalise(decay_matrix,decay_matrix_eigenvalues,decay_matrix_eigenvectors)
       exp_decay_matrix = matmul( decay_matrix_eigenvectors, matmul( diag(exp(decay_matrix_eigenvalues)), transpose(decay_matrix_eigenvectors) ) )
       do i = 1, at%N
          if (at%data%int(prop_index,i) /= value) cycle
          at%velo(:,i) = matmul(exp_decay_matrix,at%velo(:,i))
          !at%velo(:,i) = at%velo(:,i) + matmul(decay_matrix,at%velo(:,i))
       end do
       
       volume_p = cell_volume(at)
       ke_virial = matmul(at%velo*spread(at%mass,dim=1,ncopies=3),transpose(at%velo))
       this%lattice_f = ke_virial + virial - this%p*volume_p*matrix_one + trace(ke_virial)*matrix_one/this%Ndof

       this%lattice_v = this%lattice_v + 0.5_dp*dt*this%lattice_f / this%W_p
       lattice_p = at%lattice + 0.5_dp * dt * matmul(this%lattice_v,at%lattice)
       call set_lattice(at,lattice_p, scale_positions=.false.)

    end select

  end subroutine thermostat4

  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  !X
  !X BINARY READING/WRITING
  !X
  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  
  subroutine thermostat_file_write(this,outfile)

    type(thermostat), intent(in)    :: this
    type(inoutput),   intent(inout) :: outfile
    
    call write_binary('thermostat',outfile)

    call write_binary(this%type,outfile)
    call write_binary(this%gamma,outfile)
    call write_binary(this%eta,outfile)
    call write_binary(this%p_eta,outfile)
    call write_binary(this%f_eta,outfile)
    call write_binary(this%Q,outfile)
    call write_binary(this%T,outfile)
    call write_binary(this%Ndof,outfile)
    call write_binary(this%work,outfile)

  end subroutine thermostat_file_write

  subroutine thermostat_file_read(this,infile)

    type(thermostat), intent(inout) :: this
    type(inoutput),   intent(inout) :: infile
    character(10)                   :: id

    call read_binary(id,infile)
    if (id /= 'thermostat') call system_abort('Bad thermostat found in file '//trim(infile%filename))

    call read_binary(this%type,infile)
    call read_binary(this%gamma,infile)
    call read_binary(this%eta,infile)
    call read_binary(this%p_eta,infile)
    call read_binary(this%f_eta,infile)
    call read_binary(this%Q,infile)
    call read_binary(this%T,infile)
    call read_binary(this%Ndof,infile)
    call read_binary(this%work,infile)

  end subroutine thermostat_file_read

  subroutine thermostats_file_write(this,outfile)

    type(thermostat), allocatable, intent(in)    :: this(:)
    type(inoutput),                intent(inout) :: outfile
    integer :: l(1), u(1), i

    l = lbound(this)
    u = ubound(this)

    call write_binary('thermoarray',outfile)
    call write_binary(l(1),outfile)
    call write_binary(u(1),outfile)
    do i = l(1),u(1)
       call write_binary(this(i),outfile)
    end do

  end subroutine thermostats_file_write

  subroutine thermostats_file_read(this,infile)

    type(thermostat), allocatable, intent(inout) :: this(:)
    type(inoutput),                intent(inout) :: infile
    integer :: l(1), u(1), i
    character(11) :: id

    call read_binary(id,infile)
    if (id /= 'thermoarray') call system_abort('Bad thermostat array in file '//trim(infile%filename))

    call read_binary(l(1),infile)
    call read_binary(u(1),infile)
    
    call finalise(this)
    allocate(this(l(1):u(1)))

    do i = l(1),u(1)
       call read_binary(this(i),infile)
    end do

  end subroutine thermostats_file_read

  function kinetic_virial(this)
     type(atoms), intent(in) :: this
     real(dp), dimension(3,3) :: kinetic_virial
     integer :: i

     kinetic_virial = 0.0_dp

     do i = 1, this%N
        kinetic_virial = kinetic_virial + this%mass(i)*( this%velo(:,i) .outer. this%velo(:,i) )
     enddo
     kinetic_virial = kinetic_virial / cell_volume(this)

  endfunction kinetic_virial

end module thermostat_module
