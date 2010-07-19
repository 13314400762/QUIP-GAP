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

program eval

use libAtoms_module
use QUIP_module
use libatoms_misc_utils_module
use elasticity_module
use phonons_module


implicit none

  type(Potential) pot
  type(MPI_context) mpi_glob
  type(Atoms) at

  type(Dictionary) :: cli_params

  character(len=FIELD_LENGTH) verbosity, test_dir_field
  logical :: do_E, do_F, do_V, do_cij, do_c0ij, do_local, do_test, do_n_test, do_relax, &
	     do_phonons, do_frozen_phonons, do_phonons_zero_rotation, do_force_const_mat, do_parallel_phonons, do_dipole_moment, do_absorption, &
             & do_fine_phonons
  real(dp) :: mu(3)
  real(dp), pointer :: local_dn(:)
  real(dp) :: phonons_dx
  logical :: use_n_minim, do_torque, precond_n_minim
  real(dp) :: tau(3)
  character(len=FIELD_LENGTH) :: relax_print_file, linmin_method, minim_method
  character(len=FIELD_LENGTH) init_args, calc_args, at_file, param_file
  integer relax_iter
  real(dp) :: relax_tol, relax_eps
  type(CInOutput) :: relax_io
  type(CInOutput) :: infile
  real(dp) :: absorption_polarization_in(6)
  complex(dp) :: absorption_polarization(3)
  real(dp) :: absorption_freq_range(3), absorption_gamma
  real(dp), allocatable :: absorption_freqs(:), absorption_v(:)
  integer :: freq_i
  integer, dimension(3) :: phonon_supercell

  real(dp) :: E0
  real(dp), allocatable :: local_E0(:)
  real(dp), allocatable :: F0(:,:)
  real(dp) :: V0(3,3), P0(3,3)
  real(dp) :: c(6,6), c0(6,6), cij_dx 

  real(dp) :: iso_pressure
  real(dp), dimension(3) :: diag_pressure
  real(dp), dimension(9) :: pressure
  real(dp), dimension(3,3) :: external_pressure
  logical :: has_iso_pressure, has_diag_pressure, has_pressure

  real(dp), pointer :: forces_p(:,:), local_E_p(:)
  real(dp), pointer :: phonon(:,:)
  real(dp), allocatable :: phonon_evals(:), phonon_evecs(:,:), IR_intensities(:), phonon_masses(:)
  real(dp), allocatable :: force_const_mat(:,:)
  real(dp) :: eval_froz

  logical did_something
  logical test_ok
  integer error

  integer i, n_iter, j

  call system_initialise()

  call initialise(cli_params)
  call param_register(cli_params, 'verbosity', 'NORMAL', verbosity)
  if (.not. param_read_args(cli_params, ignore_unknown=.true., task="preliminary eval CLI arguments")) then
    call system_abort("Nearly impossible failure to look for verbosity argument in preliminary parse")
  end if
  select case(verbosity)
    case ("NORMAL")
      call verbosity_push(PRINT_NORMAL)
    case ("VERBOSE")
      call verbosity_push(PRINT_VERBOSE)
    case ("NERD")
      call verbosity_push(PRINT_NERD)
    case ("ANAL")
      call verbosity_push(PRINT_ANAL)
    case default
      call system_abort("confused by verbosity " // trim(verbosity))
  end select
  call finalise(cli_params)

  call enable_timing()

  init_args = ''
  calc_args = ''
  relax_print_file=''
  test_dir_field=''
  call initialise(cli_params)
  call param_register(cli_params, 'at_file', 'stdin', at_file)
  call param_register(cli_params, 'param_file', 'quip_params.xml', param_file)
  call param_register(cli_params, 'E', 'F', do_E)
  call param_register(cli_params, 'energy', 'F', do_E)
  call param_register(cli_params, 'F', 'F', do_F)
  call param_register(cli_params, 'forces', 'F', do_F)
  call param_register(cli_params, 'V', 'F', do_V)
  call param_register(cli_params, 'virial', 'F', do_V)
  call param_register(cli_params, 'L', 'F', do_local)
  call param_register(cli_params, 'local', 'F', do_local)
  call param_register(cli_params, 'cij', 'F', do_cij)
  call param_register(cli_params, 'c0ij', 'F', do_c0ij)
  call param_register(cli_params, 'cij_dx', '0.001', cij_dx)
  call param_register(cli_params, 'torque', 'F', do_torque)
  call param_register(cli_params, 'phonons', 'F', do_phonons)
  call param_register(cli_params, 'frozen_phonons', 'F', do_frozen_phonons)
  call param_register(cli_params, 'phonons_zero_rotation', 'F', do_phonons_zero_rotation)
  call param_register(cli_params, 'force_const_mat', 'F', do_force_const_mat)
  call param_register(cli_params, 'parallel_phonons', 'F', do_parallel_phonons)
  call param_register(cli_params, 'dipole_moment', 'F', do_dipole_moment)
  call param_register(cli_params, 'absorption', 'F', do_absorption)
  call param_register(cli_params, 'absorption_polarization', '0.0 0.0  0.0 0.0  1.0 0.0', absorption_polarization_in)
  call param_register(cli_params, 'absorption_freq_range', '0.1 1.0 0.1', absorption_freq_range)
  call param_register(cli_params, 'absorption_gamma', '0.01', absorption_gamma)
  call param_register(cli_params, 'phonons_dx', '0.001', phonons_dx)
  call param_register(cli_params, 'phonon_supercell', '3 3 3', phonon_supercell,do_fine_phonons)
  call param_register(cli_params, 'test', 'F', do_test)
  call param_register(cli_params, 'n_test', 'F', do_n_test)
  call param_register(cli_params, 'test_dir_field', '', test_dir_field)
  call param_register(cli_params, 'relax', 'F', do_relax)
  call param_register(cli_params, 'relax_print_file', '', relax_print_file)
  call param_register(cli_params, 'relax_iter', '1000', relax_iter)
  call param_register(cli_params, 'relax_tol', '0.001', relax_tol)
  call param_register(cli_params, 'relax_eps', '0.0001', relax_eps)
  call param_register(cli_params, 'init_args', PARAM_MANDATORY, init_args)
  call param_register(cli_params, 'calc_args', '', calc_args)
  call param_register(cli_params, 'verbosity', 'NORMAL', verbosity)
  call param_register(cli_params, 'use_n_minim', 'F', use_n_minim)
  call param_register(cli_params, 'precond_n_minim', 'F', precond_n_minim)
  call param_register(cli_params, 'linmin_method', 'FAST_LINMIN', linmin_method)
  call param_register(cli_params, 'minim_method', 'cg', minim_method)
  call param_register(cli_params, 'iso_pressure', '0.0_dp', iso_pressure, has_iso_pressure)
  call param_register(cli_params, 'diag_pressure', '0.0_dp 0.0_dp 0.0_dp', diag_pressure, has_diag_pressure)
  call param_register(cli_params, 'pressure', '0.0_dp 0.0_dp 0.0_dp 0.0_dp 0.0_dp 0.0_dp 0.0_dp 0.0_dp 0.0_dp', pressure, has_pressure)

  if (.not. param_read_args(cli_params, do_check = .true., task="eval CLI arguments")) then
    call print("Usage: eval [at_file=file(stdin)] [param_file=file(quip_params.xml)",PRINT_ALWAYS)
    call print("  [E|energy] [F|forces] [V|virial] [L|local] [cij] [c0ij] [cij_dx=0.001] [torque]", PRINT_ALWAYS)
    call print("  [phonons] [phonons_dx=0.001] [force_const_mat] [test] [n_test]", PRINT_ALWAYS)
    call print("  [absorption] [absorption_polarization='{0.0 0.0 0.0 0.0 1.0 0.0}']", PRINT_ALWAYS)
    call print("  [absorption_freq_range='{0.1 1.0 0.1}'] [absorption_gamma=0.01]", PRINT_ALWAYS)
    call print("  [relax] [relax_print_file=file(none)] [relax_iter=i] [relax_tol=r] [relax_eps=r]", PRINT_ALWAYS)
    call print("  [init_args='str'] [calc_args='str'] [verbosity=VERBOSITY(PRINT_NORMAL)] [precond_n_minim] [use_n_minim]", PRINT_ALWAYS)
    call print("  [linmin_method=string(FAST_LINMIN)]", PRINT_ALWAYS)
    call print("  [minim_method=string(cg)]", PRINT_ALWAYS)
    call system_abort("Confused by CLI arguments")
  end if
  call finalise(cli_params)

  call print ("Using init args " // trim(init_args))
  call print ("Using calc args " // trim(calc_args))

  call Initialise(mpi_glob)

  call Potential_Filename_Initialise(pot, args_str=init_args, param_filename=param_file, mpi_obj=mpi_glob)

  call print(pot)

  call initialise(infile, trim(at_file))

  if( count( (/has_iso_pressure, has_diag_pressure, has_pressure/) ) > 1 ) call system_abort('External pressure specified in an ambiguous way')
  external_pressure = 0.0_dp
  if(has_iso_pressure) then
     external_pressure(1,1) = iso_pressure
     external_pressure(2,2) = iso_pressure
     external_pressure(3,3) = iso_pressure
  endif
  if(has_diag_pressure) then
     external_pressure(1,1) = diag_pressure(1)
     external_pressure(2,2) = diag_pressure(2)
     external_pressure(3,3) = diag_pressure(3)
  endif
  if(has_pressure) external_pressure = reshape(pressure, (/3,3/))

  ! main loop over frames
  do 
     call read(at, infile, error=error)
     if (error /= 0) exit

     call set_cutoff(at, cutoff(pot)+0.5_dp)

     call calc_connect(at)

     did_something=.false.
     
     if (do_test .or. do_n_test) then
        did_something=.true.
        if (do_test) then
           call verbosity_set_minimum(PRINT_NERD)
           if (len(trim(test_dir_field)) > 0) then
              test_ok = test_gradient(pot, at, do_F, do_V, args_str = calc_args, dir_field=trim(test_dir_field))
           else
              test_ok = test_gradient(pot, at, do_F, do_V, args_str = calc_args)
           endif
           call verbosity_unset_minimum()
           call print ("test is OK? " // test_ok)
        endif
        if (do_n_test) then
           if (len(trim(test_dir_field)) > 0) then
              call n_test_gradient(pot, at, do_F, do_V, args_str = calc_args, dir_field=trim(test_dir_field))
           else
              call n_test_gradient(pot, at, do_F, do_V, args_str = calc_args)
           endif
        end if
        call finalise(at)
        cycle
     end if
     
     if (do_relax) then
        if (len(trim(relax_print_file)) > 0) then
           call initialise(relax_io, relax_print_file, OUTPUT)
           n_iter = minim(pot, at, trim(minim_method), relax_tol, relax_iter, trim(linmin_method), do_print = .true., &
                print_cinoutput = relax_io, do_pos = do_F, do_lat = do_V, args_str = calc_args, &
                eps_guess=relax_eps, use_n_minim = use_n_minim, external_pressure=external_pressure/GPA, &
		use_precond=precond_n_minim)
           call finalise(relax_io)
        else
           n_iter = minim(pot, at, trim(minim_method), relax_tol, relax_iter, trim(linmin_method), do_print = .false., &
                do_pos = do_F, do_lat = do_V, args_str = calc_args, eps_guess=relax_eps, use_n_minim = use_n_minim, &
		external_pressure=external_pressure/GPA, use_precond=precond_n_minim)
        endif
        mainlog%prefix='RELAXED_POS'
        call print_xyz(at,mainlog,real_format='f12.5')
        mainlog%prefix=''
        call print('Cell Volume: '//cell_volume(at)//' A^3')
        call calc_connect(at)
     end if
     
     if (do_c0ij .or. do_cij) then
        did_something=.true.
        call print("Elastic constants in GPa")
        call print("Using finite difference = "//cij_dx)
        if (do_c0ij .and. do_cij) then
           call calc_elastic_constants(pot, at, cij_dx, calc_args, c=c, c0=c0, relax_initial=.false., relax_tol=relax_tol)
        else if (do_c0ij) then
           call calc_elastic_constants(pot, at, cij_dx, calc_args, c0=c0, relax_initial=.false., relax_tol=relax_tol)
        else
           call calc_elastic_constants(pot, at, cij_dx, calc_args, c=c, relax_initial=.false., relax_tol=relax_tol)
        endif
        if (do_c0ij) then
           mainlog%prefix="C0IJ"
           call print(c0*GPA)
           mainlog%prefix=""
        endif
        if (do_cij) then
           mainlog%prefix="CIJ"
           call print(c*GPA)
           mainlog%prefix=""
        endif
        call print("")
     endif
     
     if (do_dipole_moment) then
        call add_property(at, 'local_dn', 0.0_dp, 1)
     endif
     
     if (do_phonons) then
        did_something = .true.
        if (do_force_const_mat) then
           allocate(force_const_mat(at%N*3,at%N*3))
        endif
        
        allocate(phonon_evals(at%N*3))
        allocate(phonon_masses(at%N*3))
        allocate(phonon_evecs(at%N*3,at%N*3))
        if (do_dipole_moment) then
           allocate(IR_intensities(at%N*3))
           if (do_force_const_mat) then
              call phonons(pot, at, phonons_dx, phonon_evals, phonon_evecs, phonon_masses, calc_args = calc_args, &
                   IR_intensities=IR_intensities, do_parallel=do_parallel_phonons, zero_rotation=do_phonons_zero_rotation, &
		   force_const_mat=force_const_mat)
           else
              call phonons(pot, at, phonons_dx, phonon_evals, phonon_evecs, phonon_masses, calc_args = calc_args, &
                   IR_intensities=IR_intensities, zero_rotation=do_phonons_zero_rotation, &
		   do_parallel=do_parallel_phonons)
           endif
        else
           if (do_force_const_mat) then
              call phonons(pot, at, phonons_dx, phonon_evals, phonon_evecs, phonon_masses, calc_args = calc_args, &
                   do_parallel=do_parallel_phonons, zero_rotation=do_phonons_zero_rotation, &
		   force_const_mat=force_const_mat)
           else
              call phonons(pot, at, phonons_dx, phonon_evals, phonon_evecs, phonon_masses, calc_args = calc_args, &
                   do_parallel=do_parallel_phonons, zero_rotation=do_phonons_zero_rotation)
           endif
        endif
        
        if (do_force_const_mat) then
           call print ("Force constants are usually in eV/A^2")
           mainlog%prefix="FORCE_CONST_MAT"
           do i=1, size(force_const_mat,1)
              do j=1, size(force_const_mat,2)
                 call print( ((i-1)/3+1) // " " // (mod(i-1,3)+1) // " " // ((j-1)/3+1) // " " // (mod(j-1,3)+1) // " " // force_const_mat(i,j))
              end do
           end do
           mainlog%prefix=""
           deallocate(force_const_mat)
        endif

        call print ("Phonons frequencies are \omega usually in fs^-1")
        
        call add_property(at,"phonon", 0.0_dp, 3)
        if (.not. assign_pointer(at,"phonon", phonon)) &
             call system_abort("Failed to assign pointer for phonon property")
        do i=1, at%N*3
           phonon = reshape(phonon_evecs(:,i), (/ 3, at%N /))
           call set_value(at%params, "phonon_i", i)
           if (phonon_evals(i) > 0.0_dp) then
              call set_value(at%params, "phonon_freq", sqrt(phonon_evals(i)))
           else
              call set_value(at%params, "phonon_freq", "I*"//sqrt(-phonon_evals(i)))
           endif
           call set_value(at%params, "phonon_eff_mass", phonon_masses(i))
           if (do_dipole_moment) then
              call set_value(at%params, "IR_intensity", 10**6*IR_intensities(i))
           endif

	   if (do_frozen_phonons) then
	      call verbosity_push(PRINT_VERBOSE)
              eval_froz = eval_frozen_phonon(pot, at, phonons_dx, phonon_evecs(:,i), calc_args)/phonon_masses(i)
	      if (eval_froz > 0.0_dp) then
		 call set_value(at%params, "frozen_phonon_freq", sqrt(eval_froz))
	      else
		 call set_value(at%params, "frozen_phonon_freq", "I*"//sqrt(-eval_froz))
	      endif
	      call verbosity_pop()
           endif

           mainlog%prefix = "PHONON"
           if (do_dipole_moment) then
              call print_xyz(at,mainlog,properties="pos:phonon:local_dn",real_format='f14.6')
           else
              call print_xyz(at,mainlog,properties="pos:phonon",real_format='f14.6')
           endif
           mainlog%prefix = ""

	   if (do_frozen_phonons) call remove_value(at%params, "frozen_phonon_freq")

        end do
        if (do_dipole_moment) then
           deallocate(IR_intensities)
        endif
        deallocate(phonon_evals)
        deallocate(phonon_masses)
        deallocate(phonon_evecs)
        call remove_property(at,"phonon")
	call remove_value(at%params, 'phonon_i')
	call remove_value(at%params, 'phonon_freq')
	call remove_value(at%params, 'phonon_eff_mass')
	if (do_dipole_moment) call remove_value(at%params, 'IR_intensity')
     endif

     if (do_fine_phonons) then
        did_something = .true.
        call phonons_fine(pot, at, phonons_dx, calc_args = calc_args, do_parallel=do_parallel_phonons, &
             & phonon_supercell=phonon_supercell)
     endif
     
     
     if (do_E .or. do_F .or. do_V .or. do_local) then
        did_something=.true.

        if (do_F) allocate(F0(3,at%N))
        if (do_local) allocate(local_E0(at%N))
        
        if (do_E) then
           if (do_F) then
              if (do_V) then
                 if (do_local) then
                    call calc(pot, at, e = E0, local_e = local_E0, f = F0, virial = V0, args_str = calc_args)
                 else
                    call calc(pot, at, e = E0, f = F0, virial = V0, args_str = calc_args)
                 endif
              else ! no V
                 if (do_local) then
                    call calc(pot, at, e = E0, local_e = local_E0, f = F0, args_str = calc_args)
                 else
                    call calc(pot, at, e = E0, f = F0, args_str = calc_args)
                 endif
              endif
           else ! no F
              if (do_V) then
                 if (do_local) then
                    call calc(pot, at, e = E0, local_e = local_E0, virial = V0, args_str = calc_args)
                 else
                    call calc(pot, at, e = E0, virial = V0, args_str = calc_args)
                 endif
              else ! no V
                 if (do_local) then
                    call calc(pot, at, e = E0, local_e = local_E0, args_str = calc_args)
                 else
                    call calc(pot, at, e = E0, args_str = calc_args)
                 endif
              endif
           endif
        else ! no E
           if (do_F) then
              if (do_V) then
                 call calc(pot, at, f = F0, virial = V0, args_str = calc_args)
              else ! no V
                 call calc(pot, at, f = F0, args_str = calc_args)
              endif
           else ! no F
              if (do_V) then
                 call calc(pot, at, virial = V0, args_str = calc_args)
              endif
           endif
        endif
        
        if (do_E) then
           call print ("Energy=" // E0)
           call set_value(at%params, 'Energy', "" // E0)
        endif
        
        if (do_dipole_moment) then
           if (.not. assign_pointer(at, "local_dn", local_dn)) &
                call system_abort("impossible failure to assign pointer for local_dn")
           mu = dipole_moment(at%pos, local_dn)
           call print ("Dipole moment " // mu)
           call set_value(at%params, 'Dipole_Moment', ""//mu)
        endif
        
        if (do_V) then
           P0 = V0/cell_volume(at)
           do i=1, 3
              call print ("Virial " // V0(i,:))
           end do
           do i=1, 3
              call print ("Pressure eV/A^3 " // P0(i,:) // "   GPa " // (P0(i,:)*GPA))
           end do
        end if
        
        if (do_F) call add_property(at, "forces", F0)
        if (do_local) call add_property(at, "local_E", local_E0)
        
        if (do_torque) then
           if (.not. do_F) then
              call print("ERROR: Can't do torque without forces", PRINT_ALWAYS)
           else
              tau = torque(at%pos, F0)
              call print("Torque " // tau)
           endif
        endif
        if (do_F) deallocate(F0)
        if (do_local) deallocate(local_E0)
     endif
     
     if (do_absorption) then
        if (.not. associated (pot%pot%tb)) &
             call system_abort("Can only do absorption of TB model")
        
        absorption_polarization = (/ cmplx(absorption_polarization_in(1), absorption_polarization_in(2), dp), &
             cmplx(absorption_polarization_in(3), absorption_polarization_in(4), dp), &
             cmplx(absorption_polarization_in(5), absorption_polarization_in(6), dp) /)
        call print("do absorption: polarization " // absorption_polarization)
        call print("do absorption: freq_range " // absorption_freq_range)
        call print("do absorption: gamma " // absorption_gamma)
        
        allocate(absorption_freqs(floor((absorption_freq_range(2)-absorption_freq_range(1))/absorption_freq_range(3)+1.5_dp)))
        allocate(absorption_v(floor((absorption_freq_range(2)-absorption_freq_range(1))/absorption_freq_range(3)+1.5_dp)))
        do freq_i=1, size(absorption_freqs)
           absorption_freqs(freq_i) = absorption_freq_range(1) +(freq_i-1)*absorption_freq_range(3)
        end do
        
        call absorption(pot%pot%tb, absorption_polarization, absorption_freqs, absorption_gamma, absorption_v)
        do freq_i=1, size(absorption_freqs)
           call print("absorption i " // freq_i // " freq " // absorption_freqs(freq_i) // " a " // absorption_v(freq_i))
        end do
        deallocate(absorption_freqs)
        deallocate(absorption_v)
     endif
     
     if (.not. did_something) call system_abort("Nothing to be calculated")
          
     mainlog%prefix = "AT"
     call print_xyz(at, mainlog, all_properties=.true., real_format='e16.8')
     mainlog%prefix = ""

     call finalise(at)
     
  enddo

  call system_finalise()

end program
