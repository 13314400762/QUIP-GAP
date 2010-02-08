module CrackTools_module

  use libAtoms_module
  use QUIP_module
  use elasticity_module
  use CrackParams_module
  use atoms_module

  implicit none

  !% Print crack slab to XYZ file, using properties defined in 'params%io_print_properties'
  !% or all properties if 'params%io_print_all_properties' is true.
  interface crack_print
     module procedure crack_print_cio
     module procedure crack_print_filename
  end interface

contains

  subroutine crack_fix_pointers(crack_slab, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
       old_nn, hybrid, hybrid_mark) 

    type(Atoms), intent(in) :: crack_slab
    real(dp), pointer, dimension(:,:) :: load 
    integer, pointer, dimension(:) :: move_mask, nn, changed_nn, edge_mask, md_old_changed_nn, &
         old_nn, hybrid, hybrid_mark

    if (has_property(crack_slab, 'nn')) then
       if (.not. assign_pointer(crack_slab, 'nn', nn)) &
            call system_abort('nn pointer assignment failed')
    end if

    if (has_property(crack_slab, 'changed_nn')) then
       if (.not. assign_pointer(crack_slab, 'changed_nn', changed_nn)) &
            call system_abort('changed_nn pointer assignment failed')
    end if
  
    if (has_property(crack_slab, 'load')) then
       if (.not. assign_pointer(crack_slab, 'load', load)) &
            call system_abort('load pointer assignment failed')
    end if

    if (has_property(crack_slab, 'move_mask')) then
       if (.not. assign_pointer(crack_slab, 'move_mask', move_mask)) &
            call system_abort('move_mask pointer assignment failed')
    end if

    if (has_property(crack_slab, 'edge_mask')) then
       if (.not. assign_pointer(crack_slab, 'edge_mask', edge_mask)) &
            call system_abort('edge_mask pointer assignment failed')
    end if

    if (has_property(crack_slab, 'md_old_changed_nn')) then
       if (.not. assign_pointer(crack_slab, 'md_old_changed_nn', md_old_changed_nn)) &
            call system_abort('md_old_changed_nn pointer assignment failed')
    end if

    if (has_property(crack_slab, 'old_nn')) then
       if (.not. assign_pointer(crack_slab, 'old_nn', old_nn)) &
            call system_abort('old_nn pointer assignment failed')
    end if
    
    if (has_property(crack_slab, 'hybrid')) then
       if (.not. assign_pointer(crack_slab, 'hybrid', hybrid)) &
            call system_abort('hybrid pointer assignment failed')
    end if

    if (has_property(crack_slab, 'hybrid_mark')) then
       if (.not. assign_pointer(crack_slab, 'hybrid_mark', hybrid_mark)) &
            call system_abort('hybrid_mark pointer assignment failed')
    end if

  end subroutine crack_fix_pointers

  !% Parse crack name in the format is (ijk)[lmn], with negative numbers
  !% denoted by a trailing 'b' (short for 'bar'), e.g. '(111)[11b0]'
  !% Axes of crack slab returned as $3\times3$ matrix with columns
  !% $\mathbf{x}$,$\mathbf{y}$,$\mathbf{z}$.
  subroutine crack_parse_name(crackname, axes)
    character(len=*), intent(in) :: crackname
    real(dp), intent(out), dimension(3,3) :: axes

    real(dp), dimension(3) :: x,y,z
    integer :: crack(6), i, j

    j = 1
    do i=1, len(crackname)
       if (crackname(i:i) == 'b') crack(j-1) = -crack(j-1)
       if (verify(crackname(i:i), '0123456789') == 0) then
          crack(j) = ichar(crackname(i:i)) - ichar('0')
          j = j + 1
       end if
    end do

    y = (/ (real(crack(i),dp), i=1,3) /)
    z = (/ (real(crack(i),dp), i=4,6) /)
    x = y .cross. z

    write (line,'(a,3f8.3)') 'x =', x
    call print(line)
    write (line,'(a,3f8.3)') 'y =', y
    call print(line)
    write (line,'(a,3f8.3)') 'z =', z
    call print(line)

    axes(:,1) = x;  axes(:,2) = y;  axes(:,3) = z

  end subroutine crack_parse_name

  !% Calculate energy release rate $G$ from strain using 
  !% $$G = \frac{1}{2} \frac{E}{1-\nu^2} \epsilon^2 h$$
  !% from thin strip result. Quantities are:
  !% 'strain',$\epsilon$, dimensionless ratio $\frac{\Delta y}{y}$;
  !% 'E', $E$,  Young's modulus, GPa;
  !% 'v', $\nu$, Poisson ratio, dimensionless;
  !% 'height', $h$ \AA{}, 10$^{-10}$~m;
  !% 'G', Energy release rate, J/m$^2$.
  function crack_strain_to_g(strain, E, v, height)
    real(dp), intent(in) :: strain, E, v, height
    real(dp) :: crack_strain_to_g

    crack_strain_to_g = 1.0_dp/2.0_dp*E/(1-v*v)*strain*strain*height*0.1_dp

  end function crack_strain_to_g


  !% Calculate $epsilon$ from $G$, inverse of above formula.
  !% Units are as the same as 'crack_strain_to_g'
  function crack_g_to_strain(G, E, v, height)
    real(dp), intent(in) :: G, E, v, height
    real(dp) :: crack_g_to_strain

    crack_g_to_strain = sqrt(2.0_dp*G*(1.0_dp-v*v)/(E*height*0.1_dp))

  end function crack_g_to_strain

  !% Convert from energy release rate $G$ to stress intensity factor $K$
  !% Units: G (J/m$^2$), E (GPa), K (Pa sqrt(m))
  function crack_g_to_k(G, E, v, mode) result(K)
    real(dp), intent(in) :: G, E, v
    character(*), optional, intent(in) :: mode
    real(dp) :: K

    real(dp) :: Ep
    character(20) :: use_mode

    use_mode = optional_default("plane strain", mode)

    if (trim(use_mode) == 'plane stress') then
       Ep = E
    else if (trim(use_mode) == 'plane strain') then
       Ep = E/(1.0_dp-v*v)
    else
       call system_abort('crack_k_to_g: bad mode '//trim(use_mode))
    end if

    K = sqrt(G*Ep*1e9_dp)

  end function crack_g_to_k

  !% Convert from stress intensity factor $K$ to energy release rate $G$
  !% Units: G (J/m$^2$), E (GPa), K (Pa sqrt(m))
  function crack_k_to_g(K, E, v, mode) result(G)
    real(dp), intent(in) :: K, E, v
    character(*), optional, intent(in) :: mode
    real(dp) :: G

    real(dp) :: Ep
    character(20) :: use_mode

    use_mode = optional_default("plane strain", mode)

    if (trim(use_mode) == 'plane stress') then
       Ep = E
    else if (trim(use_mode) == 'plane strain') then
       Ep = E/(1.0_dp-v*v)
    else
       call system_abort('crack_k_to_g: bad mode '//trim(use_mode))
    end if

    G = K*K/(Ep*1e9_dp)

  end function crack_k_to_g


  !% Measure the current height of slab and calculate
  !% energy release rate $G$ from current and original
  !% heights and elastic constants $E$ and $\nu$, using the equation
  !% $$ G = \frac{1}{2} \frac{E}{1-\nu^2} \frac{{h - h_0}^2}{h_0} $$
  !% where $h_0$ is the original height and $h$ the new height.
  !% Otherwise, symbols and units are the same as in 'crack_strain_to_g'.
  function crack_measure_g(at, E, v, orig_height) result(G)
    type(Atoms), intent(in) :: at
    real(dp), intent(in) :: E, v, orig_height
    real(dp) :: G

    real(dp) :: new_height

    new_height = maxval(at%pos(2,:))-minval(at%pos(2,:))
    G = 0.1_dp*0.5_dp*E/(1.0_dp-v*v)*(new_height - orig_height)**2.0_dp/orig_height

  end function crack_measure_g


  !% Rescale atoms in slab, with atoms in front of either crack tip
  !% strained in y direction by 'strain' and atoms behind crack tip
  !% rigidly shifted to keep top and bottom edges flat. A transition
  !% zone is created in between with linearly varying strain to 
  !% avoid creation of defects.
  !%
  !%>  --------------------------------------
  !%>  |           |   |   |   |            |
  !%>  |           |   |___|   |            |
  !%>  |           |   |   |   |            |
  !%>  |           |   |___|   |            |
  !%>  |           |   |   |   |            |
  !%>  |    1      | 2 | 3 | 4 |     5      |
  !%>  --------------------------------------
  !% \begin{center}\begin{tabular}{clc}
  !% \hline \hline
  !% Region &  Positon & Load \\
  !% \hline
  !%   1    &  $x <$ 'l_crack_pos'-'zone_width' & $G$ \\
  !%   2    &  'l_crack_pos'-'zone_width' $\le x <$ 'l_crack_pos' & $G \to 0$ \\
  !%   3    &  'l_crack_pos' $< x <$ 'r_crack_pos'& $0$ \\
  !%   4    &  'r_crack_pos' $< x \le$ 'r_crack_pos'+'zone_width' & $0 \to G$ \\
  !%   5    &  $x >$ 'r_crack_pos'+'zone_width' & $G$ \\
  !% \hline 
  !% \hline
  !% \end{tabular}\end{center}
  subroutine crack_uniform_load(at, params, l_crack_pos, r_crack_pos, zone_width, G, apply_load, disp)
    type(Atoms), intent(inout)    :: at
    type(CrackParams), intent(in) :: params
    real(dp), intent(in)          :: l_crack_pos, r_crack_pos, zone_width
    real(dp), intent(inout)       :: G
    logical, optional             :: apply_load
    real(dp), allocatable, dimension(:,:), intent(out) :: disp

    integer ::  j
    real(dp) top_old, top_new, bottom_old, bottom_new, x, y, q, strain, E, v, &
         orig_height, new_height, crack_pos_y, y_check
    logical :: do_apply_load

    if (.not. get_value(at%params, 'OrigHeight', orig_height)) &
         call system_abort('crack_uniform_load: "OrigHeight" parameter missing')

    if (.not. get_value(at%params, 'YoungsModulus', E)) &
         call system_abort('crack_uniform_load: "YoungsModulus" missing')

    if (.not. get_value(at%params, 'PoissonRatio_yx', v)) &
         call system_abort('crack_uniform_load: "PoissonRatio_yx" missing')

    if (.not. get_value(at%params, 'CrackPosy', crack_pos_y)) & 
         call system_abort('crack_uniform_load: CrackPosy parameter missing from atoms')

    allocate(disp(3,at%N))

    ! Calculate strain corresponding to given G
    strain = crack_g_to_strain(G, E, v, orig_height)

    call print('Requested G = '//G)
    call Print('Applying strain '//strain)

    top_old = 0.0; top_new = 0.0; bottom_old = 0.0; bottom_new = 0.0

    ! Find top and bottom
    do j=1, at%N
       if (at%pos(2,j) > top_old)       top_old = at%pos(2,j)
       if (at%pos(2,j) < bottom_old) bottom_old = at%pos(2,j);
    end do

    disp = 0.0_dp

    do j=1, at%N
       x = at%pos(1,j);
       y = at%pos(2,j)-crack_pos_y; 

       ! Strain regions 1 and 5
       if (x < l_crack_pos-zone_width .or. x > r_crack_pos+zone_width) then
          disp(2,j) = strain*y
       end if

       ! Strain region 2
       if (x >= l_crack_pos-zone_width .and. x < l_crack_pos) then
          q = (x - (l_crack_pos - zone_width))/zone_width
          y_check = y
          if(params%crack_check_surface_coordination.and.at%Z(j).eq.params%crack_check_coordination_atom_type.and.abs(y).lt.params%crack_check_coordination_region) then
             call crack_check_coordination(at,params,j,y_check)
          endif 
          if (y_check >= 0.0) then
             disp(2,j) = strain*(y*(1.0-q) + top_old*q)
          else
             disp(2,j) = strain*(y*(1.0-q) + bottom_old*q)
          end if
       end if

       ! Strain region 4
       if (x > r_crack_pos .and. x <= r_crack_pos+zone_width) then
          q = (x - r_crack_pos)/zone_width;
          y_check = y
          if(params%crack_check_surface_coordination.and.at%Z(j).eq.params%crack_check_coordination_atom_type.and.abs(y).lt.params%crack_check_coordination_region) then
             call crack_check_coordination(at,params,j,y_check)
          endif 
          if (y_check >= 0.0) then
             disp(2,j) = strain*(y*q + top_old*(1.0-q))
          else
             disp(2,j) = strain*(y*q + bottom_old*(1.0-q))
          end if
       end if

       ! Rigidly shift region 3
       if (x >= l_crack_pos .and. x <= r_crack_pos) then
          y_check = y
          if(params%crack_check_surface_coordination.and.at%Z(j).eq.params%crack_check_coordination_atom_type.and.abs(y).lt.params%crack_check_coordination_region) then
             call crack_check_coordination(at,params,j,y_check)
          endif 
          if(y_check >= 0.0) then
             disp(2,j) = strain*top_old
          else
             disp(2,j) = strain*bottom_old
          end if
       end if
    end do

    do_apply_load = optional_default(.false.,apply_load)
    if (do_apply_load) then

       at%pos(2,:) = at%pos(2,:) + disp(2,:)

       new_height = maxval(at%pos(2,:))-minval(at%pos(2,:))
       call print('Measured slab height after strain = '//new_height)
       G = 0.1_dp*0.5_dp*E/(1.0_dp-v*v)*(new_height - orig_height)**2.0_dp/orig_height
       call print('Measured G = '//G)

       call set_value(at%params, 'G', G)
    end if

  end subroutine crack_uniform_load

  !% Calculate Irwin K-field stresses and/or displacements for all atoms in 'at'.
  !% Atomic positions should be the original undistorted bulk crystal positions. 
  !% 'YoungsModulus' and 'PoissonRatio_yx' parameters are extracted from 'at', along
  !% with 'CrackPos' to specify the location of the crack tip. If neither 'sig' nor 'disp'
  !% are present thenn properties are added to at if do_disp or do_sig are true.
  !% Stress is in 6 component Voigt notation: $1=xx, 2=yy, 3=zz, 4=yz, 5=zx$ and $6=xy$, and 
  !% displacement is a Cartesian vector $(u_x,u_y,u_z)$.

  !Instead of adding a property to the atom structure, return 
  !an array with sig and disp, if do_sig or do_disp are true
  subroutine crack_k_field(at, K, mode, sig, disp, do_sig, do_disp)
    type(Atoms), intent(in) :: at 
    real(dp), intent(in) :: K
    character(*), intent(in), optional :: mode
    real(dp), dimension(:,:), optional, intent(out) :: sig, disp 
    logical, optional, intent(in) :: do_sig, do_disp

    real(dp), allocatable, dimension(:,:) :: mysig
    real(dp) :: E, v, r, theta, kappa, vp, vpp, crack_pos(3), pos(3)
    character(20) :: use_mode
    logical :: my_do_sig, my_do_disp
    integer :: i

    use_mode = optional_default("plane strain", mode)
    my_do_sig  = optional_default(.false., do_sig)
    my_do_disp = optional_default(.false., do_disp)

    if (.not. get_value(at%params, 'YoungsModulus', E)) &
         call system_abort('crack_k_field: "YoungsModulus" missing')

    if (.not. get_value(at%params, 'PoissonRatio_yx', v)) &
         call system_abort('crack_k_field: "PoissonRatio_yx" missing')

    crack_pos = 0.0_dp
    if (.not. get_value(at%params, 'CrackPosx', crack_pos(1))) &
         call system_abort('crack_k_field: CrackPosx parameter missing from atoms')

    if (.not. get_value(at%params, 'CrackPosy', crack_pos(2))) &
         call system_abort('crack_k_field: CrackPosy parameter missing from atoms')

    if (trim(use_mode) == 'plane stress') then
       kappa = (3.0_dp - v)/(1.0_dp + v)
       vp = 0.0_dp
       vpp = v
    else if (trim(use_mode) == 'plane strain') then
       kappa = 3.0_dp - 4.0_dp*v
       vp = v
       vpp = 0.0_dp
    else
       call system_abort('crack_k_field: bad mode '//trim(use_mode))
    end if


    allocate(mysig(6,at%N))

    do i=1,at%N

       pos = at%pos(:,i) - crack_pos
       r = sqrt(pos(1)*pos(1) + pos(2)*pos(2))*1e-10_dp
       theta = atan2(pos(2),pos(1))

       mysig(1,i) = K/sqrt(2.0_dp*pi*r)*cos(theta/2.0_dp)*(1.0_dp - sin(theta/2.0_dp)* &
            sin(3.0_dp*theta/2.0_dp))
       
       mysig(2,i) = K/sqrt(2.0_dp*pi*r)*cos(theta/2.0_dp)*(1.0_dp + sin(theta/2.0_dp)* &
            sin(3.0_dp*theta/2.0_dp))
       
       mysig(3,i) = vp*(mysig(1,i) + mysig(2,i))
       mysig(4,i) = 0.0_dp
       mysig(5,i) = 0.0_dp
       
       mysig(6,i) = K/sqrt(2.0_dp*pi*r)*sin(theta/2.0_dp)*cos(theta/2.0_dp)* &
            cos(3.0_dp*theta/2.0_dp)

       if(my_do_disp) then
          disp(1,i) = K/(2.0_dp*E*1e9_dp)*sqrt(r/(2.0_dp*pi))*((1.0_dp+v)*(2.0_dp*kappa-1.0_dp)*cos(theta/2.0_dp) - &
               cos(3.0_dp*theta/2.0_dp))/1e-10
          disp(2,i) = K/(2.0_dp*E*1e9_dp)*sqrt(r/(2.0_dp*pi))*((1.0_dp+v)*(2.0_dp*kappa-1.0_dp)*sin(theta/2.0_dp) - &
               sin(3.0_dp*theta/2.0_dp))/1e-10
          disp(3,i) = -vpp*pos(3)*1e-10_dp/(E*1e9_dp)*(mysig(1,i) + mysig(2,i))/1e-10
       end if

    end do

    if (my_do_sig) sig = mysig/1e9_dp
    deallocate(mysig)

  end subroutine crack_k_field



  subroutine crack_apply_strain_ramp(at, G1, G2, d1, d2, d3)  !I didn't change crack tip from 1D to 2D in this routine...
    type(Atoms), intent(inout) :: at
    real(dp), intent(in) :: G1, G2, d1, d2, d3

    integer ::  j
    real(dp) x, y, q, strain1, strain2, &
         E, v, orig_height, orig_width, new_height, G

    if (.not. get_value(at%params, 'OrigHeight', orig_height)) &
         call system_abort('crack_apply_strain_ramp: "OrigHeight" parameter missing')

    if (.not. get_value(at%params, 'OrigWidth', orig_width)) &
         call system_abort('crack_apply_strain_ramp: "OrigWidth" parameter missing')

    if (.not. get_value(at%params, 'YoungsModulus', E)) &
         call system_abort('crack_apply_strain_ramp: "YoungsModulus" missing')

    if (.not. get_value(at%params, 'PoissonRatio_yx', v)) &
         call system_abort('crack_apply_strain_ramp: "PoissonRatio_yx" missing')

    ! Calculate strains corresponding to given Gs
    strain1 = crack_g_to_strain(G1, E, v, orig_height)
    strain2 = crack_g_to_strain(G2, E, v, orig_height)

    call print('Starting load G1 = '//G1//' --> strain '//strain1)
    call print('Final load    G2 = '//G2//' --> strain '//strain2)


    do j=1, at%N
       x = at%pos(1,j)
       y = at%pos(2,j)

       ! Rigidly shift first region
       if (x <= d1) then
          at%pos(2,j) = at%pos(2,j) + strain1*orig_height/2.0_dp*sign(1.0_dp,y)
       end if

       ! Linearly increasing strain in region 2
       ! Interpolate between 0 at x=d1 and strain1 at x=d2
       ! Add shift to align with first region at x=d1
       if (x > d1 .and. x <= d2) then
          q = (x - d1)/(d2-d1)
          at%pos(2,j) = at%pos(2,j) * (1.0_dp + strain1*q) + &
               strain1*orig_height/2.0_dp*sign(1.0_dp,y)*(1.0_dp-q)
       end if

       ! Decreasing strain in region 3
       ! Interpolate between strain1 at x=d2 and strain2 at x=d3
       if (x > d2 .and. x <= d3) then
          q = (x - d2)/(d3-d2)
          at%pos(2,j) = at%pos(2,j) * (1.0_dp +  (strain1*(1.0_dp-q) + strain2*q))
       end if

       ! Constant strain2 in last region
       if (x > d3) then
          at%pos(2,j) = at%pos(2,j) * (1.0_dp + strain2)
       end if

    end do

    new_height = maxval(at%pos(2,:))-minval(at%pos(2,:))
    call print('Measured slab height after strain = '//new_height)
    G = 0.1_dp*0.5_dp*E/(1.0_dp-v*v)*(new_height - orig_height)**2.0_dp/orig_height
    call print('Measured G = '//G)

    call set_value(at%params, 'G', G)

  end subroutine crack_apply_strain_ramp


  subroutine crack_setup_marks(crack_slab, params)
    type(Atoms) :: crack_slab
    type(CrackParams) :: params

    integer :: i
    real(dp), dimension(2) :: crack_pos

    ! Pointers into Atoms data structure
    real(dp), pointer, dimension(:,:) :: load!, k_disp, u_disp
    integer, pointer, dimension(:) :: move_mask, nn, changed_nn, edge_mask, md_old_changed_nn, &
         old_nn, hybrid, hybrid_mark

    call crack_fix_pointers(crack_slab, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
         old_nn, hybrid, hybrid_mark)!, u_disp, k_disp)

    ! Setup edge_mask to allow easy exclusion of edge atoms
    do i=1,crack_slab%N
       if (crack_is_edge_atom(crack_slab, i, params%selection_edge_tol)) &
	    edge_mask(i) = 1
    end do

    ! Calculate connectivity and numbers of nearest neighbours
    call crack_update_connect(crack_slab, params)

    ! Find rightmost undercoordinated atoms in bulk - this is initial crack tip position
    crack_pos = crack_find_crack_pos(crack_slab, params)

    call crack_fix_pointers(crack_slab, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
         old_nn, hybrid, hybrid_mark)!, u_disp, k_disp)

    ! clear changed_nn, hybrid and hybrid_mark 
    hybrid(:) = 0
    hybrid_mark(:) = 0
    changed_nn(:) = 0

    ! Artificially set changed_nn to 1 for atoms near to crack tip
    do i = 1, crack_slab%N
       if (distance_min_image(crack_slab, i, (/crack_pos(1),0.0_dp,0.0_dp/)) < params%crack_seed_embed_tol) &
	    changed_nn(i) = 1
    end do

    call Print('Seeded embed region with '//count(changed_nn /= 0)//' atoms.')

    call crack_update_selection(crack_slab, params)

  end subroutine crack_setup_marks

  subroutine crack_calc_load_field(crack_slab, params, classicalpot, metapot, load_method, overwrite_pos, mpi) 
    type(Atoms), intent(inout) :: crack_slab
    type(CrackParams), intent(in) :: params
    type(Potential), intent(in) :: classicalpot
    type(MetaPotential), intent(inout) :: metapot
    character(*), intent(in) :: load_method
    logical, intent(in) :: overwrite_pos
    type(MPI_Context), intent(in) :: mpi

    type(Atoms) :: crack_slab1, bulk
    real(dp), pointer, dimension(:,:) :: load
    real(dp), allocatable, dimension(:,:) :: k_disp, u_disp
    integer, pointer, dimension(:) :: move_mask, nn, changed_nn, edge_mask, md_old_changed_nn, &
         old_nn, hybrid, hybrid_mark
    type(CInOutput) :: movie
    real(dp), allocatable :: relaxed_pos(:,:), initial_pos(:,:), new_pos(:,:)
    integer :: i, k, steps
    real(dp) :: G, G1, E, v, v2, Orig_Width, Orig_Height, width1, height1
    real(dp) :: K1, r, l_crack_pos, r_crack_pos, crack_pos(2)
    !NB workaround for pgf90 bug (as of 9.0-1)
    real(dp) :: t_norm
    !NB end workaround for pgf90 bug (as of 9.0-1)

    if (.not. get_value(crack_slab%params, 'OrigHeight', orig_height)) &
         call system_abort('crack_calc_load_field: "OrigHeight" parameter missing')

    if (.not. get_value(crack_slab%params, 'OrigWidth', orig_width)) &
       call system_abort('crack_calc_load_field: "OrigWidth" parameter missing')

    if (.not. get_value(crack_slab%params, 'YoungsModulus', E)) &
         call system_abort('crack_calc_load_field: "YoungsModulus" missing')

    if (.not. get_value(crack_slab%params, 'PoissonRatio_yx', v)) &
         call system_abort('crack_calc_load_field: "PoissonRatio_yx" missing')

    if (.not. get_value(crack_slab%params, 'PoissonRatio_yz', v2)) &
         call system_abort('crack_calc_load_field: "PoissonRatio_yz" missing')

    if (.not. get_value(crack_slab%params, 'CrackPosx', crack_pos(1))) &
         call system_abort('crack_calc_load_field: "CrackPosx" missing')

    if (.not. get_value(crack_slab%params, 'CrackPosy', crack_pos(2))) &
         call system_abort('crack_calc_load_field: "CrackPosy" missing')

    if (.not. get_value(crack_slab%params, 'G', G)) &
         call system_abort('crack_calc_load_field: "G" missing')

       call add_property(crack_slab, 'load', 0.0_dp, n_cols=3)

       call crack_fix_pointers(crack_slab, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
            old_nn, hybrid, hybrid_mark)  

       if (.not. mpi%active .or. (mpi%active .and.mpi%my_proc == 0)) then
          if (params%io_netcdf) then
             call initialise(movie, 'crack_relax_loading_movie.nc', action=OUTPUT)
          else
             call initialise(movie, 'crack_relax_loading_movie.xyz', action=OUTPUT)
          end if
       end if

       if (params%crack_double_ended) then
          l_crack_pos = -params%crack_seed_length
       else
          l_crack_pos = -orig_width
       end if

       allocate(relaxed_pos(3,crack_slab%N), new_pos(3,crack_slab%N))
       allocate(k_disp(3, crack_slab%N))  
       allocate(u_disp(3, crack_slab%N))
       allocate(initial_pos(3,crack_slab%N))

       !save initial positions of crack_slab
       initial_pos = crack_slab%pos

       !create a bulk slab
       call crack_make_slab(params, classicalpot, metapot, crack_slab1, width1, height1, E, v, v2, bulk)

       ! Apply loading field   
       if (trim(load_method) == 'saved') then
 
          !relax the positions of the original slab 
          if (params%crack_relax_loading_field) then
            ! Geometry optimise
             steps = minim(metapot, crack_slab, method=params%minim_mm_method, convergence_tol=params%minim_mm_tol, &
               max_steps=params%minim_mm_max_steps, linminroutine=params%minim_mm_linminroutine, do_print=.true., &
               do_pos=.true.,do_lat=.false., use_fire=(trim(params%minim_mm_method)=='fire'), &
               print_cinoutput=movie)
          end if

          ! Save relaxed positions 
          relaxed_pos = crack_slab%pos
 
          crack_slab%pos = initial_pos 
 
          call print_title('Applying saved load increment')
          call crack_apply_load_increment(crack_slab)

       else if (trim(load_method) == 'uniform') then
 
          !relax the positions of the original slab 
          if (params%crack_relax_loading_field) then
            ! Geometry optimise
             steps = minim(metapot, crack_slab, method=params%minim_mm_method, convergence_tol=params%minim_mm_tol, &
               max_steps=params%minim_mm_max_steps, linminroutine=params%minim_mm_linminroutine, do_print=.true., &
               do_pos=.true.,do_lat=.false., use_fire=(trim(params%minim_mm_method)=='fire'), &
               print_cinoutput=movie)
          endif

          ! Save relaxed positions 
          relaxed_pos = crack_slab%pos
 
          crack_slab%pos = initial_pos  
          call print_title('Applying uniform load increment')
          ! strain it a bit
          do i=1,crack_slab%N
             crack_slab%pos(2,i) = crack_slab%pos(2,i)*(1.0_dp+params%crack_initial_loading_strain)
          end do

       else if (trim(load_method) == 'kfield') then

          call print_title('Applying K-field load increment')

          crack_slab%pos = crack_slab1%pos

          k_disp = 0.0_dp
          call print('Energy release rate     G = '//G//' J/m^2')
          call print('Stress Intensity Factor K = '//(crack_g_to_k(G,E,v)/1e6_dp)//' MPa.sqrt(m)')
          call crack_k_field(crack_slab, crack_g_to_k(G,E,v), do_sig=.false., disp=k_disp, do_disp=.true.)  

          do i=1,crack_slab%N
             crack_slab%pos(:,i) = crack_slab%pos(:,i) + k_disp(:,i)
          end do

         if (params%crack_relax_loading_field) then
              ! now relax
            steps = minim(metapot, crack_slab, method=params%minim_mm_method, convergence_tol=params%minim_mm_tol, &
                 max_steps=params%minim_mm_max_steps, linminroutine=params%minim_mm_linminroutine, do_print=.true., &
                 do_pos=.true.,do_lat=.false., use_fire=(trim(params%minim_mm_method)=='fire'), &
                 print_cinoutput=movie)
         end if
         relaxed_pos = crack_slab%pos  


          crack_slab%pos = crack_slab1%pos
          ! apply load increment
          K1 = crack_g_to_k(crack_strain_to_g( &
               crack_g_to_strain(G, E, v, orig_height) + &
               params%crack_initial_loading_strain, E, v, orig_height),E,v)
       
          k_disp = 0.0_dp
          call print('Stress Intensity Factor K_1 = '//(K1/1e6_dp)//' MPa.sqrt(m)')
          call crack_k_field(crack_slab, K1, do_sig=.false., disp=k_disp, do_disp=.true.)

          do i=1,crack_slab%N
             crack_slab%pos(:,i) = crack_slab%pos(:,i) + k_disp(:,i)
          end do


       else if (trim(load_method) == 'interp_kfield_uniform') then

          crack_slab%pos = crack_slab1%pos
          r_crack_pos = crack_pos(1)-0.85*params%crack_strain_zone_width
       
          call print('Applying load 1')

          u_disp = 0.0_dp
          call crack_uniform_load(crack_slab, params, l_crack_pos, r_crack_pos, &
               params%crack_strain_zone_width, G, apply_load=.false., disp=u_disp) 

          k_disp = 0.0_dp
          call print('Energy release rate     G = '//G//' J/m^2')
          call print('Stress Intensity Factor K = '//(crack_g_to_k(G,E,v)/1e6_dp)//' MPa.sqrt(m)')
          call crack_k_field(crack_slab, crack_g_to_k(G,E,v), do_sig=.false., disp=k_disp, do_disp=.true.)  

          r = 0.0 
          do i=1,crack_slab%N
             r = sqrt((crack_slab%pos(1,i) - crack_pos(1))**2.0_dp + &
                  (crack_slab%pos(2,i) - crack_pos(2))**2.0_dp)
             if (r > params%crack_load_interp_length) then
                crack_slab%pos(:,i) = crack_slab%pos(:,i) + u_disp(:,i)
             else
                do k=1,3
                   crack_slab%pos(k,i) = crack_slab%pos(k,i) +  &
                        linear_interpolate(0.0_dp, k_disp(k,i), params%crack_load_interp_length, u_disp(k,i), r)
                end do
             end if
          end do
 
         if (params%crack_relax_loading_field) then
            steps = minim(metapot, crack_slab, method=params%minim_mm_method, convergence_tol=params%minim_mm_tol, &
                 max_steps=params%minim_mm_max_steps, linminroutine=params%minim_mm_linminroutine, do_print=.true., &
                 do_pos=.true.,do_lat=.false., use_fire=(trim(params%minim_mm_method)=='fire'), &
                 print_cinoutput=movie)
         end if
         relaxed_pos = crack_slab%pos  

          call print('Applying new load')

          crack_slab%pos = crack_slab1%pos

          G1 = crack_strain_to_g( &
               crack_g_to_strain(G, E, v, orig_height) + &
               params%crack_initial_loading_strain, E, v, orig_height)

          u_disp = 0.0_dp
          call crack_uniform_load(crack_slab, params, l_crack_pos, r_crack_pos, &
            params%crack_strain_zone_width, G1, apply_load=.false., disp=u_disp) 

          ! apply load increment to K_disp
          K1 = crack_g_to_k(G1,E,v)

          k_disp = 0.0_dp
          call print('Energy release rate     G_1 = '//G1//' J/m^2')
          call print('Stress Intensity Factor K_1 = '//(K1/1e6_dp)//' MPa.sqrt(m)')
          call crack_k_field(crack_slab, K1, do_sig=.false., disp=k_disp, do_disp=.true.)  

          r = 0.0 
          do i=1,crack_slab%N
             r = sqrt((crack_slab%pos(1,i) - crack_pos(1))**2.0_dp + &
                  (crack_slab%pos(2,i) - crack_pos(2))**2.0_dp)
             if (r > params%crack_load_interp_length) then
                crack_slab%pos(:,i) = crack_slab%pos(:,i) + u_disp(:,i)
             else
                do k=1,3
                   crack_slab%pos(k,i) = crack_slab%pos(k,i) +  &
                        linear_interpolate(0.0_dp, k_disp(k,i), params%crack_load_interp_length, u_disp(k,i), r)
                end do
             end if
          end do
 
       end if


       if (params%crack_relax_loading_field) then
       
          ! now re-relax
           steps = minim(metapot, crack_slab, method=params%minim_mm_method, convergence_tol=params%minim_mm_tol, &
               max_steps=params%minim_mm_max_steps, linminroutine=params%minim_mm_linminroutine, do_print=.true., &
               do_pos=.true.,do_lat=.false., use_fire=(trim(params%minim_mm_method)=='fire'), &
               print_cinoutput=movie)
       end if
    
       call crack_fix_pointers(crack_slab, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
            old_nn, hybrid, hybrid_mark)  
 
       ! work out displacement field, using relaxed positions
       do i=1,crack_slab%N
          load(:,i) = crack_slab%pos(:,i) - relaxed_pos(:,i)
       end do
   
       call print('Displacement field generated. Max disp: '//maxval(load))
       !NB workaround for pgf90 bug (as of 9.0-1)
       t_norm = norm(reshape(load,(/3*crack_slab%N/)))
       !NB end workaround for pgf90 bug (as of 9.0-1)
       call print('                              RMS disp: '//(t_norm/sqrt(3.0_dp*crack_slab%N)))
   
       if (overwrite_pos) then
          crack_slab%pos = relaxed_pos
       else
          crack_slab%pos = initial_pos
       end if


    call calc_connect(crack_slab, store_is_min_image=.true.)

    deallocate(relaxed_pos, new_pos)
    deallocate(u_disp, k_disp)
    call finalise(movie)
    call finalise(crack_slab1)
    
  end subroutine crack_calc_load_field

  subroutine crack_make_seed(crack_slab, params) 
    type(Atoms), intent(inout) :: crack_slab
    type(CrackParams), intent(in) :: params

    real(dp), allocatable, dimension(:,:):: k_disp, u_disp 
    real(dp), pointer, dimension(:,:) :: load
    integer, pointer, dimension(:) :: move_mask, nn, changed_nn, edge_mask, md_old_changed_nn, &
         old_nn, hybrid, hybrid_mark
    real(dp) :: G, E, v, v2, Orig_Width, Orig_Height,  r, l_crack_pos, r_crack_pos, strain
    integer :: i, k

    call crack_fix_pointers(crack_slab, nn, changed_nn, load, move_mask, edge_mask, md_old_changed_nn, &
         old_nn, hybrid, hybrid_mark) 

    if (.not. get_value(crack_slab%params, 'OrigHeight', orig_height)) &
         call system_abort('crack_make_seed: "OrigHeight" parameter missing')

    if (.not. get_value(crack_slab%params, 'OrigWidth', orig_width)) &
         call system_abort('crack_make_seed: "OrigWidth" parameter missing')

    if (.not. get_value(crack_slab%params, 'YoungsModulus', E)) &
         call system_abort('crack_make_seed: "YoungsModulus" missing')

    if (.not. get_value(crack_slab%params, 'PoissonRatio_yx', v)) &
         call system_abort('crack_make_seed: "PoissonRatio_yx" missing')

    if (.not. get_value(crack_slab%params, 'PoissonRatio_yz', v2)) &
         call system_abort('crack_make_seed: "PoissonRatio_yz" missing')

    allocate(k_disp(3,crack_slab%N))
    allocate(u_disp(3,crack_slab%N))

    ! Determine position of seed crack
    if (.not. params%crack_double_ended) then
       l_crack_pos = -orig_width ! single ended crack
       r_crack_pos = -orig_width/2.0_dp + params%crack_seed_length
    else
       l_crack_pos = -params%crack_seed_length/2.0_dp
       r_crack_pos = params%crack_seed_length/2.0_dp
    end if

!!$    if (trim(params%crack_structure) == 'graphene') then
!!$       r_crack_pos = -orig_width
!!$    end if

    if (trim(params%crack_loading) == 'uniform') then
       if (params%crack_G > 0.0_dp) then

          call print_title('Seed crack - Uniform Load')

          G = params%crack_G
          call set_value(crack_slab%params, 'G', G)
          call set_value(crack_slab%params, 'CrackPosx', r_crack_pos + 0.85_dp*params%crack_strain_zone_width)
          call set_value(crack_slab%params, 'CrackPosy', 0.0_dp)
          call set_value(crack_slab%params, 'OrigCrackPos', r_crack_pos + 0.85_dp*params%crack_strain_zone_width)
          call crack_uniform_load(crack_slab, params, l_crack_pos, r_crack_pos, &
               params%crack_strain_zone_width, G, apply_load=.true., disp=u_disp) 

          if(params%crack_rescale_x_z) then
             !  Rescale in x direction by v and in z direction by v2
             if (.not. get_value(crack_slab%params,'OrigHeight',orig_height)) orig_height = 0.0_dp
             strain = crack_g_to_strain(params%crack_G, E, v, orig_height)
             crack_slab%pos(1,:) = crack_slab%pos(1,:)*(1.0_dp-v*strain)
             crack_slab%pos(3,:) = crack_slab%pos(3,:)*(1.0_dp-v2*strain)
             crack_slab%lattice(3,3) = crack_slab%lattice(3,3)*(1.0_dp-v2*strain)
             call atoms_set_lattice(crack_slab, crack_slab%lattice)
          elseif(params%crack_rescale_x) then 
             !  Rescale in x direction by v 
             if (.not. get_value(crack_slab%params,'OrigHeight',orig_height)) orig_height = 0.0_dp
             strain = crack_g_to_strain(params%crack_G, E, v, orig_height)
             crack_slab%pos(1,:) = crack_slab%pos(1,:)*(1.0_dp-v*strain)
          endif
       end if

    else if (trim(params%crack_loading) == 'ramp') then

       call print_title('Seed crack - Loading Ramp')

       call crack_apply_strain_ramp(crack_slab, params%crack_G, params%crack_ramp_end_G, r_crack_pos, &
            r_crack_pos+params%crack_strain_zone_width, &
            r_crack_pos+params%crack_strain_zone_width+params%crack_ramp_length)

    else if (trim(params%crack_loading) == 'kfield') then

       call print_title('Seed crack - Irwin K-field Loading')

       if (.not. get_value(crack_slab%params,'OrigHeight',orig_height)) orig_height = 0.0_dp

       call print('Initial stress intesity factor K_0 = '//crack_g_to_k(params%crack_G, E, v)/1e6_dp//' MPa.sqrt(m)')

       call set_value(crack_slab%params, 'CrackPosx', r_crack_pos + 0.85_dp*params%crack_strain_zone_width)
       call set_value(crack_slab%params, 'CrackPosy', 0.0_dp)
       call set_value(crack_slab%params, 'OrigCrackPos', r_crack_pos + 0.85_dp*params%crack_strain_zone_width)
       call set_value(crack_slab%params, 'G', params%crack_G)
       call crack_k_field(crack_slab, crack_g_to_k(params%crack_G, E, v), disp=k_disp, do_disp=.true.)  

       do i=1,crack_slab%N
          crack_slab%pos(:,i) = crack_slab%pos(:,i) + k_disp(:,i)
       end do

    else if (trim(params%crack_loading) == 'interp_kfield_uniform') then

       ! interpolate linearly between K field (near tip) and uniform loading (near edge)

       call print_title('Seed crack - K-field and Uniform Loading')

       k_disp = 0.0_dp
       u_disp = 0.0_dp
       call print('Interpolation length '//params%crack_load_interp_length//' A')

       if (.not. get_value(crack_slab%params,'OrigHeight',orig_height)) orig_height = 0.0_dp

       call print('Initial energy release rate    G_0 = '//params%crack_G//' J/m^2')
       call print('Initial stress intesity factor K_0 = '//crack_g_to_k(params%crack_G, E, v)/1e6_dp//' MPa.sqrt(m)')


       call set_value(crack_slab%params, 'CrackPosx', r_crack_pos + 0.85_dp*params%crack_strain_zone_width)
       call set_value(crack_slab%params, 'CrackPosy', 0.0_dp)
       call set_value(crack_slab%params, 'OrigCrackPos', r_crack_pos + 0.85_dp*params%crack_strain_zone_width)

       call crack_k_field(crack_slab, crack_g_to_k(params%crack_G, E, v), disp=k_disp, do_disp=.true.)

       G = params%crack_G
       call crack_uniform_load(crack_slab, params, l_crack_pos, r_crack_pos, &
            params%crack_strain_zone_width, G, apply_load=.false., disp=u_disp)  
       call set_value(crack_slab%params, 'G', G)

       do i=1,crack_slab%N
          r = sqrt((crack_slab%pos(1,i) - (r_crack_pos + 0.85*params%crack_strain_zone_width))**2.0_dp + &
               crack_slab%pos(2,i)**2.0_dp)
          if (r > params%crack_load_interp_length) then
             crack_slab%pos(:,i) = crack_slab%pos(:,i) + u_disp(:,i)
          else
             do k=1,3
                crack_slab%pos(k,i) = crack_slab%pos(k,i) +  &
                     linear_interpolate(0.0_dp, k_disp(k,i), params%crack_load_interp_length, u_disp(k,i), r)
             end do
          end if
       end do
    else
       call system_abort('Unknown loading type '//trim(params%crack_loading))
    end if

    deallocate(u_disp) 
    deallocate(k_disp) 

  end subroutine crack_make_seed


  !% Increase the load by adding the the load displacement field
  !% to the atomic positions. The routine recalculates the loading 
  !% G and stores it in the atom parameter dictionary.
  subroutine crack_apply_load_increment(at, G_increment)
    type(Atoms) :: at
    real(dp), optional :: G_increment

    integer :: i
    real(dp), pointer, dimension(:,:) :: load
    real(dp) :: orig_height, new_height, G, E, v
    real(dp) :: load_scale, my_G_increment
    real(dp) :: cur_height, cur_G, test_height, load_dheight, prefactor, target_G

    if (.not. get_value(at%params, 'OrigHeight', orig_height)) &
         call system_abort('crack_apply_load_increment: "OrigHeight" parameter missing from atoms structure')

    if (.not. get_value(at%params, 'YoungsModulus', E)) &
         call system_abort('crack_apply_load_increment: "YoungsModulus" missing')

    if (.not. get_value(at%params, 'PoissonRatio_yx', v)) &
         call system_abort('crack_apply_load_increment: "PoissonRatio_yx" missing')

    if (.not. assign_pointer(at, 'load', load)) &
         call system_abort('crack_apply_load_increment: load field is missing')

    my_G_increment = optional_default(0.0_dp, G_increment)
    if (my_G_increment .fne. 0.0_dp) then
       ! calc cur properties
       cur_height = maxval(at%pos(2,:))-minval(at%pos(2,:))
       cur_G = 0.1_dp*0.5_dp*E/(1.0_dp-v*v)*(cur_height - orig_height)**2.0_dp/orig_height
       target_G = cur_G + G_increment

       call print("crack_apply_load: doing G_increment, cur_G="//cur_G)

       ! calc properties after full load_step
       do i=1,at%N
          at%pos(:,i) = at%pos(:,i) + load(:,i)
       end do
       test_height = maxval(at%pos(2,:))-minval(at%pos(2,:))
       load_dheight = test_height-cur_height
       ! step back to orig positions
       do i=1,at%N
          at%pos(:,i) = at%pos(:,i) - load(:,i)
       end do

       ! cur_G = A (cur_h-orig_h)^2/orig_h
       ! load_dheight = test_height - cur_height
       ! target_G = A (cur_h + x load_dh - orig_h)^2/orig_h
       !
       ! A = cur_G*orig_h / (cur_h-orig_h)^2
       ! x = (sqrt(target_G*orig_h/A)-cur_h+orig_h)/load_dh
       prefactor = cur_G*orig_height / (cur_height-orig_height)**2
       load_scale = (sqrt(target_G*orig_height/prefactor) - cur_height + orig_height) / load_dheight
    else
       load_scale = 1.0_dp
    endif

    do i=1,at%N
       at%pos(:,i) = at%pos(:,i) + load_scale*load(:,i)
    end do
    call calc_dists(at)

    new_height = maxval(at%pos(2,:))-minval(at%pos(2,:))
    call print('crack_apply_load: new height = '//new_height)
    G = 0.1_dp*0.5_dp*E/(1.0_dp-v*v)*(new_height - orig_height)**2.0_dp/orig_height
    call print('crack_apply_load: new loading G = '//G)

    call set_value(at%params, 'G', G)

  end subroutine crack_apply_load_increment



  !% Return true if the point 'd' is within an ellipse centred at the origin
  !% with the $x$, $y$, and $z$ radii specifeid in the vector 'ellipse'.
  function in_ellipse(d, ellipse)
    real(dp), dimension(3), intent(in) :: d, ellipse
    logical :: In_Ellipse

    In_Ellipse = (d(1)/ellipse(1))*(d(1)/ellipse(1))+ &
         (d(2)/ellipse(2))*(d(2)/ellipse(2))+ &
         (d(3)/ellipse(3))*(d(3)/ellipse(3)) < 1.0_dp
  end function in_ellipse


  !% Select atoms in ellipse around atom 'c'.
  !% Principal radii of ellipse in $x$,$y$ and $z$ directions
  !% are given by the components of the vector 'ellipse'
  !% 'ellipse_bias' shifts ellipse, positive values forward
  !% On exit 'list' contains indexes of selected atoms.
  subroutine select_ellipse(at, ellipse, ellipse_bias, list, c)
    type(Atoms), intent(in) :: at
    real(dp), intent(in) :: ellipse(3), ellipse_bias(3)
    type(Table), intent(inout) :: list
    integer, intent(in) :: c

    integer :: i
    real(dp) :: p(3), cutoff

    call table_allocate(list, 4, 0, 0, 0)
    call append(list, (/c,0,0,0/))

    if (at%use_uniform_cutoff) then
       cutoff = at%cutoff*bond_length(at%Z(c),at%Z(c))
    else
       cutoff = at%cutoff
    endif

    ! Grow in all directions by enough steps to select sphere of 2*principal radius.
    ! With nneigh_only set to false, each hop will increase radius by about the
    ! neighbour cutoff distance
    call bfs_grow(at, list, max(nint(2.5_dp*maxval(ellipse)/cutoff),1), &
         nneighb_only=.false., min_images_only = .true.)

    ! Remove things we've added that are outside ellipse
    i = 1
    do while (i <= list%N)
       p = diff(at,c,list%int(1,i),list%int(2:4,i))
       p = p - ellipse_bias ! bias ellipse (arbitrary direction)
       if (.not. In_Ellipse(p, ellipse)) then
          call delete(list, i)
       else
          i = i + 1
       end if
    end do

  end subroutine select_ellipse


  !% Returns true if atom 'i' is near to an open surface of slab.
  !% Open surfaces are planes at $x = \pm$'OrigWidth/2' and $y = \pm$'OrigHeight/2'
  !% Near to means within 'edge_gap' of the surface.
  function crack_is_edge_atom(slab, i, edge_gap)
    type(Atoms), intent(in) :: slab
    integer, intent(in) :: i
    real(dp), intent(in) :: edge_gap
    logical :: crack_is_edge_atom
    real(dp) :: width, height

    if (.not. get_value(slab%params, 'OrigWidth', width)) &
         call system_abort('crack_is_edge_atom: "OrigWidth" parameter missing')

    if (.not. get_value(slab%params, 'OrigHeight', height)) &
         call system_abort('crack_is_edge_atom: "OrigWidth" parameter missing')

    crack_is_edge_atom =  abs(slab%pos(2,i)) > height/2.0_dp - edge_gap .or. &
         abs(slab%pos(1,i)) > width/2.0_dp - edge_gap

  end function crack_is_edge_atom


  !% Update the connectivity of a crack slab. calc_connect is only called if 
  !% necessary (i.e. if the maximal atomic displacement is bigger than
  !% 'params%md_recalc_connect_factor*params%md_crust'
  !% The 'nn' and 'changed_nn' properties are updated each call, with
  !% the (cheaper) nearest neighbour calc_connect always being perforemd.
  subroutine crack_update_connect(at, params)
    type(Atoms), intent(inout) :: at
    type(CrackParams), intent(in) :: params

    type(Atoms), save :: nn_atoms
    real(dp) :: max_disp
    real(dp), allocatable, save, dimension(:,:) :: stored_pos
    integer, pointer, dimension(:) :: old_nn, nn, changed_nn, edge_mask
    integer :: i
    logical :: first_time

    call system_timer('connectivity update')

    if (.not. assign_pointer(at, 'nn', nn)) &
         call system_abort('crack_update_connect: nn property missing from atoms')

    if (.not. assign_pointer(at, 'old_nn', old_nn)) &
         call system_abort('crack_update_connect: old_nn property missing from atoms')

    if (.not. assign_pointer(at, 'changed_nn', changed_nn)) &
         call system_abort('crack_update_connect: changed_nn property missing from atoms')

    if (.not. assign_pointer(at, 'edge_mask', edge_mask)) &
         call system_abort('crack_update_connect: edge property missing from atoms')

    ! First time we need to allocate stored_pos
    first_time = .false.
    if (.not. allocated(stored_pos)) then
       allocate(stored_pos(3,at%N))
       stored_pos = 0.0_dp
       first_time = .true.
       nn_atoms = at  ! First time we copy entire atoms structure
    end if

    if (.not. first_time) then
       max_disp = maxval(norm2(stored_pos - at%pos, 1))
       call print('Maximum atomic displacement since last calc_connect is '//max_disp)
    end if

    if (first_time .or. (max_disp > params%md_recalc_connect_factor*params%md_crust)) then
       call print('Recalculating connectivity')
       call calc_connect(at, store_is_min_image=.true.)
       stored_pos = at%pos ! Save positions for next time
    end if

    call print('Recalculating nearest neighbour table')
    call atoms_set_cutoff_factor(nn_atoms, params%md_nneigh_tol)
    if (trim(params%simulation_task) == 'md' .and. associated(at%avgpos)) then
       nn_atoms%pos = at%avgpos
    else
       nn_atoms%pos = at%pos
    end if
    call calc_connect(nn_atoms)

    ! fix pointers - calc_connect() may have called map_into_cell() which adds properties
    if (.not. assign_pointer(at, 'nn', nn)) &
         call system_abort('crack_update_connect: nn property missing from atoms')

    if (.not. assign_pointer(at, 'old_nn', old_nn)) &
         call system_abort('crack_update_connect: old_nn property missing from atoms')

    if (.not. assign_pointer(at, 'changed_nn', changed_nn)) &
         call system_abort('crack_update_connect: changed_nn property missing from atoms')

    if (.not. assign_pointer(at, 'edge_mask', edge_mask)) &
         call system_abort('crack_update_connect: edge property missing from atoms')    

    nn = 0
    do i = 1,nn_atoms%N
       nn(i) = atoms_n_neighbours(nn_atoms, i)
    end do

    if (all(old_nn == 0)) old_nn = nn ! Special case for first time

    ! Age all the NN changes by 1
    where (changed_nn /= 0) changed_nn = changed_nn + 1

    ! Update changed_nn flag (excludes edge atoms)
    where (edge_mask == 0 .and. nn /= old_nn) changed_nn = 1

    if (count(changed_nn == 1) /= 0) then
       call print('CONNECT '//count(changed_nn == 1)//' atoms changed their neighbour count.')
    end if
    old_nn = nn

    call system_timer('connectivity update')

  end subroutine crack_update_connect


  !% Update QM selection region for a crack configuration using the 'nn' and 'changed_nn'
  !% properties and the 'CrackPos' parameter from the atoms structure, as well as the
  !% selection parameters in 'params'. If 'update_embed' is true then the embed region is
  !% updated, otherwise we simply recompute the fit region from the embed region.
  !% The value of 'num_directionality' returned can be passed to adjustable_potential_init.
  subroutine crack_update_selection(at, params)
    type(Atoms), intent(inout) :: at
    type(CrackParams), intent(in) :: params

    integer :: p, i, j, surface, age, ti
    type(Table) :: old_embed, selectlist(2), tmp_select, embedlist, temptable
    type(Table), dimension(2) :: new_embed
    integer, allocatable, dimension(:) :: sindex
    real(dp), allocatable, dimension(:) :: sorted, tip_dist
    real(dp), dimension(2,3) :: selection_ellipse
    real(dp) :: ellipse_bias(3), crack_pos(3)
    integer :: dislo_seed, temp_N, crack_tip_atom 

    integer, pointer, dimension(:) :: nn, changed_nn, hybrid, edge_mask

    call system_timer('selection update')

    if (.not. assign_pointer(at, 'nn', nn)) &
         call system_abort('crack_update_selection: nn property missing from atoms')

    if (.not. assign_pointer(at, 'edge_mask', edge_mask)) &
         call system_abort('crack_update_selection: nn property missing from atoms')

    if (.not. assign_pointer(at, 'changed_nn', changed_nn)) &
         call system_abort('crack_update_selection: changed_nn property missing from atoms')

    if (.not. assign_pointer(at, 'hybrid', hybrid)) &
         call system_abort('crack_update_selection: atoms structure is missing hybrid property')


    if (.not. get_value(at%params, 'CrackPosx', crack_pos(1))) &
         call system_abort('crack_update_selection: CrackPosx parameter missing from atoms')

    if (.not. get_value(at%params, 'CrackPosy', crack_pos(2))) &
         call system_abort('crack_update_selection: CrackPosy parameter missing from atoms')

    call print('Building QM selection zone...')
    
    call allocate(embedlist, 1,0,0,0)
    call allocate(old_embed, 1,0,0,0)
    call print('count(changed_nn /= 0) = '//count(changed_nn /= 0))
    call print('Got '//count(hybrid == HYBRID_ACTIVE_MARK)//' old embed atoms')
    if (count(hybrid == HYBRID_ACTIVE_MARK) /= 0) &
         call append(old_embed, find(hybrid == HYBRID_ACTIVE_MARK))

    selection_ellipse(1,:) = params%selection_ellipse
    selection_ellipse(2,:) = params%selection_ellipse
    do i=1,3
       selection_ellipse(2,i) = selection_ellipse(2,i) + params%selection_ellipse_buffer
    end do
    ellipse_bias = 0.0_dp
    ! bias ellipse forward by arbitrary fraction of a radius (0.5 => 1/4 back, 3/4 ahead)
    ellipse_bias(1) = params%selection_ellipse_bias*selection_ellipse(1,1)

    !if there is a dislo_seed, add qm atoms around the dislocation core
    call allocate(temptable, 4,0,0,0)
    dislo_seed = params%crack_dislo_seed
    temp_N=0
    if (dislo_seed .ne. 0) then
       call print('DISLOCATION: adding atoms around the core '//dislo_seed)
       call bfs_grow(at, temptable, dislo_seed, 3,nneighb_only=.false.,min_images_only=.true.)
       temp_N = temptable%N
       call print('found '//temp_N//' extra qm atoms')
    endif

    ! Do selection twice, once to get inner and once to get outer surface
    do surface=1,2
       
       call table_allocate(selectlist(surface), 5, 0, 0, 0)

       ! Mark ellipsoid around each real atom with changed_nn /= 0 with its age
       !  - If central (active) atom already marked, keep the newer mark
       !  - If embedded atoms already marked, also keep newer mark
       
       do i=1,at%N
          if (changed_nn(i) == 0) cycle
          
          if (abs(at%pos(1,i)-crack_pos(1)) < params%selection_cutoff_plane .and. & 
               abs(at%pos(2,i)-crack_pos(2)) < params%selection_cutoff_plane) then
             
             p = Find_in_array(selectlist(surface)%int(1,1:selectlist(surface)%N), i)
             if (p == 0) then
                call append(selectlist(surface), (/i,0,0,0,changed_nn(i)/))
             else
                selectlist(surface)%int(5,p) = min(selectlist(surface)%int(5,p), changed_nn(i))
             end if
             
             if (old_embed%N == 0) then
                ! First time we do embedding, use ellipse halfway between inner and outer
                call select_ellipse(at, 0.5_dp*(selection_ellipse(1,:) + selection_ellipse(2,:)), &
                     ellipse_bias, tmp_select, i)
             else
                call select_ellipse(at, selection_ellipse(surface,:), ellipse_bias, tmp_select, i)
             end if
             
             do j = 1, tmp_select%N
                p = Find_in_array(int_part(selectlist(surface),(/1,2,3,4/)), tmp_select%int(:,j))
                if (p == 0) then
                   ! Marking for first time
                   call append(selectlist(surface), (/tmp_select%int(:,j), changed_nn(i)/))
                else
                   ! Keep newer mark
                   selectlist(surface)%int(5,p) = min(selectlist(surface)%int(5,p), changed_nn(i))
                end if
             end do
          end if
       end do
    
       ! Sort by age of NN changes, most recent are smallest values
       allocate(sorted(selectlist(surface)%N))
       allocate(tip_dist(selectlist(surface)%N))
       allocate(sindex(selectlist(surface)%N))
       sorted = selectlist(surface)%int(5,1:selectlist(surface)%N)
       
       ! multiply sorted by abs(distance from tip). 
       do i = 1, selectlist(surface)%N
          j = selectlist(surface)%int(1,i)
          tip_dist(i) =  ((crack_pos(1)-at%pos(1,j))**2+(crack_pos(2)-at%pos(2,j))**2)**(1/2)
          sorted(i) = sorted(i)*tip_dist(i)
       enddo

	   call insertion_sort(sorted, sindex)

       i = 1
       do while (i <= selectlist(surface)%N .and. new_embed(surface)%N < params%selection_max_qm_atoms-temp_N) 
          age = sorted(i)
          write (line, '(a,i0)') '  Selecting changed_nn age ', age
          call print(line)
          
          do while(i <= selectlist(surface)%N)
             if (sorted(i) /= age) exit
             call append(new_embed(surface), selectlist(surface)%int(1:4,sindex(i)))
             i = i + 1
          end do
          
          write (line,'(a,i0,a,i0,a)') 'Surface ',surface,' Now embedding ', new_embed(surface)%N, ' atoms'
          call print(line)
       end do
       
       deallocate(sorted)
       deallocate(tip_dist)
       deallocate(sindex)

       ! First time there's no need to go round twice
       if(old_embed%N == 0) exit
    end do


    call wipe(embedlist)

    ! Keep old embed atoms unless they're now outside outer surface
    do i=1,old_embed%N
       if (is_in_array(new_embed(2)%int(1,1:new_embed(2)%N), old_embed%int(1,i))) &
            call append(embedlist, old_embed%int(:,i))
    end do
    
    ! Add atoms inside inner surface
    do i=1,new_embed(1)%N
       if (.not. is_in_array(embedlist%int(1,1:embedlist%N), new_embed(1)%int(1,i))) &
            call append(embedlist, new_embed(1)%int(1,i))
    end do
    
    call Print('Embedding '//embedlist%N//' atoms.')

    call finalise(old_embed)
    call finalise(new_embed(1))
    call finalise(new_embed(2))
    call finalise(selectlist(1))
    call finalise(selectlist(2))
    call finalise(tmp_select)


!!$    ! Grow QM region to form fit region
!!$    call print('Building fit zone...')
!!$
!!$    if (params%hack_fit_on_eqm_coordination_only) then
!!$       fitlist = embedlist
!!$
!!$       ! Only add atoms which aren't undercoordinated to fit list
!!$       do i=1, params%fit_hops
!!$          call wipe(tmplist)
!!$          call bfs_step(at, fitlist, tmplist, nneighb_only = .true., min_images_only = .true.)
!!$          do j=1,tmplist%N
!!$             if (nn(tmplist%int(1,j)) == params%md_eqm_coordination) call append(fitlist, tmplist%int(:,j)) 
!!$          end do
!!$       end do
!!$    else
!!$       fitlist = embedlist
!!$       call bfs_grow(at, fitlist, params%fit_hops, min_images_only = .true.)
!!$    end if
!!$    call print('Fitting on '//fitlist%N//' atoms')
!!$
!!$    ! How many atoms should we require good directionality on, i.e. good spring
!!$    ! spanning of 3D space?
!!$    if (params%selection_directionality) then
!!$       num_directionality = embedlist%N
!!$    else
!!$       num_directionality = 0
!!$    end if

    ! Update crack position: set to average of embed atom time-averaged x coordinate
    ! (or just normal positions if we're not doing MD)
    !if (embedlist%N /= 0) then
    !   crack_pos(1) = 0.0_dp
    !   do i=1,embedlist%N
    !      if (trim(params%simulation_task) == 'md' .and. associated(at%avgpos)) then

    !         lattice_coord = at%g .mult. at%avgpos(:,embedlist%int(1,i))
    !         do n=1,3
    !            if ((lattice_coord(n) < -0.5_dp) .or. (lattice_coord(n) >= 0.5_dp)) then
    !               k = floor(lattice_coord(n)+0.5_dp)
    !               lattice_coord(n) = lattice_coord(n) - k
    !            end if
    !         end do

    !         real_pos = at%lattice .mult. lattice_coord
    !         crack_pos(1) = crack_pos(1) + real_pos(1)
    !      else
    !         crack_pos(1) = crack_pos(1) + at%pos(1,embedlist%int(1,i))
    !      end if
    !   end do
    !   crack_pos(1) = crack_pos(1)/embedlist%N
    !end if
    !call Print('Crack position x = '//crack_pos(1))
    !call set_value(at%params, 'CrackPosx', crack_pos(1))

    !update crack position: use embedlist and find 
    !the rightmost undercoordinated atom within that

    crack_pos(1) = -100000.0_dp
    crack_tip_atom = 0
    do j=1,embedlist%N
       i = embedlist%int(1,j)
       ti = find_in_array(params%crack_z, at%z(i))
       if (ti == 0) call system_abort('Bad atom type i='//i//' z='//at%z(i))
       if (nn(i) >= params%md_eqm_coordination(ti)) cycle
       if (edge_mask(i) == 1) cycle
       if (at%pos(1,i) > crack_pos(1)) then
          crack_pos(1) = at%pos(1,i)
          crack_pos(2) = at%pos(2,i)
          crack_tip_atom = i
       end if
    end do

    crack_pos(3) = 0.0_dp 

    call Print('Crack position x = '//crack_pos(1)//' near atom '//crack_tip_atom)
    call Print('Crack position y = '//crack_pos(2)//' near atom '//crack_tip_atom)
    call set_value(at%params, 'CrackPosx', crack_pos(1))
    call set_value(at%params, 'CrackPosy', crack_pos(2))

    !quantum atoms around the dislocation
    if (dislo_seed .ne. 0) then
       do i = 1, temp_N
          if (.not.Is_In_Array(int_part(embedlist,1),temptable%int(1,i))) then
             call append(embedlist,temptable%int(1,i))
          endif
       enddo
       call print('atoms in the embedlist after = '//embedlist%N)
     endif

    ! Copy embedlist to 'hybrid' property
    hybrid = 0
    hybrid(int_part(embedlist,1)) = 1

    call system_timer('selection update')

    call finalise(embedlist)

  end subroutine crack_update_selection


  !% Return $x$ coordinate of rightmost undercoordinated atom
  function crack_find_crack_pos(at, params) result(crack_pos)
    type(Atoms), intent(inout) :: at
    type(CrackParams) :: params
    real(dp), dimension(2) :: crack_pos

    integer :: i, crack_tip_atom, ti
    integer, pointer, dimension(:) :: nn, edge_mask
    real(dp) :: orig_width

    if (.not. assign_pointer(at, 'nn', nn)) &
         call system_abort('crack_find_crack_pos: nn property missing from atoms')

    if (.not. assign_pointer(at, 'edge_mask', edge_mask)) &
         call system_abort('crack_find_crack_pos: edge property missing from atoms')

    if (.not. get_value(at%params, 'OrigWidth', orig_width)) &
         call system_abort('crack_find_crack_pos: "OrigWidth" parameter missing from atoms')
    
    crack_pos(1) = -orig_width
    crack_tip_atom = 0
    do i=1,at%N
       ti = find_in_array(params%crack_z, at%z(i))
       if (nn(i) >= params%md_eqm_coordination(ti)) cycle
       if (edge_mask(i) == 1) cycle
       if (at%pos(1,i) > crack_pos(1)) then
          crack_pos(1) = at%pos(1,i)
          crack_pos(2) = at%pos(2,i)
          crack_tip_atom = i
       end if
    end do

    call Print('Crack position = '//crack_pos//' near atom '//crack_tip_atom)
    call set_value(at%params, 'CrackPosx', crack_pos(1))
    call set_value(at%params, 'CrackPosy', crack_pos(2))

  end function crack_find_crack_pos

  function percolation_step(grid)
    integer, dimension(:,:,:), intent(inout) :: grid
    logical :: percolation_step

    integer i,j,k
    integer, allocatable, dimension(:,:,:) :: ngrid

    ! Copy of `grid` with bounds (0:nx+1,0:ny+1,0:nz+1) and zeros around edges
    allocate(ngrid(0:size(grid,1)+1,0:size(grid,2)+1,0:size(grid,3)+1))
    ngrid = 0
    ngrid(1:size(grid,1),1:size(grid,2),1:size(grid,3)) = grid

    ! Age burned out regions
    where (grid >= 2)
       grid = grid + 1
    end where

    ! Spread fire
    do k=1,size(grid,3)
       do j=1,size(grid,2)
          do i=1,size(grid,1)
             if (ngrid(i,j,k) /= 1) cycle

             if (ngrid(i+1,j,k) == 2 .or. ngrid(i-1,j,k) == 2 .or. &
                 ngrid(i,j+1,k) == 2 .or. ngrid(i,j-1,k) == 2 .or. &
                 ngrid(i,j,k+1) == 2 .or. ngrid(i,j,k-1) == 2) then
                grid(i,j,k) = 2
             end if
          end do
       end do
    end do

    deallocate(ngrid)

    ! Return true if fire still alive
    percolation_step = count(grid == 2) /= 0

  end function percolation_step


  !% Locate crack tips within 'at' using a percolation algorithm. A grid with cells
  !% of side 'params%crack_tip_grid_size' is initialised and populated with 1s in cells containing
  !% atoms and 0s where there are no atoms. The percolation is then
  !% seeded in the void at (0,0,0) for a double-ended crack or (-OrigWidth/2, 0, 0)
  !% for a single-ended crack, and then spreads between connected cells
  !% like a forest fire. A filter is used to remove local minima closer than 
  !% 'params%crack_tip_min_separation' cells from one another. The result is a Table
  !% with realsize=3 containing the coordinates of the crack tips detected. 
  !% If a through-going crack is detected the result table will have size zero.
  subroutine crack_find_tips(at, params, crack_tips)
    type(Atoms), intent(inout) :: at
    type(CrackParams), intent(in) :: params
    type(Table), intent(out) :: crack_tips

    type(Connection) :: connect
    type(Table) :: minima
    integer, dimension(:,:,:), allocatable, target :: cells, min_cells
    integer :: cellsna, cellsnb, cellsnc, min_dist
    integer :: start_i, start_j, start_k, i, j, k, nstep, crack_cell(3), d1, d2
    integer :: min_i, max_i, min_j, max_j, min_k, max_k, fill
    integer :: top_edge, bottom_edge, left_edge, right_edge
    real(dp) :: crack_t(3), orig_width, start_pos(3)
    logical :: duplicate
    integer, pointer, dimension(:) :: horz_slice, vert_slice

    if (.not. get_value(at%params, 'OrigWidth', orig_width)) &
         call system_abort('crack_find_tips: "OrigWidth" parameter missing from atoms')

    ! Construct temporary Connection object and partition atoms into cells
    call print('crack_find_tips: allocating percolation grid with cell size '//params%crack_tip_grid_size//' A', VERBOSE)
    call divide_cell(at%lattice, params%crack_tip_grid_size, cellsNa, cellsNb, cellsNc)
    call connection_initialise(connect, at%N, at%pos, at%lattice, at%g)
    call connection_cells_initialise(connect, cellsna, cellsnb, cellsnc, at%n)
    call partition_atoms(connect, at)

    allocate(cells(connect%cellsNa,connect%cellsNb, connect%cellsNc))
    allocate(min_cells(connect%cellsNa,connect%cellsNb, connect%cellsNc))
    call allocate(crack_tips, 0, 3, 0, 0)

    cells = 0
    do k=1,connect%cellsnc
       do j=1,connect%cellsnb
          do i=1,connect%cellsna
             if (connect%cell(i,j,k)%n == 0) cells(i,j,k) = 1
          end do
       end do
    end do

    if (params%crack_double_ended) then
       start_pos = (/ 0.0_dp, 0.0_dp, 0.0_dp /)
    else
       start_pos = (/ -orig_width/2.0_dp, 0.0_dp, 0.0_dp /)
    end if

    call cell_of_pos(connect, at%g, start_pos, start_i, start_j, start_k)

    if (cells(start_i, start_j, start_k) /= 1) &
         call system_abort('crack_find_tips: cannot start percolation since start_pos='//start_pos//' is not in void')

    call print('crack_find_tips: seeding percolation in cell ('//i//','//j//','//k//')', VERBOSE)

    ! For single ended crack, stop percolation from going backwards
    if (.not. params%crack_double_ended) cells(1:start_i,:,:) = 0

    ! Seed percolation at start_pos then allow "fire" to percolate through cells
    cells(start_i,start_j,start_k) = 2
    nstep = 0
    do while (percolation_step(cells))
       nstep = nstep + 1
    end do
    call print('crack_find_tips: percolation completed in '//nstep//' steps', VERBOSE)

    ! Check for presence of a through-going crack

    ! Find cells containing top and bottom edges of slab
    vert_slice => cells(max(1,size(cells,1)/2),:,max(1,size(cells,3)/2))
    top_edge = 1
    do while (vert_slice(top_edge) /= 1)
       top_edge = top_edge + 1
    end do
    top_edge = top_edge + 2

    bottom_edge = size(vert_slice)
    do while (vert_slice(bottom_edge) /= 1)
       bottom_edge = bottom_edge - 1
    end do
    bottom_edge = bottom_edge - 2

    ! Find cells containing left and right edges of slab
    if (params%crack_double_ended) then
       left_edge = 1
       right_edge = -1
    else
       horz_slice => cells(:,max(1,size(cells,2)/2),max(1,size(cells,3)/2))

       left_edge = 1
       do while (horz_slice(left_edge) /= 1)
          left_edge = left_edge + 1
       end do
       left_edge = left_edge + 2
       
       right_edge = size(horz_slice)
       do while (horz_slice(right_edge) /= 1)
          right_edge = right_edge - 1
       end do
       right_edge = right_edge - 2
    end if

    if (any(cells(left_edge,top_edge:bottom_edge,:) > 1) .and. any(cells(right_edge,top_edge:bottom_edge,:) > 1)) then
       call print('crack_find_tips: through-going crack detected')
    else

       ! Fill cells outside the slab and those containing atoms to avoid them showing up as minima
       fill = 2*maxval(cells)
       where(cells == 0 .or. cells == 1)
          cells = fill
       end where

       min_dist = params%crack_tip_min_separation/params%crack_tip_grid_size
       call print('crack_find_tips: minimum distance between tips is '//params%crack_tip_min_separation//' A = '//min_dist//' cells.', VERBOSE)

       ! minimum filter: each point on the grid is set to the minimum of nearby points
       ! Equivalent to 
       !   min_cells(i,j,k) = minval(cells(i-min_dist/2:i+min_dist/2, j-min_dist/2:j+min_dist/2, k-min_dist/2:j+min_dist/2)
       ! but without overflowing any array boundaries
       min_cells = 0
       do k=1,connect%cellsnc
          min_k = min(max(k - min_dist/2, 1), connect%cellsnc)
          max_k = min(max(k + min_dist/2, 1), connect%cellsnc)

          do j=1,connect%cellsnb
             min_j = min(max(j - min_dist/2, 1), connect%cellsnb)
             max_j = min(max(j + min_dist/2, 1), connect%cellsnb)

             do i=1,connect%cellsna
                min_i = min(max(i - min_dist/2, 1), connect%cellsna)
                max_i = min(max(i + min_dist/2, 1), connect%cellsna)

                min_cells(i,j,k) = minval(cells(min_i:max_i, min_j:max_j, min_k:max_k))
             end do
          end do
       end do

       ! Find all the local minima
       call allocate(minima, 3,0,0,0)
       do k=1,connect%cellsnc
          do j=1,connect%cellsnb
             do i=1,connect%cellsna
                if (min_cells(i,j,k) == cells(i,j,k) .and. min_cells(i,j,k) /= fill) call append(minima, (/i,j,k/))
             end do
          end do
       end do

       call print('crack_find_tips: got '//minima%n//' tips before duplicate removal', VERBOSE)
       if (current_verbosity() >= VERBOSE) then
          do i=1,minima%n
             crack_t(1) = real(minima%int(1,i),dp)/connect%cellsna
             crack_t(2) = real(minima%int(2,i),dp)/connect%cellsnb
             crack_t(3) = real(minima%int(3,i),dp)/connect%cellsnc
             crack_t = crack_t - 0.5_dp
             call print(' tip #'//i//' at positon '//(at%lattice .mult. crack_t))
          end do
       end if

       ! Remove duplicate minima of same depth within params%crack_tip_min_separation of one another
       do while (.true.)
          duplicate = .false.
          OUTER: do i=1,minima%N
             do j=i+1,minima%N
                if (dot_product((minima%int(:,i) - minima%int(:,j)),(minima%int(:,i) - minima%int(:,j))) < min_dist**2) then
                   duplicate = .true.
                   exit OUTER
                end if
             end do
          end do OUTER

          if (duplicate) then
             d1 = dot_product((minima%int(:,i) - (/start_i, start_j, start_k/)),(minima%int(:,i) - (/start_i, start_j, start_k/)))
             d2 = dot_product((minima%int(:,j) - (/start_i, start_j, start_k/)),(minima%int(:,j) - (/start_i, start_j, start_k/)))

             if (d1 < d2) then
                call delete(minima, j, .true.)
             else
                call delete(minima, i, .true.)
             end if
          else
             exit
          end if
       end do

       call print('crack_find_tips: found '//minima%n//' crack tips')

       do i=1,minima%n
          crack_t(1) = real(minima%int(1,i),dp)/connect%cellsna
          crack_t(2) = real(minima%int(2,i),dp)/connect%cellsnb
          crack_t(3) = real(minima%int(3,i),dp)/connect%cellsnc
          crack_t = crack_t - 0.5_dp
          call append(crack_tips, realpart=(at%lattice .mult. crack_t))
       end do

    end if

    deallocate(cells)
    deallocate(min_cells)
    call finalise(connect)
    call finalise(minima)

  end subroutine crack_find_tips

  subroutine crack_print_cio(at, cio, params)
    type(Atoms), intent(inout) :: at
    type(CInoutput), intent(inout) :: cio
    type(CrackParams), intent(in) :: params

    if (params%io_print_all_properties) then
       call write(cio, at)
    else
       call write(cio, at, properties=params%io_print_properties)
    end if
  end subroutine crack_print_cio

  subroutine crack_print_filename(at, filename, params)
    type(Atoms), intent(inout) :: at
    character(*), intent(in) :: filename
    type(CrackParams), intent(in) :: params

    type(CInOutput) :: cio

    call initialise(cio, filename, action=OUTPUT)
    if (params%io_print_all_properties) then
       call write(cio, at)
    else
       call write(cio, at, properties=params%io_print_properties)
    end if
    call finalise(cio)

  end subroutine crack_print_filename

  subroutine crack_make_slab(params, classicalpot, simple, crack_slab,width, height, E, v, v2, bulk)
    type(CrackParams), intent(in) :: params
    type(Potential), intent(in) :: classicalpot
    type(Metapotential), intent(in) :: simple
    type(Atoms), intent(out) :: crack_slab
    real(dp), intent(out) :: width, height, E, v, v2
    type(Atoms), intent(out) :: bulk

    real(dp) :: a, shift, uij(3), ydiff, mindiff, minabsy
    type(inoutput) :: infile
    type(Atoms) :: crack_layer
    real (dp), dimension(3,3) :: axes, lattice
    integer :: i, atom1, atom2, n, j, nx, ny
    real(dp), dimension(6,6) :: c, c0
    type(Metapotential) :: simple_metapot

    if (trim(params%crack_bulk_filename) /= '') then

       call print_title('Reading bulk cell from file '//trim(params%crack_bulk_filename))
       call read(bulk, params%crack_bulk_filename)

       if (params%elastic_read) then
          c = params%elastic_cij/GPA
       else
          simple_metapot = simple
          call calc_elastic_constants(simple_metapot, bulk, c=c, c0=c0, relax_initial=.true., return_relaxed=.true.)
          
          call print('Relaxed elastic constants (GPa):')
          call print(c*GPA)
          call print('')
          call print('Unrelaxed elastic constants (GPa):')
          call print(c0*GPA)
          call print('')
          
          call print('Relaxed lattice')
          call print(bulk%lattice)
       end if
       
       if (.not. get_value(bulk%params, 'YoungsModulus', E)) &
            call system_abort('crack_uniform_load: "YoungsModulus" missing')
       
       if (.not. get_value(bulk%params, 'PoissonRatio_yx', v)) &
            call system_abort('crack_uniform_load: "PoissonRatio_yx" missing')

       if (.not. get_value(bulk%params, 'PoissonRatio_yz', v2)) &
            call system_abort('crack_uniform_load: "PoissonRatio_yz" missing')

       call Print('')
       call print('Youngs modulus E_y = '//E)
       call print('Poisson ratio v_yx = '//v)
       call print('Poisson ratio v_yz = '//v2)
       call Print('')

       nx = int(floor(params%crack_width/bulk%lattice(1,1)))
       ny = int(floor(params%crack_height/bulk%lattice(2,2)))

       nx = max(nx, 1)
       ny = max(ny, 1)

       call supercell(crack_layer, bulk, nx, ny, 1)
      
       call atoms_set_cutoff(crack_layer, cutoff(classicalpot)+params%md_crust)
       call supercell(crack_slab, crack_layer, 1, 1, params%crack_num_layers)
       call calc_connect(crack_slab, store_is_min_image=.true.)

       call Print('Slab contains '//crack_slab%N//' atoms.')

       ! Actual width and height differ a little from requested
       width = maxval(crack_slab%pos(1,:))-minval(crack_slab%pos(1,:))
       height = maxval(crack_slab%pos(2,:))-minval(crack_slab%pos(2,:))
       call Print('Actual slab dimensions '//width//' A x '//height//' A')

    else

       if (trim(params%crack_structure) == 'graphene') then

          call print_title('Graphene Crack')

!!$     call graphene_elastic(simple, a, v, E)

          a = 1.42_dp
          v = 0.144_dp
          E = 344.0_dp

          call Print('graphene sheet, lattice constant a='//a)

          bulk = graphene_cubic(a)

          if (trim(params%crack_slab_filename).ne.'') then
             call Initialise(infile, trim(params%crack_slab_filename))
             call print('Reading atoms from input file')
             call read_xyz(crack_slab, infile)
          else
             call graphene_slab(crack_layer, a, params%crack_graphene_theta, &
                  params%crack_width, params%crack_height)
             crack_layer%Z = 6

             if (abs(params%crack_graphene_theta - 0.0_dp) < 1e-3_dp) then
                call print('armchair sheet')
                shift = 0.61567821_dp
             else if (abs(params%crack_graphene_theta - pi/6.0_dp) < 1e-3_dp) then
                call print('zigzag sheet')
                shift = 0.53319064_dp
             end if

             lattice = crack_layer%lattice
             lattice(1,1) = lattice(1,1) + params%crack_vacuum_size
             lattice(2,2) = lattice(2,2) + params%crack_vacuum_size
             call atoms_set_lattice(crack_layer, lattice)

             do i=1,crack_layer%N
                crack_layer%pos(2,i) = crack_layer%pos(2,i) + shift
             end do
          endif

          ! Actual width and height differ a little from requested
          width = maxval(crack_layer%pos(1,:))-minval(crack_layer%pos(1,:))
          height = maxval(crack_layer%pos(2,:))-minval(crack_layer%pos(2,:))
          call Print('Actual slab dimensions '//width//' A x '//height//' A')

          ! Cut notch
          if (params%crack_graphene_notch_width  > 0.0_dp .and. &
               params%crack_graphene_notch_height > 0.0_dp) then
             call Print('Cutting notch with width '//params%crack_graphene_notch_width// &
                  ' A, height '//params%crack_graphene_notch_height//' A.')

             i = 1
             do
                if ((crack_layer%pos(2,i) < &
                     -(0.5_dp*params%crack_graphene_notch_height/ &
                     params%crack_graphene_notch_width*(crack_layer%pos(1,i)+width/2.0_dp)) + &
                     params%crack_graphene_notch_height/2.0_dp) .and. &
                     (crack_layer%pos(2,i) > &
                     (0.5_dp*params%crack_graphene_notch_height/ &
                     params%crack_graphene_notch_width*(crack_layer%pos(1,i)+width/2.0_dp)) - &
                     params%crack_graphene_notch_height/2.0_dp)) then
                   call remove_atoms(crack_layer, i)

                   i = i - 1 ! retest
                end if
                if (i == crack_layer%N) exit
                i = i + 1
             end do
          end if

          crack_layer%lattice(3,3) = 10.0_dp
          crack_slab = crack_layer

          call atoms_set_cutoff(crack_slab, cutoff(classicalpot)+params%md_crust)
          call calc_connect(crack_slab, store_is_min_image=.true.)

          call Print('Graphene sheet contains '//crack_slab%N//' atoms.')

       else if (trim(params%crack_structure) == 'diamond'.or.trim(params%crack_structure) == 'bcc' &
            .or.trim(params%crack_structure) == 'fcc' .or. trim(params%crack_structure) == 'alpha_quartz' ) then

          if(trim(params%crack_structure) == 'diamond') then
             call print_title('Diamond Structure Crack')
             call diamond(bulk, params%crack_lattice_guess, params%crack_z)
          elseif(trim(params%crack_structure) == 'bcc') then
             call print_title('BCC Structure Crack')
             call bcc(bulk, params%crack_lattice_guess, params%crack_z(1))
             call set_cutoff(bulk, cutoff(simple))
          elseif(trim(params%crack_structure) == 'fcc') then
             call print_title('FCC Structure Crack')
             call fcc(bulk, params%crack_lattice_guess, params%crack_z(1))
             call set_cutoff(bulk, cutoff(simple))
          elseif(trim(params%crack_structure) == 'alpha_quartz') then
             call print_title('Alpha Quartz Crack')
             call alpha_quartz(bulk, a=params%crack_lattice_a, c=params%crack_lattice_c, u=params%crack_lattice_u, &
                  x=params%crack_lattice_x, y=params%crack_lattice_y, z=params%crack_lattice_z)
             call set_cutoff(bulk, cutoff(simple))
          endif

          if (params%elastic_read) then
             c = params%elastic_cij/GPA
          else
             simple_metapot = simple
             call calc_elastic_constants(simple_metapot, bulk, c=c, c0=c0, relax_initial=.true., return_relaxed=.true.)

             call print('Relaxed elastic constants (GPa):')
             call print(c*GPA)
             call print('')
             call print('Unrelaxed elastic constants (GPa):')
             call print(c0*GPA)
             call print('')

             call print('Relaxed lattice')
             call print(bulk%lattice)
          end if

          ! Parse crack name and make crack slab
          if (trim(params%crack_structure) == 'alpha_quartz') then

             ! basal (0001) surface
             a = params%crack_lattice_a
             axes = reshape((/1.0_dp, 0.0_dp, 0.0_dp, &
                  0.0_dp, 0.0_dp, 1.0_dp, &
                  0.0_dp, 1.0_dp, 0.0_dp/), (/3,3/))
          else
             a = bulk%lattice(1,1)

             call Print(trim(params%crack_element)//' crack: atomic number Z='//params%crack_z//&
                  ', lattice constant a = '//a)
             call Print('Crack name '//params%crack_name)

             call crack_parse_name(params%crack_name, axes)
          end if

          ! Get elastic constants relevant for a pull in y direction
          E = Youngs_Modulus(C, axes(:,2))*GPA
          v = Poisson_Ratio(C, axes(:,2), axes(:,1))
          v2 = Poisson_Ratio(C, axes(:,2), axes(:,3))

          call Print('')
          call print('Youngs modulus E_y = '//E)
          call print('Poisson ratio v_yx = '//v)
          call print('Poisson ratio v_yz = '//v2)
          call Print('')

          if (trim(params%crack_slab_filename).ne.'') then
             call Initialise(infile, trim(params%crack_slab_filename))
             call print('Reading atoms from input file')
             call read_xyz(crack_slab, infile)
          else
             call slab(crack_layer, axes, width=params%crack_width, height=params%crack_height, nz=1, atnum=params%crack_z, &
                  lat_type=trim(params%crack_structure), a=a, c=params%crack_lattice_c, u=params%crack_lattice_u, &
                  x=params%crack_lattice_x, y=params%crack_lattice_y, z=params%crack_lattice_z)
             call atoms_set_cutoff(crack_layer, cutoff(classicalpot)+params%md_crust)
             call supercell(crack_slab, crack_layer, 1, 1, params%crack_num_layers)
          endif

          call calc_connect(crack_slab, store_is_min_image=.true.)

          call Print('Slab contains '//crack_slab%N//' atoms.')

          ! Actual width and height differ a little from requested
          width = maxval(crack_slab%pos(1,:))-minval(crack_slab%pos(1,:))
          height = maxval(crack_slab%pos(2,:))-minval(crack_slab%pos(2,:))
          call Print('Actual slab dimensions '//width//' A x '//height//' A')

       else
          ! Add code here for other structures...

          call system_abort("Don't (yet!) know how to make cracks with structure "//trim(params%crack_structure))

       end if ! select on crack_structure

    end if

    if(params%crack_align_y) then
      call print_title('Aligning Seed Crack at y=0')
  
      ! Find an atom close to y=0
      minabsy = 1000.0_dp
      atom1 = -1; atom2 = -1
      mindiff = 1000.0_dp
      do i=1, crack_slab%N
         if (abs(crack_slab%pos(2,i)) < minabsy) then
            minabsy = abs(crack_slab%pos(2,i))
            atom1 = i
         end if
      end do
  
      ! Apply shift to centre the seed crack in the right place
      if (trim(params%crack_name) == '(111)[11b0]') then
  
         call calc_connect(crack_slab)
  
         ! Find atom1's closest neighbour vertically above or below it (x and z equal, not y)
         do n = 1, atoms_n_neighbours(crack_slab, atom1)
            j = atoms_neighbour(crack_slab, atom1, n, diff=uij) ! nth neighbour of atom1
            if (abs(uij(1)) < 1e-4_dp .and. & 
                 abs(uij(2)) > 1e-4_dp .and. &
                 abs(uij(3)) < 1e-4_dp) then
  
               ydiff = abs(crack_slab%pos(2,atom1)-crack_slab%pos(2,j))
               if (ydiff < mindiff) then
                  mindiff = ydiff
                  atom2 = j
               end if
            end if
         end do
  
         if (atom1 == -1 .or. atom2 == -1) &
              call system_abort('Failed to find a pair of atoms vertically aligned!')
  
         ! Align y=0 to centre line of atom1-atom2 bond
         shift = (crack_slab%pos(2,atom1) + crack_slab%pos(2,atom2))/2.0_dp
  
         call Print('Centering on (atom '//atom1//')--(atom '//atom2//') bond')
         call print('  Atom 1 pos = '//crack_slab%pos(:,atom1))
         call print('  Atom 2 pos = '//crack_slab%pos(:,atom2))
         call Print('Shifting atoms vertically by '//shift)
         do i=1,crack_slab%N
            crack_slab%pos(2,i) = crack_slab%pos(2,i) + shift
         end do
  
      else if(trim(params%crack_name) == '(110)[11b0]') then
         ! Align y=0 to atom1
         shift = -crack_slab%pos(2,atom1)
  
         call Print('Centering on atom '//atom1)
         call print('  Atom 1 pos = '//crack_slab%pos(:,atom1))
         call Print('Shifting atoms vertically by '//shift)
         do i=1,crack_slab%N
            crack_slab%pos(2,i) = crack_slab%pos(2,i) + shift
         end do
  
      else if (trim(params%crack_name) == '(110)[001b]') then
         ! Do nothing - correctly aligned already
      else if (trim(params%crack_name) == '(100)(010)') then
         ! Do nothing - correctly aligned already
      else if (trim(params%crack_structure) == 'graphene') then
         ! Do nothing - correctly aligned already
      else
         ! Get shift from params
         do i=1,crack_slab%N
            crack_slab%pos(2,i) = crack_slab%pos(2,i) + params%crack_y_shift
         end do
      end if
    endif

  end subroutine crack_make_slab

  subroutine crack_check_coordination(at,params,j,y,x_boundaries,neigh_removed, at_for_connectivity)
      type(Atoms), intent(inout)       :: at
      type(CrackParams), intent(in)    :: params
      integer, intent(in)              :: j
      real(dp), optional,intent(inout) :: y
      logical, optional, intent(in)    :: x_boundaries
      logical, optional, intent(inout) :: neigh_removed(at%n)
      type(Atoms), optional            :: at_for_connectivity
      logical                          :: my_x_boundaries
      real(dp)                         :: rmin, rij
      integer                          :: i, ji, k, kj, n2, who_closest
      integer, allocatable,dimension(:)  :: who, who_nn, who_absolute_index
 
      my_x_boundaries = optional_default(.false.,x_boundaries)

      rmin = 100.d0
      allocate(who_nn(atoms_n_neighbours(at, j)))
      allocate(who(atoms_n_neighbours(at, j)))
      allocate(who_absolute_index(atoms_n_neighbours(at, j)))
      who_absolute_index  = 0
      who_nn  = 0
      who = 0
      n2  = 0


      do i = 1, atoms_n_neighbours(at, j)
         ji = atoms_neighbour(at,j,i,distance=rij)
         if(at%Z(ji).ne.at%Z(j)) then 
            n2 = n2 + 1
            who_absolute_index(n2) = ji 
            who(n2) = i
            if(present(at_for_connectivity)) then
               who_nn(n2) = atoms_n_neighbours(at_for_connectivity, ji)
            else
               who_nn(n2) = atoms_n_neighbours(at, ji)
            endif
!           Detect who is the nearest neighbour of different type
            if(rij.lt.rmin) then
                rmin = rij
                who_closest  = i
            endif
         endif
      enddo

!     Check the connectivity. E.g.: if coordination_critical_nneigh=2, it checks when the atom has 3 nn, since it is going to loose a neighbours of its. 
!     If an atom has already lost a neighbour, do not remove another atoms from it
      do i = 1, n2
        if(present(neigh_removed).and.neigh_removed(who_absolute_index(i))) then
             who_closest = who(i)
             exit 
        elseif(who_nn(i).le.params%crack_check_coordination_critical_nneigh+1.and.who(i).ne.who_closest) then
           if(who_nn(who_closest).gt.who_nn(i)) then
              who_closest = who(i)
           endif
        endif
      enddo

      if(my_x_boundaries) then
         ! check x-boundary 
         if(at%pos(1,atoms_neighbour(at,j,who_closest)).gt.0.0_dp.and.at%pos(1,j).lt.0.0_dp) then
            at%pos(1,j) = at%pos(1,j) + at%lattice(1,1) 
         elseif(at%pos(1,atoms_neighbour(at,j,who_closest)).lt.0.0_dp.and.at%pos(1,j).gt.0.0_dp) then
            at%pos(1,j) = at%pos(1,j) - at%lattice(1,1) 
         endif
         if(present(neigh_removed)) then
           do i = 1, n2
             if( abs(at%pos(1,atoms_neighbour(at,j,who(i)))-at%pos(1,j)).gt.at%lattice(1,1)/2.0_dp) then
                neigh_removed=.true.
             endif
           enddo
         endif
      else   !check only y
         if(at%pos(2,atoms_neighbour(at,j,who_closest)).gt.0.0_dp) then
             y =  abs(at%pos(2,j))
         else
             y = -abs(at%pos(2,j))
         endif
      endif

  end subroutine crack_check_coordination

  subroutine crack_check_coordination_boundaries(at,params)
      type(Atoms), intent(inout)       :: at
      type(CrackParams), intent(inout) :: params
      type(Atoms)                      :: at_tmp
      real(dp), dimension(3,3)         :: lattice_tmp
      integer                          :: i, jjjjj
      logical, dimension(at%n)         :: neigh_removed
      logical :: ccc
      real(dp) :: width, height

      at_tmp = at
      lattice_tmp = at_tmp%lattice
      lattice_tmp(1,1) = lattice_tmp(1,1) + params%crack_vacuum_size
      lattice_tmp(2,2) = lattice_tmp(2,2) + params%crack_vacuum_size
      call atoms_set_lattice(at_tmp, lattice_tmp)
      !call calc_connect(at_tmp)

      neigh_removed = .false.

      if (.not. get_value(at_tmp%params, 'OrigWidth', width)) &
         call system_abort('crack_check_coordination_boundaries: "OrigWidth" parameter missing')

      do i = 1, at%n
        print *, i
        if(at%Z(i).eq.params%crack_check_coordination_atom_type.and.(abs(at%pos(1,i)) > width/2.0_dp - params%crack_check_coordination_region))  then
           call crack_check_coordination(at,params,i, x_boundaries=.true., neigh_removed=neigh_removed, at_for_connectivity=at_tmp)
           !call crack_check_coordination(at,params,i, x_boundaries=.true.)
        endif
      enddo
       
  end subroutine crack_check_coordination_boundaries




end module CrackTools_module
