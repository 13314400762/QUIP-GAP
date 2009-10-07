program crack


  !% The 'crack' program can either load a crack configuration that has
  !% previosuly been created with 'makecrack' or continue a previous
  !% simulation, either from an XYZ file or from a binary checkpoint file.
  !% 
  !% There are several distinct modes of operation for the crack code,
  !% corresponding to different simulation tasks, as listed in the table
  !% below. Each of these is described below.
  !%
  !% \begin{center}
  !% \begin{tabular}{cc}
  !% \hline
  !% \hline
  !% 'simulation_task' & Description \\
  !% \hline
  !% 'md' & Molecular dynamics \\
  !% 'minim' & Hybrid structural relaxation \\
  !% 'force_integraion' & Hybrid force integration \\
  !% 'quasi_static' & Quasi-static loading \\
  !% \hline
  !% \hline
  !% \end{tabular}
  !% \end{center}
  !%
  !% \subsection{Molecular Dynamics}
  !%
  !% We start with a relaxed configuration at a load $G$ below the critical
  !% Griffith load $G_c$.
  !% Depending on the range of lattice trapping, it should be possible to
  !% find a load that satisfies $G_{-} < G < G_c$ so the relaxed crack is
  !% lattice trapped and will not move until the load is increased above
  !% $G_+$.
  !% 
  !% Molecular dynamics is then carried out at a temperature of 300~K, with
  !% a weak Langevin thermostat to correct for the energy drift caused by
  !% the time dependence of the LOTF Hamiltonian.
  !% The dynamics can be accelerated using the predictor-corrector scheme.
  !% This is specified using the 'md_time_step' and 'md_extrapolate_steps'
  !% parameters; if the latter is set to one then no extrapolation is carried
  !% out.
  !% As an example, extrapolation for 10 steps of $\Delta t=1$~fs is possible for
  !% silicon crack systems.
  !%
  !% \begin{figure}[b]
  !%   \centering
  !%   \includegraphics[width=12cm]{flow-chart.eps}
  !%   \caption[Molecular dynamics methodology flow chart]
  !%   {\label{fig:flow-chart} Flow chart illustrating molecular dynamics
  !%   methodology used for the fracture simulations. See text for a
  !%   description of each state and the conditions that have to met for
  !%   transitions to take place.}
  !% \end{figure}
  !% 
  !% Unfortunately it is not possible to run dynamics for long enough to
  !% fully explore the environment at each load and to cross barriers which
  !% the real system would have sufficient thermal energy to pass over at
  !% 300~K.
  !% %
  !% Instead we allow the dynamics to proceed for some fixed amount of time
  !% 'md_wait_time', and then periodically check for rebonding near the
  !% crack tip using the time-averaged coordinates with an averaging time of 
  !% 'md_avg_time'.
  !% 
  !% Fig.~\ref{fig:flow-chart} schematically illustrates the details of the
  !% molecular dynamics methodology used for the fracture simulations.
  !% If no rebonding occurs for some time then we increase the load.
  !% After each loading increment there is a thermalisation period in which
  !% a stronger thermostat is used to dissipate the energy produced by the
  !% rescaling. 
  !% The thermalisation continues until the fluctuations in temperature
  !% are small, defined by the inequality
  !% \begin{equation}
  !% \frac{T - \left<T\right>}{T} < \frac{1}{\sqrt{N}}
  !% \end{equation}
  !% where $T$ and $\left<T\right>$ are the instantaneous and average
  !% temperatures and $N$ is the total number of atoms in the simulation.
  !% Once this condition is satisfied the thermostat is turned down and we
  !% return to almost microcanonical molecular dynamics.
  !% After the crack has started to move, the rebonding is automatically
  !% detected and the load is not increased further.
  !%
  !%\subsection{Molecular Dynamics -- smooth loading}
  !%
  !% There is now an alternative way to smoothly increase the load during
  !% an MD simulation. To use this method set the 'md_smooth_loading_rate'
  !% parameter to a non-zero value. This parameter causes the load to be 
  !% increased smoothly by an amount 'md_smooth_loading_rate*md_time_step'
  !% after each Verlet integration step. Once the crack starts to move
  !% (defined by the tip position changing by more than 'md_smooth_loading_tip_move_tol'
  !% from the original position), then loading will stop. If the crack arrests
  !% (defined by a movement of less than 'md_smooth_loading_tip_move_tol' in
  !% a time 'md_smooth_loading_arrest_time' then loading will recommence.
  !% 
  !% At the moment loading always uses the same 'load' field, but it is
  !% planned to allow the loading field to be recomputed from time to time
  !% if the crack moves and subsequently arrests.                                          
  !% 
  !% \subsection{QM Selection Algorithm}
  !% 
  !% A major advantage of LOTF is that it allows us to keep the QM region
  !% small.
  !% This requires a robust selection algorithm to follow the crack tip as
  !% it moves and identify the atoms that need to be treated with quantum
  !% mechanical accuracy.
  !% This is a difficultproblem since the timescales of thermal vibration 
  !% and crack motion are not well separated.
  !% The hysteretic selection algorithm described in Section 4.6 of my thesis
  !% \footnote{Available at 'http://www.srcf.ucam.org/\~jrk33/Publications'}.
  !% provides an effective solution to this problem.
  !% 
  !% We identify atoms as active when they change their bonding topology,
  !% and then construct embedding ellipses around each active atom.
  !% The set of active atoms is seeded with a few atoms near to the crack
  !% tip at the start of the simulation.
  !% Ellipses are used rather than spheres to allow the embedding region to be biased
  !% forwards so that the QM region always extends ahead of the crack tip.
  !% Fig.~\ref{fig:qm-selection-crack} illustrates how the algorithm works
  !% in a simple case with only two active atoms --- in reality there could
  !% be several hundred.
  !% Ellipses with different radii are used to define inner and outer
  !% selection regions, and then the hysteretic algorithm ensures that
  !% atoms near the edges of the QM region do not oscillate in and out of
  !% the active region.
  !% 
  !% \begin{figure}
  !%   \centering
  !%   \includegraphics[width=120mm]{qm-selection-crack.eps}
  !%   \caption[Hysteretic QM selection algorithm for crack tip]{
  !%     \label{fig:qm-selection-crack} Hysteretic QM selection algorithm
  !%     applied to crack tip region. The red and blue atoms are considered
  !%     `active', and are used to define inner (left panel) and outer
  !%     (right panel) selection regions. The atom indicated with the black
  !%     arrow remains selected despite oscillating in and out of the inner
  !%     region providing that it stays inside the outer region.  }
  !%     
  !% \end{figure}
  !% 
  !% As the crack moves on, we can stop treating atoms behind the crack tip
  !% quantum mechanically.
  !% We cap the size of the QM region at 'selection_max_qm_atoms'
  !% based on our computational capability --- this can be several hundred
  !% atoms for a tight binding simulation, or of the order of a hundred for
  !% an \emph{ab initio} simulation.
  !% By keeping track of the order in which atoms became active, we can
  !% remove them from the QM region in a consistent fashion.
  !% An additional condition prevents atoms further than a threshold
  !% distance 'selection_cutoff_plane' away from the centre of mass of the 
  !% current QM region from becoming active.
  !% 
  !% \subsection{Hybrid Structural Relaxation}
  !%
  !% Classical geometry optimisation can be performed rapidly using the
  !% conjugate gradients algorithm, and this provides a good first
  !% approximation to the hybrid relaxed geometry, which in turn
  !% approximates the atomic configuration that would be found by a fully
  !% quantum mechanical optimisation of the entire system.
  !% Relaxation using the hybrid forces is slightly more involved.
  !% Whenever forces are needed, a QM calculation is performed and the
  !% adjustable potential parameters are optimised to reproduce the QM
  !% forces.
  !% The forces used for the geometry optimisation are the sum of the
  !% classical and adjustable potential forces: as for MD, this ensures
  !% that there is no mechanical incompatibility at the boundary between
  !% classical and quantum regions.
  !% 
  !% The standard formulation of the conjugate gradients algorithm requires
  !% both an objective function and its derivative.
  !% For geometry optimisation, the former is the total energy.
  !% In the LOTF hybrid scheme, there is no well defined total energy, so
  !% this approach is not possible.
  !% It is possible to modify the line minimisation step of the
  !% conjugate gradient algorithm to work with derivative information only.
  !% This is done by extrapolating the projection of the derivative along
  !% the search direction to zero. This is invoked by setting 'minim_linmin_routine' 
  !% to 'LINMIN_DERIV'.
  !% To avoid errors associated with large extrapolation lengths, a maximum
  !% step size is specified and then the procedure is iterated until the
  !% projected derivative is zero.
  !% 
  !% \subsection{Quasi-static loading}
  !% 
  !% As well as MD, the 'crack' code can perform quasi-static
  !% simulations where the system is fully relaxed after each increment of
  !% load.
  !% This approach can be used to estimate the fracture toughness $G\_+$,
  !% the load at which the lattice trapping barrier first falls to zero.
  !% For this purpose, we consider fracture to have occured when the
  !% crack tip moves more than 'quasi_static_tip_move_tol' from its
  !% original position.
  !% 
  !% \subsection{Hybrid Force Integration}
  !% 
  !% Within the LOTF scheme, there is not a meaningful total energy for the
  !% hybrid classical/quantum system; the method matches forces between the
  !% QM and classical regions, rather than energies, so the solution is to
  !% use these accurate forces to evaluate the energy difference between
  !% two configurations by force integration:
  !% \begin{equation} \label{eq:force-integration}
  !%   \Delta E = \int_{\gamma} \mathbf{F}\left(\mathbf{R}\right)\cdot\mathrm{d}\mathbf{R}
  !% \end{equation}
  !% where $\mathbf{R}$ denotes all atomic positions and the integration
  !% contour $\gamma$ can be any path between the two configurations of
  !% interest.
  !% The start and end configurations should be obtained by hybrid minimisation, 
  !% so that $\mathbf{F} = 0$ at both integration limits.
  !% The ending configuation is taken from the file specified in the
  !% 'force_integration_end_file' parameter.
  !% 
  !% The simplest contour connecting the two minima is used: linear interpolation 
  !% between the relaxed unreconstructed state with atomic coordinates $\mathbf{R}_U$ and 
  !% the reconstructed state with coordinates $\mathbf{R}_R$.
  !% The QM region is fixed during the integration process.
  !% The forces $\mathbf{F}(\mathbf{R})$ are calculated in the standard
  !% LOTF fashion: classical and quantum forces are evaluated for the two
  !% regions, then the adjustable potential is optimised to reproduce the
  !% quantum forces.
  !% The forces used for the integration are the sum of the classical and
  !% corrective forces to ensure that there is no mechanical mismatch at
  !% the boundary.
  !% The integration path is discretised into $N+1$ samples according to
  !% \begin{eqnarray}
  !%   \Delta \mathbf{R} & = & \frac{1}{N}\left(\mathbf{R}_R - \mathbf{R}_U\right) \\
  !%   \mathbf{F}_i & = & \mathbf{F}(\mathbf{R}_U + i\,\Delta \mathbf{R}), \;\; 0 \le i \le N
  !% \end{eqnarray}
  !% and then Eq.~\ref{eq:force-integration} can be evaluated using
  !% Simpson's Rule:
  !% \begin{eqnarray}
  !%   \Delta E & \approx & \frac{\Delta \mathbf{R}}{3} \cdot \left[
  !%     \mathbf{F}_0 + 
  !%     2 \sum_{j=1}^{N/2-1} \mathbf{F}_{2j} +
  !%     4 \sum_{j=1}^{N/2} \mathbf{F}_{2j-1} +
  !%     \mathbf{F}_N \right]
  !% \end{eqnarray}
  !% The step-size $\Delta \mathbf{R}$ required for accurate integration of
  !% the energy difference can be calibrated using force integration with the
  !% classical potential alone, where the energy difference can be
  !% calculated exactly --- typically $N=20$ gives good results.
  !% The method has been validated by confirming that perturbing the integration
  !% path does not affect the value of $\Delta E$ obtained.
  !% $N$ is specified using the 'force_integration_n_steps' parameter.


  use libAtoms_module
  use QUIP_module

  ! Crack includes
  use CrackTools_module
  use CrackParams_module

  implicit none

  ! Constants
  integer, parameter :: STATE_THERMALISE = 1
  integer, parameter :: STATE_MD = 2
  integer, parameter :: STATE_MD_LOADING = 3
  integer, parameter :: STATE_MD_CRACKING = 4
  integer, parameter :: STATE_DAMPED_MD = 5
  integer, parameter :: STATE_MICROCANONICAL = 6
  character(len=11), dimension(6), parameter :: STATE_NAMES = &
       (/"THERMALISE", "MD", "MD_LOADING", "MD_CRACKING", "DAMPED_MD", "MICROCANONICAL"/)

  ! Objects
  type(InOutput) :: xmlfile, checkfile
  type(CInOutput) :: movie, crackin, movie_backup
  type(DynamicalSystem), target :: ds, ds_save
  type(Atoms) :: crack_slab, fd_start, fd_end, bulk
  type(CrackParams) :: params
  type(Potential) :: classicalpot, qmpot
  type(MetaPotential) :: simple_metapot, hybrid_metapot, forcemix_metapot
  type(Dictionary) :: metapot_params

  ! Pointers into Atoms data table
  real(dp), pointer, dimension(:,:) :: load
  integer, pointer, dimension(:) :: move_mask, nn, changed_nn, edge_mask, md_old_changed_nn, &
       old_nn, hybrid, hybrid_mark

  ! Big arrays
  real(dp), allocatable, dimension(:,:) :: f, f_fm, dr
  real(dp), pointer :: dr_prop(:,:), f_prop(:,:)

  ! Scalars
  integer :: movie_n, nargs, i, state, steps, iunit, n
  logical :: mismatch, movie_exist, periodic_clusters(3), dummy, texist
  real(dp) :: fd_e0, f_dr, integral, energy, last_state_change_time, last_print_time, &
       last_checkpoint_time, last_calc_connect_time, &
       last_md_interval_time, time, temp, crack_pos(2), orig_crack_pos, &
       G, orig_width
  character(STRING_LENGTH) :: stem, movie_name, xyzfilename, xmlfilename
  character(value_len) :: state_string

  type(mpi_context) :: mpi_glob

  !** Initialisation Code **

  nargs = cmd_arg_count()

  call initialise(mpi_glob)

  if (mpi_glob%active) then
     ! Same random seed for each process, otherwise velocites will differ
     call system_initialise (common_seed = .true., enable_timing=.true., mpi_all_inoutput=.false.)
     call print('MPI run with '//mpi_glob%n_procs//' processes')
  else
     call system_initialise( enable_timing=.true.)
     call print('Serial run')
  end if

  call system_timer('initialisation')
  call initialise(params)

if (.not. mpi_glob%active) then
  ! Print usage information if no arguments given
  if (nargs /= 1) then
     call print('Usage: crack <stem>')
     call print('')
     call print('Where stem.xyz and stem.xml are the crack slab XYZ file')
     call print('and parameter file respectively')
     call print('')
     call print('Available parameters and their default values are:')
     call print('')
     call print(params)

     call system_finalise
     stop
  end if
end if

  ! 1st argument contains stem for input xyz or binary checkfile and parameter files
if (.not. mpi_glob%active) then
  call get_cmd_arg(1, stem)
else
  stem = 'crack' ! Some MPIs can't handle command line arguments
end if

  xyzfilename = trim(stem)//'.xyz'
  xmlfilename = trim(stem)//'.xml'

  call print_title('Initialisation')
  call print('Reading parameters from file '//trim(xmlfilename))
  call initialise(xmlfile,xmlfilename,INPUT)
  call read_xml(params,xmlfile)
  call verbosity_push(params%io_verbosity)   ! Set base verbosity
  call print(params)

  if (params%io_mpi_print_all) then
     mainlog%mpi_all_inoutput_flag = .true.
     mainlog%mpi_print_id = .true.
  end if

  call print ("Initialising classical potential with args " // trim(params%classical_args) &
       // " from file " // trim(xmlfilename))
  call rewind(xmlfile)
  call initialise(classicalpot, params%classical_args, xmlfile, mpi_obj = mpi_glob)
  call Print(classicalpot)

  call print('Initialising metapotential')
  call initialise(simple_metapot, 'Simple', classicalpot, mpi_obj = mpi_glob)
  call print(simple_metapot)

  if (.not. params%simulation_classical) then
     call print ("Initialising QM potential with args " // trim(params%qm_args) &
          // " from file " // trim(xmlfilename))
     call rewind(xmlfile)
     if (params%qm_small_clusters) then
        ! Don't parallelise qmpot if we're doing little clusters
        call initialise(qmpot, params%qm_args, xmlfile)
     else
        ! Pass mpi_glob, so parallelise over k-points if they are defined in .xml
        call initialise(qmpot, params%qm_args, xmlfile, mpi_obj=mpi_glob)
     end if
     call finalise(xmlfile)
     call Print(qmpot)
  end if

  if (params%qm_force_periodic) then
     periodic_clusters = (/ .false., .false., .true. /)
  else
     periodic_clusters = (/ .false., .false., .not. params%qm_small_clusters/)
  endif

  if (.not. params%simulation_classical) then

     call initialise(metapot_params)
     call set_value(metapot_params, 'method', trim(params%fit_method))
     call set_value(metapot_params, 'buffer_hops', params%qm_buffer_hops)
     call set_value(metapot_params, 'fit_hops', params%fit_hops)
     call set_value(metapot_params, 'minimise_mm', params%minim_minimise_mm)
     call set_value(metapot_params, 'randomise_buffer', params%qm_randomise_buffer)
     call set_value(metapot_params, 'mm_reweight', params%classical_force_reweight)
     call set_value(metapot_params, 'minim_mm_method', trim(params%minim_mm_method))
     call set_value(metapot_params, 'minim_mm_tol', params%minim_mm_tol)
     call set_value(metapot_params, 'minim_mm_eps_guess', params%minim_mm_eps_guess)
     call set_value(metapot_params, 'minim_mm_max_steps', params%minim_mm_max_steps)
     call set_value(metapot_params, 'minim_mm_linminroutine', trim(params%minim_mm_linminroutine))
     call set_value(metapot_params, 'minim_mm_args_str', trim(params%minim_mm_args_str) )
     call set_value(metapot_params, 'minim_mm_use_n_minim', params%minim_mm_use_n_minim)
     call set_value(metapot_params, 'lotf_spring_hops', params%fit_spring_hops)
     call set_value(metapot_params, 'do_rescale_r', params%qm_rescale_r)
     call set_value(metapot_params, 'minimise_bulk', params%qm_rescale_r)
     call set_value(metapot_params, 'hysteretic_buffer', params%qm_hysteretic_buffer)
     call set_value(metapot_params, 'hysteretic_buffer_inner_radius', params%qm_hysteretic_buffer_inner_radius)
     call set_value(metapot_params, 'hysteretic_buffer_outer_radius', params%qm_hysteretic_buffer_outer_radius)

     call set_value(metapot_params, 'hysteretic_connect', params%qm_hysteretic_connect)
     call set_value(metapot_params, 'nneighb_only', (.not. params%qm_hysteretic_connect))
     call set_value(metapot_params, 'hysteretic_connect_cluster_radius', params%qm_hysteretic_connect_cluster_radius)
     call set_value(metapot_params, 'hysteretic_connect_inner_factor', params%qm_hysteretic_connect_inner_factor)
     call set_value(metapot_params, 'hysteretic_connect_outer_factor', params%qm_hysteretic_connect_outer_factor)


     call set_value(metapot_params, 'mm_args_str', params%classical_args_str)

     call set_value(metapot_params, 'qm_args_str', &
          '{ little_clusters='//params%qm_small_clusters// &
          '  single_cluster='//(.not. params%qm_small_clusters)// &
          '  terminate='//params%qm_terminate// &
          '  even_electrons='//params%qm_even_electrons// &
          '  cluster_vacuum='//params%qm_vacuum_size// &
          '  cluster_periodic_x=F cluster_periodic_y=F cluster_periodic_z='//periodic_clusters(3)// &
          '  cluster_calc_connect='//(cutoff(qmpot) /= 0.0_dp)// &
          '  buffer_hops='//params%qm_buffer_hops//&
          '  randomise_buffer='//params%qm_randomise_buffer//&
          '  hysteretic_connect='//params%qm_hysteretic_connect//&
          '  nneighb_only='//(.not. params%qm_hysteretic_connect)//&
          '  cluster_nneighb_only='//(.not. params%qm_hysteretic_connect)//&
	  '  ' //trim(params%qm_args_str) &
	  //' }')

     if (params%qm_rescale_r) then
        call Print('Reading bulk cell from file '//trim(stem)//'_bulk.xyz')
        call read_xyz(bulk, trim(stem)//'_bulk.xyz')

        call initialise(hybrid_metapot, 'ForceMixing '//write_string(metapot_params), &
             classicalpot, qmpot, bulk, mpi_obj=mpi_glob)
     else
        call initialise(hybrid_metapot, 'ForceMixing '//write_string(metapot_params), &
             classicalpot, qmpot, mpi_obj=mpi_glob)
     end if

     call print_title('Hybrid Metapotential')
     call print(hybrid_metapot)

     call set_value(metapot_params, 'method', 'force_mixing')
     if (params%qm_rescale_r) then
        call initialise(forcemix_metapot, 'ForceMixing '//write_string(metapot_params), &
             classicalpot, qmpot, bulk, mpi_obj=mpi_glob)
        call finalise(bulk)
     else
        call initialise(forcemix_metapot, 'ForceMixing '//write_string(metapot_params), &
             classicalpot, qmpot, mpi_obj=mpi_glob)
     end if
     call finalise(metapot_params)

  end if

  ! Read atoms from file <stem>.xyz, <stem>.nc or from binary <stem>.check

  if (params%simulation_restart) then
      if (params%io_netcdf) then
        call Print('Restarting from NetCDF trajectory '//trim(stem)//'.nc')
        call initialise(movie, trim(stem)//'.nc', action=INOUT, append=.true.)
        call read(movie, crack_slab, frame=int(movie%n_frame)-1) ! Read last frame
      else
        call Print('Restarting from checkfile '//trim(params%io_checkpoint_path)//trim(stem)//'.check')
        call initialise(checkfile, trim(params%io_checkpoint_path)//trim(stem)//'.check', &
             INPUT, isformatted=.false.)
        call read_binary(crack_slab, checkfile)
        call finalise(checkfile)
      end if
  else
     call print('Reading atoms from input file '//trim(stem)//'.xyz')
     call initialise(crackin, trim(stem)//'.xyz', action=INPUT)
     call read(crackin, crack_slab)
  end if

  call initialise(ds, crack_slab)
  call finalise(crack_slab)

  call print('Initialised dynamical system with '//ds%N//' atoms')

  call add_property(ds%atoms, 'force', 0.0_dp, n_cols=3)
  call add_property(ds%atoms, 'qm_force', 0.0_dp, n_cols=3)
  call add_property(ds%atoms, 'mm_force', 0.0_dp, n_cols=3)

  call crack_fix_pointers(ds%atoms, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
       old_nn, hybrid, hybrid_mark)

  ds%atoms%damp_mask = 1
  ds%atoms%thermostat_region = 1
!!$  where (ds%atoms%move_mask == 0)
!!$     ds%atoms%thermostat_region = 0
!!$     ds%atoms%damp_mask = 0
!!$  end where

  ! Set number of degrees of freedom correctly
  ds%Ndof = 3*count(ds%atoms%move_mask == 1)

  ! Reseed random number generator if necessary
  if (params%simulation_seed /= 0) call system_reseed_rng(params%simulation_seed)

#ifndef HAVE_NETCDF
  if (params%io_netcdf) &
       call system_abort('io_netcdf = .true. but NetCDF support not compiled in')
#endif 

  if (.not. mpi_glob%active .or. (mpi_glob%active .and.mpi_glob%my_proc == 0)) then
     if (.not. params%io_netcdf) then
        ! Avoid overwriting movie file from previous runs by suffixing a number
        movie_n = 1
        movie_exist = .true.
        do while (movie_exist)
           write (movie_name, '(a,i0,a)') trim(stem)//'_movie_', movie_n, '.xyz'
           inquire (file=movie_name, exist=movie_exist)
           movie_n = movie_n + 1
        end do
        
        call print('Setting up movie output file '//movie_name)
        call initialise(movie, movie_name, action=OUTPUT)
     else
        if (.not. movie%initialised) then
           call initialise(movie, trim(stem)//'.nc', action=OUTPUT)

           if (params%io_backup) &
                call initialise(movie_backup, trim(stem)//'_backup.nc', action=OUTPUT)
        endif
     end if
  endif

  call Print('Setting neighbour cutoff to '//(cutoff(classicalpot)+params%md_crust)//' A.')
  call atoms_set_cutoff(ds%atoms, cutoff(classicalpot)+params%md_crust)
  call print('Neighbour crust is '//params%md_crust// ' A.')

  call calc_connect(ds%atoms, store_is_min_image=.true.)

!!$  call table_allocate(embedlist, 4, 0, 0, 0) 
!!$  call table_allocate(fitlist, 4, 0, 0, 0)   

  ! Allocate some force arrays
  allocate(f(3,ds%atoms%N))
  f  = 0.0_dp

  if (params%qm_calc_force_error) allocate(f_fm(3,ds%atoms%N))

  ! Allocate various flags 

  call Print('Setting nneightol to '//params%md_nneigh_tol)
  ds%atoms%nneightol = params%md_nneigh_tol

  call crack_update_connect(ds%atoms, params)

  ! Initialise QM region
  if (.not. params%simulation_classical) then
     if (params%selection_dynamic) then
        call print('Initialising dynamic QM region')

        ! See if we read changed_nn from file
        if (all(changed_nn == 0)) &
             call system_abort('No seed atoms found - rerun makecrack')
        call print('count(changed_nn /=0) = '//count(changed_nn /= 0))
        call crack_update_selection(ds%atoms, params)

     else
        call print('Static QM region')
        ! Load QM mask from file, then fix it for entire simulation

        call print('Loaded hybrid mask from XYZ file')
!!$        call crack_update_selection(ds%atoms, params, embedlist=embedlist, fitlist=fitlist, &
!!$             update_embed=.false., num_directionality=directionN)
     end if
  end if

  ! Print a frame before we start
  call crack_print(ds%atoms, movie, params, mpi_glob)
  if (params%io_backup .and. params%io_netcdf) &
       call crack_print(ds%atoms, movie_backup, params, mpi_glob)

  if (.not. params%simulation_classical) then
     if (count(hybrid == 1) == 0) call system_abort('Zero QM atoms selected')
  end if

  call system_timer('initialisation')

  !** End of initialisation **

  call setup_parallel(classicalpot, ds%atoms, e=energy, f=f,args_str=params%classical_args_str)

  call crack_fix_pointers(ds%atoms, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
       old_nn, hybrid, hybrid_mark)

  if (.not. has_property(ds%atoms, 'load')) then
     call print_title('Applying Initial Load')
     call crack_calc_load_field(ds%atoms, params, classicalpot, simple_metapot, params%crack_loading, & 
          .true., mpi_glob)

     call crack_fix_pointers(ds%atoms, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
          old_nn, hybrid, hybrid_mark)
  end if

  if (params%simulation_force_initial_load_step) then
     if (.not. has_property(ds%atoms, 'load')) &
          call system_abort('simulation_force_initial_load_step is true but crack slab has no load field - set crack_apply_initial_load = T to regenerate load')
    call print_title('Force_load_step is true,  applying load')
    call crack_apply_load_increment(ds%atoms, params%crack_G_increment)
  end if

  !****************************************************************
  !*                                                              *
  !*  MOLECULAR DYNAMICS                                          *
  !*                                                              *
  !*                                                              *
  !****************************************************************    
  if (trim(params%simulation_task) == 'md' .or. trim(params%simulation_task) == 'damped_md') then

     call print_title('Molecular Dynamics')

     if (.not. get_value(ds%atoms%params, 'Temp', temp)) temp = 0.0_dp

     if (.not. params%simulation_restart) then
        call rescale_velo(ds, temp)
        call zero_momentum(ds)
	ds%cur_temp = temperature(ds, instantaneous=.true.)
	ds%avg_temp = temperature(ds)
     end if

     if (.not. get_value(ds%atoms%params, 'Time', time))  time = 0.0_dp
     ds%t = time

     if (.not. get_value(ds%atoms%params, 'LastStateChangeTime', last_state_change_time)) &
          last_state_change_time = ds%t

     if (.not. get_value(ds%atoms%params, 'LastMDIntervalTime', last_md_interval_time)) &
          last_md_interval_time = ds%t

     if (.not. get_value(ds%atoms%params, 'LastPrintTime', last_print_time)) &
          last_print_time = ds%t

     if (.not. get_value(ds%atoms%params, 'LastCheckpointTime', last_checkpoint_time)) &
          last_checkpoint_time = ds%t

     if (.not. get_value(ds%atoms%params, 'LastCalcConnectTime', last_calc_connect_time)) &
          last_calc_connect_time = ds%t

     ! Special cases for first time
     if (all(md_old_changed_nn == 0)) md_old_changed_nn = changed_nn
     if (all(old_nn == 0)) old_nn = nn

     ds%avg_time = params%md_avg_time

     if (trim(params%simulation_task) == 'md') then
        if (.not. get_value(ds%atoms%params, "State", state_string)) then
           if (params%md_smooth_loading_rate .fne. 0.0_dp) then 
              state_string = 'MD_LOADING'
           else
              state_string = 'THERMALISE'
           end if
        end if
     else 
        state_string = 'DAMPED_MD'
     end if

     if (trim(state_string) == "MD" .and. (params%md_smooth_loading_rate .fne. 0.0_dp)) state_string = 'MD_LOADING'

     if (state_string(1:10) == 'THERMALISE') then
        state = STATE_THERMALISE
        call disable_damping(ds)
        call ds_add_thermostat(ds, LANGEVIN, params%md_sim_temp, tau=params%md_thermalise_tau)

     else if (state_string(1:10) == 'MD') then
        state = STATE_MD
        call disable_damping(ds)
        call ds_add_thermostat(ds, LANGEVIN, params%md_sim_temp, tau=params%md_tau)

     else if (state_string(1:10) == 'MD_LOADING') then
        state = STATE_MD_LOADING
        call disable_damping(ds)
        call ds_add_thermostat(ds, LANGEVIN, params%md_sim_temp, tau=params%md_tau)
        dummy = get_value(ds%atoms%params, 'CrackPosx', orig_crack_pos)
        crack_pos(1) = orig_crack_pos

     else if (state_string(1:11) == 'MD_CRACKING') then
        state = STATE_MD_CRACKING
        call disable_damping(ds)
        call ds_add_thermostat(ds, LANGEVIN, params%md_sim_temp, tau=params%md_tau)

     else if (state_string(1:9) == 'DAMPED_MD') then
        state = STATE_DAMPED_MD
        call enable_damping(ds, 1000.0_dp)

     else if (state_string(1:14) == 'MICROCANONICAL') then
        state = STATE_MICROCANONICAL
        call disable_damping(ds)

     else  
        call system_abort("Don't know how to resume in molecular dynamics state "//trim(state_string))
     end if

     call print('Thermostats')
     call print(ds%thermostat)

     call print('Starting in state '//STATE_NAMES(state))

     ! Bootstrap the adjustable potential if we're doing predictor/corrector dynamics
     if (params%md_extrapolate_steps /= 1 .and. .not. params%simulation_classical) then
        call calc(hybrid_metapot, ds%atoms, f=f)
     end if

     !****************************************************************
     !*  Main MD Loop                                                *
     !*                                                              *
     !****************************************************************    
     do
        call system_timer('step')
        call crack_fix_pointers(ds%atoms, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
             old_nn, hybrid, hybrid_mark)


        select case(state)
        case(STATE_THERMALISE)
           if (ds%t - last_state_change_time >= params%md_thermalise_wait_time .and. &
                abs(ds%avg_temp - temperature(ds))/temperature(ds) < params%md_thermalise_wait_factor/sqrt(real(ds%atoms%N,dp))) then
              ! Change to state MD
              call print('STATE changing THERMALISE -> MD')
              state = STATE_MD
              last_state_change_time = ds%t
              call disable_damping(ds)
              call initialise(ds%thermostat(1), LANGEVIN, params%md_sim_temp, &
                   gamma=1.0_dp/params%md_tau)
              md_old_changed_nn = changed_nn
           end if

        case(STATE_MD)
           if ((ds%t - last_state_change_time >= params%md_wait_time) .and. &
                (ds%t - last_md_interval_time  >= params%md_interval_time)) then

              mismatch = .false.
              do i = 1,ds%atoms%N
                 if ((changed_nn(i) == 0 .and. md_old_changed_nn(i) /= 0) .or. &
                      (changed_nn(i) /= 0 .and. md_old_changed_nn(i) == 0)) then
                    mismatch = .true.
                    exit
                 end if
              end do

              if (.not. mismatch) then 
                 ! changed_nn hasn't changed for a while so we can increase strain
                 ! Rescale and change to state THERMALISE
                 call print('STATE changing MD -> THERMALISE')
                 state = STATE_THERMALISE
                 last_state_change_time = ds%t

                 call disable_damping(ds)
                 call initialise(ds%thermostat(1), LANGEVIN, params%md_sim_temp, &
                      gamma=1.0_dp/params%md_thermalise_tau)
              end if
              
              ! Apply loading field
              if (has_property(ds%atoms, 'load')) then
                 call print_title('Applying load')
                 call crack_apply_load_increment(ds%atoms, params%crack_G_increment)
                 call calc_dists(ds%atoms)
              else
                 call print('No load field found - not increasing load.')
              end if

              md_old_changed_nn = changed_nn
              last_md_interval_time = ds%t
           end if

        case(STATE_DAMPED_MD)

        case(STATE_MICROCANONICAL)

        case(STATE_MD_LOADING)
           ! If tip has moved by more than smooth_loading_tip_move_tol then
           ! turn off loading. 
           dummy = get_value(ds%atoms%params, 'CrackPosx', crack_pos(1))
           dummy = get_value(ds%atoms%params, 'OrigCrackPos', orig_crack_pos)

           if ((crack_pos(1) - orig_crack_pos) > params%md_smooth_loading_tip_move_tol) then
              call print_title('Crack Moving')
              call print('STATE changing MD_LOADING -> MD_CRACKING')
              state = STATE_MD_CRACKING
              last_state_change_time = ds%t
              orig_crack_pos = crack_pos(1)
              call set_value(ds%atoms%params, 'OrigCrackPos', orig_crack_pos)
           else
              call print('STATE: crack is not moving (crack_pos='//crack_pos(1)//')')
           end if

        case(STATE_MD_CRACKING)
           ! Monitor tip and if it doesn't move by more than smooth_loading_tip_move_tol in
           ! time smooth_loading_arrest_time then switch back to loading
           if (ds%t - last_state_change_time >= params%md_smooth_loading_arrest_time) then
              dummy = get_value(ds%atoms%params, 'CrackPos', crack_pos(1))
              dummy = get_value(ds%atoms%params, 'OrigWidth', orig_width)
              dummy = get_value(ds%atoms%params, 'OrigCrackPos', orig_crack_pos)
              
              if ((crack_pos(1) - orig_crack_pos) < params%md_smooth_loading_tip_move_tol) then

                 if ((orig_width/2.0_dp - crack_pos(1)) < params%md_smooth_loading_tip_edge_tol) then
                    call print_title('Cracked Through')
                    exit
                 else
                    call print_title('Crack Arrested')
                    call crack_calc_load_field(ds%atoms, params, classicalpot, simple_metapot, params%crack_loading, &
                         .false., mpi_glob)
                    call print('STATE changing MD_CRACKING -> MD_LOADING')
                    state = STATE_MD_LOADING
                 end if
              else
                 call print('STATE: crack is moving (crack_pos='//crack_pos//')')
              end if
              last_state_change_time = ds%t
              orig_crack_pos = crack_pos(1) 
              call set_value(ds%atoms%params, 'OrigCrackPos', orig_crack_pos)
           end if

        case default
           call system_abort('Unknown molecular dynamics state!')
        end select

        ! Are we doing predictor/corrector dynamics?
        if (params%md_extrapolate_steps /= 1) then

           !****************************************************************
           !*  Quantum Selection                                           *
           !*                                                              *
           !****************************************************************    
           if (.not. params%simulation_classical) then
              call system_timer('QM selection')
              call print_title('Quantum Selection')
              if (params%selection_dynamic) call crack_update_selection(ds%atoms, params)
              call system_timer('QM selection')
           end if


           !****************************************************************
           !*  Extrapolation                                               *
           !*                                                              *
           !****************************************************************    
           call print_title('Extrapolation')

           call system_timer('extrapolation')

           if (.not. params%simulation_classical) then
              call ds_save_state(ds_save, ds)
           end if

           do i = 1, params%md_extrapolate_steps

              if (params%simulation_classical) then
                 call calc(simple_metapot, ds%atoms, f=f, args_str=params%classical_args_str)
              else
                 if (i== 1) then
                    call calc(hybrid_metapot, ds%atoms, f=f, args_str="lotf_do_qm=F lotf_do_init=T lotf_do_map=T")
                 else
                    call calc(hybrid_metapot, ds%atoms, f=f, args_str="lotf_do_qm=F lotf_do_init=F")
                 end if
                 if (params%qm_calc_force_error) call calc(forcemix_metapot, ds%atoms, f=f_fm)

                 if (params%hack_qm_zero_z_force) then
                    ! Zero z forces in embed region
                    f(3,find(hybrid == 1)) = 0.0_dp 
                    if (params%qm_calc_force_error) f_fm(3, find(hybrid == 1)) = 0.0_dp
                 end if
              end if

              ! advance the dynamics
              call advance_verlet(ds, params%md_time_step, f)
              if (params%simulation_classical) then
                 call ds_print_status(ds, 'E', epot=energy)
              else
                 call ds_print_status(ds, 'E')
              end if
              if (params%qm_calc_force_error) call print('E err '//ds%t//' '//rms_diff(f, f_fm)//' '//maxval(abs(f_fm-f)))

              if (state == STATE_MD_LOADING) then
                 ! increment the load
                 if (has_property(ds%atoms, 'load')) then
                    call crack_apply_load_increment(ds%atoms, params%md_smooth_loading_rate*params%md_time_step)
                    call calc_dists(ds%atoms)
                    if (.not. get_value(ds%atoms%params, 'G', G)) call system_abort('No G in ds%atoms%params')
                 else
                    call print('No load field found - not increasing load.')
                 end if
              end if

           end do
           call system_timer('extrapolation')

           if (.not. params%simulation_classical) then

              !****************************************************************
              !*  QM Force Computation                                        *
              !*  and optimisation of Adjustable Potential                    *
              !*                                                              *
              !****************************************************************    

              call print_title('Computation of forces')
              call system_timer('force computation')
              call calc(hybrid_metapot, ds%atoms, f=f, args_str="lotf_do_qm=T lotf_do_init=F lotf_do_fit=T")
              call system_timer('force computation')


              !****************************************************************
              !*  Interpolation                                               *
              !*                                                              *
              !****************************************************************    
              call print_title('Interpolation')
              call system_timer('interpolation')

              ! revert to the saved positions etc.
              call ds_restore_state(ds, ds_save)

              do i = 1, params%md_extrapolate_steps

                 call calc(hybrid_metapot, ds%atoms, f=f, args_str="lotf_do_qm=F lotf_do_init=F lotf_do_interp=T lotf_interp="&
                      //(real(i-1,dp)/real(params%md_extrapolate_steps,dp)))

                 if (params%qm_calc_force_error) call calc(forcemix_metapot, ds%atoms, f=f_fm)

                 if (params%hack_qm_zero_z_force) then
                    ! Zero z forces in embed region
                    f(3,find(hybrid == 1)) = 0.0_dp 
                    if (params%qm_calc_force_error) f_fm(3, find(hybrid == 1)) = 0.0_dp
                 end if

                 ! advance the dynamics
                 call advance_verlet(ds, params%md_time_step, f)
                 call ds_print_status(ds, 'I')
                 if (params%qm_calc_force_error) call print('I err '//ds%t//' '//rms_diff(f, f_fm)//' '//maxval(abs(f_fm-f)))

                 if (trim(params%simulation_task) == 'damped_md') &
                      call print('Damped MD: norm2(force) = '//norm2(reshape(f,(/3*ds%N/)))//&
                      ' max(abs(force)) = '//maxval(abs(f)))

                 if (state == STATE_MD_LOADING) then
                    ! increment the load
                    if (has_property(ds%atoms, 'load')) then
                       call crack_apply_load_increment(ds%atoms, params%md_smooth_loading_rate*params%md_time_step)
                       call calc_dists(ds%atoms)
                       if (.not. get_value(ds%atoms%params, 'G', G)) call system_abort('No G in ds%atoms%params')
                    else
                       call print('No load field found - not increasing load.')
                    end if
                 end if

              end do
              call system_timer('interpolation')

           end if ! .not. params%simulation_classical

        else ! params%md_extrapolate_steps /= 1

           !****************************************************************
           !*  Non-Predictor/Corrector Dynamics                            *
           !*                                                              *
           !****************************************************************    

           call print_title('Quantum Selection')
           call system_timer('selection')
           if (params%selection_dynamic)  call crack_update_selection(ds%atoms, params)
           call system_timer('selection')

           call print_title('Force Computation')
           call system_timer('force computation/optimisation')
           if (params%simulation_classical) then
              call calc(simple_metapot, ds%atoms, e=energy, f=f, args_str=params%classical_args_str)
           else
              call calc(hybrid_metapot, ds%atoms, f=f)
           end if
           call system_timer('force computation/optimisation')

           if (params%hack_qm_zero_z_force) then
              ! Zero z forces in embed region
              f(3,find(hybrid == 1)) = 0.0_dp 
           end if

           call print_title('Advance Verlet')
           call advance_verlet(ds, params%md_time_step, f)
           call ds_print_status(ds, 'D')

           if (trim(params%simulation_task) == 'damped_md') &
                call print('Damped MD: norm2(force) = '//norm2(reshape(f,(/3*ds%N/)))//&
                ' max(abs(force)) = '//maxval(abs(f)))

           if (state == STATE_MD_LOADING) then
              ! increment the load
              if (has_property(ds%atoms, 'load')) then
                 call crack_apply_load_increment(ds%atoms, params%md_smooth_loading_rate*params%md_time_step)
                 call calc_dists(ds%atoms)
                 if (.not. get_value(ds%atoms%params, 'G', G)) call system_abort('No G in ds%atoms%params')
              else
                 call print('No load field found - not increasing load.')
              end if
           end if

        end if ! params%extrapolate_steps /= 1


        ! Print movie

        if (ds%t - last_print_time >=  params%io_print_interval) then
           last_print_time = ds%t
           call set_value(ds%atoms%params, 'Time', ds%t)
           call set_value(ds%atoms%params, 'Temp', temperature(ds))
           call set_value(ds%atoms%params, 'LastStateChangeTime', last_state_change_time)
           call set_value(ds%atoms%params, 'LastMDIntervalTime', last_md_interval_time)
           call set_value(ds%atoms%params, 'LastPrintTime', last_print_time)
           call set_value(ds%atoms%params, 'LastCheckpointTime', last_checkpoint_time)
           call set_value(ds%atoms%params, 'LastCalcConnectTime', last_calc_connect_time)
           call set_value(ds%atoms%params, 'State', STATE_NAMES(state))
           n = ds%t/params%io_print_interval

           if (params%io_backup .and. params%io_netcdf) then
              if (mod(n,2).eq.0) then
                 call crack_print(ds%atoms, movie, params, mpi_glob)
                 call print('writing .nc file '//trim(stem)//'.nc')
              else
                 call crack_print(ds%atoms, movie_backup, params, mpi_glob)
                 call print('writing .nc file '//trim(stem)//'_backup.nc')
              endif
           else
              call crack_print(ds%atoms, movie, params, mpi_glob)
           end if
        end if

        ! Write binary checkpoint file
        if (ds%t - last_checkpoint_time >=  params%io_checkpoint_interval .and. .not. params%io_netcdf) then
           last_checkpoint_time = ds%t
           call initialise(checkfile, trim(params%io_checkpoint_path)//trim(stem)//'.check', &
                OUTPUT, isformatted=.false.)
           call write_binary(ds%atoms, checkfile)
           call finalise(checkfile)
        endif

        ! Recalculate connectivity and nearest neighbour tables
        if (ds%t - last_calc_connect_time >= params%md_calc_connect_interval) then
           last_calc_connect_time = ds%t
           call crack_update_connect(ds%atoms, params)
        end if

        ! Exit cleanly if file 'stop_run' exists
        inquire (file='stop_run',exist=texist)
        if (texist) then
           iunit = pick_up_unit()
           open (iunit,file='stop_run',status='old')
           close (iunit,status='delete')
           exit
        endif

        call system_timer('step')

     end do


     !****************************************************************
     !*                                                              *
     !*  FORCE INTEGRATION                                           *
     !*                                                              *
     !*                                                              *
     !****************************************************************    
  else if (trim(params%simulation_task) == 'force_integration') then

!!$     params%io_print_properties = trim(params%io_print_properties) // ":dr:forces"

     call print_title('Force Integration')

     fd_start = ds%atoms
     call read_xyz(fd_end, params%force_integration_end_file)

     allocate (dr(3,ds%atoms%N))
     dr = (fd_end%pos - fd_start%pos)/real(params%force_integration_n_steps,dp)

     call add_property(ds%atoms, 'dr', 0.0_dp, 3)
     if (.not. assign_pointer(ds%atoms, 'dr', dr_prop)) &
          call system_abort("failed to add dr property to ds%atoms in force_integration task")
     dr_prop = (fd_end%pos - fd_start%pos)

     call add_property(ds%atoms, 'forces', 0.0_dp, 3)
     if (.not. assign_pointer(ds%atoms, 'forces', f_prop)) &
          call system_abort("failed to add forces property to ds%atoms in force_integration task")

     integral = 0.0_dp

     call print('Force.dr integration')
     write (line, '(a15,a15,a15,a15)') 'Step', 'Energy', 'F.dr', 'Integral(F.dr)'
     call print(line)

     do i=0,params%force_integration_n_steps

        ds%atoms%pos = fd_start%pos + dr*real(i,dp)
        call calc_connect(ds%atoms, store_is_min_image=.true.)

        if (params%simulation_classical) then
           call calc(simple_metapot, ds%atoms, f=f, e=energy, args_str=params%classical_args_str)
           if (i == 0) fd_e0 = energy
        else
           call calc(hybrid_metapot, ds%atoms, f=f)
        end if

	f_prop = f

        f_dr = f .dot. dr

        ! Simpson's rule
        if (i == 0 .or. i == params%force_integration_n_steps) then
           integral = integral + f_dr/3.0_dp
        else if (mod(i,2) == 0) then
           integral = integral + 2.0_dp/3.0_dp*f_dr
        else
           integral = integral + 4.0_dp/3.0_dp*f_dr
        end if

        if (params%simulation_classical) then
           write (line, '(i15,e15.4,f15.4,f15.4)') i, energy, f_dr, integral
        else
           write (line, '(i15,a15,f15.4,f15.4)') i, '----', f_dr, integral
        end if
        call print(line)
        call crack_print(ds%atoms, movie, params, mpi_glob)
     end do

     write (line, '(a,f15.8,a)') 'Energy difference = ', fd_e0 - energy, ' eV'
     call print(line)
     write (line, '(a,f15.8,a)') 'Integrated F.dr   = ', integral, ' eV'
     call print(line)

     deallocate(dr)
     call finalise(fd_start, fd_end)


     !****************************************************************
     !*                                                              *
     !*  GEOMETRY OPTIMISATION                                       *
     !*                                                              *
     !*                                                              *
     !****************************************************************    
  else if (trim(params%simulation_task) == 'minim') then

     call print_title('Geometry Optimisation')

     call print('Starting geometry optimisation...')

     if (params%simulation_classical) then
        steps = minim(simple_metapot, ds%atoms, method=params%minim_method, convergence_tol=params%minim_tol, &
             max_steps=params%minim_max_steps, linminroutine=params%minim_linminroutine, &
             do_pos=.true., do_lat=.false., do_print=.true., use_fire=trim(params%minim_method)=='fire', &
             print_cinoutput=movie, args_str=params%classical_args_str, eps_guess=params%minim_eps_guess, hook_print_interval=10)
     else
        steps = minim(hybrid_metapot, ds%atoms, method=params%minim_method, convergence_tol=params%minim_tol, &
             max_steps=params%minim_max_steps, linminroutine=params%minim_linminroutine, &
             do_pos=.true., do_lat=.false., do_print=.true., use_fire=trim(params%minim_method)=='fire', &
             print_cinoutput=movie, &
             eps_guess=params%minim_eps_guess, hook_print_interval=1)
     end if

  if (.not. mpi_glob%active .or. (mpi_glob%active .and.mpi_glob%my_proc == 0)) then
     call crack_update_connect(ds%atoms, params)
     call crack_print(ds%atoms, movie, params, mpi_glob)
  end if


     !****************************************************************
     !*                                                              *
     !*  QUASI-STATIC LOADING                                        *
     !*                                                              *
     !*                                                              *
     !****************************************************************    
  else if (trim(params%simulation_task) == 'quasi_static') then

     call print_title('Quasi Static Loading')

     if (.not. has_property(ds%atoms, 'load')) then
        call print('No load field found. Regenerating load.')
        call crack_calc_load_field(ds%atoms, params, classicalpot, simple_metapot, params%crack_loading, &
             .true., mpi_glob)
     end if

     call crack_update_connect(ds%atoms, params)

     dummy = get_value(ds%atoms%params, 'CrackPos', orig_crack_pos)
     crack_pos(1) = orig_crack_pos

     do while (abs(crack_pos(1) - orig_crack_pos) < params%quasi_static_tip_move_tol)

        if (params%simulation_classical) then
           steps = minim(simple_metapot, ds%atoms, method=params%minim_method, convergence_tol=params%minim_tol, &
                max_steps=params%minim_max_steps, linminroutine=params%minim_linminroutine, &
                do_pos=.true., do_lat=.false., do_print=.true., &
                print_cinoutput=movie, &
                args_str=params%classical_args_str, eps_guess=params%minim_eps_guess,use_fire=trim(params%minim_method)=='fire', hook_print_interval=100)
        else
           steps = minim(hybrid_metapot, ds%atoms, method=params%minim_method, convergence_tol=params%minim_tol, &
                max_steps=params%minim_max_steps, linminroutine=params%minim_linminroutine, &
                do_pos=.true., do_lat=.false., do_print=.true., &
                print_cinoutput=movie, eps_guess=params%minim_eps_guess, &
                use_fire=trim(params%minim_method)=='fire', hook_print_interval=100)
        end if

        call crack_update_connect(ds%atoms, params)
        if (params%simulation_classical) then
           crack_pos = crack_find_crack_pos(ds%atoms, params)
        else
           call crack_update_selection(ds%atoms, params)
           dummy = get_value(ds%atoms%params, 'CrackPosx', crack_pos(1))
        end if

        ! Apply loading field
        call print_title('Applying load')
        call crack_apply_load_increment(ds%atoms, params%crack_G_increment)
        
        call crack_print(ds%atoms, movie, params, mpi_glob)
     end do

  else

     call system_abort('Unknown task: '//trim(params%simulation_task))

  end if ! switch on simulation_task


  !** Finalisation Code **

  call finalise(movie)
  call finalise(ds)

  call finalise(simple_metapot)
  call finalise(hybrid_metapot)
  call finalise(forcemix_metapot)
  call finalise(classicalpot)
  call finalise(qmpot)

  if (allocated(f))    deallocate(f)
  if (allocated(f_fm)) deallocate(f_fm)

  call system_finalise()

end program crack
