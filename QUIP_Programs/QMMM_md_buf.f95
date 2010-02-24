!adaptive hybrid QMMM MD program.
!reads atoms & QM list & runs CP2K & writes movie xyz with QM flags
!uses the metapotential with momentum conservation, adding the corrective force only to the QM core and buffer atoms
!filepot_program can be e.g. /Users/csilla/QUIP/build.darwin_x86_64_g95/cp2k_filepot
!TODO:
!use the buffer carving of the metapotential force mixing routines.

program qmmm_md

  use libatoms_module
  use cp2k_driver_template_module
  use quip_module

  implicit none

  type(DynamicalSystem)               :: ds
  type(Atoms)                         :: my_atoms
  type(Table)                         :: constraints
  integer                             :: i, n, N_constraints
  character(len=FIELD_LENGTH)         :: Run_Type_array(5)               !_MM_, QS, QMMM_EXTENDED or QMMM_CORE

  !Force calc.
  type(Potential)                     :: cp2k_fast_pot, cp2k_slow_pot 
  type(MetaPotential)                 :: metapot, empty_qm_metapot
  character(len=STRING_LENGTH)        :: args_str
  real(dp)                            :: energy,check,TI_force, TI_corr
  real(dp), dimension(:,:), allocatable :: f,f0,f1, add_force

  !QM list generation
  type(Table)                         :: embedlist
  logical                             :: list_changed
  logical                             :: list_changed1
  integer, pointer                    :: qm_flag_p(:)
  integer, pointer                    :: hybrid(:)
  integer, pointer                    :: hybrid_mark_p(:)
  integer, pointer                    :: cluster_mark_p(:)

  !Thermostat
  real(dp)                            :: Q_QM, Q_MM, ndof_QM, ndof_MM, temp
  real(dp)                            :: Q_QM_heavy, Q_QM_H
  integer, pointer                    :: thermostat_region_p(:)

  !Spline

  type spline_pot
    real(dp) :: from
    real(dp) :: to
    real(dp) :: dpot
  end type spline_pot

  type(spline_pot)                    :: my_spline
  real(dp)                            :: pot
  real(dp), pointer                   :: pot_p(:)

  !Output XYZ
  type(Inoutput)                      :: traj_xyz, latest_xyz
!  type(CInoutput)                      :: xyz
  character(len=FIELD_LENGTH)         :: backup_coord_file          !output XYZ file
  integer                             :: backup_i

  !Topology
  character(len=FIELD_LENGTH)         :: driver_PSF_Print
  integer                             :: Topology_Print_rate     !_-1_ never, 0 print one at the 0th time step and use that
                                                                 ! n>0 print at 0th and then every n-th step
  type(Table)                         :: intrares_impropers

  !Input parameters
  type(Dictionary)            :: params_in
  character(len=FIELD_LENGTH) :: Run_Type1               !_MM_, QS, QMMM_EXTENDED or QMMM_CORE
  character(len=FIELD_LENGTH) :: Run_Type2               !_NONE_, MM, or QMMM_CORE
  integer                     :: IO_Rate                 !print coordinates at every n-th step
  integer                     :: Thermostat_Type         !_0_ none, 1 Langevin
  character(len=FIELD_LENGTH) :: PSF_Print               !_NO_PSF_, DRIVER_AT_0, DRIVER_EVERY_#, USE_EXISTING_PSF
  real(dp)                    :: Time_Step
  real(dp)                    :: Equilib_Time
  real(dp)                    :: Run_Time
  real(dp)                    :: Inner_Buffer_Radius         !for hysteretic quantum
  real(dp)                    :: Outer_Buffer_Radius         !          region selection
  real(dp)                    :: Inner_QM_Region_Radius
  real(dp)                    :: Outer_QM_Region_Radius
  real(dp)                    :: Connect_Cutoff
  real(dp)                    :: Simulation_Temperature
  character(len=FIELD_LENGTH) :: coord_file
  character(len=FIELD_LENGTH) :: latest_coord_file          !output XYZ file
  character(len=FIELD_LENGTH) :: traj_file          !output XYZ file
  character(len=FIELD_LENGTH) :: qm_list_filename        !QM list file with a strange format
  type(Table)                 :: qm_seed
  character(len=FIELD_LENGTH) :: Residue_Library
  logical                     :: Use_Constraints         !_0_ no, 1 yes
  character(len=FIELD_LENGTH) :: constraint_file
  integer                     :: Charge
  real(dp)                    :: Tau
  logical                     :: Buffer_general, do_general
  logical                     :: Continue_it
  real(dp)                    :: avg_time
  integer                     :: Seed
  logical                     :: qm_region_pt_ctr
  integer                     :: qm_region_atom_ctr
  character(len=FIELD_LENGTH) :: print_prop
  real(dp)                    :: nneightol
  logical                     :: Delete_Metal_Connections
  real(dp)                    :: spline_from
  real(dp)                    :: spline_to
  real(dp)                    :: spline_dpot
  logical                     :: use_spline
  integer                     :: max_n_steps
  character(len=FIELD_LENGTH) :: cp2k_calc_args               ! other args to calc(cp2k,...)
  character(len=FIELD_LENGTH) :: filepot_program
  logical                     :: do_carve_cluster
  real(dp) :: qm_region_ctr(3)
  real(dp) :: use_cutoff

  logical :: distance_ramp
  real(dp) :: distance_ramp_inner_radius, distance_ramp_outer_radius
  character(len=128) :: weight_interpolation

  real(dp) :: max_move_since_calc_connect
  real(dp) :: calc_connect_buffer
type(inoutput) :: csilla_out
logical :: have_silica_potential
  integer :: stat

!    call system_initialise(verbosity=ANAL,enable_timing=.true.)
!    call system_initialise(verbosity=NERD,enable_timing=.true.)
    call system_initialise(verbosity=NORMAL,enable_timing=.true.)
    call system_timer('program')

    !INPUT
      call initialise(params_in)
      call param_register(params_in, 'Run_Type1', 'MM', Run_Type1)
      call param_register(params_in, 'Run_Type2', 'NONE', Run_Type2)
      call param_register(params_in, 'IO_Rate', '1', IO_Rate)
      call param_register(params_in, 'Thermostat_Type', '0', Thermostat_Type)
      call param_register(params_in, 'PSF_Print', 'NO_PSF', PSF_Print)
      call param_register(params_in, 'Time_Step', '0.5', Time_Step)
      call param_register(params_in, 'Equilib_Time', '0.0', Equilib_Time)
      call param_register(params_in, 'Run_Time', '0.5', Run_Time)
      call param_register(params_in, 'Inner_Buffer_Radius', '0.0', Inner_Buffer_Radius)
      call param_register(params_in, 'Outer_Buffer_Radius', '0.0', Outer_Buffer_Radius)
      call param_register(params_in, 'Inner_QM_Region_Radius', '0.0', Inner_QM_Region_Radius)
      call param_register(params_in, 'Outer_QM_Region_Radius', '0.0', Outer_QM_Region_Radius)
      call param_register(params_in, 'Connect_Cutoff', '0.0', Connect_cutoff)
      call param_register(params_in, 'Simulation_Temperature', '300.0', Simulation_Temperature)
      call param_register(params_in, 'coord_file', 'coord.xyz',coord_file) 
      call param_register(params_in, 'latest_coord_file', 'latest.xyz',latest_coord_file) 
      call param_register(params_in, 'traj_file', 'movie.xyz',traj_file) 
      qm_list_filename=''
      call param_register(params_in, 'qm_list_filename', '', qm_list_filename)
      call param_register(params_in, 'Residue_Library', 'all_res.CHARMM.lib',Residue_Library) 
      call param_register(params_in, 'Use_Constraints', 'F', Use_Constraints)
      call param_register(params_in, 'constraint_file', 'constraints.dat',constraint_file) 
      call param_register(params_in, 'Charge', '0', Charge)
      call param_register(params_in, 'Tau', '500.0', Tau)
      call param_register(params_in, 'Buffer_general', 'F', Buffer_general)
      call param_register(params_in, 'Continue', 'F', Continue_it)
      call param_register(params_in, 'avg_time', '100.0', avg_time)
      call param_register(params_in, 'Seed', '-1', Seed)
      call param_register(params_in, 'qm_region_pt_ctr', 'F', qm_region_pt_ctr)
      call param_register(params_in, 'qm_region_atom_ctr', '0', qm_region_atom_ctr)
      call param_register(params_in, 'print_prop', 'all', print_prop)
      call param_register(params_in, 'nneightol', '1.2', nneightol)
      call param_register(params_in, 'Delete_Metal_Connections', 'T', Delete_Metal_Connections)
      call param_register(params_in, 'spline_from', '0.0', spline_from)
      call param_register(params_in, 'spline_to', '0.0', spline_to)
      call param_register(params_in, 'spline_dpot', '0.0', spline_dpot)
      call param_register(params_in, 'use_spline', 'F', use_spline)
      call param_register(params_in, 'max_n_steps', '-1', max_n_steps)
      cp2k_calc_args=''
      call param_register(params_in, 'cp2k_calc_args', '', cp2k_calc_args)
      call param_register(params_in, 'filepot_program', param_mandatory, filepot_program)
      call param_register(params_in, 'carve_cluster', 'F', do_carve_cluster)
      call param_register(params_in, 'qm_region_ctr', '(/0.0 0.0 0.0/)', qm_region_ctr)
      call param_register(params_in, 'calc_connect_buffer', '0.2', calc_connect_buffer)
      call param_register(params_in, 'have_silica_potential', 'F', have_silica_potential)

      call param_register(params_in, 'distance_ramp', 'F', distance_ramp)
      call param_register(params_in, 'distance_ramp_inner_radius', '3.0', distance_ramp_inner_radius)
      call param_register(params_in, 'distance_ramp_outer_radius', '4.0', distance_ramp_outer_radius)

      if (.not. param_read_args(params_in, do_check = .true.)) then
        call system_abort('could not parse argument line')
      end if

      if (count((/qm_region_pt_ctr, qm_region_atom_ctr /= 0, len_trim(qm_list_filename) /= 0 /)) /= 1) then
	call system_abort("Need exactly one of qm_region_pt_ctr, qm_region_atom_ctr="//qm_region_atom_ctr//"/=0, len_trim(qm_list_filename='"//trim(qm_list_filename)//"') /= 0")
      endif

      if (Seed.gt.0) call system_reseed_rng(Seed)
!      call hello_world(seed, common_seed)

!check different run types
      Run_Type_array(1) ='QS'
      Run_Type_array(2) ='QMMM_EXTENDED'
      Run_Type_array(3) ='QMMM_CORE'
      Run_Type_array(4) ='MM'
      Run_Type_array(5) ='NONE'
      if (.not.any(Run_Type1.eq.Run_Type_array(1:4))) &
         call system_abort('Run_Type1 must be one of "QS", "MM", "QMMM_CORE", "QMMM_EXTENDED"')
      if (.not.any(Run_Type2.eq.Run_Type_array(3:5))) &
         call system_abort('Run_Type1 must be one of "NONE", "MM", "QMMM_CORE"')
      if ( (trim(Run_Type1).eq.trim(Run_Type2) .or. &
            any(trim(Run_Type1).eq.(/'MM','QS'/))) .and. &
          trim(Run_Type2).ne.'NONE' ) then
         Run_Type2 = 'NONE'
         call print('RunType2 set to NONE')
      endif
      if ((trim(Run_Type1)).eq.'QMMM_EXTENDED' .and..not.any(trim(Run_Type2).eq.Run_Type_array(3:5))) &
	call system_abort('Run_Type1 must be higher level of accuracy than Run_Type2')
      if ((trim(Run_Type1)).eq.'QMMM_CORE' .and..not.any(trim(Run_Type2).eq.Run_Type_array(4:5))) &
	call system_abort('Run_Type1 must be higher level of accuracy than Run_Type2')

!check PSF printing
      if (trim(PSF_Print) == 'NO_PSF' .or. trim(PSF_Print) == 'USE_EXISTING_PSF') then
	 topology_print_rate=-1
	 driver_PSF_Print=PSF_Print
      else if (trim(PSF_Print) == 'DRIVER_AT_0') then
	 topology_print_rate=0
      else if (len(PSF_Print) > 13) then
	 if (PSF_Print(1:13) == 'DRIVER_EVERY_') then
	    read(unit=PSF_Print(14:len_trim(PSF_Print)),fmt=*,iostat=stat) topology_print_rate
	    if (stat /= 0) &
	       call system_abort("PSF_Print='"//trim(PSF_Print)//"' unable to parse N from DRIVER_EVERY_N '"// &
	 	 PSF_Print(14:len_trim(PSF_Print))//"'")
	 else
	   call system_abort("Unknown PSF_Print '"//trim(PSF_Print)//"'")
	 endif
      else
	 call system_abort("Unknown PSF_Print '"//trim(PSF_Print)//"'")
      endif

      call finalise(params_in)

    !PRINT INPUT PARAMETERS
      call print('Run parameters:')
      call print('  filepot_program '//trim(filepot_program))
      call print('  Run_Type1 '//Run_Type1)
      call print('  Run_Type2 '//Run_Type2)
      call print('  IO_Rate '//IO_Rate)
      if (Thermostat_Type.eq.1) then
         call print('  Thermostat_Type '//'Langevin')
         call print('  Tau '//Tau)
      elseif (Thermostat_Type.eq.2) then
         call print('  Thermostat_Type: QM core & buffer atoms in the 1st thermostat')
         call print('                   classical O & H in the 3rd thermostat')
         call system_abort('no more used. Use Thermostat_Type=5 instead.')
      elseif (Thermostat_Type.eq.5) then
         call print('  Thermostat_Type: QM core & buffer heavy atoms in the 1st thermostat')
         call print('                   QM core & buffer H in the 2nd thermostat')
         call print('                   classical O & H in the 3rd thermostat')
      endif
      call print('  PSF_Print '//PSF_Print)
      call print('  nneightol '//nneightol)
      call print('  Time_Step '//round(Time_Step,3))
      call print('  Equilib_Time '//round(Equilib_Time,3))
      call print('  Run_Time '//round(Run_Time,3))
      call print('  max_n_steps '//max_n_steps)
      call print('  Inner_Buffer_Radius '//round(Inner_Buffer_Radius,3))
      call print('  Outer_Buffer_Radius '//round(Outer_Buffer_Radius,3))
      call print('! - not used any more -  Connect_Cutoff '//round(Connect_cutoff,3))
      call print('  Simulation_Temperature '//round(Simulation_Temperature,3))
      call print('  coord_file '//coord_file) 
      call print('  latest_coord_file '//latest_coord_file) 
      call print('  traj_file '//traj_file) 
      if (len_trim(qm_list_filename) /= 0) then
         call print('  qm_list_filename '//trim(qm_list_filename))
      else if (qm_region_pt_ctr .or. qm_region_atom_ctr /= 0) then
	 if (qm_region_pt_ctr) then
	   call print('  QM core is centred around qm_region_ctr= '//qm_region_ctr)
	 else
	   call print('  QM core is centred around atom '//qm_region_atom_ctr)
	   qm_region_pt_ctr = .true.
	 endif
         call print('  Inner_QM_Region_Radius '//round(Inner_QM_Region_Radius,3))
         call print('  Outer_QM_Region_Radius '//round(Outer_QM_Region_Radius,3))
         call print('  use_spline '//use_spline)
         if (use_spline) then
            call print('  spline_from '//spline_from)
            call print('  spline_to '//spline_to)
            call print('  spline_dpot '//spline_dpot)
           ! initialise spline
            my_spline%from = spline_from
            my_spline%to = spline_to
            my_spline%dpot = spline_dpot
         endif
      endif
      call print('  Residue_Library '//Residue_Library) 
      call print('  Use_Constraints '//Use_Constraints)
      call print('  constraint_file '//constraint_file) 
      call print('  Charge '//Charge)
      call print('  Buffer_general '//Buffer_general)
      call print('  Continue '//Continue_it)
      call print('  avg_time '//avg_time)
      call print('  Seed '//Seed)
      call print('  Properties to print '//trim(print_prop))
      call print('  carve_cluster '//do_carve_cluster)
      call print('  have_silica_potential '//have_silica_potential)
      call print('---------------------------------------')
      call print('')

! STARTS HERE

    if (is_file_readable(trim(traj_file))) then
      call print("WARNING: traj_file " // trim(traj_file) // " exists, backing it up")
      backup_i=1
      backup_coord_file=trim(traj_file)//".backup_"//backup_i
      do while (is_file_readable(trim(backup_coord_file)))
	backup_i = backup_i + 1
	backup_coord_file=trim(traj_file)//".backup_"//backup_i
      end do
      call print("WARNING:      to backup_coord_file " // trim(backup_coord_file))
      call system("cp "//trim(traj_file)//" "//trim(backup_coord_file))
    endif

    call initialise(traj_xyz,traj_file,action=OUTPUT)
  
  !READ COORDINATES AND CONSTRAINTS

    call print('Reading in the coordinates from file '//trim(coord_file)//'...')
    call read_xyz(my_atoms,coord_file)
!    call read(my_atoms,coord_file)

    N_constraints = 0
    if (Use_Constraints) then
       call print('Reading in the constraints from file '//trim(constraint_file)//'...')
       call read_constraints_bond_diff(my_atoms,constraints,trim(constraint_file))
       N_constraints = constraints%N
    endif

    call initialise(ds,my_atoms,constraints=N_constraints)
    if (Continue_it) then
      if (get_value(my_atoms%params,'Time',ds%t)) then
	  call print('Found Time in atoms%params'//ds%t)
      endif
    endif

  !THERMOSTAT

    ds%avg_time = avg_time
    if (Thermostat_Type.eq.1) then
       call add_thermostat(ds,type=LANGEVIN,T=Simulation_Temperature,tau=Tau)
       call print('Langevin Thermostat added')
    elseif (Thermostat_Type.eq.2) then
      !ndof is the estimated number of atoms in the QM zone (= core + buffer)
       call print('Cell_volume: '//cell_volume(ds%atoms))
       call print('Number of atoms: '//ds%atoms%N)
       call print('Estimated volume of QM zone: '//(4._dp * ( (Inner_QM_Region_Radius + Outer_QM_Region_Radius + Inner_Buffer_Radius + Outer_Buffer_Radius) * 0.5_dp )**3._dp * PI / 3._dp ))
       ndof_QM = nint(4._dp * ( (Inner_QM_Region_Radius + Outer_QM_Region_Radius + Inner_Buffer_Radius + Outer_Buffer_Radius) * 0.5_dp )**3._dp * PI / 3._dp * real(ds%atoms%N,dp) / cell_volume(ds%atoms)) * 3
       call print('density: '//(real(ds%atoms%N,dp)/cell_volume(ds%atoms)))
       ndof_MM = 3._dp * ds%atoms%N - ndof_QM
       call print('Estimated ndof QM: '//ndof_QM)
       call print('Estimated ndof MM: '//ndof_MM)
       Q_QM = nose_hoover_mass(Ndof=ndof_QM,T=Simulation_Temperature,tau=74._dp)
       Q_MM = nose_hoover_mass(Ndof=ndof_MM,T=Simulation_Temperature,tau=74._dp)
       call add_thermostat(ds,type=NOSE_HOOVER,T=Simulation_Temperature,Q=Q_QM,gamma=0._dp)
       call add_thermostat(ds,type=NOSE_HOOVER_LANGEVIN,T=Simulation_Temperature,tau=Tau,Q=Q_MM)
    elseif (Thermostat_Type.eq.5) then
      !ndof is the estimated number of atoms in the QM zone (= core + buffer)
       call print('Cell_volume: '//cell_volume(ds%atoms))
       call print('Number of atoms: '//ds%atoms%N)
       call print('Estimated volume of QM zone: '//(4._dp * ( (Inner_QM_Region_Radius + Outer_QM_Region_Radius + Inner_Buffer_Radius + Outer_Buffer_Radius) * 0.5_dp )**3._dp * PI / 3._dp ))
       ndof_QM = nint(4._dp * ( (Inner_QM_Region_Radius + Outer_QM_Region_Radius + Inner_Buffer_Radius + Outer_Buffer_Radius) * 0.5_dp )**3._dp * PI / 3._dp * real(ds%atoms%N,dp) / cell_volume(ds%atoms)) * 3
       call print('density: '//(real(ds%atoms%N,dp)/cell_volume(ds%atoms)))
       ndof_MM = 3._dp * ds%atoms%N - ndof_QM
       call print('Estimated ndof QM: '//ndof_QM)
       call print('     out of which ndof QM heavy atom: '//(ndof_QM/3.0_dp))
       call print('     out of which ndof QM H: '//(ndof_QM*2.0_dp/3.0_dp))
       call print('Estimated ndof MM: '//ndof_MM)
       Q_QM_heavy = nose_hoover_mass(Ndof=(ndof_QM/3.0_dp),T=Simulation_Temperature,tau=74._dp)
       Q_QM_H = nose_hoover_mass(Ndof=(ndof_QM*2.0_dp/3.0_dp),T=Simulation_Temperature,tau=74._dp)
       Q_MM = nose_hoover_mass(Ndof=ndof_MM,T=Simulation_Temperature,tau=74._dp)
       call add_thermostat(ds,type=NOSE_HOOVER,T=Simulation_Temperature,Q=Q_QM_heavy,gamma=0._dp)
       call add_thermostat(ds,type=NOSE_HOOVER,T=Simulation_Temperature,Q=Q_QM_H,gamma=0._dp)
       call add_thermostat(ds,type=NOSE_HOOVER_LANGEVIN,T=Simulation_Temperature,tau=Tau,Q=Q_MM)
    endif
    call finalise(my_atoms)
    call add_property(ds%atoms,'pot',0._dp) ! always do this, it's just 0 if spline isn't active - no need to change print_props

  !SET CONSTRAINTS

    if (Use_Constraints) then
       do i=1,constraints%N
          call Constrain_Bond_Diff(ds,constraints%int(1,i),constraints%int(2,i),constraints%int(3,i))
          call print('Set constraint: '//constraints%int(1,i)//' -- '//constraints%int(2,i)//' -- '//constraints%int(3,i))
!          call Constrain_Bond(ds,constraints%int(1,i),constraints%int(2,i))
!          call print('Set constraint: '//constraints%int(1,i)//' -- '//constraints%int(2,i))
          check = distance_min_image(ds%atoms,constraints%int(1,i),constraints%int(2,i)) - &
                  distance_min_image(ds%atoms,constraints%int(2,i),constraints%int(3,i))
          call print('constrained bond length diff: '//round(check,10))
       enddo
    endif

  !SET VELOCITIES

    if (.not.Continue_it) then
       call rescale_velo(ds,Simulation_Temperature)
    endif

  !CALC. CONNECTIONS

!    call set_cutoff(ds%atoms,Connect_Cutoff)
!    call set_cutoff(ds%atoms,0._dp) !use the covalent radii to determine bonds
    use_cutoff = max(nneightol, Outer_Buffer_Radius)
    use_cutoff = max(use_cutoff, Outer_QM_Region_Radius)
    if (have_silica_potential) then
	use_cutoff = max(SILICA_2BODY_CUTOFF, Outer_Buffer_Radius)
    endif
    call set_cutoff(ds%atoms,use_cutoff+calc_connect_buffer)
    call calc_connect(ds%atoms)
    if (Delete_Metal_Connections) call delete_metal_connects(ds%atoms)

  !READ / CREATE QM LIST + THERMOSTATTING

   !QM BUFFER + THERMOSTATTING
      ! set general/heavy atom selection before QM region selection
       call set_value(ds%atoms%params,'Buffer_general',Buffer_general)
       call print('set Buffer_general into ds%atoms%params')
       if (get_value(ds%atoms%params,'Buffer_general',do_general)) then
           call print('Found Buffer_general in atoms%params'//do_general)
           buffer_general=do_general
       else
           call print('Not found Buffer_general in atoms%params')
           buffer_general=.false.
       endif

   !QM CORE
    if ((trim(Run_Type1).eq.'QMMM_CORE') .or. &
        (trim(Run_Type1).eq.'QMMM_EXTENDED')) then
       if (.not.Continue_it) then
	  call add_property(ds%atoms,'hybrid',HYBRID_NO_MARK)
	  call add_property(ds%atoms,'hybrid_mark',HYBRID_NO_MARK)
	  call add_property(ds%atoms,'old_hybrid_mark',HYBRID_NO_MARK)
	  call add_property(ds%atoms,'cluster_mark',HYBRID_NO_MARK)
	  call add_property(ds%atoms,'old_cluster_mark',HYBRID_NO_MARK)
	  call add_property(ds%atoms, 'cut_bonds', 0, n_cols=4) !MAX_CUT_BONDS)
          if (qm_region_pt_ctr) then
             call map_into_cell(ds%atoms)
             call calc_dists(ds%atoms)
	     if (qm_region_atom_ctr /= 0) qm_region_ctr = ds%atoms%pos(:,qm_region_atom_ctr)
             call create_pos_or_list_centred_hybrid_region(ds%atoms,Inner_QM_Region_Radius,Outer_QM_Region_Radius,origin=qm_region_ctr,add_only_heavy_atoms=(.not. buffer_general),list_changed=list_changed1)
!!!!!!!!!
!call initialise(csilla_out,filename='csillaQM.xyz',ACTION=OUTPUT,append=.true.)
!call print_xyz(ds%atoms,xyzfile=csilla_out,properties="species:pos:hybrid:hybrid_mark")
!call finalise(csilla_out)
!!!!!!!!!
!stop

             if (list_changed1) then
                call print('Core has changed')
                ! do nothing: both core and buffer belong to the QM of QM/MM
!               call set_value(ds%atoms%params,'QM_core_changed',list_changed1)
             endif
          else ! qm_region_pt_ctr
             call read_qmlist(ds%atoms,qm_list_filename,qmlist=qm_seed)
	     if (.not.(assign_pointer(ds%atoms, "hybrid_mark", hybrid_mark_p))) call system_abort('??')
	     if (.not.(assign_pointer(ds%atoms, "cluster_mark", cluster_mark_p))) call system_abort('??')
	     call print('hybrid_mark'//count(hybrid_mark_p.eq.1))
	     cluster_mark_p = hybrid_mark_p
	     call print('cluster_mark'//count(cluster_mark_p.eq.1))

             !save the qm list into qm_seed property, too
             !in case we want to change the seed in time
             !call add_property(my_atoms,'qm_seed',0)
	     !if (.not.(assign_pointer(ds%atoms, "qm_seed", qm_seed_p))) call system_abort('??')
	     !if (.not.(assign_pointer(ds%atoms, "hybrid_mark", hybrid_mark_p))) call system_abort('??')
	     !qm_seed_p = hybrid_mark_p

             !extend QM core around seed atoms
             call create_pos_or_list_centred_hybrid_region(ds%atoms,Inner_QM_Region_Radius,Outer_QM_Region_Radius,atomlist=qm_seed,add_only_heavy_atoms=(.not. buffer_general),nneighb_only=.false.,min_images_only=.true.,list_changed=list_changed1)
!             call construct_hysteretic_region(region=core,at=ds%atoms,core=seed,loop_atoms_no_connectivity=.false., &
!                  inner_radius=Inner_QM_Region_Radius,outer_radius=Outer_QM_Region_Radius, use_avgpos=.false., add_only_heavy_atoms=(.not.buffer_general), &
!                  nneighb_only=.false., min_images_only=.true.)
          endif ! qm_region_pt_ctr
          call print('hybrid, hybrid_mark and old_hybrid_mark properties added')
       endif ! .not. Continue_it

    endif
    call map_into_cell(ds%atoms)
    call calc_dists(ds%atoms)

  !TOPOLOGY

   ! topology calculation
    if (trim(Run_Type1).ne.'QS') then
!       if (.not.Continue_it) then
          call set_value(ds%atoms%params,'Library',trim(Residue_Library))
          temp = ds%atoms%nneightol
          ds%atoms%nneightol = nneightol
	  call map_into_cell(ds%atoms)
	  call calc_dists(ds%atoms)
          call create_residue_labels(ds%atoms,do_CHARMM=.true.,intrares_impropers=intrares_impropers)
          call check_topology(ds%atoms)
          ds%atoms%nneightol = temp
!       endif
    endif

  !CHARGE

    if (trim(Run_Type1).eq.'QS') then
       call set_value(ds%atoms%params,'Charge',Charge)
    endif

  !PRINTING
     !----------------------------------------------------
    call set_value(ds%atoms%params,'Time',ds%t)
    if (trim(print_prop).eq.'all') then
        call print_xyz(ds%atoms,traj_xyz,all_properties=.true.,real_format='f17.10')
    else
        call print_xyz(ds%atoms,traj_xyz,properties=trim(print_prop),real_format='f17.10')
    endif
    call initialise(latest_xyz,trim(latest_coord_file)//".new",action=OUTPUT)
    call print_xyz(ds%atoms,latest_xyz,all_properties=.true.,real_format='f17.10')
    call finalise(latest_xyz)
    call system("mv "//trim(latest_coord_file)//".new "//trim(latest_coord_file))
     !----------------------------------------------------

  !INIT. METAPOTENTIAL

    !only QMMM_EXTENDED for the moment **************
    !if (trim(Run_Type1).ne.'QMMM_EXTENDED') call system_abort('ONLY QMMM_EXTENDED')

    ! set up metapot
    if (trim(Run_Type2) == 'NONE') then ! no force mixing
       call setup_pot(cp2k_slow_pot, Run_Type1, filepot_program)
       call initialise(metapot,args_str='Simple=T',pot=CP2K_slow_pot)
       ! set up mm only metapot, in case we need it for empty QM core
       call setup_pot(cp2k_fast_pot, 'MM', filepot_program)
       call initialise(empty_qm_metapot,args_str='Simple=T',pot=CP2K_fast_pot)
    else ! doing force mixing
       call setup_pot(cp2k_slow_pot, Run_Type1, filepot_program)
       call setup_pot(cp2k_fast_pot, Run_Type2, filepot_program)
       if (distance_ramp) then
	 if (.not. qm_region_pt_ctr) call system_abort("Distance ramp needs qm_region_pt_ctr (or qm_region_atom_ctr)")
	 weight_interpolation='distance_ramp'
       else
	 weight_interpolation='hop_ramp'
       endif
       call initialise(metapot,args_str='ForceMixing=T use_buffer_for_fitting=T add_cut_H_in_fitlist=T'// &
	  ' method=conserve_momentum conserve_momentum_weight_method=mass calc_weights=T'// &
	  ' min_images_only=F nneighb_only=F lotf_nneighb_only=F fit_hops=1 hysteretic_buffer=T'// &
	  ' hysteretic_buffer_inner_radius='//Inner_Buffer_Radius// &
	  ' hysteretic_buffer_outer_radius='//Outer_Buffer_Radius// &
	  ' weight_interpolation='//trim(weight_interpolation)// &
	  ' distance_ramp_inner_radius='//distance_ramp_inner_radius//' distance_ramp_outer_radius='//distance_ramp_outer_radius// &
	  ' single_cluster=T little_clusters=F carve_cluster='//do_carve_cluster &
!next line is for playing with silica carving
!          //' even_electrons=T terminate=T cluster_same_lattice=T termination_clash_check=T' &
	  //' construct_buffer_use_only_heavy_atoms='//(.not.(buffer_general)), &
	  pot=CP2K_fast_pot, pot2=CP2K_slow_pot)

       ! if Run_Type2 = QMMM_CORE, we'll crash if QM core is ever empty
       if (trim(Run_Type2) == 'MM') then
	 call initialise(empty_qm_metapot,args_str='Simple=T',pot=CP2K_fast_pot)
       endif
    endif

    !allocate force lists
    allocate(f0(3,ds%N),f1(3,ds%N),f(3,ds%N))

!FIRST STEP - first step of velocity verlet

    call system_timer('step')

     n = 0

  !FORCE

     if (topology_print_rate >= 0) driver_PSF_Print='DRIVER_PRINT_AND_SAVE'
     call do_calc_call(metapot, empty_qm_metapot, ds%atoms, Run_Type1, Run_Type2, qm_region_pt_ctr, &
       distance_ramp, qm_region_ctr, cp2k_calc_args, do_carve_cluster, driver_PSF_Print, f1, energy)
     if (topology_print_rate >= 0) driver_PSF_Print='USE_EXISTING_PSF'

     !spline force calculation, if needed
     if (qm_region_pt_ctr.and.use_spline) then
        allocate(add_force(1:3,1:ds%atoms%N))
	call verbosity_push_decrement()
	  call print('Force due to added spline potential (eV/A):')
	  call print('atom     F(x)     F(y)     F(z)')
          if (.not.(assign_pointer(ds%atoms, "pot", pot_p))) &
             call system_abort("couldn't find pot property")
	  do i = 1, ds%atoms%N
	     add_force(1:3,i) = spline_force(ds%atoms,i,my_spline, pot=pot)
	     pot_p(i) = pot
	     call print('  '//i//'    '//round(add_force(1,i),5)//'  '//round(add_force(2,i),5)//'  '//round(add_force(3,i),5))
	  enddo
	call verbosity_pop()
        call print('Sum of the forces: '//sum(add_force(1,1:ds%atoms%N))//' '//sum(add_force(2,1:ds%atoms%N))//' '//sum(add_force(3,1:ds%atoms%N)))
        f = sumBUFFER(f1+add_force,ds%atoms,my_spline)
        deallocate(add_force)
     else
        f = sum0(f1,ds%atoms)
     endif

  !PRINT DS,CONSTRAINT

     call ds_print_status(ds, 'E',energy)
     call print(ds%thermostat)
     if (Use_Constraints) then
        call print(ds%constraint)
        do i=1,constraints%N
           TI_force = force_on_collective_variable(ds%atoms,(/f(1:3,constraints%int(1,i)),f(1:3,constraints%int(2,i)),f(1:3,constraints%int(3,i))/),constraints%int(1:3,i), TI_corr, check)
           call print('constrained bond length diff: '//round(check,10))
           call print('force on colvar '//i//' :'//round(TI_force,10)//' '//round(TI_corr,10))
        enddo
     endif

!NB do i=1,ds%atoms%N
!NB      call print('FFF '//f(1,i)//' '//f(2,i)//' '//f(3,i))
!NB enddo

  !THERMOSTATTING now - hybrid_mark was updated only in calc
       if (trim(Run_Type1).eq.'QMMM_EXTENDED') then
          if (Thermostat_Type.eq.2) then !match thermostat_region to cluster_mark property
!             if (.not.(assign_pointer(ds%atoms, "hybrid_mark", qm_flag_p))) &
             if (.not.(assign_pointer(ds%atoms, "cluster_mark", qm_flag_p))) &
!                call system_abort("couldn't find hybrid_mark property")
                call system_abort("couldn't find cluster_mark property")
             if (.not.(assign_pointer(ds%atoms, "thermostat_region", thermostat_region_p))) &
                call system_abort("couldn't find thermostat_region property")
             do i=1,ds%atoms%N
                select case(qm_flag_p(i))
                   case(HYBRID_NO_MARK, HYBRID_TERM_MARK)
                     thermostat_region_p(i) = 2
                   case(HYBRID_ACTIVE_MARK, HYBRID_BUFFER_MARK)
                     thermostat_region_p(i) = 1
                   case default
!                     call system_abort('Unknown hybrid_mark '//qm_flag_p(i))
                     call system_abort('Unknown cluster_mark '//qm_flag_p(i))
                end select
             enddo
          elseif (Thermostat_Type.eq.5) then !match thermostat_region to cluster_mark property
             if (.not.(assign_pointer(ds%atoms, "cluster_mark", qm_flag_p))) &
                call system_abort("couldn't find cluster_mark property")
             if (.not.(assign_pointer(ds%atoms, "thermostat_region", thermostat_region_p))) &
                call system_abort("couldn't find thermostat_region property")
             do i=1,ds%atoms%N
                select case(qm_flag_p(i))
                   case(HYBRID_NO_MARK, HYBRID_TERM_MARK)
                     thermostat_region_p(i) = 3
                   case(HYBRID_ACTIVE_MARK, HYBRID_BUFFER_MARK)
                     if (ds%atoms%Z(i).eq.1) then !QM or buffer H
                        thermostat_region_p(i) = 2
                     else !QM or buffer heavy atom
                        thermostat_region_p(i) = 1
                     endif
                   case default
                     call system_abort('Unknown cluster_mark '//qm_flag_p(i))
                end select
             enddo
          else
            ! all atoms are in thermostat 1 by default
          endif
       endif

  !ADVANCE VERLET 1

     call advance_verlet1(ds, Time_Step, f)

  !PRINT XYZ

     call set_value(ds%atoms%params,'Time',ds%t)
     if (trim(print_prop).eq.'all') then
         call print_xyz(ds%atoms,traj_xyz,all_properties=.true.,real_format='f17.10')
!         call write(ds%atoms,xyz,real_format='%17.10f')
     else
         call print_xyz(ds%atoms,traj_xyz,properties=trim(print_prop),real_format='f17.10')
!         call write(ds%atoms,xyz,real_format='%17.10f')
         !call write(ds%atoms,xyz,properties=trim(print_prop),real_format='%17.10f')
     endif
     call initialise(latest_xyz,trim(latest_coord_file)//".new",action=OUTPUT)
     call print_xyz(ds%atoms,latest_xyz,all_properties=.true.,real_format='f17.10')
     call finalise(latest_xyz)
     call system("mv "//trim(latest_coord_file)//".new "//trim(latest_coord_file))

    call system_timer('step')

!LOOP - force calc, then VV-2, VV-1

  ! keep track of how far atoms could have moved
  max_move_since_calc_connect = 0.0_dp
  do while (ds%t < (Equilib_Time + Run_Time) .and. ((max_n_steps < 0) .or. (n < (max_n_steps-1))))

    max_move_since_calc_connect = max_move_since_calc_connect + Time_Step* maxval(abs(ds%atoms%velo))
    ! max distance atom could have moved is about max_move_since_calc_connect
    ! 2.0 time that is max that interatomic distance could have changed
    ! another factor of 1.5 to account for inaccuracy in max_move_since_calc_connect (because atoms really move a distance dependent on both velo and higher derivatives like acc)
    if (max_move_since_calc_connect*2.0_dp*1.5_dp >= calc_connect_buffer) then
      call system_timer("calc_connect")
      call calc_connect(ds%atoms)
      if (Delete_Metal_Connections) call delete_metal_connects(ds%atoms)
      max_move_since_calc_connect = 0.0_dp
      call system_timer("calc_connect")
    endif

    call system_timer('step')
     n = n + 1

  !QM CORE + BUFFER UPDATE + THERMOSTAT REASSIGNMENT

     if (trim(Run_Type1).eq.'QMMM_EXTENDED') then
        if (qm_region_pt_ctr) then
	   if (qm_region_atom_ctr /= 0) qm_region_ctr = ds%atoms%pos(:,qm_region_atom_ctr)
           call create_pos_or_list_centred_hybrid_region(ds%atoms,Inner_QM_Region_Radius,Outer_QM_Region_Radius,origin=qm_region_ctr,add_only_heavy_atoms=(.not. buffer_general),list_changed=list_changed1)
           if (list_changed1) then
              call print('Core has changed')
!             call set_value(ds%atoms%params,'QM_core_changed',list_changed)
              ! do nothing: both core and buffer belong to the QM of QM/MM
           endif
        else !qm_region_pt_ctr
           !extend QM core around seed atoms
             call create_pos_or_list_centred_hybrid_region(ds%atoms,Inner_QM_Region_Radius,Outer_QM_Region_Radius,atomlist=qm_seed,add_only_heavy_atoms=(.not. buffer_general),nneighb_only=.false.,min_images_only=.true.,list_changed=list_changed1)
        endif
     endif

  !FORCE

     if (Topology_Print_rate > 0) then !every #th step
        if (mod(n,Topology_Print_rate) == 0) then    !recalc connectivity & generate PSF (at every n-th step) and then use it
           driver_PSF_Print = 'DRIVER_PRINT_AND_SAVE'
	else
           driver_PSF_Print = 'USE_EXISTING_PSF'
        endif
     endif
     call do_calc_call(metapot, empty_qm_metapot, ds%atoms, Run_Type1, Run_Type2, qm_region_pt_ctr, &
       distance_ramp, qm_region_ctr, cp2k_calc_args, do_carve_cluster, driver_PSF_Print, f1, energy)

    !SPLINE force calculation, if needed
     if (qm_region_pt_ctr.and.use_spline) then
	call verbosity_push_decrement()
	  call print('Force due to added spline potential (eV/A):')
	  call print('atom     F(x)     F(y)     F(z)')
	  allocate(add_force(1:3,1:ds%atoms%N))
          if (.not.(assign_pointer(ds%atoms, "pot", pot_p))) &
             call system_abort("couldn't find pot property")
	  do i = 1, ds%atoms%N
	     add_force(1:3,i) = spline_force(ds%atoms,i,my_spline, pot=pot)
	     pot_p(i) = pot
	     call print('  '//i//'    '//round(add_force(1,i),5)//'  '//round(add_force(2,i),5)//'  '//round(add_force(3,i),5))
	  enddo
	call verbosity_pop()
        call print('Sum of the forces: '//sum(add_force(1,1:ds%atoms%N))//' '//sum(add_force(2,1:ds%atoms%N))//' '//sum(add_force(3,1:ds%atoms%N)))
        f = sumBUFFER(f1+add_force,ds%atoms,my_spline)
        deallocate(add_force)
     else
        f = sum0(f1,ds%atoms)
     endif

do i=1,ds%atoms%N
     call print('FFF '//f(1,i)//' '//f(2,i)//' '//f(3,i))
enddo

  !THERMOSTATTING now - hybrid_mark was updated only in calc
       if (trim(Run_Type1).eq.'QMMM_EXTENDED') then
          if (Thermostat_Type.eq.2) then !match thermostat_region to QM_flag property
!             if (.not.(assign_pointer(ds%atoms, "hybrid_mark", qm_flag_p))) &
             if (.not.(assign_pointer(ds%atoms, "cluster_mark", qm_flag_p))) &
!                call system_abort("couldn't find hybrid_mark property")
                call system_abort("couldn't find cluster_mark property")
             if (.not.(assign_pointer(ds%atoms, "thermostat_region", thermostat_region_p))) &
                call system_abort("couldn't find thermostat_region property")
             do i=1,ds%atoms%N
                select case(qm_flag_p(i))
                   case(HYBRID_NO_MARK, HYBRID_TERM_MARK)
                     thermostat_region_p(i) = 2
                   case(HYBRID_ACTIVE_MARK, HYBRID_BUFFER_MARK)
                     thermostat_region_p(i) = 1
                   case default
!                     call system_abort('Unknown hybrid_mark '//qm_flag_p(i))
                     call system_abort('Unknown cluster_mark '//qm_flag_p(i))
                end select
             enddo
          elseif (Thermostat_Type.eq.5) then !match thermostat_region to cluster_mark property
             if (.not.(assign_pointer(ds%atoms, "cluster_mark", qm_flag_p))) &
                call system_abort("couldn't find cluster_mark property")
             if (.not.(assign_pointer(ds%atoms, "thermostat_region", thermostat_region_p))) &
                call system_abort("couldn't find thermostat_region property")
             do i=1,ds%atoms%N
                select case(qm_flag_p(i))
                   case(HYBRID_NO_MARK, HYBRID_TERM_MARK)
                     thermostat_region_p(i) = 3
                   case(HYBRID_ACTIVE_MARK, HYBRID_BUFFER_MARK)
                     if (ds%atoms%Z(i).eq.1) then !QM or buffer H
                        thermostat_region_p(i) = 2
                     else !QM or buffer heavy atom
                        thermostat_region_p(i) = 1
                     endif
                   case default
                     call system_abort('Unknown cluster_mark '//qm_flag_p(i))
                end select
             enddo
          else
            ! all atoms are in thermostat 1 by default
          endif
       endif

  !ADVANCE VERLET 2

     call advance_verlet2(ds, Time_Step, f)

  !PRINT DS,THERMOSTAT,CONSTRAINT,XYZ

     if (ds%t < Equilib_Time) then
        call ds_print_status(ds, 'E',energy)
     else
        call ds_print_status(ds, 'I',energy)
     end if

     !Thermostat
     call print(ds%thermostat)

     !Constraint
     if (Use_Constraints) then
        call print(ds%constraint)
        do i=1,constraints%N
           TI_force = force_on_collective_variable(ds%atoms,(/f(1:3,constraints%int(1,i)),f(1:3,constraints%int(2,i)),f(1:3,constraints%int(3,i))/),constraints%int(1:3,i), TI_corr, check)
           call print('constrained bond length diff: '//round(check,10))
           call print('force on colvar '//i//' :'//round(TI_force,10)//' '//round(TI_corr,10))
        enddo
     endif

     !XYZ
     if (mod(n,IO_Rate)==0) then
        call set_value(ds%atoms%params,'Time',ds%t)
        if (trim(print_prop).eq.'all') then
            call print_xyz(ds%atoms,traj_xyz,all_properties=.true.,real_format='f17.10')
!            call write(ds%atoms,xyz,real_format='%17.10f')
        else
            call print_xyz(ds%atoms,traj_xyz,properties=trim(print_prop),real_format='f17.10')
!            call write(ds%atoms,xyz,real_format='%17.10f')
            !call write(ds%atoms,xyz,properties=trim(print_prop),real_format='%17.10f')
        endif
        call initialise(latest_xyz,trim(latest_coord_file)//".new",action=OUTPUT)
        call print_xyz(ds%atoms,latest_xyz,all_properties=.true.,real_format='f17.10')
        call finalise(latest_xyz)
        call system("mv "//trim(latest_coord_file)//".new "//trim(latest_coord_file))
     end if
     
  !ADVANCE VERLET 1

     call advance_verlet1(ds, Time_Step, f)

     call system_timer('step')

  enddo

  deallocate(f,f0,f1)

  call finalise(qm_seed)
  call finalise(ds)
  call finalise(traj_xyz)

  call finalise(metapot)
  call finalise(empty_qm_metapot)
  call finalise(CP2K_slow_pot)
  call finalise(CP2K_fast_pot)

  call print_title('THE')
  call print('Finished. CP2K is now having a rest, since deserved it. Bye-Bye!')
  call print_title('END')

  call system_timer('program')
  call system_finalise

contains

  subroutine read_constraints_bond_diff(my_atoms,constraints,constraint_file)

    type(Atoms), intent(in) :: my_atoms
    type(Table), intent(out) :: constraints
    character(len=*), intent(in) :: constraint_file
    type(InOutput) :: cons
    integer :: n, num_constraints, cons_a, cons_b,cons_c

       call initialise(cons,trim(constraint_file),action=INPUT)
       read (cons%unit,*) num_constraints
       call allocate(constraints,3,0,0,0,num_constraints)
       do n=1,num_constraints
          cons_a = 0
          cons_b = 0
          cons_c = 0
          read (cons%unit,*) cons_a,cons_b, cons_c
          call append(constraints,(/cons_a,cons_b,cons_c/))
       enddo
       if (constraints%N.ne.num_constraints) call system_abort('read_constraint: Something wrong with the constraints file')
    if (any(constraints%int(1:2,1:constraints%N).gt.my_atoms%N).or.any(constraints%int(1:2,1:constraints%N).lt.1)) &
       call system_abort("read_constraints: Constraint atom(s) is <1 or >"//my_atoms%N)
       call finalise(cons)

  end subroutine read_constraints_bond_diff

  function force_on_collective_variable(my_atoms,frc,at123,F_corr,lambda) result(F_lambda)

    type(Atoms),            intent(in)  :: my_atoms
    real(dp), dimension(9), intent(in)  :: frc
    integer,  dimension(3), intent(in)  :: at123
    real(dp), optional,     intent(out) :: F_corr         ! the metric tensor correction
    real(dp), optional,     intent(out) :: lambda         ! the metric tensor correction
    real(dp)                            :: F_lambda       ! the force on the bondlength difference

    real(dp) :: d              ! the bondlength difference
    real(dp) :: DD             ! the bondlength sum
    real(dp) :: d_12(3), d12   ! the 1>2 bond vector and its norm
    real(dp) :: d_23(3), d23   ! the 2>3 bond vector and its norm
    integer  :: a1, a2, a3     ! the 3 atoms a1-a2-a3
    real(dp) :: F_1(3), F_2(3), F_3(3)   ! the force on  the 3 atoms

     a1 = at123(1)
     a2 = at123(2)
     a3 = at123(3)

     F_1(1:3) = frc(1:3)
     F_2(1:3) = frc(4:6)
     F_3(1:3) = frc(7:9)

     d_12 = diff_min_image(my_atoms,a1,a2)
     d_23 = diff_min_image(my_atoms,a2,a3)
     d12 = distance_min_image(my_atoms,a1,a2)
     d23 = distance_min_image(my_atoms,a2,a3)

     if (abs(sqrt(dot_product(d_12,d_12))-d12).gt.0.000001_dp .or. &
         abs(sqrt(dot_product(d_23,d_23))-d23).gt.0.000001_dp) then
        call print(sqrt(dot_product(d_12,d_12))//' '//d12)
        call print(sqrt(dot_product(d_23,d_23))//' '//d23)
        call system_abort('wrong realpos')
     endif

!    ! calc. F_lambda from bondlength forces - not good
!     F_d12 = dot_product((F_1(1:3)*m_2-F_2(1:3)*m_1),(-d_12(1:3))) / ((m_1+m_2)*d12)
!     F_d23 = dot_product((F_2(1:3)*m_3-F_3(1:3)*m_2),(-d_23(1:3))) / ((m_2+m_3)*d23)
!     F_lambda = F_d12 - F_d23

     F_lambda = dot_product(F_1(1:3),-d_12(1:3)) / (2._dp*d12) - &
                dot_product(F_3(1:3),d_23(1:3)) / (2._dp*d23)

     !calc. metric tensor correction
     d = d12 - d23
     DD = d12 + d23
     if (present(F_corr)) &
        F_corr = 4 * BOLTZMANN_K * 300 * DD / (DD*DD-d*d)

     if (present(lambda)) lambda = d

  end function force_on_collective_variable

! for QM/MM and MM runs, to check water topology
  subroutine check_topology(my_atoms)

    type(Atoms), intent(in)      :: my_atoms
  
    integer                                 :: i, N
    logical                                 :: do_mm
    integer,                        pointer :: qm_flag_p(:)
    character(TABLE_STRING_LENGTH), pointer :: atom_res_name_p(:)

    do_mm = .false.

    if (.not.(assign_pointer(my_atoms, "hybrid_mark", qm_flag_p))) then ! MM RUN
       do_mm = .true.
    end if

    if (.not.(assign_pointer(my_atoms, "atom_res_name", atom_res_name_p))) &
       call system_abort("couldn't find atom_res_name property")

    if (do_mm) then
       do i=1, my_atoms%N
          if ( ('H3O'.eq.trim(atom_res_name_p(i))) .or. &
               ('HYD'.eq.trim(atom_res_name_p(i))) .or. &
               ('HWP'.eq.trim(atom_res_name_p(i))) ) then
             call system_abort('wrong topology calculated')
          endif
       enddo
    else
       N = 0
       do i=1,my_atoms%N
          if ( .not.(qm_flag_p(i).eq.1) .and. &
!          if ( .not.any((qm_flag_p(i).eq.(/1,2/))) .and. &
               any((/'H3O','HYD','HWP'/).eq.trim(atom_res_name_p(i)))) then
            N = N + 1
            call print('ERROR: classical or buffer atom '//i//'has atom_res_name '//trim(atom_res_name_p(i)))
          endif
       enddo
       if (N.gt.0) call system_abort('wrong topology calculated')
    endif

  end subroutine check_topology

! momentum conservation over all atoms, mass weighted
  function sum0(force,at) result(force0)

    real(dp), dimension(:,:), intent(in) :: force
    type(Atoms),              intent(in) :: at
    real(dp) :: force0(size(force,1),size(force,2))
    real(dp) :: sumF(3), sum_weight

    sumF = sum(force,2)
    call print('Sum of the forces is '//sumF(1:3))

    if ((sumF(1) .feq. 0.0_dp) .and.  (sumF(2) .feq. 0.0_dp) .and.  (sumF(3) .feq. 0.0_dp)) then
       call print('Sum of the forces is zero.')
       force0 = force
    else
      !F_corr weighted by element mass
      sum_weight = sum(ElementMass(at%Z(1:at%N)))

      force0(1,:) = force(1,:) - sumF(1) * ElementMass(at%Z(:)) / sum_weight
      force0(2,:) = force(2,:) - sumF(2) * ElementMass(at%Z(:)) / sum_weight
      force0(3,:) = force(3,:) - sumF(3) * ElementMass(at%Z(:)) / sum_weight
    endif

    sumF = sum(force0,2)
    call print('Sum of the forces after mom.cons.: '//sumF(1:3))

  end function sum0

! momentum conservation over atoms with QM flag 1 or 2, mass weighted
  function sumBUFFER(force,at,my_spline) result(force0)

    real(dp), dimension(:,:), intent(in) :: force
    type(Atoms),              intent(in) :: at
    type(spline_pot),         intent(in) :: my_spline
    real(dp) :: force0(size(force,1),size(force,2))
    real(dp) :: F_corr(size(force,1),size(force,2))
    integer :: i
    real(dp) :: sumF(3), sum_weight
    integer, pointer :: qm_flag_p(:)

!    if (.not. assign_pointer(at, 'hybrid_mark', qm_flag_p)) &
    if (.not. assign_pointer(at, 'cluster_mark', qm_flag_p)) &
!         call system_abort('MetaPotential_FM_Calc: hybrid_mark property missing')
         call system_abort('MetaPotential_FM_Calc: cluster_mark property missing')
    if ( .not. any(qm_flag_p(:).eq.(/1,2/)) ) then !no buffer or core: maybe empty_qm_core?
        force0 = sum0(force,at)
        return
    endif

    !sum F
    sumF = sum(force,2)
    call print('Sum of the forces is '//sumF(1:3))

    if ((sumF(1) .feq. 0.0_dp) .and.  (sumF(2) .feq. 0.0_dp) .and.  (sumF(3) .feq. 0.0_dp)) then
       call print('Sum of the forces is zero.')
       force0 = force
    else
      !F_corr weighted by element mass
      sum_weight = 0._dp
      F_corr = 0._dp
      do i=1, at%N
         if ( any(qm_flag_p(i).eq.(/1,2/)) ) then
            F_corr(1:3,i) = ElementMass(at%Z(i))
            sum_weight = sum_weight + ElementMass(at%Z(i))
         endif
      enddo
      if (sum_weight .feq. 0._dp) call system_abort('sum_buffer: 0 element masses? the presence of core or buffer atoms has already been checked.')

      force0(1,:) = force(1,:) - sumF(1) * F_corr(1,:) / sum_weight
      force0(2,:) = force(2,:) - sumF(2) * F_corr(2,:) / sum_weight
      force0(3,:) = force(3,:) - sumF(3) * F_corr(3,:) / sum_weight
    endif

    sumF = sum(force0,2)
    call print('Sum of the forces after mom.cons.: '//sumF(1:3))

  end function sumBUFFER

  !% Calculates the force on the $i$th atom due to an external potential that has
  !% the form of a spline, $my_spline$.
  !
  function spline_force(at, i, my_spline, pot) result(force)

    type(Atoms), intent(in)  :: at
    integer, intent(in) :: i
    type(spline_pot), intent(in) :: my_spline
    real(dp), optional, intent(out) :: pot
    real(dp), dimension(3) :: force

    real(dp) :: dist, factor

! dist = distance from the origin
! spline: f(dist) = spline%dpot/(spline%from-spline%to)**3._dp * (dist-spline%to)**2._dp * (3._dp*spline%from - spline%to - 2._dp*dist)
! f(spline%from) = spline%dpot; f(spline%to) = 0.
! f`(spline%from) = 0.; f`(spline%to) = 0.
! force = - grad f(dist)

    dist = distance_min_image(at,i,(/0._dp,0._dp,0._dp/))
    if (dist.ge.my_spline%to .or. dist.le.my_spline%from) then
       force = 0._dp
       if (present(pot)) then
          if (dist.ge.my_spline%to) pot = 0._dp
          if (dist.le.my_spline%from) pot = my_spline%dpot
       endif
    else
       factor = 1._dp
      ! force on H should be 1/16 times the force on O, to get the same acc.
       if (at%Z(i).eq.1) factor = ElementMass(1)/ElementMass(8)
       force = - factor * 2._dp *my_spline%dpot / ((my_spline%from - my_spline%to)**3._dp * dist) * &
               ( (3._dp * my_spline%from - my_spline%to - 2._dp * dist) * (dist - my_spline%to) &
               - (dist - my_spline%to)**2._dp ) * at%pos(1:3,i)
       if (present(pot)) pot = my_spline%dpot/(my_spline%from-my_spline%to)**3._dp * (dist-my_spline%to)**2._dp * (3._dp*my_spline%from - my_spline%to - 2._dp*dist)
    endif

  end function spline_force

  !% Reads the QM list from a file and saves it in $QM_flag$ integer property,
  !% marking the QM atoms with 1, otherwise 0.
  !
  subroutine read_qmlist(my_atoms,qmlistfilename,qmlist,verbose)

    type(Atoms),       intent(inout) :: my_atoms
    character(*),      intent(in)    :: qmlistfilename
    type(Table), optional, intent(out) :: qmlist
    logical, optional, intent(in)    :: verbose

    type(table)                      :: qm_list
    type(Inoutput)                   :: qmlistfile
    integer                          :: n,num_qm_atoms,qmatom,status
    character(80)                    :: title,testline
    logical                          :: my_verbose
    integer                          :: qm_flag_index
    character(20), dimension(10)     :: fields
    integer                          :: num_fields
    integer, pointer :: hybrid_p(:), hybrid_mark_p(:)


    my_verbose = .false.
    if (present(verbose)) my_verbose = verbose

    if (my_verbose) call print('In Read_QM_list:')
    call print('Reading the QM list from file '//trim(qmlistfilename)//'...')

    call initialise(qmlistfile,filename=trim(qmlistfilename),action=INPUT)
    title = read_line(qmlistfile,status)
    if (status > 0) then
       call system_abort('read_qmlist: Error reading from '//qmlistfile%filename)
    else if (status < 0) then
       call system_abort('read_qmlist: End of file when reading from '//qmlistfile%filename)
    end if

    call parse_line(qmlistfile,' ',fields,num_fields,status)
    if (status > 0) then
       call system_abort('read_qmlist: Error reading from '//qmlistfile%filename)
    else if (status < 0) then
       call system_abort('read_qmlist: End of file when reading from '//qmlistfile%filename)
    end if

    num_qm_atoms = string_to_int(fields(1))
    if (num_qm_atoms.gt.my_atoms%N) call print('WARNING! read_qmlist: more QM atoms then atoms in the atoms object, possible redundant QM list file',verbosity=ERROR)
    call print('Number of QM atoms: '//num_qm_atoms)
    call allocate(qm_list,4,0,0,0,num_qm_atoms)      !1 int, 0 reals, 0 str, 0 log, num_qm_atoms entries

    do while (status==0)
       testline = read_line(qmlistfile,status)
       !print *,testline
       if (testline(1:4)=='list') exit
    enddo
   ! Reading and storing QM list...
    do n=1,num_qm_atoms
       call parse_line(qmlistfile,' ',fields,num_fields,status)
       qmatom = string_to_int(fields(1))
       if (my_verbose) call print(n//'th quantum atom is: '//qmatom)
       call append(qm_list,(/qmatom,0,0,0/))
    enddo

    call finalise(qmlistfile)

    if (qm_list%N/=num_qm_atoms) call system_abort('read_qmlist: Something wrong with the QM list file')
    if (any(int_part(qm_list,1).gt.my_atoms%N).or.any(int_part(qm_list,1).lt.1)) &
       call system_abort('read_qmlist: at least 1 QM atom is out of range')
    if ((size(int_part(qm_list,1)).gt.my_atoms%N).or.(size(int_part(qm_list,1)).lt.1)) &
       call system_abort("read_qmlist: QM atoms' number is <1 or >"//my_atoms%N)

    call add_property(my_atoms,'hybrid',0)
    if (.not. assign_pointer(my_atoms, 'hybrid', hybrid_p)) &
      call system_abort("read_qmlist couldn't assign pointer for hybrid_p")
    hybrid_p(1:my_atoms%N) = 0
    hybrid_p(int_part(qm_list,1)) = 1
call print('Added '//count(hybrid_p(1:my_atoms%N) == 1)//' qm atoms.')

    call add_property(my_atoms,'hybrid_mark',0)
    if (.not. assign_pointer(my_atoms, 'hybrid_mark', hybrid_mark_p)) &
      call system_abort("read_qmlist couldn't assign pointer for hybrid_mark_p")
    hybrid_mark_p(1:my_atoms%N) = 0
    hybrid_mark_p(int_part(qm_list,1)) = HYBRID_ACTIVE_MARK
call print('Added '//count(hybrid_mark_p(1:my_atoms%N) == HYBRID_ACTIVE_MARK)//' qm atoms.')

    if (my_verbose) call print('Finished. '//qm_list%N//' QM atoms have been read successfully.')

    !output the list in a table if needed
    if (present(qmlist)) then
       call allocate(qmlist,4,0,0,0,num_qm_atoms)
       call append(qmlist,qm_list)
    endif

    call finalise(qm_list)

  end subroutine read_qmlist

  !%Prints the quantum region mark with the cluster_mark property (/=0).
  !%If file is given, into file, otherwise to the standard io.
  !
  subroutine print_qm_region(at, file)
    type(Atoms), intent(inout) :: at
    type(Inoutput), optional :: file

    integer, pointer :: cluster_mark_p(:)

    if (.not.(assign_pointer(at, "cluster_mark", cluster_mark_p))) &
      call system_abort("print_qm_region couldn't find cluster_mark property")

    if (present(file)) then
      file%prefix="QM_REGION"
      call print_xyz(at, file, mask=(cluster_mark_p /= 0))
      file%prefix=""
    else
      mainlog%prefix="QM_REGION"
      call print_xyz(at, mainlog, mask=(cluster_mark_p /= 0))
      mainlog%prefix=""
    end if
  end subroutine print_qm_region

  subroutine do_calc_call(metapot, empty_qm_metapot, at, Run_Type1, Run_Type2, qm_region_pt_ctr, &
			  distance_ramp, qm_region_ctr, cp2k_calc_args, do_carve_cluster, driver_PSF_Print, f1, energy)
     type(MetaPotential), intent(inout) :: metapot, empty_qm_metapot
     type(Atoms), intent(inout) :: at
     logical, intent(in) :: qm_region_pt_ctr, distance_ramp, do_carve_cluster
     real(dp), intent(in) :: qm_region_ctr(3)
     character(len=*), intent(in) :: Run_Type1, Run_Type2, cp2k_calc_args, driver_PSF_Print
     real(dp), intent(inout) :: f1(:,:)
     real(dp), intent(out) :: energy

     integer, pointer :: qm_flag_p(:)
     character(len=STRING_LENGTH)        :: slow_args_str, fast_args_str, args_str
     logical :: empty_QM_core

     empty_QM_core = .false.
     if (qm_region_pt_ctr) then
        if (.not.(assign_pointer(at, "hybrid_mark", qm_flag_p))) &
           call system_abort("couldn't find hybrid_mark property")
        if (.not.any(qm_flag_p(1:at%N).eq.1)) empty_QM_core = .true.
	if (empty_QM_core .and. trim(Run_Type2) == 'QMMM_CORE') &
	  call system_abort("Can't handle Run_Type2=QMMM_CORE but QM core appears empty")
     endif
     if (.not.((trim(Run_Type1).eq.'QS').or.(trim(Run_Type1).eq.'MM'))) then
        call print_qm_region(at)
     endif

     if (trim(Run_Type2) == 'NONE' .or. (qm_region_pt_ctr .and. empty_QM_core)) then ! no force mixing
        call print(trim(Run_Type1)//' run will be performed with simple metapotential.')
        args_str=trim(cp2k_calc_args) // &
          ' Run_Type='//trim(Run_Type1)// &
          ' PSF_Print='//trim(driver_PSF_Print) // &
	  ' clean_up_files=F'
        call print('ARGS_STR | '//trim(args_str))
	if (Run_Type1(1:4) == 'QMMM') then
	  if ( qm_region_pt_ctr .and. empty_QM_core) then
	    call print('WARNING: Empty QM core. MM run will be performed instead of QM/MM.', ERROR)
	    call calc(empty_qm_metapot,at,e=energy,f=f1,args_str=trim(args_str))
	  else
	    args_str = trim(args_str) // &
	      ' single_cluster=T carve_cluster='//do_carve_cluster//' cluster_nneighb_only=F ' // &
	      ' termination_clash_check=T terminate=T even_electrons=F centre_cp2k'
	  endif
	else
	  call calc(metapot,at,e=energy,f=f1,args_str=trim(args_str))
	endif
     else ! do force mixing

       slow_args_str=trim(cp2k_calc_args) // ' Run_Type='//trim(Run_Type1)//' PSF_Print='//trim(driver_PSF_print) //' clean_up_files=F'
       if (Run_Type1(1:4) == 'QMMM' .and. .not. (qm_region_pt_ctr .and. empty_QM_core)) &
	 slow_args_str = trim(slow_args_str) // &
           ' single_cluster=T carve_cluster='//do_carve_cluster//' cluster_nneighb_only=F ' // &
	   ' termination_clash_check=T terminate=T even_electrons=F centre_cp2k'

       fast_args_str=trim(cp2k_calc_args) // ' Run_Type='//trim(Run_Type2)//' PSF_Print='//trim(driver_PSF_print) //' clean_up_files=F'
       if (Run_Type2(1:4) == 'QMMM' .and. .not. (qm_region_pt_ctr .and. empty_QM_core)) &
	 fast_args_str = trim(fast_args_str) // &
           ' single_cluster=T carve_cluster='//do_carve_cluster//' cluster_nneighb_only=F ' // &
	   ' termination_clash_check=T terminate=T even_electrons=F centre_cp2k'

       args_str='qm_args_str={'//trim(slow_args_str)//'} mm_args_str={'//trim(fast_args_str)//'}'
       if (distance_ramp) then
	 args_str = trim(args_str) // ' distance_ramp_centre='//qm_region_ctr
       endif
       call print('ARGS_STR | '//trim(args_str))
       if (qm_region_pt_ctr .and. empty_QM_core) then
	 if (trim(Run_Type2) /= 'MM') &
	   call system_abort("Doing force mixing, but Run_Type2='"//trim(Run_Type2)//"' /= MM")
	 call calc(empty_qm_metapot,at,f=f1,args_str=trim(fast_args_str))
       else
	 call calc(metapot,at,f=f1,args_str=trim(args_str))
       endif
       energy=0._dp !no energy
     endif

  end subroutine do_calc_call

  subroutine setup_pot(pot, Run_Type, filepot_program)
    type(Potential), intent(inout) :: pot
    character(len=*), intent(in) :: Run_Type, filepot_program
    if (trim(Run_Type) == 'QS') then
       call initialise(pot,'FilePot command='//trim(filepot_program)//' property_list=pos min_cutoff=0.0')
    else if (trim(Run_Type) == 'MM') then
       call initialise(pot,'FilePot command='//trim(filepot_program)//' property_list=pos:avgpos:mol_id:atom_res_number min_cutoff=0.0')
    else if (trim(Run_Type) == 'QMMM_CORE' .or. trim(Run_Type1) == 'QMMM_EXTENDED') then
       call initialise(pot,'FilePot command='//trim(filepot_program)//' property_list=pos:avgpos:atom_charge:mol_id:atom_res_number:cluster_mark:old_cluster_mark min_cutoff=0.0')
    else
       call system_abort("Run_Type='"//trim(Run_Type)//"' not supported")
    endif
  end subroutine setup_pot

end program qmmm_md
