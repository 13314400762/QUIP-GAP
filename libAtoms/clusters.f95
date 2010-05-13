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

module clusters_module
  use Atoms_module
  use Table_module
  use ParamReader_module
  use system_module
  use atoms_module
  use dynamicalsystem_module
  use table_module
  use periodictable_module
  use cinoutput_module

implicit none
private

integer, parameter :: &
   HYBRID_ACTIVE_MARK = 1, &
   HYBRID_BUFFER_MARK = 2, &
   HYBRID_TRANS_MARK = 3, &
   HYBRID_TERM_MARK = 4, &
   HYBRID_BUFFER_OUTER_LAYER_MARK = 5, &
   HYBRID_NO_MARK = 0

!   HYBRID_FIT_MARK = 6, &

public :: HYBRID_ACTIVE_MARK, HYBRID_BUFFER_MARK, HYBRID_TRANS_MARK, HYBRID_TERM_MARK, &
   HYBRID_BUFFER_OUTER_LAYER_MARK, HYBRID_NO_MARK
! HYBRID_FIT_MARK

character(len=TABLE_STRING_LENGTH), parameter :: hybrid_mark_name(0:6) = &
  (/ "h_none    ", &
     "h_active  ", &
     "h_buffer  ", &
     "h_trans   ", &
     "h_term    ", &
     "h_outer_l ", &
     "h_fit     " /)

public :: create_cluster_info_from_hybrid_mark, carve_cluster, create_hybrid_weights, &
    bfs_grow, bfs_step, multiple_images, discard_non_min_images, make_convex, create_embed_and_fit_lists, &
    create_embed_and_fit_lists_from_cluster_mark, &
    add_cut_hydrogens, construct_hysteretic_region, &
    create_pos_or_list_centred_hybrid_region, get_hybrid_list
    !, construct_region, select_hysteretic_quantum_region

!% Grow a selection list by bond hopping.
interface bfs_grow
   module procedure bfs_grow_single
   module procedure bfs_grow_list
end interface

contains

  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  !X
  !X   Cluster carving routines
  !X
  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

  !% On exit, 'list' will contain 'atom' (with shift '000') 
  !% plus the atoms within 'n' bonds hops of it.
  subroutine bfs_grow_single(this, list, atom, n, nneighb_only, min_images_only, alt_connect)
    type(Atoms), intent(in)  :: this
    type(Table), intent(out) :: list
    integer, intent(in) :: atom, n
    logical, optional, intent(in)::nneighb_only, min_images_only
    type(Connection), intent(in), optional :: alt_connect

    call append(list, (/atom, 0,0,0/)) ! Add atom with shift 000
    call bfs_grow_list(this, list, n, nneighb_only, min_images_only, alt_connect)

  end subroutine bfs_grow_single


  !% On exit, 'list' will have been grown by 'n' bond hops.
  subroutine bfs_grow_list(this, list, n, nneighb_only, min_images_only, alt_connect)
    type(Atoms), intent(in)   ::this
    type(Table), intent(inout)::list
    integer, intent(in) :: n
    logical, optional, intent(in)::nneighb_only, min_images_only
    type(Connection), intent(in), optional :: alt_connect

    type(Table)::tmplist
    integer::i

    do i=1,n
       call bfs_step(this, list, tmplist, nneighb_only, min_images_only, alt_connect=alt_connect)
       call append(list, tmplist)
    end do

    if (n >= 1) call finalise(tmplist)
  end subroutine bfs_grow_list


  !% Execute one Breadth-First-Search move on the atomic connectivity graph.
  subroutine bfs_step(this,input,output,nneighb_only, min_images_only, max_r, alt_connect, property, debugfile)
    type(Atoms),        intent(in), target      :: this  !% The atoms structure to perform the step on.
    type(Table),        intent(in)      :: input !% Table with intsize 4. First integer column is indices of atoms
                                                 !% already in the region, next 3 are shifts.
    type(Table),        intent(out)     :: output !% Table with intsize 4, containing the new atomic 
                                                  !% indices and shifts.


    logical, optional,  intent(in)      :: nneighb_only
    !% If present and true, sets whether only neighbours
    !% within the sum of the two respective covalent radii (multiplied by the atom's nneightol) are included,
    !% irrespective of the cutoff in the atoms structure
    !% (default is true).

    logical, optional, intent(in)       :: min_images_only 
    !% If true, there will be no repeated atomic indices in final list - only the
    !% minimum shift image of those found will be included. Default is false.

    real(dp), optional, intent(in)      :: max_r
    !% if present, only neighbors within this range will be included

    type(Connection), intent(in), optional, target :: alt_connect
    integer, intent(in), optional:: property(:)

    type(inoutput), optional :: debugfile

    !local
    logical                             :: do_nneighb_only, do_min_images_only
    integer                             :: i, j, n, m, jshift(3), ishift(3)

    integer :: n_i, keep_row(4), in_i, min_image
    integer, allocatable, dimension(:) :: repeats
    real(dp), allocatable, dimension(:) :: norm2shift
    type(Connection), pointer :: use_connect

    if (present(debugfile)) call print("bfs_step", file=debugfile)
    if (present(alt_connect)) then
       use_connect => alt_connect
    else
      use_connect => this%connect
    endif

    if (present(debugfile)) call print("bfs_step cutoff " // this%cutoff // " " // this%use_uniform_cutoff, file=debugfile)

    if (.not.use_connect%initialised) &
         call system_abort('BFS_Step: Atomic structure has no connectivity data')

    do_nneighb_only = optional_default(.true., nneighb_only)

    do_min_images_only = optional_default(.false., min_images_only)

    if (present(debugfile)) call print('bfs_step: do_nneighb_only = ' // do_nneighb_only // ' do_min_images_only = '//do_min_images_only, file=debugfile)
    call print('bfs_step: do_nneighb_only = ' // do_nneighb_only // ' do_min_images_only = '//do_min_images_only, NERD)

    if(input%intsize /= 4 .or. input%realsize /= 0) &
         call system_abort("bfs_step: input table must have intsize=4.")

    call table_allocate(output, 4, 0, 0, 0)

    ! Now go though the atomic indices
    do m = 1, input%N
       i = input%int(1,m)
       ishift = input%int(2:4,m)

       if (present(debugfile)) call print("bfs_step check atom " // m // " " // i // " with n_neigh " // atoms_n_neighbours(this, i, alt_connect=use_connect), file=debugfile)
       ! Loop over i's neighbours
       do n = 1, atoms_n_neighbours(this,i, alt_connect=use_connect)
	  j = atoms_neighbour(this,i,n,shift=jshift,max_dist=max_r, alt_connect=use_connect)
	  if (present(debugfile)) call print("bfs_step   check neighbour " // n // " " // j, file=debugfile)
	  if (j == 0) cycle

          ! Look at next neighbour if j with correct shift is already in the cluster
          ! Must check input AND output tables
          if (find(input,(/j,ishift+jshift/)) > 0) cycle
	  if (present(debugfile)) call print("bfs_step   not in input", file=debugfile)
          if (find(output,(/j,ishift+jshift/)) > 0) cycle
	  if (present(debugfile)) call print("bfs_step   not in output", file=debugfile)

          if (do_nneighb_only .and. .not. is_nearest_neighbour(this, i, n, alt_connect=use_connect)) cycle
	  if (present(debugfile)) call print("bfs_step   acceptably near neighbor", file=debugfile)

          if (present(property)) then
             if (property(j) == 0) cycle
          endif
	  if (present(debugfile)) call print("bfs_step   property matches OK", file=debugfile)

          ! Everything checks out ok, so add j to the output table
          ! with correct shift
	  if (present(debugfile)) call print("bfs_step   appending", file=debugfile)
          call append(output,(/j,ishift+jshift/)) 
       end do
    end do

    if (present(debugfile)) call print("bfs_step   raw output", file=debugfile)
    if (present(debugfile)) call print(output, file=debugfile)

    if (do_min_images_only) then

       ! If there are repeats of any atomic index, 
       ! we want to keep the one with smallest norm2(shift)

       ! must check input and output

       n = 1
       do while (n <= output%N)

          ! How many occurances in the output list?
          n_i = count(int_part(output,1) == output%int(1,n))

          ! Is there one in the input list as well?
          in_i = find_in_array(int_part(input,1),output%int(1,n))

          ! If there's only one, and we've not got one already then move on
          if (n_i == 1 .and. in_i == 0) then 
             n = n + 1
             cycle
          end if

          ! otherwise, things are more complicated...
          ! we want to keep the one with the smallest shift, bearing
          ! in mind that it could well be the one in the input list

          allocate(repeats(n_i), norm2shift(n_i))

          ! Get indices of repeats of this atomic index
          repeats = pack((/ (j, j=1,output%N) /), &
               int_part(output,1) == output%int(1,n))

          if (in_i /= 0) then
             ! atom is in input list, remove all new occurances
             call delete_multiple(output, repeats)
          else
             ! Find row with minimum norm2(shift)
             norm2shift = norm2(real(output%int(2:4,repeats),dp),1)
             min_image = repeats(minloc(norm2shift,dim=1))
             keep_row = output%int(:,min_image)

             ! keep the minimum image
             call delete_multiple(output, &
                  pack(repeats, repeats /= min_image))
          end if

          ! don't increment n, since delete_multiple copies items from
          ! end of list over deleted items, so we need to retest

          deallocate(repeats, norm2shift)

       end do

    end if

    if (present(debugfile)) call print("bfs_step   final output", file=debugfile)
    if (present(debugfile)) call print(output, file=debugfile)

  end subroutine bfs_step


  !% Check if the list of indices and shifts 'list' contains
  !% any repeated atomic indices.
  function multiple_images(list)
    type(Table), intent(in) :: list
    logical :: multiple_images


    integer :: i
    multiple_images = .false.

    if (list%N == 0) return

    do i = 1, list%N
       if (count(int_part(list,1) == list%int(1,i)) /= 1) then
          multiple_images = .true.
          return
       end if
    end do

  end function multiple_images

  !% Given an input list with 4 integer columns for atomic indices
  !% and shifts, keep only the minimum images of each atom
  subroutine discard_non_min_images(list)
    type(Table), intent(inout) :: list

    integer :: n, n_i, j, min_image, keep_row(4)
    integer, allocatable, dimension(:) :: repeats
    real(dp), allocatable, dimension(:) :: norm2shift

    n = 1
    do while (n <= list%N)

       ! How many occurances in the list list?
       n_i = count(int_part(list,1) == list%int(1,n))

       ! If there's only one, and we've not got one already then move on
       if (n_i == 1) then 
          n = n + 1
          cycle
       end if

       ! otherwise, things are more complicated...
       ! we want to keep the one with the smallest shift

       allocate(repeats(n_i), norm2shift(n_i))

       ! Get indices of repeats of this atomic index
       repeats = pack((/ (j, j=1,list%N) /), &
            int_part(list,1) == list%int(1,n))

       ! Find row with minimum norm2(shift)
       norm2shift = norm2(real(list%int(2:4,repeats),dp),1)
       min_image = repeats(minloc(norm2shift,dim=1))
       keep_row = list%int(:,min_image)

       ! keep the minimum image
       call delete_multiple(list, &
            pack(repeats, repeats /= min_image))

       ! don't increment n, since delete_multiple copies items from
       ! end of list over deleted items, so we need to retest

       deallocate(repeats, norm2shift)

    end do

  end subroutine discard_non_min_images


  !% Add atoms to 'list' to make the selection region convex, i.e. if $i$ and
  !% $j$ are nearest neighbours, with $i$ in the list and not $j$ then $j$ will be added
  !% if more than half its nearest neighbours are in the list.
  subroutine make_convex(this, list)
    type(Atoms), intent(in) :: this
    type(Table), intent(inout) :: list
    type(Table)::tmplist
    do while(make_convex_step(this, list, tmplist) /= 0)
       call append(list, tmplist)
    end do
    call finalise(tmplist)
  end subroutine make_convex

  !% OMIT
  ! Given an input list, what needs to be added to make the selection region convex?
  function make_convex_step(this, input, output) result(newatoms)
    type(Atoms), intent(in) :: this
    type(Table), intent(in) :: input
    type(Table), intent(out) :: output
    integer::newatoms

    integer :: n, i, j, k, p, m, n_in, nn, ishift(3), jshift(3), kshift(3)
    real(dp) :: r_ij, r_kj

    ! Check table size
    if(input%intsize /= 4 .or. input%realsize /= 0) &
         call system_abort("make_convex_step: input table must have intsize=4")

    if(input%intsize /= 4 .or. input%realsize /= 0) &
         call system_abort("bfs_step: input table must have intsize=4.")

    call table_allocate(output, 4, 0, 0, 0)

    do n=1,input%N
       i = input%int(1,n)
       ishift = input%int(2:4,n)

       !Loop over neighbours
       do m = 1, atoms_n_neighbours(this,i)
          j = atoms_neighbour(this,i,m, r_ij,shift=jshift)

          ! Look for nearest neighbours of i not in input list
          if (find(input,(/j,ishift+jshift/)) == 0 .and. is_nearest_neighbour(this, i, m)) then

             n_in = 0
             nn = 0
             ! Count number of nearest neighbours of j, and how many
             ! of them are in input list
             do p = 1, atoms_n_neighbours(this,j)
                k = atoms_neighbour(this,j,p, r_kj, shift=kshift)
                if (is_nearest_neighbour(this, j, p)) then
                   nn = nn + 1
                   if (find(input,(/k,ishift+jshift+kshift/)) /= 0) n_in = n_in + 1
                end if
             end do

             !If more than half of  j's nearest neighbours are in then add it to output
             if (find(output, (/j,ishift+jshift/)) == 0 .and. real(n_in,dp)/real(nn,dp) > 0.5_dp) &
                  call append(output, (/j,ishift+jshift/))

          end if

       end do
    end do

    newatoms = output%N

  end function  make_convex_step


!OUTDATED   ! Gotcha 1: Hollow sections
!OUTDATED   !NB equivalent to reduce_n_cut_bonds when new number of bonds is 0
!OUTDATED   ! OUT and IN refers to the list in cluster_info
!OUTDATED   ! Look at the OUT nearest neighbours of IN atoms. If all the nearest neighbours of the OUT
!OUTDATED   ! atom are IN, then make the OUT atom IN.
!OUTDATED   function cluster_ss_in_out_in(this, cluster_info, connectivity_just_from_connect, use_connect, atom_mask) result(cluster_changed)
!OUTDATED     type(Atoms), intent(in) :: this
!OUTDATED     type(Table), intent(inout) :: cluster_info
!OUTDATED     logical, intent(in) :: connectivity_just_from_connect
!OUTDATED     type(Connection), intent(in) :: use_connect
!OUTDATED     logical, intent(in) :: atom_mask(6)
!OUTDATED     logical :: cluster_changed
!OUTDATED 
!OUTDATED     integer :: n, i, ishift(3), m, j, jshift(3), p, k, kshift(3)
!OUTDATED     logical :: all_in
!OUTDATED 
!OUTDATED     cluster_changed = .false.
!OUTDATED 
!OUTDATED     n = 1
!OUTDATED     ! Loop over cluster atoms (including ones that may get added in this loop)
!OUTDATED     call print('create_cluster: Checking for hollow sections', NERD)
!OUTDATED     do while (n <= cluster_info%N)
!OUTDATED       i = cluster_info%int(1,n)
!OUTDATED       ishift = cluster_info%int(2:4,n)
!OUTDATED       call print('cluster_ss_in_out_in: i = '//i//' ['//ishift//'] Looping over '//atoms_n_neighbours(this,i,alt_connect=use_connect)//' neighbours...',ANAL)
!OUTDATED 
!OUTDATED       !Loop over neighbours
!OUTDATED       do m = 1, atoms_n_neighbours(this,i,alt_connect=use_connect)
!OUTDATED 	j = atoms_neighbour(this,i,m, shift=jshift,alt_connect=use_connect)
!OUTDATED 
!OUTDATED 	if (find(cluster_info,(/j,ishift+jshift,this%Z(j),0/), atom_mask) == 0 .and. &
!OUTDATED 	    (connectivity_just_from_connect .or. is_nearest_neighbour(this, i, m, alt_connect=use_connect)) ) then
!OUTDATED 	  ! j is out and is nearest neighbour
!OUTDATED 
!OUTDATED 	  call print('cluster_ss_in_out_in:   checking j = '//j//" ["//jshift//"]",ANAL)
!OUTDATED 
!OUTDATED 	  ! We have an OUT nearest neighbour, loop over its nearest neighbours to see if they
!OUTDATED 	  ! are all IN
!OUTDATED 
!OUTDATED 	  all_in = .true.
!OUTDATED 	  do p = 1, atoms_n_neighbours(this,j,alt_connect=use_connect)
!OUTDATED 	    k = atoms_neighbour(this,j,p, shift=kshift,alt_connect=use_connect)
!OUTDATED 	    if (find(cluster_info,(/k,ishift+jshift+kshift,this%Z(k),0/), atom_mask) == 0 .and. &
!OUTDATED 	      (connectivity_just_from_connect .or. is_nearest_neighbour(this, j, p,alt_connect=use_connect)) ) then
!OUTDATED 	      all_in = .false.
!OUTDATED 	      exit
!OUTDATED 	    end if
!OUTDATED 	  end do
!OUTDATED 
!OUTDATED 	  !If all j's nearest neighbours are IN then add it
!OUTDATED 	  if (all_in) then
!OUTDATED 	    call append(cluster_info, (/j,ishift+jshift,this%Z(j),0/), (/this%pos(:,j), 1.0_dp/), (/ "hollow    "/) )
!OUTDATED 	    cluster_changed = .true.
!OUTDATED 	    call print('cluster_ss_in_out_in:  Added atom ' //j//' ['//(ishift+jshift)//'] to cluster. Atoms = ' // cluster_info%N, NERD)
!OUTDATED 	  end if
!OUTDATED 
!OUTDATED 	end if
!OUTDATED 
!OUTDATED       end do ! m
!OUTDATED       n = n + 1
!OUTDATED     end do ! while (n <= cluster_info%N)
!OUTDATED 
!OUTDATED     call print('cluster_ss_in_out_in: Finished checking',NERD)
!OUTDATED     call print("cluster_ss_in_out_in: cluster list:", NERD)
!OUTDATED     call print(cluster_info, NERD)
!OUTDATED   end function cluster_ss_in_out_in

  !% Find cases where two IN atoms have a common
  !% OUT nearest neighbour, and see if termination would cause the hydrogen
  !% atoms to be too close together. If so, include the OUT nearest neighbour
  !% in the cluster
  !% returns true if cluster was changed
  function cluster_fix_termination_clash(this, cluster_info, connectivity_just_from_connect, use_connect, atom_mask) result(cluster_changed)
    type(Atoms), intent(in) :: this !% atoms structure 
    type(Table), intent(inout) :: cluster_info !% table of cluster info, modified if necessary on output
    logical, intent(in) :: connectivity_just_from_connect !% if true, we're doing hysterestic connect and should rely on the connection object completely
    type(Connection), intent(in) :: use_connect !% connection object to use for connectivity info
    logical, intent(in) :: atom_mask(6) !% which fields in int part of table to compare when checking for identical atoms
    logical :: cluster_changed

    integer :: n, i, ishift(3), m, j, jshift(3), p, k, kshift(3)
    real(dp) :: dhat_ij(3), dhat_jk(3), r_ij, r_jk, H1(3), H2(3), diff_ik(3)
    ! real(dp) :: t_norm

    cluster_changed = .false.

    call print('doing cluster_fix_termination_clash', NERD)

    !Loop over atoms in the cluster
    n = 1
    do while (n <= cluster_info%N)
      i = cluster_info%int(1,n)     ! index of atom in the cluster
      ishift = cluster_info%int(2:4,n)
      call print('cluster_fix_termination_clash: i = '//i//'. Looping over '//atoms_n_neighbours(this,i,alt_connect=use_connect)//' neighbours...',ANAL)
      !Loop over atom i's neighbours
      do m = 1, atoms_n_neighbours(this,i,alt_connect=use_connect)
	j = atoms_neighbour(this,i,m, shift=jshift, diff=dhat_ij, distance=r_ij,alt_connect=use_connect)
	dhat_ij = dhat_ij/r_ij

	!If j is IN the cluster, or not a nearest neighbour then try the next neighbour
	if(find(cluster_info,(/j,ishift+jshift,this%Z(j),0/), atom_mask) /= 0) then
	  call print('cluster_fix_termination_clash:   j = '//j//" ["//jshift//"] is in cluster",ANAL)
	  cycle
	end if
	if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,i, m, alt_connect=use_connect))) then
	  call print('cluster_fix_termination_clash:   j = '//j//" ["//jshift//"] not nearest neighbour",ANAL)
	  cycle
	end if

	! So j is an OUT nearest neighbour of i.
	call print('cluster_fix_termination_clash:   checking j = '//j//" ["//jshift//"]",ANAL)

	!Determine the position of the would-be hydrogen along i--j
	call print('cluster_fix_termination_clash:  Finding i--j hydrogen position',ANAL)

	H1 = this%pos(:,i) + (this%lattice .mult. (ishift)) + &
	     termination_bond_rescale(this%Z(i), this%Z(j)) * r_ij * dhat_ij

	!Do a loop over j's nearest neighbours
	call print('cluster_fix_termination_clash:  Looping over '//atoms_n_neighbours(this,j, alt_connect=use_connect)//' neighbours of j', ANAL)

	do p = 1, atoms_n_neighbours(this,j, alt_connect=use_connect)
	  k = atoms_neighbour(this,j,p, shift=kshift, diff=dhat_jk, distance=r_jk, alt_connect=use_connect)
	  dhat_jk = dhat_jk/r_jk

	  !If k is OUT of the cluster or k == i or it is not a nearest neighbour of j
	  !then try the next neighbour

	  if(find(cluster_info,(/k,ishift+jshift+kshift,this%Z(k),0/), atom_mask) == 0) then
	    call print('cluster_fix_termination_clash:   k = '//k//" ["//kshift//"] not in cluster",ANAL)
	    cycle
	  end if
	  if(k == i .and. all( jshift+kshift == 0 )) cycle
	  if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,j, p, alt_connect=use_connect))) then
	    call print('cluster_fix_termination_clash:   k = '//k//" ["//kshift//"] not nearest neighbour",ANAL)
	    cycle
	  end if

	  call print('cluster_fix_termination_clash: testing k = '//k//" ["//kshift//"]", ANAL)
	  !Determine the position of the would-be hydrogen along k--j
	  call print('cluster_fix_termination_clash:   Finding k--j hydrogen position',ANAL)

	  diff_ik = r_ij * dhat_ij + r_jk * dhat_jk

	  H2 = this%pos(:,i) + (this%lattice .mult. (ishift)) + diff_ik - &
	    termination_bond_rescale(this%Z(k), this%Z(j)) * r_jk * dhat_jk
	  call print('cluster_fix_termination_clash:   Checking i--k distance and hydrogen distance',ANAL)

	  call print("cluster_fix_termination_clash: proposed hydrogen positions:", ANAL)
	  call print(H1, ANAL)
	  call print(H2, ANAL)
	  !NB workaround for pgf90 bug (as of 9.0-1)
	  ! t_norm = norm(H1-H2); call print("cluster_fix_termination_clash: hydrogen distance would be "//t_norm, ANAL)
	  !NB end of workaround for pgf90 bug (as of 9.0-1)
	  ! If i and k are nearest neighbours, or the terminating hydrogens would be very close, then
	  ! include j in the cluster. The H--H checking is conservative, hence the extra factor of 1.2
	  if ((norm(diff_ik) < bond_length(this%Z(i),this%Z(k))*this%nneightol) .or. &
	      (norm(H1-H2) < bond_length(1,1)*this%nneightol*1.2_dp) ) then

	    call append(cluster_info,(/j,ishift+jshift,this%Z(j),0/),(/this%pos(:,j),1.0_dp/), (/ "clash     "/) )
	    cluster_changed = .true.
	    call print('cluster_fix_termination_clash:  Atom '//j//' added to cluster. Atoms = '//cluster_info%N, NERD)
	    ! j is now included in the cluster, so we can exit this do loop (over p)
	    exit
	  end if 

	end do ! p

      end do ! m

      n = n + 1
    end do ! while (n <= cluster_info%N)

    call print('cluster_fix_termination_clash: Finished checking',NERD)
    call print("cluster_fix_termination_clash: cluster list:", NERD)
    call print(cluster_info, NERD)
  end function cluster_fix_termination_clash

  !% keep each whole residue (using atom_res_number(:) property) if any bit of it is already included
  function cluster_keep_whole_residues(this, cluster_info, connectivity_just_from_connect, use_connect, atom_mask, present_keep_whole_residues) result(cluster_changed)
    type(Atoms), intent(in) :: this !% atoms structure 
    type(Table), intent(inout) :: cluster_info !% table of cluster info, modified if necessary on output
    logical, intent(in) :: connectivity_just_from_connect !% if true, we're doing hysterestic connect and should rely on the connection object completely
    type(Connection), intent(in) :: use_connect !% connection object to use for connectivity info
    logical, intent(in) :: atom_mask(6) !% which fields in int part of table to compare when checking for identical atoms
    logical, intent(in) :: present_keep_whole_residues !% if true, keep_whole_residues was specified by user, not just a default value
    logical :: cluster_changed
    
    integer :: n, i, ishift(3), m, j, jshift(3)
    integer, pointer :: atom_res_number(:)

    call print('doing cluster_keep_whole_residues', NERD)

    cluster_changed = .false.
    if (.not. assign_pointer(this, 'atom_res_number', atom_res_number)) then
      if (present_keep_whole_residues) then
	call print("WARNING: cluster_keep_whole_residues got keep_whole_residues requested explicitly, but no proper atom_res_number property available", ERROR)
      endif
      return
    endif

    n = 1
    do while (n <= cluster_info%N)
      i = cluster_info%int(1,n)
      ishift = cluster_info%int(2:4,n)
      if (atom_res_number(i) < 0) cycle
      call print('cluster_keep_whole_residues: i = '//i//' residue # = ' // atom_res_number(i) //'. Looping over '//atoms_n_neighbours(this,i,alt_connect=use_connect)//' neighbours...',ANAL)
      do m=1, atoms_n_neighbours(this, i, alt_connect=use_connect)
	j = atoms_neighbour(this, i, m, shift=jshift, alt_connect=use_connect)

	if (atom_res_number(i) /= atom_res_number(j)) then
	  call print("cluster_keep_whole_residues:   j = "//j//" ["//jshift//"] has different res number " // atom_res_number(j), ANAL)
	  cycle
	endif
	if(find(cluster_info,(/j,ishift+jshift,this%Z(j),0/), atom_mask) /= 0) then
	  call print("cluster_keep_whole_residues:   j = "//j//" ["//jshift//"] is in cluster",ANAL)
	  cycle
	end if
	if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,i, m, alt_connect=use_connect))) then
	  call print("cluster_keep_whole_residues:   j = "//j//" ["//jshift//"] not nearest neighbour",ANAL)
	  cycle
	end if

	call append(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), (/ this%pos(:,j), 1.0_dp /), (/"res_num   "/) )
	cluster_changed = .true.
	call print('cluster_keep_whole_residues:  Added atom ' //j//' ['//(ishift+jshift)//'] to cluster. Atoms = ' // cluster_info%N, NERD)

      end do ! m

      n = n + 1
    end do ! while (n <= cluster_info%N)

    call print('cluster_keep_whole_residues: Finished checking',NERD)
    call print("cluster_keep_whole_residues: cluster list:", NERD)
    call print(cluster_info, NERD)

  end function cluster_keep_whole_residues

  !% keep whole silica tetrahedra -- that is, for each silicon atom, keep all it's oxygen nearest neighbours
  function cluster_keep_whole_silica_tetrahedra(this, cluster_info, connectivity_just_from_connect, use_connect, atom_mask) result(cluster_changed)
    type(Atoms), intent(in) :: this !% atoms structure 
    type(Table), intent(inout) :: cluster_info !% table of cluster info, modified if necessary on output
    logical, intent(in) :: connectivity_just_from_connect !% if true, we're doing hysterestic connect and should rely on the connection object completely
    type(Connection), intent(in) :: use_connect !% connection object to use for connectivity info
    logical, intent(in) :: atom_mask(6) !% which fields in int part of table to compare when checking for identical atoms
    logical :: cluster_changed
    
    integer :: n, i, ishift(3), m, j, jshift(3)

    call print('doing cluster_keep_whole_silica_tetrahedra', NERD)

    cluster_changed = .false.
    n = 1
    do while (n <= cluster_info%N)
      i = cluster_info%int(1,n)
      ishift = cluster_info%int(2:4,n)
      if (this%z(i) /= 14) then
         ! Consider only silicon atoms, which form centres of tetrahedra
         n = n + 1
         cycle  
      end if

      call print('cluster_keep_whole_silica_tetrahedra: i = '//i//'. Looping over '//atoms_n_neighbours(this,i,alt_connect=use_connect)//' neighbours...',ANAL)
      do m=1, atoms_n_neighbours(this, i, alt_connect=use_connect)
	j = atoms_neighbour(this, i, m, shift=jshift, alt_connect=use_connect)

	if (this%z(j) /= 8) then
	  call print("cluster_keep_whole_silica_tetrahedra:   j = "//j//" ["//jshift//"] is not oxygen ", ANAL)
	  cycle
	endif
	if(find(cluster_info,(/j,ishift+jshift,this%Z(j),0/), atom_mask) /= 0) then
	  call print("cluster_keep_whole_silica_tetrahedra:   j = "//j//" ["//jshift//"] is in cluster",ANAL)
	  cycle
	end if
	if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,i, m, alt_connect=use_connect))) then
	  call print("cluster_keep_whole_silica_tetrahedra:   j = "//j//" ["//jshift//"] not nearest neighbour",ANAL)
	  cycle
	end if

	call append(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), (/ this%pos(:,j), 1.0_dp /), (/"tetra     "/) )
	cluster_changed = .true.
	call print('cluster_keep_whole_silica_tetrahedra:  Added atom ' //j//' ['//(ishift+jshift)//'] to cluster. Atoms = ' // cluster_info%N, NERD)

      end do ! m

      n = n + 1
    end do ! while (n <= cluster_info%N)

    call print('cluster_keep_whole_silica_tetrahedra: Finished checking',NERD)
    call print("cluster_keep_whole_silica_tetrahedra: cluster list:", NERD)
    call print(cluster_info, NERD)

  end function cluster_keep_whole_silica_tetrahedra


  !% adding each neighbour outside atom if doing so immediately reduces the number of cut bonds
  function cluster_reduce_n_cut_bonds(this, cluster_info, connectivity_just_from_connect, use_connect, atom_mask) result(cluster_changed)
    type(Atoms), intent(in) :: this !% atoms structure 
    type(Table), intent(inout) :: cluster_info !% table of cluster info, modified if necessary on output
    logical, intent(in) :: connectivity_just_from_connect !% if true, we're doing hysterestic connect and should rely on the connection object completely
    type(Connection), intent(in) :: use_connect !% connection object to use for connectivity info
    logical, intent(in) :: atom_mask(6) !% which fields in int part of table to compare when checking for identical atoms
    logical :: cluster_changed

    integer :: n, i, ishift(3), m, j, jshift(3), p, k, kshift(3)
    integer :: n_bonds_in, n_bonds_out

    call print('doing cluster_reduce_n_cut_bonds', NERD)

    cluster_changed = .false.

    ! loop over each atom in the cluster already
    n = 1
    do while (n <= cluster_info%N)
      i = cluster_info%int(1,n)
      ishift = cluster_info%int(2:4,n)
      call print('cluster_reduce_n_cut_bonds: i = '//i//'. Looping over '//atoms_n_neighbours(this,i,alt_connect=use_connect)//' neighbours...',ANAL)

      ! loop over every neighbour, looking for outside neighbours
      do m=1, atoms_n_neighbours(this, i, alt_connect=use_connect)
	j = atoms_neighbour(this, i, m, shift=jshift, alt_connect=use_connect)
	if (find(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), atom_mask ) /= 0) cycle
	if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,i, m, alt_connect=use_connect))) then
	  call print("cluster_reduce_n_cut_bonds:   j = "//j//" ["//jshift//"] not nearest neighbour",ANAL)
	  cycle
	end if
	! if we're here, j must be an outside neighbour of i
	call print('cluster_reduce_n_cut_bonds: j = '//j//'. Looping over '//atoms_n_neighbours(this,j,alt_connect=use_connect)//' neighbours...',ANAL)

	n_bonds_in = 0
	n_bonds_out = 0
	do p=1, atoms_n_neighbours(this, j, alt_connect=use_connect)
	  k = atoms_neighbour(this, j, p, shift=kshift, alt_connect=use_connect)
	  if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,j, p, alt_connect=use_connect))) then
	    call print("cluster_reduce_n_cut_bonds:   k = "//k//" ["//kshift//"] not nearest neighbour of j = " // j,ANAL)
	    cycle
	  end if
	  ! count how many bonds point in vs. out
	  if (find(cluster_info, (/ k, ishift+jshift+kshift, this%Z(k), 0 /), atom_mask ) /= 0) then
	    n_bonds_in = n_bonds_in + 1
	  else
	    n_bonds_out = n_bonds_out + 1
	  endif
	end do ! p

	if (n_bonds_out < n_bonds_in) then ! adding this one would reduce number of cut bonds
	  call append(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), (/ this%pos(:,j), 1.0_dp /), (/"n_cut_bond" /) )
	  cluster_changed = .true.
	  call print('cluster_reduce_n_cut_bonds:  Added atom ' //j//' ['//(ishift+jshift)//'] n_bonds_in ' // n_bonds_in // &
		     ' out ' // n_bonds_out // '  to cluster. Atoms = ' // cluster_info%N, NERD)
	endif
      end do ! m

      n = n + 1
    end do ! while (n <= cluster_info%N)

    call print('cluster_reduce_n_cut_bonds: Finished checking',NERD)
    call print("cluster_reduce_n_cut_bonds: cluster list:", NERD)
    call print(cluster_info, NERD)
  end function cluster_reduce_n_cut_bonds

  !% Go through the cluster atoms and find cut bonds. If the bond is to
  !% hydrogen, then include the hydrogen in the cluster list (since AMBER
  !% doesn't cap a bond to hydrogen with a link atom)
  function cluster_protect_X_H_bonds(this, cluster_info, connectivity_just_from_connect, use_connect, atom_mask) result(cluster_changed)
    type(Atoms), intent(in) :: this !% atoms structure 
    type(Table), intent(inout) :: cluster_info !% table of cluster info, modified if necessary on output
    logical, intent(in) :: connectivity_just_from_connect !% if true, we're doing hysterestic connect and should rely on the connection object completely
    type(Connection), intent(in) :: use_connect !% connection object to use for connectivity info
    logical, intent(in) :: atom_mask(6) !% which fields in int part of table to compare when checking for identical atoms
    logical :: cluster_changed

    integer :: n, i, ishift(3), m, j, jshift(3)

    call print('doing cluster_protect_X_H_bonds', NERD)
    cluster_changed = .false.

    ! loop over each atom in the cluster already
    n = 1
    do while (n <= cluster_info%N)
      i = cluster_info%int(1,n)
      ishift = cluster_info%int(2:4,n)
      call print('cluster_protect_X_H_bonds: i = '//i//'. Looping over '//atoms_n_neighbours(this,i,alt_connect=use_connect)//' neighbours...',ANAL)

      ! loop over every neighbour, looking for outside neighbours
      do m=1, atoms_n_neighbours(this, i, alt_connect=use_connect)
	j = atoms_neighbour(this, i, m, shift=jshift, alt_connect=use_connect)

	! if j is in, or not a nearest neighbour, go on to next
	if (find(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), atom_mask ) /= 0) cycle
	if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,i, m, alt_connect=use_connect))) then
	  call print("cluster_protect_X_H_bonds:   j = "//j//" ["//jshift//"] not nearest neighbour",ANAL)
	  cycle
	end if
	! if we're here, j must be an outside neighbour of i

	if (this%Z(i) == 1 .or. this%Z(j) == 1) then
	  call append(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), (/ this%pos(:,j), 1.0_dp /), (/"X_H_bond  " /) )
	  cluster_changed = .true.
	  call print('cluster_protect_X_H_bonds:  Added atom ' //j//' ['//(ishift+jshift)//'] to cluster. Atoms = ' // cluster_info%N, NERD)
	endif
      end do ! m

      n = n + 1
    end do ! while (n <= cluster_info%N)

    call print('cluster_protect_X_H_bonds: Finished checking',NERD)
    call print("cluster_protect_X_H_bonds: cluster list:", NERD)
    call print(cluster_info, NERD)
  end function cluster_protect_X_H_bonds

  !if by accident a single atom is included, that is part of a larger entity (not ion)
  !then delete it from the list as it will cause error in SCF (e.g. C=O oxygen)
  !call allocate(to_delete,4,0,0,0,1)
  !do n = 1, cluster%N
  !        i = cluster%int(1,n)
  !        is_alone = .true.
  !        do j = 1, atoms_n_neighbours(at,i)
  !                k = atoms_neighbour(at,i,j)
  !                if(find(cluster_info,(/k,shift/)) /= 0) then
  !                   if(is_nearest_neighbour(at,i,j)) GOTO 120
  !                else
  !                   if(is_nearest_neighbour(at,i,j)) is_alone = .false.
  !                end if
  !        end do
  !        if(.not. is_alone) call append(to_delete,(/i,shift/))
  !   120  cycle
  !end do

  !do i = 1, to_delete%N
  ! call delete(cluster_info,to_delete%int(:,i))
  !end do

!OUTDATED   function cluster_biochem_in_out_in(this, cluster_info, connectivity_just_from_connect, use_connect, atom_mask) result(cluster_changed)
!OUTDATED     type(Atoms), intent(in) :: this
!OUTDATED     type(Table), intent(inout) :: cluster_info
!OUTDATED     logical, intent(in) :: connectivity_just_from_connect
!OUTDATED     type(Connection), intent(in) :: use_connect
!OUTDATED     logical, intent(in) :: atom_mask(6)
!OUTDATED     logical :: cluster_changed
!OUTDATED 
!OUTDATED     integer :: n, i, ishift(3), m, j, jshift(3), p, k, kshift(3)
!OUTDATED 
!OUTDATED     call print('doing cluster_biochem_in_out_in', NERD)
!OUTDATED     cluster_changed = .false.
!OUTDATED 
!OUTDATED     ! loop over each atom in the cluster already
!OUTDATED     n = 1
!OUTDATED     do while (n <= cluster_info%N)
!OUTDATED       i = cluster_info%int(1,n)
!OUTDATED       ishift = cluster_info%int(2:4,n)
!OUTDATED       call print('cluster_reduce_n_cut_bonds: i = '//i//'. Looping over '//atoms_n_neighbours(this,i,alt_connect=use_connect)//' neighbours...',ANAL)
!OUTDATED 
!OUTDATED       ! loop over every neighbour, looking for outside neighbours
!OUTDATED       do m=1, atoms_n_neighbours(this, i, alt_connect=use_connect)
!OUTDATED 	j = atoms_neighbour(this, i, m, shift=jshift, alt_connect=use_connect)
!OUTDATED 
!OUTDATED 	! if j is in, or not a neareste neighbour, go on to next
!OUTDATED 	if (find(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), atom_mask ) /= 0) cycle
!OUTDATED 	if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,i, m, alt_connect=use_connect))) then
!OUTDATED 	  call print("cluster_reduce_n_cut_bonds:   j = "//j//" ["//jshift//"] not nearest neighbour",ANAL)
!OUTDATED 	  cycle
!OUTDATED 	end if
!OUTDATED 	! if we're here, j must be an outside neighbour of i
!OUTDATED 	call print('cluster_reduce_n_cut_bonds: j = '//j//'. Looping over '//atoms_n_neighbours(this,j,alt_connect=use_connect)//' neighbours...',ANAL)
!OUTDATED 
!OUTDATED 	do p=1, atoms_n_neighbours(this, j, alt_connect=use_connect)
!OUTDATED 	  k = atoms_neighbour(this, j, p, shift=kshift, alt_connect=use_connect)
!OUTDATED 	  if (k == i .and. all(jshift + kshift == 0)) cycle
!OUTDATED 	  if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,j, p, alt_connect=use_connect))) then
!OUTDATED 	    call print("cluster_reduce_n_cut_bonds:   k = "//k//" ["//kshift//"] not nearest neighbour of j = " // j,ANAL)
!OUTDATED 	    cycle
!OUTDATED 	  end if
!OUTDATED 	  ! if k is in, then j has 2 in neighbours, and so we add it
!OUTDATED 	  if (find(cluster_info, (/ k, ishift+jshift+kshift, this%Z(k), 0 /), atom_mask ) /= 0) then
!OUTDATED 	    call append(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), (/ this%pos(:,j), 1.0_dp /), (/"bio_IOI   " /) )
!OUTDATED 	    cluster_changed = .true.
!OUTDATED 	    call print('cluster_biochem_in_out_in:  Added atom ' //j//' ['//(ishift+jshift)//'] to cluster. Atoms = ' // cluster_info%N, NERD)
!OUTDATED 	    exit
!OUTDATED 	  end if 
!OUTDATED 	end do ! p
!OUTDATED       end do ! m
!OUTDATED 
!OUTDATED       n = n + 1
!OUTDATED     end do ! while (n <= cluster_info%N)
!OUTDATED 
!OUTDATED     call print('cluster_biochem_in_out_in: Finished checking',NERD)
!OUTDATED     call print("cluster_biochem_in_out_in: cluster list:", NERD)
!OUTDATED     call print(cluster_info, NERD)
!OUTDATED   end function cluster_biochem_in_out_in

  !% if an in non-H atom is in a residue and not at right coordination, add all of its neighbours
  function cluster_protect_double_bonds(this, cluster_info, connectivity_just_from_connect, use_connect, atom_mask, present_protect_double_bonds) result(cluster_changed)
    type(Atoms), intent(in) :: this !% atoms structure 
    type(Table), intent(inout) :: cluster_info !% table of cluster info, modified if necessary on output
    logical, intent(in) :: connectivity_just_from_connect !% if true, we're doing hysterestic connect and should rely on the connection object completely
    type(Connection), intent(in) :: use_connect !% connection object to use for connectivity info
    logical, intent(in) :: atom_mask(6) !% which fields in int part of table to compare when checking for identical atoms
    logical, intent(in) :: present_protect_double_bonds !% if true, protect_double_bonds was specified by user, not just a default value
    logical :: cluster_changed

    integer :: n, i, ishift(3), m, j, jshift(3)
    integer ::  n_nearest_neighbours
    integer, pointer :: atom_res_number(:)

    call print('doing cluster_protect_double_bonds', NERD)
    cluster_changed = .false.

    if (.not. assign_pointer(this, 'atom_res_number', atom_res_number)) then
      if (present_protect_double_bonds) then
	call print("WARNING: cluster_protect_double_bonds got protect_double_bonds requested explicitly, but no proper atom_res_number property available", ERROR)
      endif
      return
    endif

    n = 1
    do while (n <= cluster_info%N)
      i = cluster_info%int(1,n)
      ishift = cluster_info%int(2:4,n)

      if (this%Z(i) /= 0 .and. atom_res_number(i) >= 0) then

	! count nearest neighbours of i
	n_nearest_neighbours = 0
	do m=1, atoms_n_neighbours(this, i, alt_connect=use_connect)
	  j = atoms_neighbour(this, i, m, alt_connect=use_connect)

	  ! if j is not nearest neighbour, go on to next one
	  if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,i, m, alt_connect=use_connect))) then
	    call print("cluster_protect_double_bonds:   j = "//j//" not nearest neighbour",ANAL)
	    cycle
	  end if
	  ! if we're here, j must be an outside neighbour of i
	  n_nearest_neighbours = n_nearest_neighbours + 1
	end do ! m

	if (ElementValence(this%Z(i)) /= -1 .and. (ElementValence(this%Z(i)) /= n_nearest_neighbours)) then ! i has a valence, and it doesn't match nn#
	  do m=1, atoms_n_neighbours(this, i)
	    j = atoms_neighbour(this, i, m, shift=jshift, alt_connect=use_connect)

	    ! if j is in, or isn't nearest neighbour, go on to next
	    if (find(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), atom_mask ) /= 0) cycle
	    if(.not. (connectivity_just_from_connect .or. is_nearest_neighbour(this,i, m, alt_connect=use_connect))) then
	      call print("cluster_protect_double_bonds:   j = "//j//" ["//jshift//"] not nearest neighbour",ANAL)
	      cycle
	    end if

	    ! if we're here, j must be an outside neighbour of i
	    call append(cluster_info, (/ j, ishift+jshift, this%Z(j), 0 /), (/ this%pos(:,j), 1.0_dp /), (/"dbl_bond  " /) )
	    cluster_changed = .true.
	    call print('cluster_protect_double_bonds:  Added atom ' //j//' ['//(ishift+jshift)//'] to cluster. Atoms = ' // cluster_info%N, NERD)
	  end do ! m
	endif ! valence defined
      end if !  atom_res_number(i) >= 0

      n = n + 1
    end do ! while (n <= cluster_info%N)

    call print('cluster_protect_double_bonds: Finished checking',NERD)
    call print("cluster_protect_double_bonds: cluster list:", NERD)
    call print(cluster_info, NERD)
  end function cluster_protect_double_bonds

  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  !
  ! Create cluster from atoms and cluster information table
  !% The output cluster contains all properties of the initial atoms object, and
  !% some additional columns, which are:
  !% "index" : index of the cluster atoms into the initial atoms object.
  !% "termindex": nonzero for termination atoms, and is an index into the cluster atoms specifiying which atom
  !% is being terminated, it is used in collecting the forces.
  !% "rescale" : a real number which for nontermination atoms is 1.0, for termination atoms records
  !% the scaling applied to termination bond lengths
  !% "shift" : the shift of each atom
  !% 
  !
  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  function carve_cluster(at, args_str, cluster_info) result(cluster)
    type(Atoms), intent(in), target :: at
    character(len=*), intent(in) :: args_str
    type(Table), intent(in) :: cluster_info
    type(Atoms) :: cluster

    type(Dictionary) :: params
    logical :: do_rescale_r
    real(dp) :: r_scale, cluster_vacuum
    logical :: terminate, randomise_buffer, print_clusters, do_calc_connect, do_same_lattice
    logical :: hysteretic_connect
    integer :: i, j, k, m
    real(dp) :: maxlen(3), sep(3), lat_maxlen(3), lat_sep(3)
    integer :: lookup(3)
    logical :: do_periodic(3)
    integer, pointer :: hybrid_mark(:), cluster_index(:), cluster_hybrid_mark(:)
    type(Inoutput)                    :: clusterfile
    character(len=255)                :: clusterfilename
    type(Table) :: outer_layer
    logical :: in_outer_layer

#ifdef _MPI
    integer::mpi_size, mpi_rank, error
    include "mpif.h"
    integer :: mpi_force_size
    real(dp), allocatable, dimension(:)  :: mpi_force

    call get_mpi_size_rank(MPI_COMM_WORLD, mpi_size, mpi_rank)
#endif _MPI

    call print('carve_cluster got args_str "'//trim(args_str)//'"', VERBOSE)

    call initialise(params)
    call param_register(params, 'terminate', 'T', terminate)
    call param_register(params, 'do_rescale_r', 'F', do_rescale_r)
    call param_register(params, 'r_scale', '1.0', r_scale)
    call param_register(params, 'randomise_buffer', 'T', randomise_buffer)
    call param_register(params, 'print_clusters', 'F', print_clusters)
    call param_register(params, 'cluster_calc_connect', 'F', do_calc_connect)
    call param_register(params, 'cluster_same_lattice', 'F', do_same_lattice)
    call param_register(params, 'cluster_periodic_x', 'F', do_periodic(1))
    call param_register(params, 'cluster_periodic_y', 'F', do_periodic(2))
    call param_register(params, 'cluster_periodic_z', 'F', do_periodic(3))
    call param_register(params, 'cluster_vacuum', '10.0', cluster_vacuum)
    call param_register(params, 'hysteretic_connect', 'F', hysteretic_connect)
    if (.not. param_read_line(params, args_str, ignore_unknown=.true.,task='carve_cluster arg_str') ) &
      call system_abort("carve_cluster failed to parse args_str='"//trim(args_str)//"'")
    call finalise(params)

    ! first pick up an atoms structure with the right number of atoms and copy the properties
    !Now turn the cluster_temp table into an atoms structure
    call print('carve_cluster: Copying atomic data to output object',NERD)
    call print('List of atoms in cluster:', NERD)
    call print(int_part(cluster_info,1), NERD)

    call select(cluster, at, list=int_part(cluster_info,1))
    ! then reset the positions species and Z (latter two needed because termination atoms have Z=1)
    ! unfold the positions to real positions using the stored shifts, at is neede because
    ! next we might make the unit cell much smaller
    do i=1,cluster_info%N
       cluster%pos(:,i) = cluster_info%real(1:3, i)+(at%lattice .mult. cluster_info%int(2:4, i))
       cluster%Z(i) = cluster_info%int(5,i)
       cluster%species(i) = ElementName(cluster_info%int(5,i))
    end do
    ! add properties to cluster
    call add_property(cluster, 'index', int_part(cluster_info,1))
    call add_property(cluster, 'shift', 0, n_cols=3, lookup=lookup)
    cluster%data%int(lookup(2):lookup(3),1:cluster%N) = cluster_info%int(2:4,1:cluster_info%N)
    call add_property(cluster, 'termindex', int_part(cluster_info,6))
    call add_property(cluster, 'rescale', real_part(cluster_info,4))
    call add_property(cluster, 'cluster_ident', cluster_info%str(1,:))

    ! Find smallest bounding box for cluster
    ! Find boxes aligned with xyz (maxlen) and with a1 a2 a3 (lat_maxlen)
    maxlen = 0.0_dp
    lat_maxlen = 0.0_dp
    do i=1,cluster%N
       do j=1,cluster%N
	  sep = cluster%pos(:,i)-cluster%pos(:,j)
	  lat_sep = cluster%g .mult. sep
	  do k=1,3
	     if (abs(sep(k)) > maxlen(k)) maxlen(k) = abs(sep(k))
	     if (abs(lat_sep(k)) > lat_maxlen(k)) lat_maxlen(k) = abs(lat_sep(k))
	  end do
       end do
    end do

    ! renormalize lat_maxlen to real dist units
    do k=1,3
      lat_maxlen(k) = lat_maxlen(k) * norm(cluster%lattice(:,k))
    end do

    ! Round up maxlen to be divisible by 3 A, so that it does not fluctuate too much
    forall (k=1:3) maxlen(k) = 3.0_dp*ceiling(maxlen(k)/3.0_dp)
    forall (k=1:3) lat_maxlen(k) = 3.0_dp*ceiling(lat_maxlen(k)/3.0_dp)

    ! vacuum pad cluster (if didn't set do_same_lattice)
    ! if not periodic at all, just do vacuum padding
    ! if periodic along some dir, keep supercell vector directions, and set
    !    extent in each direction to lesser of cluster extent + vacuum or original extent
    if (do_same_lattice) then
      cluster%lattice = at%lattice
    else
      if (any(do_periodic)) then
	do k=1,3
	  if (do_periodic(k)) then
	    if (lat_maxlen(k)+cluster_vacuum >= norm(at%lattice(:,k))) then
	      cluster%lattice(:,k) = at%lattice(:,k)
	    else
	      cluster%lattice(:,k) = (lat_maxlen(k)+cluster_vacuum)*at%lattice(:,k)/norm(at%lattice(:,k))
	    endif
	  else
	    cluster%lattice(:,k) = (lat_maxlen(k)+cluster_vacuum)*at%lattice(:,k)/norm(at%lattice(:,k))
	  endif
	end do
      else
	cluster%lattice = 0.0_dp
	do k=1,3
	  cluster%lattice(k,k) = maxlen(k) + cluster_vacuum
	end do
      endif
    endif

    call set_lattice(cluster, cluster%lattice, scale_positions=.false.)

    ! Remap positions so any image atoms end up inside the cell
    call map_into_cell(cluster)

    call print ('carve_cluster: carved cluster with '//cluster%N//' atoms', VERBOSE)

    write (line, '(a,f10.3,f10.3,f10.3)') &
         'carve_cluster: Cluster dimensions are ', cluster%lattice(1,1), &
         cluster%lattice(2,2), cluster%lattice(3,3)
    call print(line, VERBOSE)

    ! reassign pointers
    if (.not. assign_pointer(at, 'hybrid_mark', hybrid_mark)) &
         call system_abort('cannot reassign hybrid_mark property')

    ! rescale cluster positions and lattice 
    if (do_rescale_r) then
       call print('carve_cluster: rescaling cluster positions and lattice by factor '//r_scale, VERBOSE)
       cluster%pos = r_scale * cluster%pos
       call set_lattice(cluster, r_scale * cluster%lattice, scale_positions=.false.)
    end if

    if (randomise_buffer .and. .not. any(hybrid_mark == HYBRID_BUFFER_OUTER_LAYER_MARK)) &
         do_calc_connect = .true.

    if (do_calc_connect) then
       call print('carve_cluster: doing calc_connect', VERBOSE)
       ! Does QM force model need connectivity information?
       if (at%use_uniform_cutoff) then
          call atoms_set_cutoff(cluster, at%cutoff)
       else
          call atoms_set_cutoff_factor(cluster, at%cutoff)
       end if
       call calc_connect(cluster)
    end if

    if (randomise_buffer) then
       ! If outer buffer layer is not marked do so now. This will be
       ! the case if we're using hysteretic_buffer selection option.
       ! In this case we consider any atoms connected to terminating
       ! hydrogens to be in the outer layer - obviously this breaks down 
       ! if we're not terminating so we abort if that's the case.
       if (.not. assign_pointer(cluster, 'index', cluster_index)) &
            call system_abort('carve_cluster: cluster is missing index property')

       if (.not. any(hybrid_mark == HYBRID_BUFFER_OUTER_LAYER_MARK)) then
          if (.not. terminate) call system_abort('cannot determine which buffer atoms to randomise if terminate=F and hysteretic_buffer=T')

          if (.not. assign_pointer(cluster, 'hybrid_mark', cluster_hybrid_mark)) &
               call system_abort('hybrid_mark property not found in cluster')

          do i=1,cluster%N
             if (hybrid_mark(cluster_info%int(1,i)) /= HYBRID_BUFFER_MARK) cycle
             in_outer_layer = .false.
             do m = 1, cluster_info%N
                if (cluster_info%int(6,m).eq. i) then
                   in_outer_layer = .true.
                   exit
                end if
             enddo
             if (in_outer_layer) then
                hybrid_mark(cluster_info%int(1,i)) = HYBRID_BUFFER_OUTER_LAYER_MARK
                cluster_hybrid_mark(i) = HYBRID_BUFFER_OUTER_LAYER_MARK
             end if
          end do
       end if

      if (any(hybrid_mark == HYBRID_BUFFER_OUTER_LAYER_MARK)) then
	 ! Slightly randomise the positions of the outermost layer
	 ! of the buffer region in order to avoid systematic errors
	 ! in QM forces.

	 call initialise(outer_layer, 1,0,0,0)
	 call append(outer_layer, find(hybrid_mark == HYBRID_BUFFER_OUTER_LAYER_MARK))

	 do i=1,outer_layer%N
	    ! Shift atom by randomly distributed vector of magnitude 0.05 A
	    j = find_in_array(cluster_index, outer_layer%int(1,i))
	    cluster%pos(:,j) = cluster%pos(:,j) + 0.05_dp*random_unit_vector()
	 end do

	 call finalise(outer_layer)
      end if

    end if

    if (value(mainlog%verbosity_stack) >= VERBOSE .or. print_clusters) then
#ifdef _MPI
       write (clusterfilename, '(a,i3.3,a)') 'clusters.',mpi_rank,'.xyz'
#else
       clusterfilename = 'clusters.xyz'
#endif _MPI
       call initialise(clusterfile, clusterfilename, append=.true., action=OUTPUT)
       call inoutput_mpi_all_inoutput(clusterfile, .true.)
       call print_xyz(cluster, clusterfile, all_properties=.true.)
       call finalise(clusterfile)
    end if

  end function carve_cluster

  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  !
  !% Create a cluster using the 'hybrid_mark' property and options in 'args_str'.
  !% All atoms that are marked with anything other than 'HYBRID_NO_MARK' will
  !% be included in the cluster; this includes active, transition and buffer
  !% atoms. 
  !% Returns an Table object (cluster_info) which contains info on atoms whose
  !% indices are given in atomlist, possibly with some extras for consistency,
  !% and optionally terminated with Hydrogens, that can be used by carve_cluster().
  !
  !XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

  function create_cluster_info_from_hybrid_mark(at, args_str, cut_bonds) result(cluster_info)
    type(Atoms), intent(inout), target :: at
    character(len=*), intent(in) :: args_str
    type(Table), optional, intent(out)   :: cut_bonds !% Return a list of the bonds cut when making
                                                      !% the cluster.  See create_cluster() documentation.
    type(Table) :: cluster_info

    type(Dictionary) :: params
    logical :: terminate, periodic_x, periodic_y, periodic_z, &
       even_electrons, do_periodic(3), cluster_nneighb_only, &
       cluster_allow_modification, hysteretic_connect, same_lattice, &
       fix_termination_clash, keep_whole_residues, keep_whole_silica_tetrahedra, reduce_n_cut_bonds, &
       protect_X_H_bonds, protect_double_bonds, has_termination_rescale
    logical :: keep_whole_residues_has_value, protect_double_bonds_has_value
    real(dp) :: r, r_min, centre(3), termination_rescale
    type(Table) :: cluster_list, currentlist, nextlist, activelist, bufferlist
    integer :: i, j, jj, first_active, old_n, n_cluster, shift(3)
    integer, pointer :: hybrid_mark(:), modified_hybrid_mark(:)
    integer :: prev_cluster_info_n
    integer, allocatable, dimension(:) :: uniqed, tmp_index

    type(Table)                              :: n_term, sorted_n_term
    integer                                  :: m, n, p

    real(dp)                                 :: H1(3)
    real(dp)                                 :: dhat_ij(3)
    real(dp)                                 :: r_ij, rescale
    integer                                  :: ishift(3), jshift(3), oldN, most_hydrogens
    logical                                  :: atom_mask(6)
    integer, allocatable, dimension(:) :: idx

    type(Connection), pointer :: use_connect
    logical :: connectivity_just_from_connect
    logical :: cluster_changed

    call print('create_cluster_info_from_hybrid_mark got args_str "'//trim(args_str)//'"', VERBOSE)

    call initialise(params)
    call param_register(params, 'terminate', 'T', terminate)
    call param_register(params, 'cluster_periodic_x', 'F', periodic_x)
    call param_register(params, 'cluster_periodic_y', 'F', periodic_y)
    call param_register(params, 'cluster_periodic_z', 'F', periodic_z)
    call param_register(params, 'even_electrons', 'F', even_electrons)
    call param_register(params, 'cluster_nneighb_only', 'T', cluster_nneighb_only)
    call param_register(params, 'cluster_allow_modification', 'T', cluster_allow_modification)
    call param_register(params, 'hysteretic_connect', 'F', hysteretic_connect)
    call param_register(params, 'cluster_same_lattice', 'F', same_lattice)
    call param_register(params, 'fix_termination_clash','T', fix_termination_clash)
    call param_register(params, 'keep_whole_residues','T', keep_whole_residues, keep_whole_residues_has_value)
    call param_register(params, 'keep_whole_silica_tetrahedra','F', keep_whole_silica_tetrahedra)
    call param_register(params, 'reduce_n_cut_bonds','T', reduce_n_cut_bonds)
    call param_register(params, 'protect_X_H_bonds','T', protect_X_H_bonds)
    call param_register(params, 'protect_double_bonds','T', protect_double_bonds, protect_double_bonds_has_value)
    call param_register(params, 'termination_rescale', '0.0', termination_rescale, has_termination_rescale)

    if (.not. param_read_line(params, args_str, ignore_unknown=.true.,task='create_cluster_info_from_hybrid_mark args_str') ) &
      call system_abort("create_cluster_info_from_hybrid_mark failed to parse args_str='"//trim(args_str)//"'")
    call finalise(params)

    do_periodic = (/periodic_x,periodic_y,periodic_z/)

    if (.not. has_property(at, 'hybrid_mark')) &
         call system_abort('create_cluster_info_from_hybrid_mark: atoms structure has no "hybrid_mark" property')

    if (cluster_allow_modification) then
      call add_property(at, 'modified_hybrid_mark', 0)
      if (.not. assign_pointer(at, 'modified_hybrid_mark', modified_hybrid_mark)) &
	   call system_abort('create_cluster_info_from_hybrid_mark passed atoms structure with no hybrid_mark property')
    endif

    ! only after adding modified_hybrid_mark_property
    if (.not. assign_pointer(at, 'hybrid_mark', hybrid_mark)) &
         call system_abort('create_cluster_info_from_hybrid_mark passed atoms structure with no hybrid_mark property')

    ! Calculate centre of cluster
    call allocate(cluster_list, 1,0,0,0)
    call append(cluster_list, find(hybrid_mark /= HYBRID_NO_MARK))
    centre = 0.0_dp
    do i=1,cluster_list%N
       centre = centre + at%pos(:,cluster_list%int(1,i))
    end do
    centre = centre / cluster_list%N
!!$    call print('centre = '//centre)

    ! Find atom closest to centre of cluster, using min image convention  
    r_min = huge(1.0_dp)
    do i=1,cluster_list%N
       r = distance_min_image(at, centre, cluster_list%int(1,i))
!!$       call print(cluster_list%int(1,i)//' '//r)
       if (r < r_min) then
          first_active = cluster_list%int(1,i)
          r_min = r
       end if
    end do

    n_cluster = cluster_list%N
    call wipe(cluster_list)
    call allocate(cluster_list, 4,0,0,0)

    ! Add first marked atom to cluster_list. shifts will be relative to this atom
    call print('Growing cluster starting from atom '//first_active//', n_cluster='//n_cluster, VERBOSE)
    call append(cluster_list, (/first_active,0,0,0/))
    call append(currentlist, cluster_list)

    ! Add other active atoms using bond hopping from the central cluster atom
    ! to find the other cluster atoms and hence to determine the correct 
    ! periodic shifts. 
    !
    ! This will fail if marked atoms do not form a single connected cluster
    old_n = cluster_list%N
    do 
       if (hysteretic_connect) then
	 call BFS_step(at, currentlist, nextlist, nneighb_only = .false., min_images_only = any(do_periodic) .or. same_lattice , alt_connect=at%hysteretic_connect)
       else
	 call BFS_step(at, currentlist, nextlist, nneighb_only = .false., min_images_only = any(do_periodic) .or. same_lattice)
       endif
       do j=1,nextlist%N
          jj = nextlist%int(1,j)
!          shift = nextlist%int(2:4,j)
          if (hybrid_mark(jj) /= HYBRID_NO_MARK) &
               call append(cluster_list, nextlist%int(:,j))
       end do
       call append(currentlist, nextlist)

       ! check exit condition
       allocate(tmp_index(cluster_list%N))
       tmp_index = int_part(cluster_list,1)
       call sort_array(tmp_index)
       call uniq(tmp_index, uniqed)
       call print('cluster hopping: got '//cluster_list%N//' atoms, of which '//size(uniqed)//' are unique.', VERBOSE)
       if (size(uniqed) == n_cluster) exit !got them all
       deallocate(uniqed, tmp_index)

       ! check that cluster is still growing
       if (cluster_list%N == old_n) then
          call write(at, 'create_cluster_abort.xyz')
          call print(cluster_list)
          call system_abort('create_cluster_info_from_hybrid_mark: cluster stopped growing before all marked atoms found - check for split QM region')
       end if
       old_n = cluster_list%N
    end do
    deallocate(tmp_index, uniqed)
    call finalise(nextlist)
    call finalise(currentlist)

    ! partition cluster_list so that active atoms come first
    do i=1,cluster_list%N
       if (hybrid_mark(cluster_list%int(1,i)) == HYBRID_ACTIVE_MARK) then
          call append(activelist, cluster_list%int(:,i))
       else
          call append(bufferlist, cluster_list%int(:,i))
       end if
    end do

    call wipe(cluster_list)
    call append(cluster_list, activelist)
    call append(cluster_list, bufferlist)
    call finalise(activelist)
    call finalise(bufferlist)
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    ! 
    ! Validate arguments
    !

    ! check for consistency in optional arguments

    if (.not. (count(do_periodic) == 0 .or. count(do_periodic) == 1 .or. count(do_periodic) == 3)) &
         call system_abort('count(periodic) must be zero, one or three.')

    if (same_lattice) do_periodic = .true.

    if (any(do_periodic) .and. multiple_images(cluster_list)) &
         call system_abort("create_cluster: can't make a periodic cluster since cluster_list contains repeats")

    ! check for empty list

    if(cluster_list%N == 0) then
       call print('create_cluster: empty cluster_list', NORMAL)
       return
    end if

    call print('create_cluster: Entering create_cluster', NERD)

    if(.not.(cluster_list%intsize == 1 .or. cluster_list%intsize == 4) .or. cluster_list%realsize /= 0) &
         call system_abort("create_cluster: cluster_list table must have intsize=1 or 4 and realsize=0.")


    ! Cluster_info is extensible storage for the cluster
    ! It stores atomic indices and shifts (4 ints)
    ! atomic number (1 int)
    ! termination index (1 int): for termination atoms, which atom is being terminated?
    ! and atomic positions (3 reals)
    ! It's length will be at least cluster_list%N

    call print('create_cluster: Creating temporary cluster table', NERD)
    call table_allocate(cluster_info,6,4,1,0,cluster_list%N)

    ! First, put all the marked atoms into cluster_info, storing their positions and shifts
    call print('create_cluster: Adding specified atoms to the cluster', NERD)
    do i = 1, cluster_list%N
       if(cluster_list%intsize == 4) then
          ! we have shifts
          ishift = cluster_list%int(2:4,i)
       else
          ! no incoming shifts
          ishift = (/0,0,0/)
       end if
       call append(cluster_info, (/cluster_list%int(1,i),ishift,at%Z(cluster_list%int(1,i)),0/),&
	    (/at%pos(:,cluster_list%int(1,i)),1.0_dp/), (/ hybrid_mark_name(hybrid_mark(cluster_list%int(1,i))) /) )
    end do

    call print("create_cluster: cluster list:", NERD)
    call print(cluster_info, NERD)

    ! Next, check for various gotchas

    ! at mask is used to match with atoms already in the cluster_info table
    ! if we are periodic in a direction, we don't care about the shifts in that direction when matching
    atom_mask = (/.true.,.not.do_periodic, .true., .true./)

    connectivity_just_from_connect = .not. cluster_nneighb_only
    if (hysteretic_connect) then
      use_connect => at%hysteretic_connect
      ! will also pass true for connectivity_just_from_connect to cluster_...() routines, so that
      ! is_nearest_neighbour() won't be used
      connectivity_just_from_connect = .true.
    else
      use_connect => at%connect
    endif

    if (cluster_allow_modification) then
      cluster_changed = .true.
      modified_hybrid_mark = hybrid_mark
      do while (cluster_changed) 
	cluster_changed = .false.
	call print("fixing up cluster according to heuristics keep_whole_residues " // keep_whole_residues // &
          ' keep_whole_silica_tetrahedra ' // keep_whole_silica_tetrahedra // &
	  ' reduce_n_cut_bonds ' // reduce_n_cut_bonds // &
	  ' protect_X_H_bonds ' // protect_X_H_bonds // &
	  ' protect_double_bonds ' // protect_double_bonds // &
	  ' terminate .or. fix_termination_clash ' // (terminate .or. fix_termination_clash), verbosity=NERD)
	if (keep_whole_residues) then
	  prev_cluster_info_n = cluster_info%N
	  if (cluster_keep_whole_residues(at, cluster_info, connectivity_just_from_connect, use_connect, atom_mask, keep_whole_residues_has_value)) then
	    cluster_changed = .true.
	    modified_hybrid_mark(cluster_info%int(1,prev_cluster_info_n+1:cluster_info%N)) = HYBRID_BUFFER_MARK
	  endif
	endif
        if (keep_whole_silica_tetrahedra) then
           prev_cluster_info_n = cluster_info%N
           if (cluster_keep_whole_silica_tetrahedra(at, cluster_info, connectivity_just_from_connect, use_connect, atom_mask)) then
              cluster_changed = .true.
              modified_hybrid_mark(cluster_info%int(1,prev_cluster_info_n+1:cluster_info%N)) = HYBRID_BUFFER_MARK
           endif
        end if
	if (reduce_n_cut_bonds) then
	  prev_cluster_info_n = cluster_info%N
	  if (cluster_reduce_n_cut_bonds(at, cluster_info, connectivity_just_from_connect, use_connect, atom_mask)) then
	    cluster_changed = .true.
	    modified_hybrid_mark(cluster_info%int(1,prev_cluster_info_n+1:cluster_info%N)) = HYBRID_BUFFER_MARK
	  endif
	endif
	if (protect_X_H_bonds) then
	  prev_cluster_info_n = cluster_info%N
	  if (cluster_protect_X_H_bonds(at, cluster_info, connectivity_just_from_connect, use_connect, atom_mask)) then
	    cluster_changed = .true.
	    modified_hybrid_mark(cluster_info%int(1,prev_cluster_info_n+1:cluster_info%N)) = HYBRID_BUFFER_MARK
	  endif
	endif
	if (protect_double_bonds) then
	  prev_cluster_info_n = cluster_info%N
	  if (cluster_protect_double_bonds(at, cluster_info, connectivity_just_from_connect, use_connect, atom_mask, protect_double_bonds_has_value)) then
	    cluster_changed = .true.
	    modified_hybrid_mark(cluster_info%int(1,prev_cluster_info_n+1:cluster_info%N)) = HYBRID_BUFFER_MARK
	  endif
	endif
	if (terminate .or. fix_termination_clash) then
	  prev_cluster_info_n = cluster_info%N
	  if (cluster_fix_termination_clash(at, cluster_info, connectivity_just_from_connect, use_connect, atom_mask)) then
	    cluster_changed = .true.
	    modified_hybrid_mark(cluster_info%int(1,prev_cluster_info_n+1:cluster_info%N)) = HYBRID_BUFFER_MARK
	  endif
	endif
!OUTDATED if (ss_in_out_in) cluster_changed = cluster_changed .or. cluster_ss_in_out_in(at, cluster_info, use_connect)
!OUTDATED if (biochem_in_out_in) cluster_changed = cluster_changed .or. cluster_biochem_in_out_in(at, cluster_info, use_connect)
      end do ! while cluster_changed

      call print('create_cluster: Finished fixing cluster for various heuristic pathologies',NERD)
      call print("create_cluster: cluster list:", NERD)
      call print(cluster_info, NERD)
    end if ! allow_cluster_mod

    !So now cluster_info contains all the atoms that are going to be in the cluster.
    !If terminate is set, we need to add terminating hydrogens along nearest neighbour bonds
    if (terminate) then
       call print('create_cluster: Terminating cluster with hydrogens',NERD)

       call table_allocate(n_term, 5, 0, 0, 0)
       oldN = cluster_info%N

       !Loop over atoms in the cluster
       do n = 1, oldN

          i = cluster_info%int(1,n)
          ishift = cluster_info%int(2:4,n)
          !Loop over atom i's neighbours
          do m = 1, atoms_n_neighbours(at,i, alt_connect=use_connect)

             j = atoms_neighbour(at,i,m, r_ij, diff=dhat_ij, shift=jshift, alt_connect=use_connect)
             dhat_ij = dhat_ij / r_ij

             if (find(cluster_info,(/j,ishift+jshift,at%Z(j),0/), atom_mask) == 0 .and. &
                  (hysteretic_connect .or. is_nearest_neighbour(at, i, m, alt_connect=use_connect))) then

                ! If j is an OUT atom, and it is close enough, put a terminating hydrogen
                ! at the scaled distance between i and j

                if (.not. has_termination_rescale) then
                   rescale = termination_bond_rescale(at%Z(i), at%Z(j))
                else
                   rescale = termination_rescale
                end if
                H1 = at%pos(:,i) + rescale * r_ij * dhat_ij

                ! Label term atom with indices into original atoms structure.
                ! j is atom it's generated from and n is index into cluster table of atom it's attached to
                call append(cluster_info,(/j,ishift,1,n/),(/H1, rescale/), (/ "term      " /)) 
		! label term atom in original atos object calso
!!$		hybrid_mark(j) = HYBRID_TERM_MARK

                ! Keep track of how many termination atoms each cluster atom has
                p = find_in_array(int_part(n_term,(/1,2,3,4/)),(/n,ishift/))
                if (p == 0) then
                   call append(n_term, (/n,ishift,1/))
                else
                   n_term%int(5,p) = n_term%int(5,p) + 1
                end if

                ! optionally keep a record of the bonds that we have cut
                if (present(cut_bonds)) &
                     call append(cut_bonds, (/i,j,ishift,jshift/))

                if(current_verbosity() .ge. NERD) then
                   write(line,'(a,i0,a,i0,a)')'create_cluster: Replacing bond ',i,'--',j,' with hydrogen'
                   call print(line, NERD)
                end if
             end if
          end do

       end do

       ! Do we need to remove a hydrogen atom to ensure equal n_up and n_down electrons?
       if (even_electrons .and. mod(sum(int_part(cluster_info,5)),2) == 1) then

          ! Find first atom with a maximal number of terminating hydrogens

          do i=1,n_term%n
             call append(sorted_n_term, (/n_term%int(5,i), n_term%int(1,i)/))
          end do
          allocate(idx(n_term%n))
          call sort(sorted_n_term, idx)

          n = sorted_n_term%int(2, sorted_n_term%n)
          most_hydrogens = idx(sorted_n_term%n)
          ishift = n_term%int(2:4,most_hydrogens)

          ! Loop over termination atoms
          do j=oldN,cluster_info%N
             ! Remove first H atom attached to atom i
             if (all(cluster_info%int(2:6,j) == (/ishift,1,n/))) then
                call delete(cluster_info, j)
                call print('create_cluster: removed one of atom '//cluster_info%int(1,n)//" "//maxval(int_part(n_term,5))// &
                     ' terminating hydrogens to zero total spin', VERBOSE)
                exit 
             end if
          end do

          deallocate(idx)
       end if

       call finalise(n_term)

       call print('create_cluster: Finished terminating cluster',NERD)
    end if

    call print ('Exiting create_cluster_info', NERD)

    call finalise(cluster_list)

  end function create_cluster_info_from_hybrid_mark


  !% Given an atoms structure with a 'hybrid_mark' property, this routine
  !% creates a 'weight_region1' property, whose values are between 0 and
  !% 1. Atoms marked with HYBRID_ACTIVE_MARK in 'hybrid_mark' get weight
  !% 1, the neighbourhopping is done up to transition_hops times, during which
  !% the weight linearly decreases to zero with hop count if 'weight_interpolation=hop_ramp'.
  !% If weight_interpolation=distance_ramp, weight is 1 up to
  !% distance_ramp_inner_radius, and goes linearly to 0 by distance_ramp_outer_radius,
  !% where distance is calculated from distance_ramp_center(1:3).
  !% distance_ramp makes the most sense if the HYBRID_ACTIVE_MARK is set 
  !% on a sphere with radius distance_ramp_inner_radius from 
  !% distance_ramp_center, no hysteresis, and with transition_hops < 0 so hops
  !% continue until no more atoms are added.
  !% Transition atoms are marked with HYBRID_TRANS_MARK. Further hopping 
  !% is done 'buffer_hops' times and atoms are marked with HYBRID_BUFFER_MARK 
  !% and given weight
  !% zero.

  subroutine create_hybrid_weights(at, args_str)
    type(Atoms), intent(inout) :: at
    character(len=*), intent(in) :: args_str

    type(Dictionary) :: params
    logical :: has_distance_ramp_inner_radius, has_distance_ramp_outer_radius, has_distance_ramp_center
    real(dp) :: distance_ramp_inner_radius, distance_ramp_outer_radius, distance_ramp_center(3)
    logical :: min_images_only, mark_buffer_outer_layer, nneighb_only, hysteretic_buffer, hysteretic_connect
    real(dp) :: hysteretic_buffer_inner_radius, hysteretic_buffer_outer_radius
    real(dp) :: hysteretic_connect_cluster_radius, hysteretic_connect_inner_factor, hysteretic_connect_outer_factor
    integer :: buffer_hops, transition_hops
    character(FIELD_LENGTH) :: weight_interpolation
    logical :: construct_buffer_use_only_heavy_atoms

    integer, pointer :: hybrid_mark(:)
    real(dp), pointer :: weight_region1(:)
    integer :: n_region1, n_trans, n_region2 !, n_term
    integer :: i, j, jj, first_active, shift(3)
    logical :: dummy
    type(Table) :: activelist, currentlist, nextlist, distances, oldbuffer, bufferlist
    real(dp) :: core_CoM(3), core_mass, mass
    integer :: list_1, hybrid_number 
    type(Table) :: total_embedlist 

    real(dp) :: origin(3), extent(3,3)
    real(dp) :: save_cutoff, save_cutoff_break
    logical :: save_use_uniform_cutoff
    integer :: old_n
    integer, allocatable :: uniq_Z(:)

    logical :: distance_ramp, hop_ramp
    logical :: add_this_atom, more_hops
    integer :: cur_trans_hop
    real(dp) :: bond_len, d

! only one set of defaults now, not one in args_str and one in arg list 
    call initialise(params)
    call param_register(params, 'transition_hops', '0', transition_hops)
    call param_register(params, 'buffer_hops', '3', buffer_hops)
    call param_register(params, 'weight_interpolation', 'hop_ramp', weight_interpolation)
    call param_register(params, 'distance_ramp_inner_radius', '0', distance_ramp_inner_radius, has_distance_ramp_inner_radius)
    call param_register(params, 'distance_ramp_outer_radius', '0', distance_ramp_outer_radius, has_distance_ramp_outer_radius)
    call param_register(params, 'distance_ramp_center', '0 0 0', distance_ramp_center, has_distance_ramp_center)
    call param_register(params, 'nneighb_only', 'T', nneighb_only)
    call param_register(params, 'min_images_only', 'F', min_images_only)
    call param_register(params, 'mark_buffer_outer_layer', 'T', mark_buffer_outer_layer)
    call param_register(params, 'hysteretic_buffer', 'F', hysteretic_buffer)
    call param_register(params, 'hysteretic_buffer_inner_radius', '5.0', hysteretic_buffer_inner_radius)
    call param_register(params, 'hysteretic_buffer_outer_radius', '7.0', hysteretic_buffer_outer_radius)
    call param_register(params, 'hysteretic_connect', 'F', hysteretic_connect)
    call param_register(params, 'hysteretic_connect_cluster_radius', '1.2', hysteretic_connect_cluster_radius)
    call param_register(params, 'hysteretic_connect_inner_factor', '1.2', hysteretic_connect_inner_factor)
    call param_register(params, 'hysteretic_connect_outer_factor', '1.5', hysteretic_connect_outer_factor)
    call param_register(params, 'construct_buffer_use_only_heavy_atoms', 'F', construct_buffer_use_only_heavy_atoms)
    if (.not. param_read_line(params, args_str, ignore_unknown=.true.,task='create_hybrid_weights_args_str args_str') ) &
      call system_abort("create_hybrid_weights_args_str failed to parse args_str='"//trim(args_str)//"'")
    call finalise(params)

    ! do_nneighb_only = optional_default(.false., nneighb_only)
    ! do_min_images_only = optional_default(.true., min_images_only) 
    ! do_mark_buffer_outer_layer = optional_default(.true., mark_buffer_outer_layer)
    ! do_weight_interpolation = optional_default('hop_ramp', weight_interpolation)
    ! do_hysteretic_buffer = optional_default(.false., hysteretic_buffer)
    ! do_hysteretic_buffer_inner_radius = optional_default(5.0_dp, hysteretic_buffer_inner_radius)
    ! do_hysteretic_buffer_outer_radius = optional_default(7.0_dp, hysteretic_buffer_outer_radius)
    ! do_construct_buffer_use_only_heavy_atoms = optional_default(.false.,construct_buffer_use_only_heavy_atoms)
    ! do_hysteretic_connect = optional_default(.false., hysteretic_connect)
    ! do_hysteretic_connect_cluster_radius = optional_default(30.0_dp, hysteretic_connect_cluster_radius)
    ! do_hysteretic_connect_inner_factor = optional_default(1.2_dp, hysteretic_connect_inner_factor)
    ! do_hysteretic_connect_outer_factor = optional_default(1.5_dp, hysteretic_connect_outer_factor)

    hop_ramp = .false.
    distance_ramp = .false.
    if (trim(weight_interpolation) == 'hop_ramp') then
       hop_ramp = .true.
    else if (trim(weight_interpolation) == 'distance_ramp') then
       distance_ramp = .true.
    else
       call system_abort('create_hybrid_weights_args: unknown weight_interpolation value: '//trim(weight_interpolation))
    end if

    call print('create_hybrid_weights: transition_hops='//transition_hops//' buffer_hops='//buffer_hops//' weight_interpolation='//weight_interpolation, VERBOSE)
    call print('  nneighb_only='//nneighb_only//' min_images_only='//min_images_only//' mark_buffer_outer_layer='//mark_buffer_outer_layer, VERBOSE)
    call print('  hysteretic_buffer='//hysteretic_buffer//' hysteretic_buffer_inner_radius='//hysteretic_buffer_inner_radius, VERBOSE)
    call print('  hysteretic_buffer_outer_radius='//hysteretic_buffer_outer_radius, VERBOSE)
    call print('  hysteretic_connect='//hysteretic_connect//' hysteretic_connect_cluster_radius='//hysteretic_connect_cluster_radius, VERBOSE)
    call print('  hysteretic_connect_inner_factor='//hysteretic_connect_inner_factor //' hysteretic_connect_outer_factor='//hysteretic_connect_outer_factor, VERBOSE)

    ! check to see if atoms has a 'weight_region1' property already, if so, check that it is compatible, if not present, add it
    if(assign_pointer(at, 'weight_region1', weight_region1)) then
       weight_region1 = 0.0_dp
    else
       call add_property(at, 'weight_region1', 0.0_dp)
       dummy = assign_pointer(at, 'weight_region1', weight_region1)
    end if

    ! check for a compatible hybrid_mark property. it must be present
    if(.not.assign_pointer(at, 'hybrid_mark', hybrid_mark)) &
       call system_abort('create_hybrid_weights: atoms structure has no "hybrid_mark" property')

    ! Add first marked atom to activelist. shifts will be relative to this atom
    first_active = find_in_array(hybrid_mark, HYBRID_ACTIVE_MARK)

    n_region1 = count(hybrid_mark == HYBRID_ACTIVE_MARK)
    list_1 = 0  
    call allocate(activelist, 4,0,0,0)
    call allocate(total_embedlist, 4,0,0,0) 

    do while (total_embedlist%N < n_region1)

       call wipe(currentlist)
       call wipe(activelist)
       call wipe(nextlist)    

       call append(activelist, (/first_active,0,0,0/))
       call append(currentlist, activelist)
       weight_region1(first_active) = 1.0_dp

       if (distance_ramp) then ! we might need ACTIVE_MARK center of mass
          if (has_property(at, 'mass')) then
             core_mass = at%mass(first_active)
          else
             core_mass = ElementMass(at%Z(first_active))
          end if
          core_CoM = core_mass*at%pos(:,first_active) ! we're taking this as reference atom so no shift needed here
       end if

       if (hysteretic_connect) then
         call system_timer('hysteretic_connect')
         call estimate_origin_extent(at, hybrid_mark == HYBRID_ACTIVE_MARK, hysteretic_connect_cluster_radius, origin, extent)
         save_use_uniform_cutoff = at%use_uniform_cutoff
         save_cutoff = at%cutoff
         save_cutoff_break = at%cutoff_break
         call set_cutoff_factor(at, hysteretic_connect_inner_factor, hysteretic_connect_outer_factor)
         call calc_connect_hysteretic(at, at%hysteretic_connect, origin, extent)
         if (save_use_uniform_cutoff) then
           call set_cutoff(at, save_cutoff, save_cutoff_break)
         else
           call set_cutoff_factor(at, save_cutoff, save_cutoff_break)
         endif
         call system_timer('hysteretic_connect')
       endif

       ! Add other active atoms using bond hopping from the first atom
       ! in the cluster to find the other active atoms and hence to determine the correct 
       ! periodic shifts
       
       hybrid_number = 1
       do while (hybrid_number .ne. 0)
          if (hysteretic_connect) then
            call BFS_step(at, currentlist, nextlist, nneighb_only = .false., min_images_only = min_images_only, alt_connect=at%hysteretic_connect)
          else
            call BFS_step(at, currentlist, nextlist, nneighb_only = .false., min_images_only = min_images_only, property=hybrid_mark)
          endif
          hybrid_number = 0 
          do j=1,nextlist%N
             jj = nextlist%int(1,j)
             shift = nextlist%int(2:4,j)
             if (hybrid_mark(jj) == HYBRID_ACTIVE_MARK) then
                hybrid_number = hybrid_number+1 
                call append(activelist, nextlist%int(:,j))
                weight_region1(jj) = 1.0_dp

                if (distance_ramp) then ! we might need ACTIVE_MARK center of mass
                   if (has_property(at, 'mass')) then
                      mass = at%mass(jj)
                   else
                      mass = ElementMass(at%Z(jj))
                   end if
                   core_CoM = core_CoM + mass*(at%pos(:,jj) + (at%lattice .mult. (shift)))
                   core_mass = core_mass + mass
                end if

             end if
          end do
          call append(currentlist, nextlist)
       enddo
       list_1 = list_1 + activelist%N
       call append(total_embedlist, activelist)    

       if (distance_ramp) then ! calculate actual distance ramp parameters 
	 ! distance_ramp center is as specified, otherwise ACTIVE_MARK center of mass
	 core_CoM = core_CoM/core_mass
	 if (.not. has_distance_ramp_center) distance_ramp_center = core_CoM

	 ! distance_ramp_inner_radius is as specified, otherwise distance of atom furthest from distance_ramp_center
	 if (.not. has_distance_ramp_inner_radius) then
	   call initialise(distances, 1, 1, 0, 0)
	   do i=1, activelist%N
	     jj = activelist%int(1,i)
	     call append(distances, jj, distance_min_image(at, distance_ramp_center, jj))
	   end do
	   distance_ramp_inner_radius = maxval(distances%real(1,1:distances%N))
	   call finalise(distances)
	 endif

	 if (.not. has_distance_ramp_outer_radius) then
	   distance_ramp_outer_radius = 0.0_dp
	   call uniq(at%Z, uniq_Z)
	   do i=1, size(uniq_Z)
	   do j=1, size(uniq_Z)
	     bond_len = bond_length(uniq_Z(i), uniq_Z(j))
	     if (bond_len > distance_ramp_outer_radius) distance_ramp_outer_radius = bond_len 
	   end do
	   end do
	   if (transition_hops <= 0) &
	     call print("WARNING: using transition_hops for distance_ramp outer radius, but transition_hops="//transition_hops,ERROR)
	   distance_ramp_outer_radius = distance_ramp_inner_radius + distance_ramp_outer_radius*transition_hops
	 endif
       endif ! distance_ramp

       call wipe(currentlist)
       call append(currentlist, activelist)

       ! create transition region
       call print('create_hybrid_mark: creating transition region',VERBOSE)
       n_trans = 0

       cur_trans_hop = 1
       if (distance_ramp) transition_hops = -1 ! distance ramp always does as many hops as needed to get every atom within outer radius
       more_hops = (transition_hops < 0 .or. transition_hops >= 2)
       do while (more_hops)
	 more_hops = .false.
         if (hysteretic_connect) then
           call BFS_step(at, currentlist, nextlist, nneighb_only = nneighb_only .and. (transition_hops > 0), min_images_only = min_images_only, alt_connect=at%hysteretic_connect)
         else
           call BFS_step(at, currentlist, nextlist, nneighb_only = nneighb_only .and. (transition_hops > 0), min_images_only = min_images_only)
         endif

         call wipe(currentlist)
         do j = 1,nextlist%N
            jj = nextlist%int(1,j)
            if(hybrid_mark(jj) == HYBRID_NO_MARK) then
	       add_this_atom = .true.
	       if (distance_ramp) then
                  d = distance_min_image(at, distance_ramp_center, jj)
		  if (d >= distance_ramp_outer_radius) add_this_atom = .false.
	       endif

	       if (add_this_atom) then
		 if (hop_ramp) weight_region1(jj) = 1.0_dp - real(cur_trans_hop,dp)/real(transition_hops,dp) ! linear transition
		 if (distance_ramp) then        ! Save distance, weight will be calculated later
		   if (d <= distance_ramp_inner_radius) then
		     weight_region1(jj) = 1.0_dp
		   else
		     weight_region1(jj) = 1.0_dp - (d-distance_ramp_inner_radius)/(distance_ramp_outer_radius-distance_ramp_inner_radius)
		   endif
		 endif
		 call append(currentlist, nextlist%int(:,j))
		 hybrid_mark(jj) = HYBRID_TRANS_MARK
		 n_trans = n_trans+1
		 more_hops = .true.
	       end if
            end if
         end do ! do j=1,nextlist%N

	 cur_trans_hop = cur_trans_hop + 1
	 if (transition_hops >= 0 .and. cur_trans_hop >= transition_hops) more_hops = .false.
       end do ! more_hops

       if (list_1 < n_region1) then
          call print('searching for a new quantum zone as found '//list_1//' atoms, need to get to '//n_region1, VERBOSE)
          do i =1, at%N
             if (hybrid_mark(i) == HYBRID_ACTIVE_MARK .and. .not. Is_in_Array(total_embedlist%int(1,1:total_embedlist%N), i)) then
                first_active = i
                exit
             endif
          enddo
       endif

    enddo ! while (total_embedlist%N < n_region1)

    ! create region2 (buffer region) 
    if (.not. hysteretic_buffer) then
       ! since no hysteresis, safe to reset non ACTIVE/TRANS atoms to HYBRID_NO_MARK
       where (hybrid_mark /= HYBRID_ACTIVE_MARK .and. hybrid_mark /= HYBRID_TRANS_MARK) hybrid_mark = HYBRID_NO_MARK

       n_region2 = 0
       do i = 0,buffer_hops-1
	  if (hysteretic_connect) then
	    call BFS_step(at, currentlist, nextlist, nneighb_only = nneighb_only, min_images_only = min_images_only, alt_connect=at%hysteretic_connect)
	  else
	    call BFS_step(at, currentlist, nextlist, nneighb_only = nneighb_only, min_images_only = min_images_only)
	  endif
          call wipe(currentlist)
          do j = 1,nextlist%N
             jj = nextlist%int(1,j)
             if(hybrid_mark(jj) == HYBRID_NO_MARK) then
                call append(currentlist, nextlist%int(:,j))
                weight_region1(jj) = 0.0_dp
                if (i==buffer_hops-1 .and. mark_buffer_outer_layer) then
                   hybrid_mark(jj) = HYBRID_BUFFER_OUTER_LAYER_MARK
                else
                   hybrid_mark(jj) = HYBRID_BUFFER_MARK
                end if
                n_region2 = n_region2+1
             end if
          end do
       end do
    else 
       ! hysteretic buffer here

       call initialise(oldbuffer, 1,0,0,0)
       !call wipe(oldbuffer)
       call append(oldbuffer, find(hybrid_mark /= HYBRID_NO_MARK))

       call wipe(currentlist)

       ! Add first marked atom to embedlist. shifts will be relative to this atom
       first_active = find_in_array(hybrid_mark, HYBRID_ACTIVE_MARK)
       call append(bufferlist, (/first_active,0,0,0/))
       call append(currentlist, bufferlist)

       n_region2 = count(hybrid_mark /= HYBRID_NO_MARK)

       ! Find old embed + buffer atoms using bond hopping from the first atom
       ! in the cluster to find the other buffer atoms and hence to determine the correct 
       ! periodic shifts
       !
       ! This will fail if marked atoms do not form connected clusters around the active atoms
       old_n = bufferlist%N
       do while (bufferlist%N < n_region2)
	  if (hysteretic_connect) then
	    call BFS_step(at, currentlist, nextlist, nneighb_only = .false., min_images_only = min_images_only, alt_connect=at%hysteretic_connect)
	  else
	    call BFS_step(at, currentlist, nextlist, nneighb_only = .false., min_images_only = min_images_only, property =hybrid_mark)
	  endif
          do j=1,nextlist%N
             jj = nextlist%int(1,j)
             shift = nextlist%int(2:4,j)
             if (hybrid_mark(jj) /= HYBRID_NO_MARK) call append(bufferlist, nextlist%int(:,j))
          end do
          call append(currentlist, nextlist)

          ! check that cluster is still growing
          if (bufferlist%N == old_n) &
               call system_abort('create_hybrid_weights_args: buffer cluster stopped growing before all marked atoms found - check for split buffer region')
          old_n = bufferlist%N
       end do

       ! Remove marks on all buffer atoms
       do i=1,oldbuffer%N
          if (hybrid_mark(oldbuffer%int(1,i)) == HYBRID_BUFFER_MARK .or. &
              hybrid_mark(oldbuffer%int(1,i)) == HYBRID_BUFFER_OUTER_LAYER_MARK) &
              hybrid_mark(oldbuffer%int(1,i)) = HYBRID_NO_MARK
       end do

       !construct the hysteretic buffer region:
       if (hysteretic_connect) then
	 call print("create_hybrid_weights calling construct_hysteretic_region", verbosity=NERD)
	 call construct_hysteretic_region(region=bufferlist,at=at,core=total_embedlist,loop_atoms_no_connectivity=.false., &
	   inner_radius=hysteretic_buffer_inner_radius,outer_radius=hysteretic_buffer_outer_radius,use_avgpos=.false., &
	   add_only_heavy_atoms=construct_buffer_use_only_heavy_atoms, nneighb_only=nneighb_only, min_images_only=min_images_only, &
	   alt_connect=at%hysteretic_connect) !NB, debugfile=mainlog)
       else
	 call print("create_hybrid_weights calling construct_hysteretic_region", verbosity=NERD)
	 call construct_hysteretic_region(region=bufferlist,at=at,core=total_embedlist,loop_atoms_no_connectivity=.false., &
	   inner_radius=hysteretic_buffer_inner_radius,outer_radius=hysteretic_buffer_outer_radius,use_avgpos=.false., &
	   add_only_heavy_atoms=construct_buffer_use_only_heavy_atoms, nneighb_only=nneighb_only, min_images_only=min_images_only) !NB, &
	   !NB debugfile=mainlog)
       endif


       call print('bufferlist=',VERBOSE)
       call print(bufferlist,VERBOSE)


       ! Mark new buffer region, leaving core QM region alone
       ! at the moment only ACTIVE and NO marks are present, because hybrid_mark was set to =hybrid
       do i=1,bufferlist%N
          if (hybrid_mark(bufferlist%int(1,i)) == HYBRID_NO_MARK) & 
               hybrid_mark(bufferlist%int(1,i)) = HYBRID_BUFFER_MARK

          ! Marking the outer layer with  HYBRID_BUFFER_OUTER_LAYER_MARK is
          ! dealt with in create_cluster_hybrid_mark.

       end do

       call finalise(bufferlist)
       call finalise(oldbuffer)
!       call finalise(embedlist)

    end if

    ! this is commented out for now, terminations are controlled in create_cluster only
    ! create terminations
    !n_term = 0
    !if(terminate) then
    !   call BFS_step(at, currentlist, nextlist, nneighb_only = .true., min_images_only = .true.)
    !   do j = 1,nextlist%N
    !      jj = nextlist%int(1,j)
    !      if(hybrid_mark(jj) == HYBRID_NO_MARK) then
    !         weight_region1(jj) = 0.0_dp
    !         hybrid_mark(jj) = HYBRID_TERM_MARK
    !         n_term = n_term+1
    !      end if
    !   end do
    !end do

    call print('create_hybrid_weights: '//list_1//' region 1, '//n_trans//' transition, '//n_region2//&
         ' region 2, '//count(hybrid_mark /= HYBRID_NO_MARK)//' in total', VERBOSE)
    !call print('create_hybrid_weights: '//n_region1//' region 1, '//n_trans//' transition, '//n_region2//&
    !     ' region 2, '//count(hybrid_mark /= HYBRID_NO_MARK)//' in total', VERBOSE)
    !    call sort(total_embedlist)

    call finalise(activelist)
    call finalise(currentlist)
    call finalise(nextlist)
    call finalise(distances)
    call finalise(total_embedlist)

  end subroutine create_hybrid_weights

  subroutine estimate_origin_extent(at, active, cluster_radius, origin, extent)
    type(Atoms), intent(in) :: at
    logical, intent(in) :: active(:)
    real(dp), intent(in) :: cluster_radius
    real(dp), intent(out) :: origin(3), extent(3,3)

    real(dp) :: center(3), low_corner(3), high_corner(3), dr(3)
    integer :: i, n_active, first_active
    logical :: found_first_active

    found_first_active = .false.
    n_active = 0
    do i=1, at%N
      if (.not. active(i)) cycle
      n_active = n_active + 1
      if (found_first_active) then
	center = center + diff_min_image(at, first_active, i)
      else
	center = 0.0_dp
	first_active = i
	found_first_active = .true.
      endif
    end do
    center = center / real(n_active, dp)
    center = center + at%pos(:,first_active)

    call print("estimate_origin_extent: got center" // center, verbosity=VERBOSE)

    low_corner = 1.0e38_dp
    high_corner = -1.0e38_dp
    do i=1, at%N
      if (.not. active(i)) cycle
      dr = diff_min_image(at, at%pos(:,i), center)
      low_corner = min(low_corner, dr)
      high_corner = max(high_corner, dr)
    end do
    call print("estimate_origin_extent: got relative low_corner" // low_corner, verbosity=NERD)
    call print("estimate_origin_extent: got relative high_corner" // high_corner, verbosity=NERD)
    low_corner = low_corner + center
    high_corner = high_corner + center

    call print("estimate_origin_extent: got low_corner" // low_corner, verbosity=NERD)
    call print("estimate_origin_extent: got high_corner" // high_corner, verbosity=NERD)

    origin = low_corner - cluster_radius
    extent = 0.0_dp
    extent(1,1) = (high_corner(1)-low_corner(1))+2.0_dp*cluster_radius
    extent(2,2) = (high_corner(2)-low_corner(2))+2.0_dp*cluster_radius
    extent(3,3) = (high_corner(3)-low_corner(3))+2.0_dp*cluster_radius

    call print("estimate_origin_extent: got origin" // origin, verbosity=VERBOSE)
    call print("estimate_origin_extent: got extent(1,:) " // extent(1,:), verbosity=VERBOSE)
    call print("estimate_origin_extent: got extent(2,:) " // extent(2,:), verbosity=VERBOSE)
    call print("estimate_origin_extent: got extent(3,:) " // extent(3,:), verbosity=VERBOSE)

  end subroutine estimate_origin_extent

  !% Given an Atoms structure with an active region marked in the 'hybrid_mark'
  !% property using 'HYBRID_ACTIVE_MARK', grow the embed region by 'fit_hops'
  !% bond hops to form a fit region. Returns the embedlist and fitlist with correct
  !% periodic shifts.
  subroutine create_embed_and_fit_lists(at, fit_hops, embedlist, fitlist, nneighb_only, min_images_only)

    type(Atoms), intent(inout) :: at
    integer :: fit_hops
    type(Table), intent(out) :: embedlist, fitlist
    logical, intent(in), optional :: nneighb_only, min_images_only

    integer, pointer :: hybrid_mark(:)
    integer :: n_region1, n_region2 !, n_term
    integer :: i, j, jj, first_active, shift(3)
    logical :: do_nneighb_only, do_min_images_only
    type(Table) :: currentlist, nextlist, tmpfitlist
    integer :: n, hybrid_number
    type(Table) :: totallist
    integer :: list_1

    integer :: old_n

    call print('Entered create_embed_and_fit_lists.',VERBOSE)
    do_nneighb_only = optional_default(.false., nneighb_only)
    do_min_images_only = optional_default(.true., min_images_only)

    ! check for a compatible hybrid_mark property. it must be present
    if(.not.assign_pointer(at, 'hybrid_mark', hybrid_mark)) &
       call system_abort('create_fit_region: atoms structure has no "hybrid_mark" property')

    call wipe(embedlist)
    call wipe(fitlist)

    ! Add first marked atom to embedlist. shifts will be relative to this atom
    first_active = find_in_array(hybrid_mark, HYBRID_ACTIVE_MARK)

    n_region1 = count(hybrid_mark == HYBRID_ACTIVE_MARK)
    list_1 = 0
    call allocate(totallist,4,0,0,0)
    call allocate(currentlist,4,0,0,0)

    ! Add other active atoms using bond hopping from the first atom
    ! in the cluster to find the other active atoms and hence to determine the correct 
    ! periodic shifts
    !
    old_n = embedlist%N
    do while (embedlist%N < n_region1)

      call wipe(currentlist)
      call wipe(nextlist)
      call wipe(totallist)

      call append(totallist, (/first_active,0,0,0/))
      call print('create_embed_and_fit_lists: expanding quantum region starting from '//first_active//' atom', VERBOSE)
      call append(currentlist, totallist)

      hybrid_number = 1 
      do while (hybrid_number .ne. 0) 
       call BFS_step(at, currentlist, nextlist, nneighb_only = .false., min_images_only = do_min_images_only, property =hybrid_mark)

       hybrid_number = 0 
       do j=1,nextlist%N
          jj = nextlist%int(1,j)
          shift = nextlist%int(2:4,j)
          if (hybrid_mark(jj) == HYBRID_ACTIVE_MARK) then
                hybrid_number = hybrid_number + 1 
                call append(totallist, nextlist%int(:,j))
          endif
       end do
       call append(currentlist, nextlist)
      enddo

      list_1 = list_1 + totallist%N
      call append(embedlist, totallist)
      call print('create_embed_and_fit_lists: number of atoms in the embedlist is '//embedlist%N, VERBOSE)

      if (list_1 .lt. n_region1) then
         n = 0
         do i =1, at%N
            if (hybrid_mark(i) == HYBRID_ACTIVE_MARK) then
               n = n+1
               if (.not. Is_in_Array(int_part(embedlist,1), i)) then
                  first_active = i
                  exit
               endif
            endif
         enddo
      endif

       ! check that cluster is still growing
       !if (embedlist%N == old_n) &
       !     call system_abort('create_embed_and_fit_lists: (embedlist) cluster stopped growing before all marked atoms found - check for split QM region')
       !old_n = embedlist%N
    end do


    call wipe(currentlist)
    call append(currentlist, embedlist)


    ! create region2 (fit region)
    call initialise(tmpfitlist,4,0,0,0,0)
    n_region2 = 0
    do i = 0,fit_hops-1
       call BFS_step(at, currentlist, nextlist, nneighb_only = do_nneighb_only, min_images_only = do_min_images_only)
       do j = 1,nextlist%N
          jj = nextlist%int(1,j)
          if(hybrid_mark(jj) /= HYBRID_ACTIVE_MARK) then
            call append(tmpfitlist, nextlist%int(:,j))
            n_region2 = n_region2+1
          end if
       end do
       call append(currentlist, nextlist)
    end do

    call print('create_embed_and_fit_lists: '//list_1//' embed, '//n_region2//' fit', VERBOSE)

    ! Sort order to we are stable to changes in neighbour ordering introduced
    ! by calc_connect. 
    call sort(embedlist)
    call sort(tmpfitlist)

    ! fitlist consists of sorted embedlist followed by sorted list of remainder of fit atoms
    call append(fitlist, embedlist)
    call append(fitlist, tmpfitlist)

    if (do_min_images_only) then
       if (multiple_images(embedlist)) then
          call discard_non_min_images(embedlist)
          call print('create_embed_and_fits_lists: multiple images discarded from embedlist', VERBOSE)
       endif

       if (multiple_images(fitlist)) then
          call discard_non_min_images(fitlist)
          call print('create_embed_and_fits_lists: multiple images discarded from fitlist', VERBOSE)
       endif
    endif

    call finalise(currentlist)
    call finalise(nextlist)
    call finalise(tmpfitlist)

  end subroutine create_embed_and_fit_lists

  !% Given an Atoms structure with an active region marked in the 'hybrid_mark'
  !% property using 'HYBRID_ACTIVE_MARK', and buffer region marked using 'HYBRID_BUFFER_MARK',
  !% 'HYBRID_TRANS_MARK' or 'HYBRID_BUFFER_OUTER_LAYER_MARK', simply returns the embedlist and fitlist
  !% according to 'hybrid_mark'. It does not take into account periodic shifts.
  subroutine create_embed_and_fit_lists_from_cluster_mark(at,embedlist,fitlist)

    type(Atoms), intent(in)  :: at
    type(Table), intent(out) :: embedlist, fitlist

    type(Table)              :: tmpfitlist

    call print('Entered create_embed_and_fit_lists_from_cluster_mark.',VERBOSE)
    call wipe(embedlist)
    call wipe(fitlist)
    call wipe(tmpfitlist)

    !build embed list from ACTIVE atoms
    !call list_matching_prop(at,embedlist,'hybrid_mark',HYBRID_ACTIVE_MARK)
    call list_matching_prop(at,embedlist,'cluster_mark',HYBRID_ACTIVE_MARK)

    !build fitlist from BUFFER and TRANS atoms
    !call list_matching_prop(at,tmpfitlist,'hybrid_mark',HYBRID_BUFFER_MARK)
    call list_matching_prop(at,tmpfitlist,'cluster_mark',HYBRID_BUFFER_MARK)
    call append(fitlist,tmpfitlist)
    !call list_matching_prop(at,tmpfitlist,'hybrid_mark',HYBRID_TRANS_MARK)
    call list_matching_prop(at,tmpfitlist,'cluster_mark',HYBRID_TRANS_MARK)
    call append(fitlist,tmpfitlist)
    !call list_matching_prop(at,tmpfitlist,'hybrid_mark',HYBRID_BUFFER_OUTER_LAYER_MARK)
    call list_matching_prop(at,tmpfitlist,'cluster_mark',HYBRID_BUFFER_OUTER_LAYER_MARK)
    call append(fitlist,tmpfitlist)

    call wipe(tmpfitlist)
    call append(tmpfitlist,fitlist)

    ! Sort in order to we are stable to changes in neighbour ordering introduced
    ! by calc_connect. 
    call sort(embedlist)
    call sort(tmpfitlist)

    ! fitlist consists of sorted embedlist followed by sorted list of remainder of fit atoms
    call wipe(fitlist)
    call append(fitlist, embedlist)
    call append(fitlist, tmpfitlist)

    call print('Embedlist:',ANAL)
    call print(int_part(embedlist,1),ANAL)
    call print('Fitlist:',ANAL)
    call print(int_part(fitlist,1),ANAL)

    call finalise(tmpfitlist)
    call print('Leaving create_embed_and_fit_lists_from_cluster_mark.',VERBOSE)

  end subroutine create_embed_and_fit_lists_from_cluster_mark

  !% Return the atoms in a hysteretic region:
  !% To become part of the 'list' region, atoms must drift within the
  !% 'inner' list. To leave the 'list' region, an atom
  !% must drift further than 'outer'.
  !% Optionally use time averaged positions
  !
  subroutine update_hysteretic_region(at,inner,outer,list,verbosity)

    type(Atoms),       intent(in)    :: at
    type(Table),       intent(inout) :: inner, outer
    type(Table),       intent(inout) :: list
    integer, optional, intent(in)    :: verbosity

    integer                          :: n, my_verbosity, atom(list%intsize)

    my_verbosity = optional_default(NORMAL,verbosity)

    if (my_verbosity == ANAL) then
       call print('In Select_Hysteretic_Quantum_Region:')
       call print('List currently contains '//list%N//' atoms')
    end if

    if ((list%intsize /= inner%intsize) .or. (list%intsize /= outer%intsize)) &
       call system_abort('update_hysteretic_region: inner, outer and list must have the same intsize')

    ! Speed up searching
    call sort(outer)
    call sort(list)

    !Check for atoms in 'list' and not in 'outer'
    do n = list%N, 1, -1
       atom = list%int(:,n) !the nth atom in the list
       if (search(outer,atom)==0) then
          call delete(list,n)
          if (my_verbosity > NORMAL) call print('Removed atom ('//atom//') from quantum list')
       end if
    end do

    call sort(list)

    !Check for new atoms in 'inner' cluster and add them to list
    do n = 1, inner%N
       atom = inner%int(:,n)
       if (search(list,atom)==0) then
          call append(list,atom)
          call sort(list)
          if (my_verbosity > NORMAL) call print('Added atom ('//atom//') to quantum list')
       end if
    end do

    if (my_verbosity >= NORMAL) call print(list%N//' atoms selected for quantum treatment')

  end subroutine update_hysteretic_region


  !
  !% Given an atoms object, and a point 'centre' or a list of atoms 'core',
  !% fill the 'region' table with all atoms hysteretically within 'inner_radius -- outer_radius'
  !% of the 'centre' or any 'core' atom, which can be reached by connectivity hopping.
  !% In the case of building the 'region' around 'centre', simply_loop_over_atoms loops instead of
  !% bond hopping.
  !% Optionally use the time averaged positions.
  !% Optionally use only heavy atom selection.
  !
  subroutine construct_hysteretic_region(region,at,core,centre,loop_atoms_no_connectivity,inner_radius,outer_radius,use_avgpos,add_only_heavy_atoms,nneighb_only,min_images_only,alt_connect,debugfile)

    type(Table),           intent(inout) :: region
    type(Atoms),           intent(in)    :: at
    type(Table), optional, intent(in)    :: core
    real(dp),    optional, intent(in)    :: centre(3)
    logical,     optional, intent(in)    :: loop_atoms_no_connectivity
    real(dp),              intent(in)    :: inner_radius
    real(dp),              intent(in)    :: outer_radius
    logical,     optional, intent(in)    :: use_avgpos
    logical,     optional, intent(in)    :: add_only_heavy_atoms
    logical,     optional, intent(in)  :: nneighb_only
    logical,     optional, intent(in)  :: min_images_only
    type(Connection), optional,intent(in) :: alt_connect
    type(inoutput), optional :: debugfile

    type(Table)                          :: inner_region
    type(Table)                          :: outer_region
    logical                              :: no_hysteresis

    if (present(debugfile)) call print("construct_hysteretic_region radii " // inner_radius // " " // outer_radius, file=debugfile)
    !check the input arguments only in construct_region.
    if (inner_radius.lt.0._dp) call system_abort('inner_radius must be > 0 and it is '//inner_radius)
    if (outer_radius.lt.inner_radius) call system_abort('outer radius ('//outer_radius//') must not be smaller than inner radius ('//inner_radius//').')

    no_hysteresis = .false.
    if ((outer_radius-inner_radius).lt.epsilon(0._dp)) no_hysteresis = .true.
    if (inner_radius .feq. 0.0_dp) call print('WARNING: hysteretic region with inner_radius .feq. 0.0', ERROR)
    if (no_hysteresis) call print('WARNING! construct_hysteretic_region: inner_buffer=outer_buffer. no hysteresis applied: outer_region = inner_region used.',ERROR)
    if (present(debugfile)) call print("   no_hysteresis " // no_hysteresis, file=debugfile)

    if (present(debugfile)) call print("   constructing inner region", file=debugfile)
    call construct_region(region=inner_region,at=at,core=core,centre=centre,loop_atoms_no_connectivity=loop_atoms_no_connectivity, &
      radius=inner_radius,use_avgpos=use_avgpos,add_only_heavy_atoms=add_only_heavy_atoms,nneighb_only=nneighb_only, &
      min_images_only=min_images_only,alt_connect=alt_connect,debugfile=debugfile)
    if (no_hysteresis) then
       call initialise(outer_region,4,0,0,0,0)
       call append(outer_region,inner_region)
    else
    if (present(debugfile)) call print("   constructing outer region", file=debugfile)
       call construct_region(region=outer_region,at=at,core=core,centre=centre,loop_atoms_no_connectivity=loop_atoms_no_connectivity, &
	radius=outer_radius, use_avgpos=use_avgpos,add_only_heavy_atoms=add_only_heavy_atoms,nneighb_only=nneighb_only, &
	min_images_only=min_images_only,alt_connect=alt_connect,debugfile=debugfile)
    endif

    if (present(debugfile)) call print("   orig inner_region list", file=debugfile)
    if (present(debugfile)) call print(inner_region, file=debugfile)
    if (present(debugfile)) call print("   orig outer_region list", file=debugfile)
    if (present(debugfile)) call print(outer_region, file=debugfile)
    if (present(debugfile)) call print("   old region list", file=debugfile)
    if (present(debugfile)) call print(region, file=debugfile)

     call print('construct_hysteretic_region: old region list:',VERBOSE)
     call print(region,VERBOSE)

    call update_hysteretic_region(at,inner_region,outer_region,region)

       call print('construct_hysteretic_region: inner_region list:',VERBOSE)
       call print(inner_region,VERBOSE)

       call print('construct_hysteretic_region: outer_region list:',VERBOSE)
       call print(outer_region,VERBOSE)

       if (present(debugfile)) call print("   new inner region list", file=debugfile)
       if (present(debugfile)) call print(inner_region, file=debugfile)
       if (present(debugfile)) call print("   new outer region list", file=debugfile)
       if (present(debugfile)) call print(outer_region, file=debugfile)

       call print('construct_hysteretic_region: new region list:',VERBOSE)
       call print(region,VERBOSE)

       if (present(debugfile)) call print("   new region list", file=debugfile)
       if (present(debugfile)) call print(region, file=debugfile)

    call finalise(inner_region)
    call finalise(outer_region)

  end subroutine construct_hysteretic_region

  !
  !% Given an atoms object, and a point or a list of atoms in the first integer of
  !% the 'core' table, fill the 'buffer' table with all atoms within 'radius'
  !% of any core atom (which can be reached by connectivity hopping) or the point
  !%(with bond hopping or simply looping once over the atoms).
  !% Optionally use the time averaged positions (only for the radius).
  !% Optionally use a heavy atom based selection (applying to both the core and the region atoms).
  !% Alternatively use the hysteretic connection, only nearest neighbours and/or min_images (only for the n_connectivity_hops).
  !
  subroutine construct_region(region,at,core,centre,loop_atoms_no_connectivity,radius,n_connectivity_hops,use_avgpos,add_only_heavy_atoms,nneighb_only,min_images_only,alt_connect,debugfile)

    type(Table),           intent(out) :: region
    type(Atoms),           intent(in)  :: at
    type(Table), optional, intent(in)  :: core
    real(dp),    optional, intent(in)  :: centre(3)
    logical,     optional, intent(in)  :: loop_atoms_no_connectivity
    real(dp),    optional, intent(in)  :: radius
    integer,     optional, intent(in)  :: n_connectivity_hops
    logical,     optional, intent(in)  :: use_avgpos
    logical,     optional, intent(in)  :: add_only_heavy_atoms
    logical,     optional, intent(in)  :: nneighb_only
    logical,     optional, intent(in)  :: min_images_only
    type(Connection), optional,intent(in) :: alt_connect
type(inoutput), optional :: debugfile

    logical                             :: do_use_avgpos
    logical                             :: do_loop_atoms_no_connectivity
    logical                             :: do_add_only_heavy_atoms
    logical                             :: do_nneighb_only
    logical                             :: do_min_images_only
    integer                             :: i, j, ii, ij
    type(Table)                         :: nextlist
    logical                             :: more_hops, add_i
    integer                             :: cur_hop
    real(dp), pointer                   :: use_pos(:,:)
    integer                             ::  shift_i(3)

    do_loop_atoms_no_connectivity = optional_default(.false.,loop_atoms_no_connectivity)

    do_add_only_heavy_atoms = optional_default(.false.,add_only_heavy_atoms)
    if (do_add_only_heavy_atoms .and. .not. has_property(at,'Z')) &
      call system_abort("construct_region: atoms has no Z property")

    do_use_avgpos = optional_default(.false.,  use_avgpos)

    if (count((/ present(centre), present(core) /)) /= 1) &
      call system_abort("Need either centre or core, but not both present(centre) " // present(centre) // " present(core) "// present(core))

    ! if we have radius, we'll have to decide what positions to use
    if (present(radius)) then
      if (do_use_avgpos) then
        if (.not. assign_pointer(at, "avgpos", use_pos)) &
	  call system_abort("do_use_avgpos is true, but no avgpos property")
      else
        if (.not. assign_pointer(at, "pos", use_pos)) &
	  call system_abort("do_use_avgpos is false, but no pos property")
      endif
    endif

    call initialise(region,4,0,0,0,0)

    if (do_loop_atoms_no_connectivity) then
      if (present(debugfile)) call print("   loop over atoms", file=debugfile)
      if (.not. present(radius)) &
	call system_abort("do_loop_atoms_no_connectivity=T requires radius")
      if (present(n_connectivity_hops) .or. present(min_images_only) .or. present(nneighb_only)) &
	call print("WARNING: do_loop_atoms_no_connectivity, but specified unused arg n_connectivity_hops " // present(n_connectivity_hops) // &
	  " min_images_only " // present(min_images_only) // " nneighb_only " // present(nneighb_only), ERROR)
       call print('WARNING: check if your cell is greater than the radius, looping only works in that case.',ERROR)
       if (any((/at%lattice(1,1),at%lattice(2,2),at%lattice(3,3)/) < radius)) call system_abort('too small cell')
       do i = 1,at%N
	 if (present(debugfile)) call print("check atom i " // i // " Z " // at%Z(i) // " pos " // at%pos(:,i), file=debugfile)
	 if (do_add_only_heavy_atoms .and. at%Z(i) == 1) cycle
	 if (present(centre)) then ! distance from centre is all that matters
	   if (present(debugfile)) call print(" distance_min_image use_pos i " // use_pos(:,i) // " centre " // centre // " dist " // distance_min_image(at, use_pos(:,i), centre(1:3), shift_i(1:3)), file=debugfile)
	   if (distance_min_image(at,use_pos(:,i),centre(1:3),shift_i(1:3)) < radius) then
	     if (present(debugfile)) call print("   adding i " // i  // " at " // use_pos(:,i) // " center " // centre // " dist " // distance_min_image(at, use_pos(:,i), centre(1:3), shift_i(1:3)), file=debugfile)
	     call append(region,(/i,shift_i(1:3)/))
	    endif
	  else ! no centre, check distance from each core list atom
	    do ij=1, core%N
	      j = core%int(1,ij)
	      if (present(debugfile)) call print(" core atom ij " // ij // " j " // j // " distance_min_image use_pos i " // use_pos(:,i) // " use_pos j " // use_pos(:,j) // " dist " // distance_min_image(at, use_pos(:,i), use_pos(:,j), shift_i(1:3)), file=debugfile)
	      if (distance_min_image(at,use_pos(:,i),use_pos(:,j),shift_i(1:3)) < radius) then
		if (present(debugfile)) call print("   adding i " // i // " at " // use_pos(:,i) // " near j " // j // " at " // use_pos(:,j) // " dist " // distance_min_image(at, use_pos(:,i), use_pos(:,j), shift_i(1:3)), file=debugfile)
	        call append(region,(/i,shift_i(1:3)/))
		exit
	      endif
	    end do ! j
	  endif ! no centre, use core
       enddo ! i

    else ! do_loop_atoms_no_connectivity

      if (.not. present(core)) &
	call system_abort("do_loop_atoms_no_connectivity is false, trying connectivity hops, but no core list is specified")

	if (present(debugfile)) call print("   connectivity hopping", file=debugfile)
	if (present(debugfile) .and. present(radius)) call print("    have radius " // radius, file=debugfile)
	if (present(debugfile)) call print("   present nneighb_only " // present(nneighb_only), file=debugfile)
	if (present(debugfile) .and. present(nneighb_only)) call print("   nneighb_only " // nneighb_only, file=debugfile)
      do_nneighb_only = optional_default(.true., nneighb_only)
      do_min_images_only = optional_default(.true., min_images_only)
      if (do_use_avgpos) &
	call system_abort("can't use avgpos with connectivity hops - make sure your connectivity is based on avgpos instead")

      ! start with core
      call append(region,core)

      more_hops = .true.
      cur_hop = 1
      do while (more_hops)
	if (present(debugfile)) call print('   construct_region do_nneighb_only = ' // do_nneighb_only // ' do_min_images_only = '//do_min_images_only, file=debugfile)
	if (present(debugfile)) call print('   doing hop ' // cur_hop, file=debugfile)
	if (present(debugfile)) call print('   cutoffs ' // at%cutoff // ' ' // at%use_uniform_cutoff, file=debugfile)
	more_hops = .false.
	call bfs_step(at, region, nextlist, nneighb_only=do_nneighb_only .and. .not. present(radius), min_images_only=do_min_images_only, max_r=radius, alt_connect=alt_connect, debugfile=debugfile)
	if (present(debugfile)) call print("   bfs_step returned nextlist%N " // nextlist%N, file=debugfile)
	if (present(debugfile)) call print(nextlist, file=debugfile)
	if (nextlist%N /= 0) then ! go over things in next hop
	  do ii=1, nextlist%N
	    i = nextlist%int(1,ii)
	    add_i = .true.
	    if (do_add_only_heavy_atoms) then
	      if (at%Z(i) == 1) cycle
	    endif
	    if (present(debugfile)) call print("  i " // i // " is heavy or all atoms requested", file=debugfile)
	    if (present(radius)) then ! check to make sure we're close enough to core list
	      if (present(debugfile)) call print("  radius is present, check distance from core list", file=debugfile)
	      add_i = .false.
	      do ij=1, core%N
		j = core%int(1,ij)
		if (present(debugfile)) call print("  distance of ii " // ii // " i " // i // " at  " // use_pos(:,i) // " from ij " // ij // " j " // j // " at " // use_pos(:,j) // " is " // distance_min_image(at,use_pos(:,i),use_pos(:,j),shift_i(1:3)), file=debugfile)
		if (distance_min_image(at,use_pos(:,i),use_pos(:,j),shift_i(1:3)) <= radius) then
		  if (present(debugfile)) call print("  decide to add i", file=debugfile)
		  add_i = .true.
		  exit ! from ij loop
		endif
	      end do ! ij
	    endif ! present(radius)
	    if (add_i) then
	      if (present(debugfile)) call print("  actually adding i")
	      more_hops = .true.
	      call append(region, nextlist%int(1:4,ii))
	    endif
	  end do
	else ! nextlist%N == 0
	  if (present(n_connectivity_hops)) then
	    if (n_connectivity_hops > 0) &
	      call print("WARNING: n_connectivity_hops = " // n_connectivity_hops // " cur_hop " // cur_hop // " but no atoms added")
	  endif
	endif ! nextlist%N

	cur_hop = cur_hop + 1
	if (present(n_connectivity_hops)) then
	  if (cur_hop > n_connectivity_hops) more_hops = .false.
	endif
      end do ! while more_hops

    endif ! do_loop_atoms_no_connectivity
    if (present(debugfile)) call print("leaving construct_region()", file=debugfile)

  end subroutine construct_region


  subroutine update_active(this, nneightol, avgpos, reset)
    type(Atoms) :: this
    real(dp), optional :: nneightol
    logical, optional :: avgpos, reset

    type(Atoms), save :: nn_atoms
    integer, pointer, dimension(:) :: nn, old_nn, active
    integer  :: i
    real(dp) :: use_nn_tol
    logical  :: use_avgpos, do_reset

    use_nn_tol = optional_default(this%nneightol, nneightol)
    use_avgpos = optional_default(.true., avgpos)
    do_reset   = optional_default(.false., reset)

    ! First time copy entire atoms structure into nn_atoms and
    ! add properties for nn, old_nn and active
    if (reset .or. .not. nn_atoms%initialised) then
       nn_atoms = this
       call add_property(this, 'nn', 0)
       call add_property(this, 'old_nn', 0)
       call add_property(this, 'active', 0)

       call set_cutoff_factor(nn_atoms, use_nn_tol)
    end if

    if (this%N /= nn_atoms%N) &
         call system_abort('update_actives: Number mismatch between this%N ('//this%N// &
         ') and nn_atoms%N ('//nn_atoms%N//')')

    if (.not. assign_pointer(this, 'nn', nn)) &
         call system_abort('update_actives: Atoms is missing "nn" property')

    if (.not. assign_pointer(this, 'old_nn', old_nn)) &
         call system_abort('update_actives: Atoms is missing "old_nn" property')

    if (.not. assign_pointer(this, 'active', active)) &
         call system_abort('update_actives: Atoms is missing "active" property')

    call print('update_actives: recalculating nearest neighbour table', VERBOSE)
    if (use_avgpos .and. associated(this%avgpos)) then
       call print('update_actives: using time averaged atomic positions', VERBOSE)
       nn_atoms%pos = this%avgpos
    else
       call print('update_actives: using instantaneous atomic positions', VERBOSE)
       nn_atoms%pos = this%pos
    end if
    call calc_connect(nn_atoms)

    nn = 0
    do i = 1,nn_atoms%N
       nn(i) = atoms_n_neighbours(nn_atoms, i)
    end do

    if (all(old_nn == 0)) old_nn = nn ! Special case for first time

    ! Decrement the active counts
    where (active /= 0) active = active -1

    ! Find newly active atoms
    where (nn /= old_nn) active = 1

    if (count(active == 1) /= 0) then
       call print('update_actives: '//count(active == 1)//' atoms have become active.')
    end if

    old_nn = nn

  end subroutine update_active


  !
  !% Given an atoms structure and a list of quantum atoms, find X-H
  !% bonds which have been cut and include the other atom of 
  !% the pair in the quantum list.
  !
  subroutine add_cut_hydrogens(this,qmlist,verbosity,alt_connect)

    type(Atoms),       intent(in),          target :: this
    type(Table),       intent(inout)               :: qmlist
    integer, optional, intent(in)                  :: verbosity
    type(Connection), intent(in), optional, target :: alt_connect

    type(Table)                :: neighbours, bonds, centre
    logical                    :: more_atoms
    integer                    :: i, j, n, nn, added
    type(Connection), pointer :: use_connect

    ! Check for atomic connectivity
    if (present(alt_connect)) then
      use_connect => alt_connect
    else
      use_connect => this%connect
    endif

    more_atoms = .true.
    added = 0
    call allocate(centre,4,0,0,0,1)

    !Repeat while the search trigger is true
    do while(more_atoms)

       more_atoms = .false.

       !Find nearest neighbours of the cluster
       call bfs_step(this,qmlist,neighbours,nneighb_only=.true.,min_images_only=.true.,alt_connect=use_connect)

       !Loop over neighbours
       do n = 1, neighbours%N

          i = neighbours%int(1,n)

          call wipe(centre)
          call append(centre,(/i,0,0,0/))

          ! Find atoms bonded to this neighbour
          call bfs_step(this,centre,bonds,nneighb_only=.true.,min_images_only=.true.,alt_connect=use_connect)

          !Loop over these bonds
          do nn = 1, bonds%N

             j = bonds%int(1,nn)

             !Try to find j in the qmlist
             if (find_in_array(int_part(qmlist,1),j)/=0) then
                !We have a cut bond. If i or j are hydrogen then add i to the 
                !quantum list and trigger another search after this one
                if (this%Z(i)==1 .or. this%Z(j)==1) then
                   call append(qmlist,(/i,0,0,0/))
                   if (present(verbosity)) then
                      if (verbosity >= NORMAL) call print('Add_Cut_Hydrogens: Added atom '//i//', neighbour of atom '//j)
                   end if
                   more_atoms = .true.
                   added = added + 1
                   exit !Don't add the same atom more than once
                end if
             end if

          end do

       end do

    end do

    !Report findings
    if (present(verbosity)) then
       if (verbosity >= NORMAL) then
          write(line,'(a,i0,a)')'Add_Cut_Hydrogens: Added ',added,' atoms to quantum region'
          call print(line)
       end if
    end if

    call finalise(centre)
    call finalise(bonds)
    call finalise(neighbours)

  end subroutine add_cut_hydrogens

!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!X
!X GROUP CONVERSION
!X
!XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

  !
  !% Convert a constrained atom's group to a normal group prior to quantum treatment
  !% The constraints are not deleted, just ignored. The number of degrees of freedom
  !% of the system is also updated.
  !
  subroutine constrained_to_quantum(this,i)

    type(DynamicalSystem), intent(inout) :: this
    integer,               intent(in)    :: i
    integer                              :: g!, n, j, a1, a2

    g = this%group_lookup(i)

    if (this%group(g)%type == TYPE_CONSTRAINED) then
       write(line,'(2(a,i0),a)')' INFO: Converting group ',g,' from Constrained to Quantum'
       call print(line)

       !Change the group type
       call set_type(this%group(g),TYPE_ATOM)

       !Update the number of degrees of freedom (add 1 per removed constraint)
       this%Ndof = this%Ndof + Group_N_Objects(this%group(g))

       !Thermalize the released constraints
!       do n = 1, group_n_objects(this%group(g))
!
!          j = group_nth_object(this%group(g),n)
!
!          !If not a two body constraint then go to the next one.
!          if (this%constraint(j)%N /= 2) cycle
!
!          !Get the indices of the atoms in this constraint
!          a1 = this%constraint(j)%atom(1)
!          a2 = this%constraint(j)%atom(2)
!
!          call thermalize_bond(this,a1,a2,this%sim_temp)
!
!       end do

!       call thermalize_group(this,g,this%sim_temp)

    end if

  end subroutine constrained_to_quantum

  !
  !% When a constraint is released as a molecule drifts into the quantum region the
  !% new, unconstrained degree of freedom has zero temperature. This routine adds
  !% velocities in the directions between atoms which make up two body constraints
  !% at a specified temperature
  !
  subroutine thermalize_bond(this,i,j,T)

    type(DynamicalSystem), intent(inout) :: this         !% The dynamical system
    integer,               intent(in)    :: i,j          !% The two atoms
    real(dp),              intent(in)    :: T            !% Temperature
    real(dp)                             :: meff         !  effective mass
    real(dp), dimension(3)               :: u_hat        !  unit vector between the atoms
    real(dp)                             :: w, wi, wj, & ! magnitude of velocity component in bond direction
                                            mi, mj       ! masses of the atoms
    real(dp)                             :: E0,E1        ! kinetic energy in bond before and after
    real(dp), save                       :: Etot = 0.0_dp ! cumulative energy added to the system
    real(dp), save                       :: Eres = 0.0_dp ! cumulative energy already in bonds (QtoC error)
    real(dp)                             :: r, v         ! relative distance and velocity

    call print('Thermalize_Bond: Thermalizing bond '//i//'--'//j)

    ! Find unit vector along bond and current relative velocity
    call distance_relative_velocity(this%atoms,i,j,r,v)

    ! Find unit vector between atoms
    u_hat = diff_min_image(this%atoms,i,j)
    u_hat = u_hat / norm(u_hat)

    ! Calculate effective mass
    mi = ElementMass(this%atoms%Z(i))
    mj = ElementMass(this%atoms%Z(j))
    meff = mi * mj / (mi + mj)

    ! Calculate energy currently stored in this bond (should be zero)
    E0 = 0.5_dp * meff * v * v
    Eres = Eres + E0

    call print('Thermalize_Bond: Bond currently contains '//round(E0,8)//' eV')
    call print('Thermalize_Bond: Residual energy encountered so far: '//round(Eres,8)//' eV')

    ! Draw a velocity for this bond
    w = gaussian_velocity_component(meff,T)
    w = w - v ! Adjust for any velocity which the bond already had

    ! Distribute this between the two atoms, conserving momentum
    wi = (meff / mi) * w
    wj = -(meff / mj) * w

    this%atoms%velo(:,i) = this%atoms%velo(:,i) + wi * u_hat
    this%atoms%velo(:,j) = this%atoms%velo(:,j) + wj * u_hat

    call distance_relative_velocity(this%atoms,i,j,r,v)
    E1 = 0.5_dp * meff * v * v

    Etot = Etot + E1 - E0

    call print('Thermalize_Bond: Added '//round(E1-E0,8)//' eV to bond')
    call print('Thermalize_Bond: Added '//round(Etot,8)//' eV to the system so far')

  end subroutine thermalize_bond

  !
  !% Convert a quantum atom's group to a constrained group. The group is searched for
  !% two body constraints, which are assumed to be bond length or time dependent bond length
  !% constraints. The required final length is extracted, and a new time dependent bond length
  !% constraint is imposed, taking the current length and relative velocity along the bond
  !% to the required values, in the time given by smoothing_time.
  !%
  !% Any other constraints are left untouched.
  !
  subroutine quantum_to_constrained(this,i,smoothing_time)

    type(DynamicalSystem), intent(inout) :: this
    integer,               intent(in)    :: i
    real(dp),              intent(in)    :: smoothing_time
    integer, save                        :: CUBIC_FUNC
    logical, save                        :: first_call = .true.
    integer                              :: g, j, n, a1, a2, datalength
    real(dp)                             :: x0,y0,y0p,x1,y1,y1p, coeffs(4), t, dE, m1, m2, meff
    real(dp), save                       :: Etot = 0.0_dp

    !Register the constraint function if this is the first call
    if (first_call) then
       CUBIC_FUNC = Register_Constraint(CUBIC_BOND)
       first_call = .false.
    end if

    g = this%group_lookup(i)

    if (this%group(g)%type == TYPE_ATOM) then
       write(line,'(2(a,i0),a)')' INFO: Converting group ',g,' from Quantum to Constrained'
       call print(line)

       !Change the group type
       call set_type(this%group(g),TYPE_CONSTRAINED)

       !Update the number of degrees of freedom (subtract 1 per added constraint)
       this%Ndof = this%Ndof - Group_N_Objects(this%group(g))

       !Loop over constraints
       do n = 1, Group_N_Objects(this%group(g))

          j = Group_Nth_Object(this%group(g),n)

          !If not a two body constraint then go to the next one.
          if (this%constraint(j)%N /= 2) cycle

          !Get the indices of the atoms in this constraint
          a1 = this%constraint(j)%atom(1)
          a2 = this%constraint(j)%atom(2)

          !Detect the type of constraint (simple bondlength or time dependent bond length) 
          !from the size of the data array (1 or 6)
          datalength = size(this%constraint(j)%data)
          select case(datalength)
          case(1) 
             !Simple bond length: the required final length is the only entry
             y1 = this%constraint(j)%data(1)
          case(6)
             !Time dependent bond length: the final length is the polynomial evaluated at the end point
             coeffs = this%constraint(j)%data(1:4)
             t = this%constraint(j)%data(6)
             y1 = ((coeffs(1)*t + coeffs(2))*t + coeffs(3))*t + coeffs(4)
          case default
             !This isn't a known bond length constraint. Set y1 to a negative value.
             y1 = -1.0_dp
          end select

          !If an existing bond length constraint has been found then set up a time dependent constraint
          if (y1 > 0.0_dp) then

             call print('Quantum_to_Constrained: Reconstraining bond '//a1//'--'//a2)

             x0 = this%t
             call distance_relative_velocity(this%atoms,a1,a2,y0,y0p)
             x1 = this%t + smoothing_time
             y1p = 0.0_dp

             !Find the coefficients of the cubic which fits these boundary conditions
             call fit_cubic(x0,y0,y0p,x1,y1,y1p,coeffs)

             !Change the constraint
             call ds_amend_constraint(this,j,CUBIC_FUNC,(/coeffs,x0,x1/))

             !Work out the amount of energy which will be removed
             m1 = ElementMass(this%atoms%Z(a1))
             m2 = ElementMass(this%atoms%Z(a2))
             meff = m1 * m2 / (m1 + m2)

             dE = 0.5_dp * meff * y0p * y0p
             Etot = Etot + dE

             call print('Quantum_to_Constrained: Gradually removing '//round(dE,8)//' eV from bond')
             call print('Quantum_to_Constrained: Will have removed approximately '//round(Etot,8)//' eV in total')

          end if

       end do

    end if

  end subroutine quantum_to_constrained


  subroutine thermalize_group(this,g,T)

    type(DynamicalSystem), intent(inout) :: this
    integer,               intent(in)    :: g
    real(dp),              intent(in)    :: T

    integer  :: i, j, k
    real(dp) :: mi, mj, mk, mij, mik, mjk, vij, vik, vjk, rij, rik, rjk, gij, gik, gjk
    real(dp) :: ri(3), rj(3), rk(3), Rcom(3)
    real(dp) :: A(9,9), b(9), A_inv(9,9), x(9)

    real(dp) :: dEij, dEik, dEjk
    real(dp), save :: Etot = 0.0_dp

    ! Get atoms
    i = this%group(g)%atom(1)
    j = this%group(g)%atom(2)
    k = this%group(g)%atom(3)

    ! Get shifted positions
    ri = 0.0_dp
    rj = diff_min_image(this%atoms,i,j)
    rk = diff_min_image(this%atoms,i,k)  

    ! Get separations and current bond velocities
    call distance_relative_velocity(this%atoms,i,j,rij,vij)
    call distance_relative_velocity(this%atoms,i,k,rik,vik)
    call distance_relative_velocity(this%atoms,j,k,rjk,vjk)

    ! Calculate masses
    mi = ElementMass(this%atoms%Z(i))
    mj = ElementMass(this%atoms%Z(j))
    mk = ElementMass(this%atoms%Z(k))   
    mij = mi * mj / (mi + mj)
    mik = mi * mk / (mi + mk)
    mjk = mj * mk / (mj + mk)

    ! Calculate centre of mass
    Rcom = (mi*ri + mj*rj + mk*rk) / (mi+mj+mk)

    ! Select a gaussian distributed velocity adjustment for each bond
    gij = gaussian_velocity_component(mij,T)
    gik = gaussian_velocity_component(mik,T)
    gjk = gaussian_velocity_component(mjk,T)
    vij = gij - vij
    vik = gik - vik
    vjk = gjk - vjk

    ! Build matrix...
    A = 0.0_dp
    b = 0.0_dp

    ! Momentum conservation
    A(1,1) = mi; A(2,2) = mi; A(3,3) = mi
    A(1,4) = mj; A(2,5) = mj; A(3,6) = mj
    A(1,7) = mk; A(2,8) = mk; A(3,9) = mk

    ! Angular momentum conservation
    A(4,2) = -mi * (ri(3) - Rcom(3)); A(4,3) = mi * (ri(2) - Rcom(2))
    A(4,5) = -mj * (rj(3) - Rcom(3)); A(4,6) = mj * (rj(2) - Rcom(2))
    A(4,8) = -mk * (rk(3) - Rcom(3)); A(4,9) = mk * (rk(2) - Rcom(2))

    A(5,1) = mi * (ri(3) - Rcom(3)); A(5,3) = -mi * (ri(1) - Rcom(1))
    A(5,4) = mj * (rj(3) - Rcom(3)); A(5,6) = -mj * (rj(1) - Rcom(1))
    A(5,7) = mk * (rk(3) - Rcom(3)); A(5,9) = -mk * (rk(1) - Rcom(1))

    A(6,1) = -mi * (ri(2) - Rcom(2)); A(6,2) = mi * (ri(1) - Rcom(1))
    A(6,4) = -mj * (rj(2) - Rcom(2)); A(6,5) = mj * (rj(1) - Rcom(1))
    A(6,7) = -mk * (rk(2) - Rcom(2)); A(6,8) = mk * (rk(1) - Rcom(1))

    ! Bond length velocities
    A(7,1) = ri(1) - rj(1); A(7,2) = ri(2) - rj(2); A(7,3) = ri(3) - rj(3)
    A(7,4) = rj(1) - ri(1); A(7,5) = rj(2) - ri(2); A(7,6) = rj(3) - ri(3)
    b(7) = rij * vij

    A(8,1) = ri(1) - rk(1); A(8,2) = ri(2) - rk(2); A(8,3) = ri(3) - rk(3)
    A(8,7) = rk(1) - ri(1); A(8,8) = rk(2) - ri(2); A(8,9) = rk(3) - ri(3)
    b(8) = rik * vik

    A(9,4) = rj(1) - rk(1); A(9,5) = rj(2) - rk(2); A(9,6) = rj(3) - rk(3)
    A(9,7) = rk(1) - rj(1); A(9,8) = rk(2) - rj(2); A(9,9) = rk(3) - rj(3)
    b(9) = rjk * vjk

    ! Invert
    call matrix_inverse(A,A_inv)
    x = A_inv .mult. b

    call print('Momentum before update = '//momentum(this,(/i,j,k/)))

    call print('Angular momentum before update = '//&
         (mi*((ri-Rcom) .cross. this%atoms%velo(:,i)) + &
          mj*((rj-Rcom) .cross. this%atoms%velo(:,j)) + &
          mk*((rk-Rcom) .cross. this%atoms%velo(:,k))))

    dEij = -bond_energy(this,i,j)
    dEik = -bond_energy(this,i,k)
    dEjk = -bond_energy(this,j,k)

    this%atoms%velo(:,i) = this%atoms%velo(:,i) + x(1:3)
    this%atoms%velo(:,j) = this%atoms%velo(:,j) + x(4:6)
    this%atoms%velo(:,k) = this%atoms%velo(:,k) + x(7:9)

    dEij = dEij + bond_energy(this,i,j)
    dEik = dEik + bond_energy(this,i,k)
    dEjk = dEjk + bond_energy(this,j,k)

    call print('Momentum after update = '//momentum(this,(/i,j,k/)))

    call print('Angular momentum after update = '//&
         (mi*((ri-Rcom) .cross. this%atoms%velo(:,i)) + &
          mj*((rj-Rcom) .cross. this%atoms%velo(:,j)) + &
          mk*((rk-Rcom) .cross. this%atoms%velo(:,k))))

    ! Now check the result

    call print('Required velocity for bond '//i//'--'//j//': '//gij)
    call print('Required velocity for bond '//i//'--'//k//': '//gik)
    call print('Required velocity for bond '//j//'--'//k//': '//gjk)

    call distance_relative_velocity(this%atoms,i,j,rij,vij)
    call distance_relative_velocity(this%atoms,i,k,rik,vik)
    call distance_relative_velocity(this%atoms,j,k,rjk,vjk)

    call print('')

    call print('Actual velocity for bond '//i//'--'//j//': '//vij)
    call print('Actual velocity for bond '//i//'--'//k//': '//vik)
    call print('Actual velocity for bond '//j//'--'//k//': '//vjk)

    call print('Energy added to bond '//i//'--'//j//': '//dEij)
    call print('Energy added to bond '//i//'--'//k//': '//dEik)
    call print('Energy added to bond '//j//'--'//k//': '//dEjk)

    Etot = Etot + dEij + dEik + dEjk

    call print('Total energy added so far = '//Etot)

  end subroutine thermalize_group

  function bond_energy(this,i,j)

    type(DynamicalSystem), intent(in) :: this
    integer,               intent(in) :: i, j
    real(dp)                          :: bond_energy

    real(dp)                          :: mi, mj, vij, rij

    mi = ElementMass(this%atoms%Z(i))
    mj = ElementMass(this%atoms%Z(j))

    call distance_relative_velocity(this%atoms,i,j,rij,vij)

    bond_energy = 0.5_dp * mi * mj * vij * vij / (mi + mj)

  end function bond_energy

  !% Updates the core QM flags saved in $hybrid$ and $hybrid_mark$ properties.
  !% Do this hysteretically, from $R_inner$ to $R_outer$ around $origin$ or $atomlist$, that is
  !% the centre of the QM region (a position in space or a list of atoms).
  !
  subroutine create_pos_or_list_centred_hybrid_region(my_atoms,R_inner,R_outer,origin, atomlist,use_avgpos,add_only_heavy_atoms,nneighb_only,min_images_only,list_changed)

    type(Atoms),        intent(inout) :: my_atoms
    real(dp),           intent(in)    :: R_inner
    real(dp),           intent(in)    :: R_outer
    real(dp), optional, intent(in)    :: origin(3)
    type(Table), optional, intent(in)    :: atomlist !the seed of the QM region
    logical,  optional, intent(in)   :: use_avgpos, add_only_heavy_atoms, nneighb_only, min_images_only
    logical,  optional, intent(out)   :: list_changed

    type(Atoms) :: atoms_for_add_cut_hydrogens
    type(Table) :: core, old_core, ext_qmlist
!    real(dp)    :: my_origin(3)
    integer, pointer :: hybrid_p(:), hybrid_mark_p(:)

    if (count((/present(origin),present(atomlist)/))/=1) call system_abort('create_pos_or_list_centred_hybrid_mark: Exactly 1 of origin and atomlist must be present.')
!    my_origin = optional_default((/0._dp,0._dp,0._dp/),origin)

    call map_into_cell(my_atoms)

    call allocate(core,4,0,0,0,0)
    call allocate(old_core,4,0,0,0,0)
    call allocate(ext_qmlist,4,0,0,0,0)
    ! call get_hybrid_list(my_atoms,HYBRID_ACTIVE_MARK,old_core,int_property='hybrid_mark')
    ! call get_hybrid_list(my_atoms,HYBRID_ACTIVE_MARK,core,int_property='hybrid_mark')
    ! call get_hybrid_list(my_atoms,HYBRID_BUFFER_MARK,ext_qmlist, int_property='hybrid_mark',get_up_to_mark_value=.true.)
    call get_hybrid_list(my_atoms,old_core,active_trans_only=.true., int_property='hybrid_mark')
    call get_hybrid_list(my_atoms,core,active_trans_only=.true., int_property='hybrid_mark')
    call get_hybrid_list(my_atoms,ext_qmlist, all_but_term=.true., int_property='hybrid_mark')

!Build the hysteretic QM core:
  if (present(atomlist)) then
     call print("create_pos_or_list_centred_hybrid_region calling construct_hysteretic_region", verbosity=NERD)
     call construct_hysteretic_region(region=core,at=my_atoms,core=atomlist,loop_atoms_no_connectivity=.false., &
       inner_radius=R_inner,outer_radius=R_outer, use_avgpos=use_avgpos, add_only_heavy_atoms=add_only_heavy_atoms, &
       nneighb_only=nneighb_only, min_images_only=min_images_only) !NB , debugfile=mainlog) 
  else !present origin
     call print("create_pos_or_list_centred_hybrid_region calling construct_hysteretic_region", verbosity=NERD)
     call construct_hysteretic_region(region=core,at=my_atoms,centre=origin,loop_atoms_no_connectivity=.true., &
       inner_radius=R_inner,outer_radius=R_outer, use_avgpos=use_avgpos, add_only_heavy_atoms=add_only_heavy_atoms, &
       nneighb_only=nneighb_only, min_images_only=min_images_only) !NB , debugfile=mainlog) 
  endif

!    call construct_buffer_origin(my_atoms,R_inner,inner_list,my_origin)
!    call construct_buffer_origin(my_atoms,R_outer,outer_list,my_origin)
!    call construct_region(my_atoms,R_inner,inner_list,centre=my_origin,use_avgpos=.false.,add_only_heavy_atoms=.false., with_hops=.false.)
!    call construct_region(my_atoms,R_outer,outer_list,centre=my_origin,use_avgpos=.false.,add_only_heavy_atoms=.false., with_hops=.false.)

!    call select_hysteretic_quantum_region(my_atoms,inner_list,outer_list,core)
!    call finalise(inner_list)
!    call finalise(outer_list)

!TO BE OPTIMIZED : add avgpos to add_cut_hydrogen
   ! add cut hydrogens, according to avgpos
    atoms_for_add_cut_hydrogens = my_atoms
    atoms_for_add_cut_hydrogens%oldpos = my_atoms%avgpos
    atoms_for_add_cut_hydrogens%avgpos = my_atoms%avgpos
    atoms_for_add_cut_hydrogens%pos = my_atoms%avgpos

    call set_cutoff_factor(atoms_for_add_cut_hydrogens,DEFAULT_NNEIGHTOL)
    call calc_connect(atoms_for_add_cut_hydrogens)

    call add_cut_hydrogens(atoms_for_add_cut_hydrogens,core)
    !call print('Atoms in hysteretic quantum region after adding the cut hydrogens:')
    !do i=1,core%N
    !   call print(core%int(1,i))
    !enddo
    call finalise(atoms_for_add_cut_hydrogens)

   ! check changes in QM list and set the new QM list
    if (present(list_changed)) then
       list_changed = check_list_change(old_list=old_core,new_list=core)
       if (list_changed)  call print('QM list around the origin  has changed')
    endif

   ! update QM_flag of my_atoms
    if (.not. assign_pointer(my_atoms,'hybrid_mark',hybrid_mark_p)) &
      call system_abort("create_pos_or_list_centred_hybrid_region couldn't get hybrid_mark property")
    hybrid_mark_p(1:my_atoms%N) = 0
    hybrid_mark_p(int_part(ext_qmlist,1)) = HYBRID_BUFFER_MARK
    hybrid_mark_p(int_part(core,1)) = HYBRID_ACTIVE_MARK
    ! qm_flag_index = get_property(my_atoms,'hybrid_mark')
    ! my_atoms%data%int(qm_flag_index,1:my_atoms%N) = 0
    ! my_atoms%data%int(qm_flag_index,int_part(ext_qmlist,1)) = 2
    ! my_atoms%data%int(qm_flag_index,int_part(core,1)) = 1

   ! update hybrid property of my_atoms
    if (.not. assign_pointer(my_atoms,'hybrid',hybrid_p)) &
      call system_abort("create_pos_or_list_centred_hybrid_region couldn't get hybrid property")
    hybrid_p(1:my_atoms%N) = 0
    hybrid_p(int_part(core,1)) = 1
    ! qm_flag_index = get_property(my_atoms,'hybrid')
    ! my_atoms%data%int(qm_flag_index,1:my_atoms%N) = 0
    ! my_atoms%data%int(qm_flag_index,int_part(core,1)) = 1

    call finalise(core)
    call finalise(old_core)
    call finalise(ext_qmlist)

  end subroutine create_pos_or_list_centred_hybrid_region

!  !% Returns a $hybridlist$ table with the atom indices whose $cluster_mark$
!  !% (or optionally any $int_property$) property takes no greater than $hybridflag$ positive value.
!  !
!  subroutine get_hybrid_list(my_atoms,hybridflag,hybridlist,int_property,get_up_to_mark_value)
!
!    type(Atoms), intent(in)  :: my_atoms
!    integer,     intent(in)  :: hybridflag
!    type(Table), intent(out) :: hybridlist
!    character(len=*), optional, intent(in) :: int_property
!    logical, intent(in), optional :: get_up_to_mark_value
!
!    integer, pointer :: mark_p(:)
!    integer              :: i
!    logical :: do_get_up_to_mark_value
!
!    do_get_up_to_mark_value = optional_default(.false., get_up_to_mark_value)
!
!    if (present(int_property)) then
!       if (.not. assign_pointer(my_atoms, trim(int_property), mark_p)) &
!	 call system_abort("get_hybrid_list_int couldn't get int_property='"//trim(int_property)//"'")
!    else
!       if (.not. assign_pointer(my_atoms, 'cluster_mark', mark_p)) &
!	 call system_abort("get_hybrid_list_int couldn't get default int_property='cluster_mark'")
!    endif
!
!    call initialise(hybridlist,4,0,0,0,0)      !1 int, 0 reals, 0 str, 0 log, num_hybrid_atoms entries
!    if (do_get_up_to_mark_value) then
!       do i=1,my_atoms%N
!          ! if (my_atoms%data%int(hybrid_flag_index,i).gt.0.and. &
!             ! my_atoms%data%int(hybrid_flag_index,i).le.hybridflag) &
!          if (mark_p(i) > 0 .and.  mark_p(i) <= hybridflag) &
!               call append(hybridlist,(/i,0,0,0/))
!       enddo
!    else
!       do i=1,my_atoms%N
!          ! if (my_atoms%data%int(hybrid_flag_index,i).eq.hybridflag) &
!          if (mark_p(i) == hybridflag) call append(hybridlist,(/i,0,0,0/))
!       enddo
!    endif
!
!    if (hybridlist%N.eq.0) call print('Empty QM list with cluster_mark '//hybridflag,verbosity=SILENT)
!
!  end subroutine get_hybrid_list

  !% Checks and reports the changes between two tables, $old_qmlist$ and $new_qmlist$.
  !
  function check_list_change(old_list,new_list) result(list_changed)

    type(Table), intent(in) :: old_list, new_list
    integer :: i
    logical :: list_changed

    list_changed = .false.
    if (old_list%N.ne.new_list%N) then
       call print ('list has changed: new number of atoms is: '//new_list%N//', was: '//old_list%N)
       list_changed = .true.
    else
       if (any(old_list%int(1,1:old_list%N).ne.new_list%int(1,1:new_list%N))) then
           do i=1,old_list%N
              if (.not.find_in_array(int_part(old_list,1),(new_list%int(1,i))).gt.0) then
                 call print('list has changed: atom '//new_list%int(1,i)//' has entered the region')
                 list_changed = .true.
              endif
              if (.not.find_in_array(int_part(new_list,1),(old_list%int(1,i))).gt.0) then
                 call print('list has changed: atom '//old_list%int(1,i)//' has left the region')
                 list_changed = .true.
              endif
           enddo
       endif
    endif

  end function check_list_change

  !% return list of atoms that have various subsets of hybrid marks set
  subroutine get_hybrid_list(at,hybrid_list,all_but_term,active_trans_only,int_property)
    type(Atoms), intent(in)  :: at !% object to scan for marked atoms
    type(Table), intent(out) :: hybrid_list !% on return, list of marked atoms
    logical, intent(in), optional :: all_but_term !% if present and true, select all marked atoms that aren't TERM
    logical, intent(in), optional :: active_trans_only !% if present and true, select all atoms marked ACTIVE or TRANS
    !% exactly one of all_but_term and active_trans_only must be present and true
    character(len=*), optional, intent(in) :: int_property !% if present, property to check, default cluster_mark

    integer :: i
    integer, pointer :: hybrid_mark(:)
    logical              :: my_all_but_term, my_active_trans_only
    character(STRING_LENGTH) :: my_int_property

    if (.not. present(all_but_term) .and. .not. present(active_trans_only)) &
      call system_abort("get_hybrid_list called with neither all_but_term nor active_trans_only present")

    my_all_but_term = optional_default(.false., all_but_term)
    my_active_trans_only = optional_default(.false., active_trans_only)

    if ((my_all_but_term .and. my_active_trans_only) .or. (.not. my_all_but_term .and. .not. my_active_trans_only)) &
      call system_abort("get_hybrid_list needs exactly one of all_but_term=" // all_but_term // " and active_trans_only="//my_active_trans_only)

    my_int_property = ''
    if (present(int_property)) then
       my_int_property = trim(int_property)
    else
       my_int_property = "cluster_mark"
    endif
    if (.not.(assign_pointer(at, trim(my_int_property), hybrid_mark))) &
      call system_abort("get_hybrid_list couldn't find "//trim(my_int_property)//" field")

    call initialise(hybrid_list,4,0,0,0,0)      !1 int, 0 reals, 0 str, 0 log, num_qm_atoms entries
    do i=1, at%N
      if (my_all_but_term) then
	if (hybrid_mark(i) /= HYBRID_NO_MARK .and. hybrid_mark(i) /= HYBRID_TERM_MARK) call append(hybrid_list,(/i,0,0,0/))
      else if (my_active_trans_only) then
	if (hybrid_mark(i) == HYBRID_ACTIVE_MARK .or. hybrid_mark(i) == HYBRID_TRANS_MARK) call append(hybrid_list,(/i,0,0,0/))
      else
	call system_abort("impossible! get_hybrid_list has no selection mode set")
      endif
    end do

    if (hybrid_list%N.eq.0) call print('get_hybrid_list returns empty hybrid list with field '//trim(my_int_property)// &
                                   ' all_but_term ' // my_all_but_term // ' active_trans_only ' // my_active_trans_only ,ERROR)
  end subroutine get_hybrid_list


end module clusters_module
