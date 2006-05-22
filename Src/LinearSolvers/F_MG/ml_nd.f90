module ml_nd_module

  use bl_constants_module
  use stencil_module
  use mg_module
  use ml_boxarray_module
  use ml_layout_module
  use itsol_module

  use ml_restriction_module
  use ml_prolongation_module
  use ml_interface_stencil_module
  use ml_util_module
  use bndry_reg_module

  implicit none

contains

  subroutine ml_nd(mla,mgt,rh,full_soln,fine_mask,ref_ratio,do_diagnostics,eps)

    type(ml_layout), intent(in   ) :: mla
    type(mg_tower ), intent(inout) :: mgt(:)
    type( multifab), intent(inout) :: rh(:)
    type( multifab), intent(inout) :: full_soln(:)
    type(lmultifab), intent(in   ) :: fine_mask(:)
    integer        , intent(in   ) :: ref_ratio(:,:)
    integer        , intent(in   ) :: do_diagnostics 
    real(dp_t)     , intent(in   ) :: eps

    integer :: nlevs
    type(multifab), allocatable  ::      soln(:)
    type(multifab), allocatable  ::        uu(:)
    type(multifab), allocatable  ::   uu_hold(:)
    type(multifab), allocatable  ::       res(:)
    type(multifab), allocatable  ::  temp_res(:)

    type(bndry_reg), allocatable :: brs_flx(:)

    type(box   ) :: pd,pdc
    type(layout) :: la,lac
    integer :: i, n, dm
    integer :: mglev, mglev_crse, iter, it
    logical :: fine_converged
    logical :: zero_only

    real(dp_t) :: Anorm, bnorm, res_norm
    real(dp_t) :: tres

    logical, allocatable :: nodal(:)

    dm = rh(1)%dim
    allocate(nodal(dm))
    nodal = .True.

    nlevs = mla%nlevel

    allocate(soln(nlevs), uu(nlevs), uu_hold(2:nlevs-1), res(nlevs))
    allocate(temp_res(nlevs))
    allocate(brs_flx(2:nlevs))

    do n = 2,nlevs-1
       la = mla%la(n)
       call multifab_build( uu_hold(n), la, 1, 1, rh(nlevs)%nodal)
       call setval( uu_hold(n), ZERO,all=.true.)
    end do

    do n = nlevs, 1, -1

       la = mla%la(n)
       call multifab_build(    soln(n), la, 1, 1, rh(nlevs)%nodal)
       call multifab_build(      uu(n), la, 1, 1, rh(nlevs)%nodal)
       call multifab_build(     res(n), la, 1, 1, rh(nlevs)%nodal)
       call multifab_build(temp_res(n), la, 1, 1, rh(nlevs)%nodal)
       call setval(    soln(n), ZERO,all=.true.)
       call setval(      uu(n), ZERO,all=.true.)
       call setval(     res(n), ZERO,all=.true.)
       call setval(temp_res(n), ZERO,all=.true.)

       if ( n == 1 ) exit

       ! Build the (coarse resolution) flux registers to be used in computing
       !  the residual at a non-finest AMR level.

       pdc = layout_get_pd(mla%la(n-1))
       lac = mla%la(n-1)
       call bndry_reg_rr_build_1(brs_flx(n), la, lac, ref_ratio(n-1,:), pdc, nodal = nodal)

    end do

!   DONT WANT TO DO THIS AS CAN ERRONEOUSLY PUT FINE GRID RH FROM NODE NEXT
!     TO CRSE-FINE BDRY ONTO CRSE POINT AT CRSE-FINE BDRY
!   do n = nlevs,2,-1
!      mglev      = mgt(n  )%nlevels
!      mglev_crse = mgt(n-1)%nlevels
!      call ml_restriction(rh(n-1), rh(n), mgt(n)%mm(mglev),&
!           mgt(n-1)%mm(mglev_crse), mgt(n)%face_type, ref_ratio(n-1,:))
!   end do
    bnorm = ml_norm_inf(rh,fine_mask)

    Anorm = stencil_norm(mgt(nlevs)%ss(mgt(nlevs)%nlevels))
    do n = 1, nlevs-1
       Anorm = max(stencil_norm(mgt(n)%ss(mgt(n)%nlevels), fine_mask(n)), Anorm)
    end do

    do n = nlevs,1,-1
       mglev = mgt(n)%nlevels
       call mg_defect(mgt(n)%ss(mglev),res(n),rh(n),full_soln(n),mgt(n)%mm(mglev))
    end do

!   do n = nlevs,2,-1
!      mglev      = mgt(n  )%nlevels
!      mglev_crse = mgt(n-1)%nlevels
!      call ml_restriction(res(n-1), res(n), mgt(n)%mm(mglev),&
!           mgt(n-1)%mm(mglev_crse), mgt(n)%face_type, ref_ratio(n-1,:))
!      pdc = layout_get_pd(mla%la(n-1))
!      call crse_fine_residual_nodal(n,mgt,brs_flx(n),res(n-1),temp_res(n),temp_res(n-1), &
!           full_soln(n-1),full_soln(n),ref_ratio(n-1,:),pdc)
!   enddo

    do n = 1,nlevs
       call multifab_copy(rh(n),res(n),all=.true.)
    end do

    ! ****************************************************************************

    fine_converged = .false.

    do iter = 1, mgt(nlevs)%max_iter

       if ( (iter .eq. 1) .or. fine_converged ) then
          if ( ml_converged(res, soln, fine_mask, bnorm, Anorm, eps) ) exit
       end if

       ! Set: uu = 0
       do n = 1,nlevs
          call setval(uu(n), ZERO, all=.true.)
       end do

       ! Set: uu_hold = 0
       do n = 2,nlevs-1
          call setval(uu_hold(n), ZERO, all=.true.)
       end do

       !   Down the V-cycle
       do n = nlevs,1,-1

          mglev = mgt(n)%nlevels

          if ( do_diagnostics == 1 ) then
             tres = norm_inf(res(n))
             if ( parallel_ioprocessor() ) then
                print *,'DWN: RES BEFORE GSRB AT LEVEL ',n, tres
             end if
          end if

          ! Relax ...
          if (n > 1) then
             call mini_cycle(mgt(n), mgt(n)%cycle, mglev, mgt(n)%ss(mglev), &
                  uu(n), res(n), mgt(n)%mm(mglev), mgt(n)%nu1, mgt(n)%nu2, &
                  mgt(n)%gamma)
          else 
             call mg_tower_cycle(mgt(n), mgt(n)%cycle, mglev, mgt(n)%ss(mglev), &
                  uu(n), res(n), mgt(n)%mm(mglev), mgt(n)%nu1, mgt(n)%nu2, &
                  mgt(n)%gamma)
          end if

          ! Add: Soln += uu
          call saxpy(soln(n),ONE,uu(n))

          if (n > 1) then
             mglev_crse = mgt(n-1)%nlevels

             ! Compute COARSE Res = Rh - Lap(Soln)
             call mg_defect(mgt(n-1)%ss(mglev_crse),res(n-1), &
                  rh(n-1),soln(n-1),mgt(n-1)%mm(mglev_crse))

             ! Compute FINE Res = Res - Lap(uu)
             mglev = mgt(n)%nlevels
             call mg_defect(mgt(n)%ss(mglev), temp_res(n), &
                  res(n),uu(n),mgt(n)%mm(mglev))
             call multifab_copy(res(n),temp_res(n),all=.true.)

             if ( do_diagnostics == 1 ) then
                tres = norm_inf(res(n))
                if ( parallel_ioprocessor() ) then
                   print *,'DWN: RES AFTER  GSRB AT LEVEL ',n, tres
                end if
             end if

             ! Restrict FINE Res to COARSE Res
             call ml_restriction(res(n-1), res(n), mgt(n)%mm(mglev),& 
                  mgt(n-1)%mm(mglev_crse), mgt(n)%face_type, ref_ratio(n-1,:), &
                  inject = .false., zero_only = .true.)

             call setval(temp_res(n-1),ZERO,all=.true.)
             call ml_restriction(temp_res(n-1), res(n), mgt(n)%mm(mglev),&
                                 mgt(n-1)%mm(mglev_crse), mgt(n)%face_type, ref_ratio(n-1,:))
             do i = 1,dm
               if (temp_res(n-1)%la%lap%pmask(i)) then
                 call periodic_add_copy(temp_res(n-1),i)
               end if
             end do
             call saxpy(res(n-1),ONE,temp_res(n-1))

             ! Compute CRSE-FINE Res = Rh - Lap(Soln)
             pdc = layout_get_pd(mla%la(n-1))
             call crse_fine_residual_nodal(n,mgt,brs_flx(n),res(n-1),rh(n),temp_res(n),temp_res(n-1), &
                  soln(n-1),soln(n),ref_ratio(n-1,:),pdc)

             ! Copy u_hold = uu
             if (n < nlevs) call multifab_copy(uu_hold(n),uu(n),all=.true.)

             ! Set: uu = 0
             call setval(uu(n),ZERO,all=.true.)

          else

             if (do_diagnostics == 1 ) then
                call mg_defect(mgt(n)%ss(mglev),temp_res(n), res(n),uu(n),mgt(n)%mm(mglev))
                tres = norm_inf(temp_res(n))
                if ( parallel_ioprocessor() ) then
                   print *,'DWN: RES AFTER  GSRB AT LEVEL ',n, tres
                end if
             end if

          end if

       end do

       !   Back up the V-cycle
       do n = 2, nlevs

          pd = layout_get_pd(mla%la(n))
          mglev = mgt(n)%nlevels

          ! Interpolate uu from coarser level
          if (iter == 1) call saxpy(uu(n-1),  ONE, full_soln(n-1))
          call ml_prolongation(uu(n), uu(n-1), pd, ref_ratio(n-1,:))
          if (iter == 1) call saxpy(uu(n-1), -ONE, full_soln(n-1))

          ! Subtract: uu -= full_soln
          !     Must do this in order to remove interpolated full_soln...
          if (iter == 1) call saxpy(uu(n),-ONE,full_soln(n))

          ! Add: Soln += uu
          call saxpy(soln(n), ONE, uu(n), .true.)

          ! Add: uu_hold += uu 
          if (n < nlevs) call saxpy(uu_hold(n), ONE, uu(n), .true.)

          ! Compute Res = Res - Lap(uu)
          call mg_defect(mgt(n)%ss(mglev),temp_res(n),res(n),uu(n),mgt(n)%mm(mglev))
          call multifab_copy(res(n),temp_res(n),all=.true.)

          if ( do_diagnostics == 1 ) then
             tres = norm_inf(res(n))
             if ( parallel_ioprocessor() ) then
                print *,'UP : RES BEFORE GSRB AT LEVEL ',n, tres
             end if
          end if

          ! Set: uu = 0
          call setval(uu(n),ZERO,all=.true.)

          ! Relax ...
          call mini_cycle(mgt(n), mgt(n)%cycle, mglev, mgt(n)%ss(mglev), &
               uu(n), res(n), mgt(n)%mm(mglev), mgt(n)%nu1, mgt(n)%nu2, &
               mgt(n)%gamma)

          ! Compute Res = Res - Lap(uu)
          call mg_defect(mgt(n)%ss(mglev),temp_res(n),res(n),uu(n),mgt(n)%mm(mglev))
          call multifab_copy(res(n),temp_res(n),all=.true.)

          if ( do_diagnostics == 1 ) then
             tres = norm_inf(res(n))
             if ( parallel_ioprocessor() ) then
                print *,'UP : RES AFTER  GSRB AT LEVEL ',n, tres
                if (n == nlevs) print *,' '
             end if
          end if

          ! Add: soln += uu
          call saxpy(soln(n), ONE, uu(n), .true.)

          ! Add: uu += uu_hold so that it will be interpolated too.
          if (n < nlevs) call saxpy(  uu(n), ONE, uu_hold(n), .true.)

       end do

       !    Inject the solution to the coarser grids.
       do n = nlevs,2,-1
          mglev      = mgt(n)%nlevels
          mglev_crse = mgt(n-1)%nlevels
          call ml_restriction(soln(n-1), soln(n), mgt(n)%mm(mglev), &
               mgt(n-1)%mm(mglev_crse), mgt(n)%face_type, &
               ref_ratio(n-1,:), inject = .true.)
       end do

       do n = 1,nlevs
          call multifab_fill_boundary(soln(n))
       end do

       !    Optimization so don't have to do multilevel convergence test each time

       !    Compute the residual on just the finest level
       n = nlevs
       mglev = mgt(n)%nlevels
       call mg_defect(mgt(n)%ss(mglev),res(n),rh(n),soln(n),mgt(n)%mm(mglev))

       if ( ml_fine_converged(res, soln, bnorm, Anorm, eps) ) then

          fine_converged = .true.

          !      Compute the residual on every level
          do n = 1,nlevs-1
             mglev = mgt(n)%nlevels
             call mg_defect(mgt(n)%ss(mglev),res(n),rh(n),soln(n),mgt(n)%mm(mglev))
          end do

          do n = nlevs,2,-1
             mglev      = mgt(n  )%nlevels
             mglev_crse = mgt(n-1)%nlevels
             call ml_restriction(res(n-1), res(n), mgt(n)%mm(mglev),&
                  mgt(n-1)%mm(mglev_crse), mgt(n)%face_type, ref_ratio(n-1,:))
          end do

          do n = nlevs,2,-1
             pdc = layout_get_pd(mla%la(n-1))
             call crse_fine_residual_nodal(n,mgt,brs_flx(n),res(n-1),rh(n),temp_res(n),temp_res(n-1), &
                  soln(n-1),soln(n),ref_ratio(n-1,:),pdc)
          end do

          if ( mgt(nlevs)%verbose > 0 ) then
             do n = 1,nlevs
                tres = norm_inf(res(n))
                if ( parallel_IOProcessor() ) then
                   write(unit=*, fmt='(i3,": Level ",i2,"  : SL_Ninf(defect) = ",g15.8)') iter,n,tres
                end if
             end do
             tres = ml_norm_inf(res,fine_mask)
             if ( parallel_IOProcessor() ) then
                write(unit=*, fmt='(i3,": All Levels: ML_Ninf(defect) = ",g15.8)') iter, tres
             end if
          end if

       else

          fine_converged = .false.
          if ( mgt(nlevs)%verbose > 0 ) then
             tres = norm_inf(res(nlevs))
             if ( parallel_IOProcessor() ) then
                write(unit=*, fmt='(i3,": FINE_Ninf(defect) = ",g15.8)') iter, tres
             end if
          end if

       end if

    end do

    if ( mgt(nlevs)%verbose > 0 .AND. parallel_IOProcessor() ) &
         write(unit=*, fmt='("MG finished at ", i3, " iterations")') iter-1

    ! Add: soln += full_soln
    do n = 1,nlevs
       call saxpy(full_soln(n),ONE,soln(n))
    end do


    ! ****************************************************************************

    do n = 2,nlevs-1
       call multifab_destroy(uu_hold(n))
    end do

    do n = nlevs, 1, -1
       call multifab_destroy(    soln(n))
       call multifab_destroy(      uu(n))
       call multifab_destroy(     res(n))
       call multifab_destroy(temp_res(n))
       if ( n == 1 ) exit
       call bndry_reg_destroy(brs_flx(n))
    end do

  contains

    subroutine crse_fine_residual_nodal(n,mgt,brs_flx,crse_res,fine_rhs,temp_res,temp_crse_res, &
         crse_soln,fine_soln,ref_ratio,pdc)

      integer        , intent(in   ) :: n
      type(mg_tower) , intent(inout) :: mgt(:)
      type(bndry_reg), intent(inout) :: brs_flx
      type(multifab) , intent(inout) :: crse_res
      type(multifab) , intent(in   ) :: fine_rhs
      type(multifab) , intent(inout) :: temp_res
      type(multifab) , intent(inout) :: temp_crse_res
      type(multifab) , intent(inout) :: crse_soln
      type(multifab) , intent(inout) :: fine_soln
      integer        , intent(in   ) :: ref_ratio(:)
      type(box)      , intent(in   ) :: pdc

      type(layout)   :: la
      integer :: i,dm,mglev_crse,mglev_fine

      mglev_crse = mgt(n-1)%nlevels
      mglev_fine = mgt(n  )%nlevels
      dm = temp_res%dim

      la = multifab_get_layout(temp_res)

      !    Zero out the flux registers which will hold the fine contributions
      call bndry_reg_setval(brs_flx, ZERO, all = .true.)

      !    Compute the fine contributions at faces, edges and corners.

      !    First compute a residual which only takes contributions from the
      !       grid on which it is calculated.
      call grid_res(mgt(n),mglev_fine,mgt(n)%ss(mglev_fine),temp_res, &
           fine_rhs,fine_soln,mgt(n)%mm(mglev_fine),mgt(n)%face_type)

      do i = 1,dm
         call ml_fine_contrib(brs_flx%bmf(i,0), &
              temp_res,mgt(n)%mm(mglev_fine),ref_ratio,pdc,-i)
         call ml_fine_contrib(brs_flx%bmf(i,1), &
              temp_res,mgt(n)%mm(mglev_fine),ref_ratio,pdc,+i)
      end do

!     Compute the crse contributions at edges and corners and add to fine contributions
!        in temp_crse_res (need to do this in a temporary for periodic issues)
      call setval(temp_crse_res,ZERO,all=.true.)

      do i = 1,dm
         call ml_crse_contrib(temp_crse_res, brs_flx%bmf(i,0), crse_soln, &
              mgt(n-1)%ss(mgt(n-1)%nlevels), &
              mgt(n-1)%mm(mglev_crse), &
              mgt(n  )%mm(mglev_fine), pdc,ref_ratio, -i)
         call ml_crse_contrib(temp_crse_res, brs_flx%bmf(i,1), crse_soln, &
              mgt(n-1)%ss(mgt(n-1)%nlevels), &
              mgt(n-1)%mm(mglev_crse), &
              mgt(n  )%mm(mglev_fine), pdc,ref_ratio, +i)
      end do

      do i = 1,dm
        if (crse_res%la%lap%pmask(i)) then
          call periodic_add_copy(temp_crse_res,i)
        end if
      end do

!     Add to res(n-1).
      call saxpy(crse_res,ONE,temp_crse_res)

!     Clear temp_crse_res (which is temp_res(n-1) from calling routine) just in case...
      call setval(temp_crse_res,ZERO,all=.true.)

    end subroutine crse_fine_residual_nodal

    subroutine periodic_add_copy(res,dir)

      type(multifab), intent(inout) :: res
      integer       , intent(in   ) :: dir

      type(box)           :: domain,bxi,bxj,bx_lo,bx_hi
      real(dp_t), pointer :: ap(:,:,:,:)
      real(dp_t), pointer :: bp(:,:,:,:)
      integer             :: i,j
      logical             :: nodal(res%dim)

      nodal = .true.
      domain = box_nodalize(res%la%lap%pd,nodal)

      ! Add values at hi end of domain to lo end.
      do j = 1, res%nboxes
  
        bxj = get_ibox(res,j)
        if (bxj%lo(dir) == domain%lo(dir)) then
          call box_set_upb_d(bxj,dir,domain%lo(dir))
          do i = 1, res%nboxes
            bxi = get_ibox(res,i)
            if (bxi%hi(dir) == domain%hi(dir)) then
              call box_set_lwb_d(bxi,dir,domain%lo(dir))
              call box_set_upb_d(bxi,dir,domain%lo(dir))
  
              bx_lo = box_intersection(bxi,bxj)
              bx_hi = bx_lo
              
              call box_set_lwb_d(bx_hi,dir,domain%hi(dir))
              call box_set_upb_d(bx_hi,dir,domain%hi(dir))
  
              if (.not. box_empty(bx_lo)) then
                ap => dataptr(res,j,bx_lo)
                bp => dataptr(res,i,bx_hi)
                ap = ap + bp
              end if
            end if
          end do
        end if

      end do
  
      ! Copy values from lo end of domain to hi end.
      do j = 1, res%nboxes

        bxj = get_ibox(res,j)
        if (bxj%lo(dir) == domain%lo(dir)) then
          call box_set_upb_d(bxj,dir,domain%lo(dir))
          do i = 1, res%nboxes
            bxi = get_ibox(res,i)
            if (bxi%hi(dir) == domain%hi(dir)) then
              call box_set_lwb_d(bxi,dir,domain%lo(dir))
              call box_set_upb_d(bxi,dir,domain%lo(dir))
  
              bx_lo = box_intersection(bxi,bxj)
              bx_hi = bx_lo
              
              call box_set_lwb_d(bx_hi,dir,domain%hi(dir))
              call box_set_upb_d(bx_hi,dir,domain%hi(dir))
  
              if (.not. box_empty(bx_lo)) then
                ap => dataptr(res,j,bx_lo)
                bp => dataptr(res,i,bx_hi)
                  bp = ap
              end if
            end if
          end do
        end if

      end do

    end subroutine periodic_add_copy

    function ml_fine_converged(res, sol, bnorm, Anorm, eps) result(r)
      logical :: r
      type(multifab), intent(in) :: res(:), sol(:)
      real(dp_t), intent(in) :: Anorm, eps, bnorm
      real(dp_t) :: ni_res, ni_sol
      integer    :: nlevs
      nlevs = size(res)
      ni_res = norm_inf(res(nlevs))
      ni_sol = norm_inf(sol(nlevs))
      r =  ni_res <= eps*(Anorm*ni_sol + bnorm) .or. &
           ni_res <= spacing(Anorm)
    end function ml_fine_converged

    function ml_converged(res, sol, mask, bnorm, Anorm, eps) result(r)
      logical :: r
      type(multifab), intent(in) :: res(:), sol(:)
      type(lmultifab), intent(in) :: mask(:)
      real(dp_t), intent(in) :: Anorm, eps, bnorm
      real(dp_t) :: ni_res, ni_sol
      ni_res = ml_norm_inf(res, mask)
      ni_sol = ml_norm_inf(sol, mask)
      r =  ni_res <= eps*(Anorm*ni_sol + bnorm) .or. &
           ni_res <= spacing(Anorm)
    end function ml_converged

    function ml_norm_inf(rr, mask) result(r)
      real(dp_t)  :: r
      type(multifab), intent(in) :: rr(:)
      type(lmultifab), intent(in) :: mask(:)
      integer n
      r = 0
      do n = 1, size(rr)
         r = max(norm_inf(rr(n),mask(n)), r)
      end do
    end function ml_norm_inf

  end subroutine ml_nd

end module ml_nd_module
