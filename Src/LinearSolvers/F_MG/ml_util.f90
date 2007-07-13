module ml_util_module

  use stencil_module
  use stencil_nodal_module
  use bl_prof_module

  implicit none

contains

  subroutine ml_fill_fluxes(ss, flux, uu, mm, ratio, face, dim)
    type(multifab), intent(inout) :: flux
    type(multifab), intent(in) :: ss
    type(multifab), intent(inout) :: uu
    type(imultifab), intent(in) :: mm
    integer :: ratio
    integer :: face, dim
    integer :: i, n
    real(kind=dp_t), pointer :: fp(:,:,:,:)
    real(kind=dp_t), pointer :: up(:,:,:,:)
    real(kind=dp_t), pointer :: sp(:,:,:,:)
    integer        , pointer :: mp(:,:,:,:)
    integer :: ng
    type(bl_prof_timer), save :: bpt

    call build(bpt, "ml_fill_fluxes")

    ng = uu%ng

    if ( uu%nc /= flux%nc ) then
       call bl_error("ML_FILL_FLUXES: uu%nc /= flux%nc")
    end if

    do i = 1, flux%nboxes
       if ( remote(flux, i) ) cycle
       fp => dataptr(flux, i)
       up => dataptr(uu, i)
       sp => dataptr(ss, i)
       mp => dataptr(mm, i)
       do n = 1, uu%nc
          select case(ss%dim)
          case (1)
             call stencil_flux_1d(sp(:,1,1,:), fp(:,1,1,n), up(:,1,1,n), &
                  mp(:,1,1,1), ng, ratio, face, dim)
          case (2)
             call stencil_flux_2d(sp(:,:,1,:), fp(:,:,1,n), up(:,:,1,n), &
                  mp(:,:,1,1), ng, ratio, face, dim)
          case (3)
             call stencil_flux_3d(sp(:,:,:,:), fp(:,:,:,n), up(:,:,:,n), &
                  mp(:,:,:,1), ng, ratio, face, dim)
          end select
       end do
    end do
    call destroy(bpt)
  end subroutine ml_fill_fluxes

  subroutine ml_fill_fluxes_c(ss, flux, cf, uu, cu, mm, ratio, face, dim)
    type(multifab), intent(inout) :: flux
    type(multifab), intent(in) :: ss
    type(multifab), intent(inout) :: uu
    type(imultifab), intent(in) :: mm
    integer, intent(in) :: cf, cu
    integer :: ratio
    integer :: face, dim
    integer :: i
    real(kind=dp_t), pointer :: fp(:,:,:,:)
    real(kind=dp_t), pointer :: up(:,:,:,:)
    real(kind=dp_t), pointer :: sp(:,:,:,:)
    integer        , pointer :: mp(:,:,:,:)
    integer :: ng
    logical :: lcross
    type(bl_prof_timer), save :: bpt

    call build(bpt, "ml_fill_fluxes_c")

    ng = uu%ng

    lcross = ((ncomp(ss) == 5) .or. (ncomp(ss) == 7))

    call multifab_fill_boundary(uu, cross = lcross)
    do i = 1, flux%nboxes
       if ( remote(flux, i) ) cycle
       fp => dataptr(flux, i, cf)
       up => dataptr(uu, i, cu)
       sp => dataptr(ss, i)
       mp => dataptr(mm, i)
       select case(ss%dim)
       case (1)
          call stencil_flux_1d(sp(:,1,1,:), fp(:,1,1,1), up(:,1,1,1), &
               mp(:,1,1,1), ng, ratio, face, dim)
       case (2)
          call stencil_flux_2d(sp(:,:,1,:), fp(:,:,1,1), up(:,:,1,1), &
               mp(:,:,1,1), ng, ratio, face, dim)
       case (3)
          call stencil_flux_3d(sp(:,:,:,:), fp(:,:,:,1), up(:,:,:,1), &
               mp(:,:,:,1), ng, ratio, face, dim)
       end select
    end do
    call destroy(bpt)
  end subroutine ml_fill_fluxes_c

  subroutine ml_fill_fine_fluxes(ss, flux, uu, mm, face, dim)
    type(multifab), intent(inout) :: flux
    type(multifab), intent(in) :: ss
    type(multifab), intent(inout) :: uu
    type(imultifab), intent(in) :: mm
    integer :: face, dim
    integer :: i, n
    real(kind=dp_t), pointer :: fp(:,:,:,:)
    real(kind=dp_t), pointer :: up(:,:,:,:)
    real(kind=dp_t), pointer :: sp(:,:,:,:)
    integer        , pointer :: mp(:,:,:,:)
    integer :: ng
    logical :: lcross
    type(bl_prof_timer), save :: bpt

    call build(bpt, "ml_fill_fine_fluxes")

    ng = uu%ng

    lcross = ((ncomp(ss) == 5) .or. (ncomp(ss) == 7))

    if ( uu%nc /= flux%nc ) then
       call bl_error("ML_FILL_FINE_FLUXES: uu%nc /= flux%nc")
    end if

    call multifab_fill_boundary(uu, cross = lcross)

    do i = 1, flux%nboxes
       if ( remote(flux, i) ) cycle
       fp => dataptr(flux, i)
       up => dataptr(uu, i)
       sp => dataptr(ss, i)
       mp => dataptr(mm, i)
       do n = 1, uu%nc
          select case(ss%dim)
          case (1)
             call stencil_fine_flux_1d(sp(:,1,1,:), fp(:,1,1,n), up(:,1,1,n), &
                  mp(:,1,1,1), ng, face, dim)
          case (2)
             call stencil_fine_flux_2d(sp(:,:,1,:), fp(:,:,1,n), up(:,:,1,n), &
                  mp(:,:,1,1), ng, face, dim)
          case (3)
             call stencil_fine_flux_3d(sp(:,:,:,:), fp(:,:,:,n), up(:,:,:,n), &
                  mp(:,:,:,1), ng, face, dim)
          end select
       end do
    end do

    call destroy(bpt)

  end subroutine ml_fill_fine_fluxes

  subroutine ml_fill_all_fluxes(ss, flux, uu, mm)
    type( multifab), intent(in   ) :: ss
    type( multifab), intent(inout) :: flux(:)
    type( multifab), intent(inout) :: uu
    type(imultifab), intent(in   ) :: mm

    integer :: face, dim, i, n, ngu, ngf
    logical :: lcross

    real(kind=dp_t), pointer :: fp(:,:,:,:)
    real(kind=dp_t), pointer :: up(:,:,:,:)
    real(kind=dp_t), pointer :: sp(:,:,:,:)
    integer        , pointer :: mp(:,:,:,:)

    type(bl_prof_timer), save :: bpt
    call build(bpt, "ml_fill_all_fluxes")

    ngu = uu%ng

    lcross = ((ncomp(ss) == 5) .or. (ncomp(ss) == 7))

    if ( uu%nc /= flux(1)%nc ) then
       call bl_error("ML_FILL_ALL_FLUXES: uu%nc /= flux%nc")
    end if

    call multifab_fill_boundary(uu, cross = lcross)

    do dim = 1, uu%dim
     do i = 1, flux(dim)%nboxes
       if ( remote(flux(dim), i) ) cycle
       ngf = flux(dim)%ng
       fp => dataptr(flux(dim), i)
       up => dataptr(uu, i)
       sp => dataptr(ss, i)
       mp => dataptr(mm, i)
       select case(ss%dim)
       case (2)
          call stencil_all_flux_2d(sp(:,:,1,:), fp(:,:,1,1), up(:,:,1,1), &
               mp(:,:,1,1), ngu, ngf, dim)
       case (3)
          call stencil_all_flux_3d(sp(:,:,:,:), fp(:,:,:,1), up(:,:,:,1), &
               mp(:,:,:,1), ngu, ngf, dim)
       end select
     end do
    end do

    call destroy(bpt)

  end subroutine ml_fill_all_fluxes

  subroutine ml_fine_contrib(flux, res, mm, ratio, crse_domain, side)
    type(multifab), intent(inout) :: flux
    type(multifab), intent(inout) :: res
    type(imultifab), intent(in) :: mm
    type(box) :: crse_domain
    type(box) :: fbox
    integer :: side
    integer :: ratio(:)
    integer :: lof(flux%dim)
    integer :: lo_dom(flux%dim), hi_dom(flux%dim)
    integer :: i, n, dir
    real(kind=dp_t), pointer :: fp(:,:,:,:)
    real(kind=dp_t), pointer :: rp(:,:,:,:)
    integer        , pointer :: mp(:,:,:,:)
    integer :: nc
    type(bl_prof_timer), save :: bpt

    call build(bpt, "ml_fine_contrib")

    nc = res%nc

    if ( res%nc /= flux%nc ) then
       call bl_error("ML_FILL_FLUXES: res%nc /= flux%nc")
    end if

    lo_dom = lwb(crse_domain)
    hi_dom = upb(crse_domain)
    if ( nodal_q(res) ) hi_dom = hi_dom + 1
    dir = iabs(side)

    do i = 1, flux%nboxes
       if ( remote(flux, i) ) cycle
       fbox   = get_ibox(flux,i)
       lof = lwb(fbox)
       fp => dataptr(flux, i)
       rp => dataptr(res, i)
       mp => dataptr(mm, i)
       do n = 1, nc
          if ( (res%la%lap%pmask(dir)) .or. &
               (lof(dir) /= lo_dom(dir) .and. lof(dir) /= hi_dom(dir)) ) then
             select case(flux%dim)
             case (1)
                call bl_error("ML_FILL_FLUXES: no 1 D case")
             case (2)
                call fine_edge_resid_2d(fp(:,:,1,n), rp(:,:,1,1), mp(:,:,1,1), ratio, side, lof)
             case (3)
                call fine_edge_resid_3d(fp(:,:,:,n), rp(:,:,:,1), mp(:,:,:,1), ratio, side, lof)
             end select
          end if
       end do
    end do
    call destroy(bpt)
  end subroutine ml_fine_contrib

end module ml_util_module
