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

!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X
!X cp2k_driver_template_module
!X
!% Driver for CP2K code using a template input file
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
#include "error.inc"
module cp2k_driver_template_module
use libatoms_module
use topology_module
implicit none

private

public :: do_cp2k_calc


contains

  subroutine do_cp2k_calc_fake(at, f, e, args_str)
    type(Atoms), intent(inout) :: at
    real(dp), intent(out) :: f(:,:), e
    character(len=*), intent(in) :: args_str

    type(inoutput) :: last_run_io
    type(cinoutput) :: force_cio
    character(len=1024) :: last_run_s
    integer :: this_run_i
    integer :: stat
    type(Atoms) :: for
    real(dp), pointer :: frc(:,:)

    call initialise(last_run_io, "cp2k_driver_fake_run", action=INPUT)
    last_run_s = read_line(last_run_io, status=stat)
    call finalise(last_run_io)
    if (stat /= 0) then
      this_run_i = 1
    else
      read (fmt=*,unit=last_run_s) this_run_i
      this_run_i = this_run_i + 1
    endif

    call print("do_cp2k_calc_fake run_i " // this_run_i, PRINT_ALWAYS)

    call initialise(force_cio, "cp2k_force_file_log")
    call read(force_cio, for, frame=this_run_i-1)
    !NB why does this crash now?
    ! call finalise(force_cio)
    if (.not. assign_pointer(for, 'frc', frc)) &
      call system_abort("do_cp2k_calc_fake couldn't find frc field in force log file")
    f = frc

    if (.not. get_value(for%params, "energy", e)) then
      if (.not. get_value(for%params, "Energy", e)) then
	if (.not. get_value(for%params, "E", e)) then
	  call system_abort("do_cp2k_calc_fake didn't find energy")
	endif
      endif
    endif

    e = e * HARTREE
    f  = f * HARTREE/BOHR 

    call initialise(last_run_io, "cp2k_driver_fake_run", action=OUTPUT)
    call print(""//this_run_i, file=last_run_io)
    call finalise(last_run_io)

  end subroutine do_cp2k_calc_fake


  subroutine do_cp2k_calc(at, f, e, args_str, error)
    type(Atoms), intent(inout) :: at
    real(dp), intent(out) :: f(:,:), e
    character(len=*), intent(in) :: args_str
    integer, intent(out), optional :: error

    type(Dictionary) :: cli
    character(len=FIELD_LENGTH) :: run_type, cp2k_template_file, psf_print, cp2k_program, link_template_file, topology_suffix
    logical :: clean_up_files, save_output_files, save_output_wfn_files
    integer :: max_n_tries
    real(dp) :: max_force_warning
    real(dp) :: qm_vacuum
    real(dp) :: centre_pos(3), cp2k_box_centre_pos(3)
    logical :: auto_centre, has_centre_pos
    logical :: try_reuse_wfn

    character(len=128) :: method

    type(Inoutput) :: template_io
    integer :: template_n_lines
    character(len=1024), allocatable :: cp2k_template_a(:)
    type(Inoutput) :: link_template_io
    integer :: link_template_n_lines
    character(len=1024), allocatable :: link_template_a(:)
    integer :: i_line

    character(len=1024) :: run_dir

    integer :: run_type_i

    type(Table) :: qm_list
    type(Table) :: cut_bonds
    integer, pointer :: cut_bonds_p(:,:)
    integer, allocatable :: qm_list_a(:)
    integer, allocatable :: link_list_a(:)
    integer, allocatable :: qm_and_link_list_a(:)
    integer :: i_inner, i_outer
    logical :: inserted_atoms
    integer :: counter

    integer :: charge
    logical :: do_lsd

    logical :: can_reuse_wfn, qm_list_changed
    character(len=20) :: qm_name_postfix

    logical :: use_QM, use_MM, use_QMMM
    logical :: cp2k_calc_fake

    integer, pointer :: isolated_atom(:)
    integer i, j, atno, insert_pos
    real(dp) :: cur_qmmm_qm_abc(3), old_qmmm_qm_abc(3)

    type(Atoms) :: at_cp2k

    character(len=TABLE_STRING_LENGTH), pointer :: from_str(:), to_str(:)
    character(len=TABLE_STRING_LENGTH) :: dummy_s
    real(dp), pointer :: from_dp(:), to_dp(:)
    integer, pointer :: from_i(:), to_i(:)

    integer, pointer :: old_cluster_mark_p(:), cluster_mark_p(:)
    logical :: dummy, have_silica_potential
    type(Table) :: intrares_impropers

    integer :: mol_id_lookup(3), atom_res_number_lookup(3), sort_index_lookup(3)
    integer, pointer :: sort_index_p(:)
    integer :: at_i

    integer :: run_dir_i

    logical :: at_periodic

    INIT_ERROR(error)

    call system_timer('do_cp2k_calc')

    call initialise(cli)
      run_type = ''
      call param_register(cli, 'Run_Type', PARAM_MANDATORY, run_type)
      cp2k_template_file = ''
      call param_register(cli, 'cp2k_template_file', 'cp2k_input.template', cp2k_template_file)
      link_template_file = ""
      call param_register(cli, "qmmm_link_template_file", "", link_template_file)
      psf_print = ''
      call param_register(cli, 'PSF_print', 'NO_PSF', psf_print)
      topology_suffix = ''
      call param_register(cli, "topology_suffix", "", topology_suffix)
      cp2k_program = ''
      call param_register(cli, 'cp2k_program', PARAM_MANDATORY, cp2k_program)
      call param_register(cli, 'clean_up_files', 'T', clean_up_files)
      call param_register(cli, 'save_output_files', 'T', save_output_files)
      call param_register(cli, 'save_output_wfn_files', 'F', save_output_wfn_files)
      call param_register(cli, 'max_n_tries', '2', max_n_tries)
      call param_register(cli, 'max_force_warning', '2.0', max_force_warning)
      call param_register(cli, 'qm_vacuum', '6.0', qm_vacuum)
      call param_register(cli, 'try_reuse_wfn', 'T', try_reuse_wfn)
      call param_register(cli, 'have_silica_potential', 'F', have_silica_potential) !if yes, use 2.8A SILICA_CUTOFF for the connectivities
      call param_register(cli, 'auto_centre', 'F', auto_centre)
      call param_register(cli, 'centre_pos', '0.0 0.0 0.0', centre_pos, has_centre_pos)
      call param_register(cli, 'cp2k_calc_fake', 'F', cp2k_calc_fake)
      ! should really be ignore_unknown=false, but higher level things pass unneeded arguments down here
      if (.not.param_read_line(cli, args_str, do_check=.true.,ignore_unknown=.true.,task='cp2k_filepot_template args_str')) &
	call system_abort('could not parse argument line')
    call finalise(cli)

    if (cp2k_calc_fake) then
      call print("do_fake cp2k calc calculation")
      call do_cp2k_calc_fake(at, f, e, args_str)
      return
    endif

    call print("do_cp2k_calc command line arguments")
    call print("  Run_Type " // Run_Type)
    call print("  cp2k_template_file " // cp2k_template_file)
    call print("  qmmm_link_template_file " // link_template_file)
    call print("  PSF_print " // PSF_print)
    call print("  clean_up_files " // clean_up_files)
    call print("  save_output_files " // save_output_files)
    call print("  save_output_wfn_files " // save_output_wfn_files)
    call print("  max_n_tries " // max_n_tries)
    call print("  max_force_warning " // max_force_warning)
    call print("  qm_vacuum " // qm_vacuum)
    call print("  try_reuse_wfn " // try_reuse_wfn)
    call print('  have_silica_potential '//have_silica_potential)
    call print('  auto_centre '//auto_centre)
    call print('  centre_pos '//centre_pos)

    if (auto_centre .and. has_centre_pos) &
      call system_abort("do_cp2k_calc got both auto_centre and centre_pos, don't know which centre (automatic or specified) to shift to origin")

    ! read template file
    call initialise(template_io, trim(cp2k_template_file), INPUT)
    call read_file(template_io, cp2k_template_a, template_n_lines)
    call finalise(template_io)

    call prefix_cp2k_input_sections(cp2k_template_a(1:template_n_lines))

    if ( (trim(psf_print) /= 'NO_PSF') .and. &
         (trim(psf_print) /= 'DRIVER_PRINT_AND_SAVE') .and. &
         (trim(psf_print) /= 'USE_EXISTING_PSF')) &
      call system_abort("Unknown value for psf_print '"//trim(psf_print)//"'")

    ! parse run_type
    use_QM = .false.
    use_MM = .false.
    use_QMMM = .false.
    select case(trim(run_type))
      case("QS")
	use_QM=.true.
	method="QS"
	run_type_i = QS_RUN
        qm_name_postfix=""
      case("MM")
	use_MM=.true.
	method="Fist"
	run_type_i = MM_RUN
      case("QMMM_CORE")
	use_QM=.true.
	use_MM=.true.
	use_QMMM=.true.
	method="QMMM"
	run_type_i = QMMM_RUN_CORE
        qm_name_postfix="_core"
      case("QMMM_EXTENDED")
	use_QM=.true.
	use_MM=.true.
	use_QMMM=.true.
	method="QMMM"
	run_type_i = QMMM_RUN_EXTENDED
        qm_name_postfix="_extended"
      case default
	call system_abort("Unknown run_type "//trim(run_type))
    end select

    ! prepare CHARMM params if necessary
    if (use_MM) then
      if (have_silica_potential) then
        call set_cutoff(at,SILICA_2body_CUTOFF)
      else
        call set_cutoff(at,0._dp)
      endif
      call calc_connect(at)

      call map_into_cell(at)
      call calc_dists(at)

    endif

    ! if writing PSF file, calculate residue labels, before sort
    if (run_type /= "QS") then
      if (trim(psf_print) == "DRIVER_PRINT_AND_SAVE") then
	call create_residue_labels_arb_pos(at,do_CHARMM=.true.,intrares_impropers=intrares_impropers,have_silica_potential=have_silica_potential)
      end if
    end if

    ! sort by molecule, residue ID
    nullify(sort_index_p)
    if (.not. assign_pointer(at, 'sort_index', sort_index_p)) then
      call add_property(at, 'sort_index', 0)
      if (.not. assign_pointer(at, 'sort_index', sort_index_p)) &
	call print("WARNING: do_cp2k_calc failed to assign pointer for sort_index, not sorting")
    endif
    if (associated(sort_index_p)) then
      do at_i=1, at%N
	sort_index_p(at_i) = at_i
      end do
    endif
    if (.not.(has_property(at,'mol_id')) .or. .not. has_property(at,'atom_res_number')) then
      call print("WARNING: can't do sort_by_molecule - need mol_id and atom_res_number.  CP2K may complain", PRINT_ALWAYS)
    else
      call atoms_sort(at, 'mol_id', 'atom_res_number', error=error)
      PASS_ERROR_WITH_INFO ("do_cp2k_calc sorting atoms by mol_id and atom_res_number", error)
      if (associated(sort_index_p)) then
	do at_i=1, at%N
	  if (sort_index_p(at_i) /= at_i) then
	    call print("sort() of at%data by mol_id, atom_res_number reordered some atoms")
	    exit
	  endif
	end do
      endif
      call calc_connect(at)
    end if

    ! write PSF file, if requested
    if (run_type /= "QS") then
      if (trim(psf_print) == "DRIVER_PRINT_AND_SAVE") then
	if (has_property(at, 'avgpos')) then
	  call write_psf_file_arb_pos(at, "quip_cp2k"//trim(topology_suffix)//".psf", run_type_string=trim(run_type),intrares_impropers=intrares_impropers,add_silica_23body=have_silica_potential)
	else if (has_property(at, 'pos')) then
	  call print("WARNING: do_cp2k_calc using pos for connectivity.  avgpos is preferred but not found.")
	  call write_psf_file_arb_pos(at, "quip_cp2k"//trim(topology_suffix)//".psf", run_type_string=trim(run_type),intrares_impropers=intrares_impropers,add_silica_23body=have_silica_potential,pos_field_for_connectivity='pos')
	else
	  call system_abort("do_cp2k_calc needs some pos field for connectivity (run_type='"//trim(run_type)//"' /= 'QS'), but found neither avgpos nor pos")
	endif
      endif
    endif

    ! set variables having to do with periodic configs
    if (.not. get_value(at%params, 'Periodic', at_periodic)) at_periodic = .true.
    insert_pos = 0
    if (at_periodic) then
      call insert_cp2k_input_line(cp2k_template_a, " @SET PERIODIC XYZ", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    else
      call insert_cp2k_input_line(cp2k_template_a, " @SET PERIODIC NONE", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    endif
    call insert_cp2k_input_line(cp2k_template_a, " @SET MAX_CELL_SIZE_INT "//int(max(norm(at%lattice(:,1)),norm(at%lattice(:,2)), norm(at%lattice(:,3)))), &
      after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1

    ! put in method
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "", "&FORCE_EVAL")
    call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL METHOD "//trim(method), after_line = insert_pos, n_l = template_n_lines)

    ! get qm_list and link_list
    if (use_QMMM) then
      select case (run_type_i)
	case(QMMM_RUN_CORE)
	  call get_hybrid_list(at, qm_list, active_trans_only=.true.,int_property="cluster_mark"//trim(qm_name_postfix))
	case(QMMM_RUN_EXTENDED)
	  call get_hybrid_list(at, qm_list, all_but_term=.true.,int_property="cluster_mark"//trim(qm_name_postfix))
	case default
	  call system_abort("use_QMM is true, but run_type_i="//run_type_i //" is neither QMMM_RUN_CORE="//QMMM_RUN_CORE// &
	    " QMMM_RUN_EXTENDED="//QMMM_RUN_EXTENDED)
      end select
      allocate(qm_list_a(qm_list%N))
      if (qm_list%N > 0) qm_list_a = int_part(qm_list,1)
      !get link list

       if (assign_pointer(at,'cut_bonds',cut_bonds_p)) then
          call initialise(cut_bonds,2,0,0,0,0)
          do i_inner=1,at%N
             do j=1,4 !MAX_CUT_BONDS
                i_outer = cut_bonds_p(j,i_inner)
                if (i_outer .eq. 0) exit
                call append(cut_bonds,(/i_inner,i_outer/))
             enddo
          enddo
          if (cut_bonds%N.gt.0) then
             call uniq(cut_bonds%int(2,1:cut_bonds%N),link_list_a)
             allocate(qm_and_link_list_a(size(qm_list_a)+size(link_list_a)))
             qm_and_link_list_a(1:size(qm_list_a)) = qm_list_a(1:size(qm_list_a))
             qm_and_link_list_a(size(qm_list_a)+1:size(qm_list_a)+size(link_list_a)) = link_list_a(1:size(link_list_a))
          else
             allocate(link_list_a(0))
             allocate(qm_and_link_list_a(size(qm_list_a)))
             if (size(qm_list_a).gt.0) qm_and_link_list_a = qm_list_a
          endif
       else
          allocate(qm_and_link_list_a(size(qm_list_a)))
          if (size(qm_list_a).gt.0) qm_and_link_list_a = qm_list_a
       endif

       !If needed, read QM/MM link_template_file
       if (allocated(link_list_a)) then
          if (trim(link_template_file).eq."") call system_abort("There are QM/MM links, but qmmm_link_template is not defined.")
          call initialise(link_template_io, trim(link_template_file), INPUT)
          call read_file(link_template_io, link_template_a, link_template_n_lines)
          call finalise(link_template_io)
          call prefix_cp2k_input_sections(link_template_a)
       endif
    else
      allocate(qm_list_a(0))
      allocate(link_list_a(0))
      allocate(qm_and_link_list_a(0))
    endif

    if (auto_centre) then
      if (qm_list%N > 0) then
	centre_pos = pbc_aware_centre(at%pos(:,qm_list_a), at%lattice, at%g)
      else
	centre_pos = pbc_aware_centre(at%pos, at%lattice, at%g)
      endif
      call print("centering got automatic center " // centre_pos, PRINT_VERBOSE)
    endif
    ! move specified centre to origin (centre is already 0 if not specified)
    at%pos(1,:) = at%pos(1,:) - centre_pos(1)
    at%pos(2,:) = at%pos(2,:) - centre_pos(2)
    at%pos(3,:) = at%pos(3,:) - centre_pos(3)
    ! move origin into center of CP2K box (0.5 0.5 0.5 lattice coords)
    call map_into_cell(at)
    if (.not. at_periodic) then
      cp2k_box_centre_pos(1:3) = 0.5_dp*sum(at%lattice,2)
      at%pos(1,:) = at%pos(1,:) + cp2k_box_centre_pos(1)
      at%pos(2,:) = at%pos(2,:) + cp2k_box_centre_pos(2)
      at%pos(3,:) = at%pos(3,:) + cp2k_box_centre_pos(3)
    endif

    if (qm_list%N == at%N) then
      call print("WARNING: requested '"//trim(run_type)//"' but all atoms are in QM region, doing full QM run instead", PRINT_ALWAYS)
      run_type='QS'
      use_QM = .true.
      use_MM = .false.
      use_QMMM = .false.
      method = 'QS'
    endif

    can_reuse_wfn = .true.

    ! put in things needed for QMMM
    if (use_QMMM) then

      if (trim(run_type) == "QMMM_CORE") then
	run_type_i = QMMM_RUN_CORE
      else if (trim(run_type) == "QMMM_EXTENDED") then
	run_type_i = QMMM_RUN_EXTENDED
      else
	call system_abort("Unknown run_type '"//trim(run_type)//"' with use_QMMM true")
      endif

      insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&QMMM", "&CELL")
      call print('INFO: The size of the QM cell is either the MM cell itself, or it will have at least '//(qm_vacuum/2.0_dp)// &
			' Angstrom around the QM atoms.')
      call print('WARNING! Please check if your cell is centreed around the QM region!',PRINT_ALWAYS)
      call print('WARNING! CP2K centreing algorithm fails if QM atoms are not all in the',PRINT_ALWAYS)
      call print('WARNING! 0,0,0 cell. If you have checked it, please ignore this message.',PRINT_ALWAYS)
      cur_qmmm_qm_abc = qmmm_qm_abc(at, qm_list_a, qm_vacuum)
      call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&QMMM&CELL ABC " // cur_qmmm_qm_abc, after_line=insert_pos, n_l=template_n_lines); insert_pos = insert_pos + 1
      call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&QMMM&CELL PERIODIC XYZ", after_line=insert_pos, n_l=template_n_lines); insert_pos = insert_pos + 1

      if (get_value(at%params, "QM_cell"//trim(qm_name_postfix), old_qmmm_qm_abc)) then
	if (cur_qmmm_qm_abc .fne. old_qmmm_qm_abc) can_reuse_wfn = .false.
      else
        can_reuse_wfn = .false.
      endif
      call set_value(at%params, "QM_cell"//trim(qm_name_postfix), cur_qmmm_qm_abc)
       call print('set_value QM_cell'//trim(qm_name_postfix)//' '//cur_qmmm_qm_abc)

      !check if QM list changed: compare cluster_mark and old_cluster_mark[_postfix]
!      if (get_value(at%params, "QM_list_changed", qm_list_changed)) then
!       if (qm_list_changed) can_reuse_wfn = .false.
!      endif
       if (.not.has_property(at, 'cluster_mark'//trim(qm_name_postfix))) call system_abort('no cluster_mark'//trim(qm_name_postfix)//' found in atoms object')
       if (.not.has_property(at, 'old_cluster_mark'//trim(qm_name_postfix))) call system_abort('no old_cluster_mark'//trim(qm_name_postfix)//' found in atoms object')
       dummy = assign_pointer(at, 'old_cluster_mark'//trim(qm_name_postfix), old_cluster_mark_p)
       dummy = assign_pointer(at, 'cluster_mark'//trim(qm_name_postfix), cluster_mark_p)

       qm_list_changed = .false.
       do i=1,at%N
          !only hybrid_no_mark matters
          if (old_cluster_mark_p(i).ne.cluster_mark_p(i) .and. &
              any((/old_cluster_mark_p(i),cluster_mark_p(i)/).eq.HYBRID_NO_MARK)) then
              qm_list_changed = .true.
          endif
       enddo
       call set_value(at%params,'QM_list_changed',qm_list_changed)
       call print('set_value QM_list_changed '//qm_list_changed)

       if (qm_list_changed) can_reuse_wfn = .false.

      !Add QM atoms
      counter = 0
      do atno=minval(at%Z), maxval(at%Z)
	if (any(at%Z(qm_list_a) == atno)) then
	  insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&QMMM", "&QM_KIND "//ElementName(atno))
	  do i=1, size(qm_list_a)
	    if (at%Z(qm_list_a(i)) == atno) then
	      call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&QMMM&QM_KIND-"//trim(ElementName(atno))// &
							" MM_INDEX "//qm_list_a(i), after_line = insert_pos, n_l = template_n_lines)
	      insert_pos = insert_pos + 1
	      counter = counter + 1
	    endif
	  end do
	end if
      end do
      if (size(qm_list_a) /= counter) &
	call system_abort("Number of QM list atoms " // size(qm_list_a) // " doesn't match number of QM_KIND atoms " // counter)

      !Add link sections from template file for each link
      if (size(link_list_a).gt.0) then
         do i=1,cut_bonds%N
            i_inner = cut_bonds%int(1,i)
            i_outer = cut_bonds%int(2,i)
            insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL", "&QMMM")
            inserted_atoms = .false.
            do i_line=1,link_template_n_lines
               call insert_cp2k_input_line(cp2k_template_a, trim("&FORCE_EVAL&QMMM")//trim(link_template_a(i_line)), after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
               if (.not.inserted_atoms) then
                  call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&QMMM&LINK MM_INDEX "//i_outer, after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
                  call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&QMMM&LINK QM_INDEX "//i_inner, after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
                  inserted_atoms = .true.
               endif
            enddo
         enddo
      endif
    endif

    ! put in things needed for QM
    if (use_QM) then
      if (try_reuse_wfn .and. can_reuse_wfn) then 
	insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL", "&DFT")
        call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&DFT WFN_RESTART_FILE_NAME ../wfn.restart.wfn"//trim(qm_name_postfix), after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
	!insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&DFT", "&SCF")
	!call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&DFT&SCF SCF_GUESS RESTART", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
      endif
      call calc_charge_lsd(at, qm_list_a, charge, do_lsd)
      insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL", "&DFT")
      call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&DFT CHARGE "//charge, after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
      if (do_lsd) call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&DFT LSD ", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    endif

    ! put in unit cell
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL", "&SUBSYS")

    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&SUBSYS", "&CELL")
    call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&CELL A " // at%lattice(:,1), after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&CELL B " // at%lattice(:,2), after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&CELL C " // at%lattice(:,3), after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1

    ! put in topology
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&SUBSYS", "&TOPOLOGY")
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&SUBSYS&TOPOLOGY", "&DUMP_PSF")
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&SUBSYS&TOPOLOGY", "&DUMP_PDB")
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&SUBSYS&TOPOLOGY", "&GENERATE")
    call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&TOPOLOGY&GENERATE REORDER F", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&TOPOLOGY&GENERATE CREATE_MOLECULES F", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&SUBSYS&TOPOLOGY&GENERATE", "&ISOLATED_ATOMS")
    if (use_QMMM) then
      do i=1, size(qm_list_a)
	call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&TOPOLOGY&GENERATE&ISOLATED_ATOMS LIST " // qm_list_a(i), after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
      end do
    endif
    if (assign_pointer(at, "isolated_atom", isolated_atom)) then
      do i=1, at%N
	if (isolated_atom(i) /= 0) then
	  call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&TOPOLOGY&GENERATE&ISOLATED_ATOMS LIST " // i, after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
	endif
      end do
    endif

    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&FORCE_EVAL&SUBSYS", "&TOPOLOGY")
    call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&TOPOLOGY COORD_FILE_NAME quip_cp2k.xyz", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&TOPOLOGY COORDINATE EXYZ", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    if (trim(psf_print) == "DRIVER_PRINT_AND_SAVE" .or. trim(psf_print) == "USE_EXISTING_PSF") then
      call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&TOPOLOGY CONN_FILE_NAME ../quip_cp2k"//trim(topology_suffix)//".psf", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
      call insert_cp2k_input_line(cp2k_template_a, "&FORCE_EVAL&SUBSYS&TOPOLOGY CONN_FILE_FORMAT PSF", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    endif

    ! put in global stuff to run a single force evalution, print out appropriate things
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "", "&GLOBAL")
    call insert_cp2k_input_line(cp2k_template_a, "&GLOBAL   PROJECT quip", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    call insert_cp2k_input_line(cp2k_template_a, "&GLOBAL   RUN_TYPE MD", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1

    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "", "&MOTION")
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&MOTION", "&PRINT")
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&MOTION&PRINT", "&FORCES")
    call insert_cp2k_input_line(cp2k_template_a, "&MOTION&PRINT&FORCES       FORMAT XMOL", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    insert_pos = find_make_cp2k_input_section(cp2k_template_a, template_n_lines, "&MOTION", "&MD")
    call insert_cp2k_input_line(cp2k_template_a, "&MOTION&MD     ENSEMBLE NVE", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1
    call insert_cp2k_input_line(cp2k_template_a, "&MOTION&MD     STEPS 0", after_line = insert_pos, n_l = template_n_lines); insert_pos = insert_pos + 1

    run_dir = make_run_directory(run_dir_i)

    call write_cp2k_input_file(cp2k_template_a(1:template_n_lines), trim(run_dir)//'/cp2k_input.inp')

    ! prepare xyz file for input to cp2k
    call write(at, trim(run_dir)//'/quip_cp2k.xyz', properties='species:pos')
    ! actually run cp2k
    call run_cp2k_program(trim(cp2k_program), trim(run_dir), max_n_tries)

    ! parse output
    call read_energy_forces(at, qm_and_link_list_a, cur_qmmm_qm_abc, trim(run_dir), "quip", e, f)

    at%pos(1,:) = at%pos(1,:) + centre_pos(1) - cp2k_box_centre_pos(1)
    at%pos(2,:) = at%pos(2,:) + centre_pos(2) - cp2k_box_centre_pos(2)
    at%pos(3,:) = at%pos(3,:) + centre_pos(3) - cp2k_box_centre_pos(3)
    call map_into_cell(at)

    ! unsort
    if (associated(sort_index_p)) then
      call atoms_sort(at, 'sort_index', error=error)
      PASS_ERROR_WITH_INFO("do_cp2k_calc sorting atoms by sort_index",error)
    endif

    if (maxval(abs(f)) > max_force_warning) &
      call print('WARNING cp2k forces max component ' // maxval(abs(f)) // ' at ' // maxloc(abs(f)) // &
		 ' exceeds warning threshold ' // max_force_warning, PRINT_ALWAYS)

    ! save output

    if (use_QM) then
      call system_command('cp '//trim(run_dir)//'/quip-RESTART.wfn wfn.restart.wfn'//trim(qm_name_postfix))
      if (save_output_wfn_files) then
	call system_command('cp '//trim(run_dir)//'/quip-RESTART.wfn run_'//run_dir_i//'_end.wfn.restart.wfn'//trim(qm_name_postfix))
      endif
    endif

    if (save_output_files) then
      call system_command(&
        ' cat '//trim(run_dir)//'/cp2k_input.inp >> cp2k_input_log; echo "##############" >> cp2k_input_log;' // &
        ' cat '//trim(run_dir)//'/cp2k_output.out >> cp2k_output_log; echo "##############" >> cp2k_output_log;' // &
        ' cat filepot.0.xyz'//' >> cp2k_filepot_in_log.xyz;' // &
        ' cat '//trim(run_dir)//'/quip-frc-1.xyz'// ' >> cp2k_force_file_log')
    endif

    ! clean up

    if (clean_up_files) call system_command('rm -rf '//trim(run_dir))

    call system_timer('do_cp2k_calc')

  end subroutine do_cp2k_calc

  function find_make_cp2k_input_section(l_a, n_l, base_sec, new_sec) result(line_n)
    character(len=*), allocatable, intent(inout) :: l_a(:)
    integer, intent(inout) :: n_l
    character(len=*), intent(in) :: base_sec, new_sec
    integer :: line_n

    integer :: i, pamp, pspc
    character(len=1024) :: sec, word, arg, base_sec_root, base_sec_tail, new_sec_end

    line_n = 0

    do i=1, n_l
      call split_cp2k_input_line(trim(l_a(i)), sec, word, arg)

      if (trim(sec) == trim(base_sec) .and. trim(word) == trim(new_sec)) then
	line_n = i
	return
      endif
    end do

    if (len_trim(base_sec) == 0) then
      i = n_l
      call insert_cp2k_input_line(l_a, " "//trim(new_sec), after_line=i, n_l=n_l); i = i + 1
      pspc = index(trim(new_sec)," ")
      if (pspc == 0) then
	new_sec_end = "&END " // new_sec(2:len_trim(new_sec))
      else
	new_sec_end = "&END " // new_sec(2:pspc-1)
      endif
      call insert_cp2k_input_line(l_a, " " // trim(new_sec_end), after_line=i, n_l=n_l); i = i + 1
      line_n = n_l-1
      return
    endif

    pamp = index(base_sec,"&", back=.true.)
    if (pamp <= 1) then
      base_sec_root = ""
      base_sec_tail = trim(base_sec)
    else
      base_sec_root = base_sec(1:pamp-1)
      base_sec_tail = base_sec(pamp:len_trim(base_sec))
    endif


    do i=1, n_l
      call split_cp2k_input_line(trim(l_a(i)), sec, word, arg)
      if (trim(sec) == trim(base_sec_root) .and. trim(word) == trim(base_sec_tail)) then
	call insert_cp2k_input_line(l_a, trim(base_sec)//" "//trim(new_sec), after_line=i, n_l=n_l)
	pspc = index(trim(new_sec)," ")
	if (pspc == 0) then
	  new_sec_end = "&END " // new_sec(2:len_trim(new_sec))
	else
	  new_sec_end = "&END " // new_sec(2:pspc-1)
	endif
	call insert_cp2k_input_line(l_a, trim(base_sec)//" " // trim(new_sec_end), after_line=i+1, n_l=n_l)
	line_n = i+1
	return
      endif
    end do

    if (line_n == 0) &
      call system_abort("Could not find or make section '"//trim(new_sec)//" in base section '"//trim(base_sec))

  end function find_make_cp2k_input_section

  subroutine read_energy_forces(at, qm_list_a, cur_qmmm_qm_abc, run_dir, proj, e, f)
    type(Atoms), intent(in) :: at
    integer, intent(in) :: qm_list_a(:)
    real(dp), intent(in) :: cur_qmmm_qm_abc(3)
    character(len=*), intent(in) :: run_dir, proj
    real(dp), intent(out) :: e, f(:,:)
    real(dp), pointer :: force_p(:,:)

    type(Atoms) :: f_xyz, p_xyz
    integer :: m

    call read(f_xyz, trim(run_dir)//'/'//trim(proj)//'-frc-1.xyz')
    call read(p_xyz, trim(run_dir)//'/'//trim(proj)//'-pos-1.xyz')

    if (.not. get_value(f_xyz%params, "E", e)) &
      call system_abort('read_energy_forces failed to find E value in '//trim(run_dir)//'/quip-frc-1.xyz file')

    if (.not.(assign_pointer(f_xyz, 'frc', force_p))) &
      call system_abort("Did not find frc property in "//trim(run_dir)//'/quip-frc-1.xyz file')
    f = force_p

    e = e * HARTREE
    f  = f * HARTREE/BOHR 
    call reorder_if_necessary(at, qm_list_a, cur_qmmm_qm_abc, p_xyz%pos, f)

    call print('')
    call print('The energy of the system: '//e)
    call verbosity_push_decrement()
      call print('The forces acting on each atom (eV/A):')
      call print('atom     F(x)     F(y)     F(z)')
      do m=1,size(f,2)
        call print('  '//m//'    '//f(1,m)//'  '//f(2,m)//'  '//f(3,m))
      enddo
    call verbosity_pop()
    call print('Sum of the forces: '//sum(f,2))

  end subroutine read_energy_forces

  subroutine reorder_if_necessary(at, qm_list_a, qmmm_qm_abc, new_p, new_f)
    type(Atoms), intent(in) :: at
    integer, intent(in) :: qm_list_a(:)
    real(dp), intent(in) :: qmmm_qm_abc(3)
    real(dp), intent(in) :: new_p(:,:)
    real(dp), intent(inout) :: new_f(:,:)

    real(dp) :: shift(3)
    integer, allocatable :: reordering_index(:)
    integer :: i, j

    ! shifted cell in case of QMMM (cp2k/src/toplogy_coordinate_util.F)
    shift = 0.0_dp
    if (size(qm_list_a) > 0) then
      do i=1,3
	shift(i) = 0.5_dp * qmmm_qm_abc(i) - (minval(at%pos(i,qm_list_a)) + maxval(at%pos(i,qm_list_a)))*0.5_dp
      end do
    endif
    allocate(reordering_index(at%N))
    call check_reordering(at%pos, shift, new_p, at%g, reordering_index)
    if (any(reordering_index == 0)) then
      ! try again with shift of a/2 b/2 c/2 in case TOPOLOGY%CENTER_COORDINATES is set
      shift = sum(at%lattice(:,:),2)/2.0_dp - &
	      (minval(at%pos(:,:),2)+maxval(at%pos(:,:),2))/2.0_dp
      call check_reordering(at%pos, shift, new_p, at%g, reordering_index)
      if (any(reordering_index == 0)) then
	! try again with uniform shift (module periodic cell)
	shift = new_p(:,1) - at%pos(:,1)
	call check_reordering(at%pos, shift, new_p, at%g, reordering_index)
	if (any(reordering_index == 0)) &
	  call system_abort("Could not match original and read in atom objects")
      endif
    endif

    new_f(1,reordering_index(:)) = new_f(1,:)
    new_f(2,reordering_index(:)) = new_f(2,:)
    new_f(3,reordering_index(:)) = new_f(3,:)

    deallocate(reordering_index)
  end subroutine reorder_if_necessary

  subroutine check_reordering(old_p, shift, new_p, recip_lattice, reordering_index)
    real(dp), intent(in) :: old_p(:,:), shift(3), new_p(:,:), recip_lattice(3,3)
    integer, intent(out) :: reordering_index(:)

    integer :: N, i, j
    real(dp) :: dpos(3), dpos_i(3)

    N = size(old_p,2)

    reordering_index = 0
    do i=1, N
      do j=1, N
	dpos = matmul(recip_lattice(1:3,1:3), old_p(1:3,i) + shift(1:3) - new_p(1:3,j))
	dpos_i = nint(dpos)
	if (all(abs(dpos-dpos_i) <= 1.0e-4_dp)) then
	  reordering_index(i) = j
	  cycle
	endif
      end do
    end do
  end subroutine check_reordering

  subroutine run_cp2k_program(cp2k_program, run_dir, max_n_tries)
    character(len=*), intent(in) :: cp2k_program, run_dir
    integer, intent(in) :: max_n_tries

    integer :: n_tries
    logical :: converged
    character(len=1024) :: cp2k_run_command
    integer :: stat, error_stat

    n_tries = 0
    converged = .false.

    do while (.not. converged .and. (n_tries < max_n_tries))
      n_tries = n_tries + 1

      cp2k_run_command = 'cd ' // trim(run_dir)//'; '//trim(cp2k_program)//' cp2k_input.inp >> cp2k_output.out'
      call print("Doing '"//trim(cp2k_run_command)//"'")
      call system_timer('cp2k_run_command')
      call system_command(trim(cp2k_run_command), status=stat)
      call system_timer('cp2k_run_command')
      call print('grep -i warning '//trim(run_dir)//'/cp2k_output.out', PRINT_ALWAYS)
      call system_command("fgrep -i 'warning' "//trim(run_dir)//"/cp2k_output.out")
      call system_command("fgrep -i 'error' "//trim(run_dir)//"/cp2k_output.out", status=error_stat)
      if (stat /= 0) &
	call system_abort('cp2k_run_command has non zero return status ' // stat //'. check output file '//trim(run_dir)//'/cp2k_output.out')
      if (error_stat == 0) &
	call system_abort('cp2k_run_command generated ERROR message in output file '//trim(run_dir)//'/cp2k_output.out')

      call system_command('egrep "FORCE_EVAL.* QS " '//trim(run_dir)//'/cp2k_output.out',status=stat)
      if (stat == 0) then ! QS or QMMM run
	call system_command('grep "FAILED to converge" '//trim(run_dir)//'/cp2k_output.out',status=stat)
	if (stat == 0) then
	  call print("WARNING: cp2k_driver failed to converge, trying again",PRINT_ALWAYS)
	  converged = .false.
	else
	  call system_command('grep "SCF run converged" '//trim(run_dir)//'/cp2k_output.out',status=stat)
	  if (stat == 0) then
	    converged = .true.
	  else
	    call print("WARNING: cp2k_driver couldn't find definitive sign of convergence or failure to converge in output file, trying again",PRINT_ALWAYS)
	    converged = .false.
	  endif
	end if
      else ! MM run
	converged = .true.
      endif
    end do

    if (.not. converged) &
      call system_abort('cp2k failed to converge after n_tries='//n_tries//'. see output file '//trim(run_dir)//'/cp2k_output.out')

  end subroutine run_cp2k_program

  function make_run_directory(run_dir_i) result(dir)
    integer, intent(out), optional :: run_dir_i
    integer i
    character(len=1024) :: dir

    logical :: exists
    integer stat

    exists = .true.
    i = 0
    do while (exists)
      i = i + 1
      dir = "cp2k_run_"//i
      inquire(file=trim(dir)//'/cp2k_input.inp', exist=exists)
    end do
    call system_command("mkdir "//trim(dir), status=stat)

    if (stat /= 0) &
      call system_abort("Failed to mkdir "//trim(dir)//" status " // stat)

    if (present(run_dir_i)) run_dir_i = i

  end function make_run_directory

  subroutine write_cp2k_input_file(l_a, filename)
    character(len=*), intent(in) :: l_a(:)
    character(len=*), intent(in) :: filename

    integer :: i, pspc
    type(Inoutput) :: io

    call initialise(io, trim(filename), OUTPUT)
    do i=1, size(l_a)
      pspc = index(l_a(i), " ")
      call print(l_a(i)(pspc+1:len_trim(l_a(i))), file=io)
    end do
    call finalise(io)

  end subroutine write_cp2k_input_file

  subroutine split_cp2k_input_line(l, sec, word, arg)
    character(len=*) :: l, sec, word, arg

    character(len=len(l)) :: t_l
    integer :: pspc

    t_l = l

    pspc = index(trim(t_l), " ")
    if (pspc == 0 .or. pspc == 1) then ! top level
      sec = ""
    else
      sec = t_l(1:pspc-1)
    endif

    t_l = adjustl(t_l(pspc+1:len_trim(t_l)))

    pspc = index(trim(t_l), " ")
    if (pspc == 0) then ! no arg
      word = trim(t_l)
      arg = ""
    else
      word = t_l(1:pspc-1)
      arg = t_l(pspc+1:len_trim(t_l))
    endif

    sec = adjustl(sec)
    word = adjustl(word)
    arg = adjustl(arg)

  end subroutine split_cp2k_input_line

  subroutine substitute_cp2k_input(l_a, s_source, s_targ, n_l)
    character(len=*), intent(inout) :: l_a(:)
    character(len=*), intent(in) :: s_source, s_targ
    integer, intent(in) :: n_l

    character(len=len(l_a(1))) :: t
    integer :: i, p, l_targ, l_source, len_before, len_after

    l_targ = len(s_targ)
    l_source = len(s_source)

    do i=1, n_l
      p = index(l_a(i), s_source)
      if (p > 0) then
	len_before = p-1
	len_after = len_trim(l_a(i)) - l_source - p + 1
	t = ""
	if (len_before > 0) then
	  t(1:len_before) = l_a(i)(1:len_before)
	endif
	t(len_before+1:len_before+1+l_targ-1) = s_targ(1:l_targ)
	if (len_after > 0) then
	  t(len_before+1+l_targ:len_before+1+l_targ+len_after-1) = l_a(i)(len_before+l_source+1:len_before+l_source+1+len_after-1)
	endif
	l_a(i) = t
      end if
    end do
  end subroutine substitute_cp2k_input

  subroutine insert_cp2k_input_line(l_a, l, after_line, n_l)
    character(len=*), allocatable, intent(inout) :: l_a(:)
    character(len=*), intent(in) :: l
    integer, intent(in) :: after_line
    integer, intent(inout) :: n_l

    integer :: i

    if (n_l+1 > size(l_a)) call extend_char_array(l_a)

    do i=n_l, after_line+1, -1
      l_a(i+1) = l_a(i)
    end do
    l_a(after_line+1) = trim(l)
    n_l = n_l + 1
  end subroutine insert_cp2k_input_line

  subroutine prefix_cp2k_input_sections(l_a)
    character(len=*), intent(inout) :: l_a(:)

    integer :: pamp
    character(len=1024) :: section_str, new_section_str
    integer :: i, j, comment_i

    section_str = ""
    new_section_str = ""
    do i=1, size(l_a)
      comment_i = index(l_a(i), "#")
      if (comment_i /= 0) then
	l_a(i)(comment_i:len(l_a(i))) = ""
      endif
      if (index(l_a(i),"&END") /= 0) then
	pamp = index(section_str, "&", .true.)
	new_section_str = section_str(1:pamp-1)
	section_str = new_section_str
      else if (index(l_a(i),"&") /= 0) then
	pamp = index(l_a(i), "&")
	new_section_str = trim(section_str)
	do j=pamp, len_trim(l_a(i))
	  if (l_a(i)(j:j) == " ") then
	    new_section_str = trim(new_section_str) // "-"
	  else
	    new_section_str = trim(new_section_str) // l_a(i)(j:j)
	  endif
	end do
      endif
      l_a(i) = (trim(section_str) //" "//trim(l_a(i)))
      section_str = new_section_str
    end do
  end subroutine

  function qmmm_qm_abc(at, qm_list_a, qm_vacuum)
    type(Atoms), intent(in) :: at
    integer, intent(in) :: qm_list_a(:)
    real(dp), intent(in) :: qm_vacuum
    real(dp) :: qmmm_qm_abc(3)

    real(dp) :: qm_maxdist(3)
    integer i, j

    qm_maxdist = 0.0_dp
    do i=1, size(qm_list_a)
    do j=1, size(qm_list_a)
      qm_maxdist(1) = max(qm_maxdist(1), at%pos(1,qm_list_a(i))-at%pos(1,qm_list_a(j)))
      qm_maxdist(2) = max(qm_maxdist(2), at%pos(2,qm_list_a(i))-at%pos(2,qm_list_a(j)))
      qm_maxdist(3) = max(qm_maxdist(3), at%pos(3,qm_list_a(i))-at%pos(3,qm_list_a(j)))
    end do
    end do

    qmmm_qm_abc(1) = min(real(ceiling(qm_maxdist(1)))+qm_vacuum,at%lattice(1,1))
    qmmm_qm_abc(2) = min(real(ceiling(qm_maxdist(2)))+qm_vacuum,at%lattice(2,2))
    qmmm_qm_abc(3) = min(real(ceiling(qm_maxdist(3)))+qm_vacuum,at%lattice(3,3))

  end function

  subroutine calc_charge_lsd(at, qm_list_a, charge, do_lsd)
    type(Atoms), intent(in) :: at
    integer, intent(in) :: qm_list_a(:)
    integer, intent(out) :: charge
    logical, intent(out) :: do_lsd

    real(dp), pointer :: atom_charge(:)
    integer, pointer  :: Z_p(:)
    integer           :: sum_Z
    logical           :: dummy

    if (.not. assign_pointer(at, "Z", Z_p)) &
	call system_abort("calc_charge_lsd could not find Z property")

    if (size(qm_list_a) > 0) then
      if (.not. assign_pointer(at, "atom_charge", atom_charge)) &
	call system_abort("calc_charge_lsd could not find atom_charge")
      charge = nint(sum(atom_charge(qm_list_a)))
      !check if we have an odd number of electrons
      sum_Z = sum(Z_p(qm_list_a(1:size(qm_list_a))))
      do_lsd = (mod(sum_Z-charge,2) /= 0)
    else
      sum_Z = sum(Z_p)
      do_lsd = .false.
      charge = 0 
      dummy = (get_value(at%params, 'LSD', do_lsd))
      !if charge is saved, also check if we have an odd number of electrons
      if (get_value(at%params, 'Charge', charge)) then
        call print("Using Charge " // charge)
        do_lsd = do_lsd .or. (mod(sum_Z-charge,2) /= 0)
      else !charge=0 is assumed by CP2K
        do_lsd = do_lsd .or. (mod(sum_Z,2) /= 0)
      endif
      if (do_lsd) call print("Using do_lsd " // do_lsd)
    endif

  end subroutine


end module cp2k_driver_template_module
