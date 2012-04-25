module advance_module

  use multifab_module
  use ml_layout_module
  use define_bc_module
  use bc_module
  use multifab_physbc_module
  use multifab_fill_ghost_module
  use ml_restriction_module
  use mg_module
  use bndry_reg_module
  use cc_stencil_fill_module
  use ml_solve_module

  implicit none

  private

  public :: advance

contains
  
  subroutine advance(mla,phi,dx,dt,the_bc_tower,do_implicit_solve)

    type(ml_layout), intent(in   ) :: mla
    type(multifab) , intent(inout) :: phi(:)
    real(kind=dp_t), intent(in   ) :: dx(:)
    real(kind=dp_t), intent(in   ) :: dt
    type(bc_tower) , intent(in   ) :: the_bc_tower
    logical        , intent(in   ) :: do_implicit_solve

    ! local variables
    integer i,dm,n,nlevs

    ! an array of multifabs; one for each direction
    type(multifab) :: flux(mla%nlevel,mla%dim) 

    type(multifab) :: alpha(mla%nlevel)
    type(multifab) :: beta(mla%nlevel,mla%dim)
    type(multifab) :: rhs(mla%nlevel)

    type(multifab), allocatable :: cell_coeffs(:)
    type(multifab), allocatable :: edge_coeffs(:,:)

    type(bndry_reg) :: fine_flx(2:mla%nlevel)

    real(dp_t) ::  xa(mla%dim),  xb(mla%dim)
    real(dp_t) :: pxa(mla%dim), pxb(mla%dim)

    integer :: stencil_order,do_diagnostics

    type(mg_tower)  :: mgt(mla%nlevel)

    type(layout) :: la
    type(box) :: pd

    real(dp_t) :: dx_vector(mla%nlevel,mla%dim)

    integer :: ns,smoother,nu1,nu2,nub,gamma,cycle_type
    integer :: bottom_solver,bottom_max_iter,max_iter,max_nlevel
    integer :: max_bottom_nlevel,min_width,verbose,cg_verbose
    real(dp_t) :: omega,bottom_solver_eps,rel_solver_eps,abs_solver_eps

    dm = mla%dim
    nlevs = mla%nlevel

    stencil_order = 2
    do_diagnostics = 0

    if (do_implicit_solve) then

       ! Solve for phi using backward Euler discretization:
       ! (phi^n+1 - phi^n) / Delta t = lap phi^n+1.
       ! ml_cc_solve solves for phi in the equation:
       ! (alpha - del dot beta grad) phi = rhs,
       ! where alpha, phi, and rhs are cell-centered and beta is face-centered.
       ! The backward Euler discretization can be rewritten as:
       ! (I - Delta t * lap) phi^n+1 = phi^n
       ! thus,
       ! alpha = 1.0
       ! beta (on all faces) = Delta t
       ! rhs = phi^n

       do n=1,nlevs

          ! set alpha=1, including ghost cells
          call multifab_build(alpha(n), mla%la(n),  1, 1)
          call setval(alpha(n), 1.d0, all=.true.)

          ! copy phi into rhs
          call multifab_build(  rhs(n), mla%la(n),  1, 0)
          call multifab_copy_c(rhs(n),1,phi(n),1,1,0)

          ! set beta=dt, including ghost cells
          do i=1,dm
             call multifab_build_edge(beta(n,i), mla%la(n), 1, 1, i)
             call setval(beta(n,i), dt, all=.true.)
          end do

       end do

       do n = 2,nlevs
          call bndry_reg_build(fine_flx(n),mla%la(n),ml_layout_get_pd(mla,n))
       end do

       ns = 1 + 3*dm

       smoother          = mgt(nlevs)%smoother
       nu1               = mgt(nlevs)%nu1
       nu2               = mgt(nlevs)%nu2
       nub               = mgt(nlevs)%nub
       gamma             = mgt(nlevs)%gamma
       cycle_type        = mgt(nlevs)%cycle_type
       omega             = mgt(nlevs)%omega
       bottom_solver     = mgt(nlevs)%bottom_solver
       bottom_max_iter   = mgt(nlevs)%bottom_max_iter
       bottom_solver_eps = mgt(nlevs)%bottom_solver_eps
       max_iter          = mgt(nlevs)%max_iter
       max_bottom_nlevel = mgt(nlevs)%max_bottom_nlevel
       min_width         = mgt(nlevs)%min_width
       rel_solver_eps    = mgt(nlevs)%eps
       abs_solver_eps    = mgt(nlevs)%abs_eps
       verbose           = mgt(nlevs)%verbose
       cg_verbose        = mgt(nlevs)%cg_verbose

       do n=1,nlevs

          pd = layout_get_pd(mla%la(n))

          dx_vector(n,:) = dx(n)

          if (n .eq. 1) then
             max_nlevel = mgt(nlevs)%max_nlevel
          else
             max_nlevel = 1
          end if

          call mg_tower_build(mgt(n), mla%la(n), pd, &
                              the_bc_tower%bc_tower_array(n)%ell_bc_level_array(0,:,:,1), &
                              dh = dx_vector(n,:), &
                              ns = ns, &
                              smoother = smoother, &
                              nu1 = nu1, &
                              nu2 = nu2, &
                              nub = nub, &
                              gamma = gamma, &
                              cycle_type = cycle_type, &
                              omega = omega, &
                              bottom_solver = bottom_solver, &
                              bottom_max_iter = bottom_max_iter, &
                              bottom_solver_eps = bottom_solver_eps, &
                              max_iter = max_iter, &
                              max_nlevel = max_nlevel, &
                              max_bottom_nlevel = max_bottom_nlevel, &
                              min_width = min_width, &
                              eps = rel_solver_eps, &
                              abs_eps = abs_solver_eps, &
                              verbose = verbose, &
                              cg_verbose = cg_verbose, &
                              nodal = nodal_flags(rhs(nlevs)), &
                              is_singular = .false.)

       end do

       ! Fill coefficient array
       do n = nlevs,1,-1

          allocate(cell_coeffs(mgt(n)%nlevels))
          allocate(edge_coeffs(mgt(n)%nlevels,dm))

          la = mla%la(n)

          call multifab_build(cell_coeffs(mgt(n)%nlevels), la, 1, 1)
          call multifab_copy_c(cell_coeffs(mgt(n)%nlevels),1,alpha(n),1,1,alpha(n)%ng)

          do i=1,dm
             call multifab_build_edge(edge_coeffs(mgt(n)%nlevels,i),la,1,1,i)
             call multifab_copy_c(edge_coeffs(mgt(n)%nlevels,i),1,beta(n,i),1,1,beta(n,i)%ng)
          end do

          if (n > 1) then
             xa = HALF*mla%mba%rr(n-1,:)*mgt(n)%dh(:,mgt(n)%nlevels)
             xb = HALF*mla%mba%rr(n-1,:)*mgt(n)%dh(:,mgt(n)%nlevels)
          else
             xa = ZERO
             xb = ZERO
          end if

          pxa = ZERO
          pxb = ZERO

          call stencil_fill_cc_all_mglevels(mgt(n), cell_coeffs, edge_coeffs, xa, xb, &
                                            pxa, pxb, stencil_order, &
                                            the_bc_tower%bc_tower_array(n)%ell_bc_level_array(0,:,:,1))

          call destroy(cell_coeffs(mgt(n)%nlevels))
          deallocate(cell_coeffs)

          do i=1,dm
             call destroy(edge_coeffs(mgt(n)%nlevels,i))
          end do
          deallocate(edge_coeffs)

       end do

       call ml_cc_solve(mla, mgt, rhs, phi, fine_flx, mla%mba%rr, &
                        do_diagnostics, rel_solver_eps)

       ! deallocate memory
       do n=1,nlevs
          call multifab_destroy(alpha(n))
          call multifab_destroy(  rhs(n))
          do i=1,dm
             call multifab_destroy(beta(n,i))
          end do
       end do
       do n = 2,nlevs
          call bndry_reg_destroy(fine_flx(n))
       end do

       do n = 1, nlevs
          call mg_tower_destroy(mgt(n))
       end do

    else
       
       ! explicit time advancement

       ! build the flux(:,:) multifabs
       do n=1,nlevs
          do i=1,dm
             ! flux(n,i) has one component, zero ghost cells, and is nodal in direction i
             call multifab_build_edge(flux(n,i),mla%la(n),1,0,i)
          end do
       end do

       ! compute the face-centered gradients in each direction
       call compute_flux(mla,phi,flux,dx,the_bc_tower)

       ! update phi using forward Euler discretization
       call update_phi(mla,phi,flux,dx,dt,the_bc_tower)

       ! make sure to destroy the multifab or you'll leak memory
       do n=1,nlevs
          do i=1,dm
             call multifab_destroy(flux(n,i))
          end do
       end do

    end if

  end subroutine advance

  subroutine compute_flux(mla,phi,flux,dx,the_bc_tower)

    type(ml_layout), intent(in   ) :: mla
    type(multifab) , intent(in   ) :: phi(:)
    type(multifab) , intent(inout) :: flux(:,:)
    real(kind=dp_t), intent(in   ) :: dx(:)
    type(bc_tower) , intent(in   ) :: the_bc_tower

    ! local variables
    integer :: lo(mla%dim), hi(mla%dim)
    integer :: dm, ng_p, ng_f, i, n, nlevs

    real(kind=dp_t), pointer ::  pp(:,:,:,:)
    real(kind=dp_t), pointer :: fxp(:,:,:,:)
    real(kind=dp_t), pointer :: fyp(:,:,:,:)
    real(kind=dp_t), pointer :: fzp(:,:,:,:)

    dm    = mla%dim
    nlevs = mla%nlevel

    ng_p = phi(1)%ng
    ng_f = flux(1,1)%ng

    do n=1,nlevs
       do i=1,nboxes(phi(n))
          if ( multifab_remote(phi(n),i) ) cycle
          pp  => dataptr(phi(n),i)
          fxp => dataptr(flux(n,1),i)
          fyp => dataptr(flux(n,2),i)
          lo = lwb(get_box(phi(n),i))
          hi = upb(get_box(phi(n),i))
          select case(dm)
          case (2)
             call compute_flux_2d(pp(:,:,1,1), ng_p, &
                                  fxp(:,:,1,1),  fyp(:,:,1,1), ng_f, &
                                  lo, hi, dx(n), &
                                  the_bc_tower%bc_tower_array(n)%adv_bc_level_array(i,:,:,1))
          case (3)
             fzp => dataptr(flux(n,3),i)
             call compute_flux_3d(pp(:,:,:,1), ng_p, &
                                  fxp(:,:,:,1),  fyp(:,:,:,1), fzp(:,:,:,1), ng_f, &
                                  lo, hi, dx(n), &
                                  the_bc_tower%bc_tower_array(n)%adv_bc_level_array(i,:,:,1))
          end select
       end do
    end do
    
    ! set level n-1 fluxes to be the average of the level n fluxes covering it
    ! the loop over nlevs must count backwards to make sure the finer grids are done first
    do n=nlevs,2,-1
       do i=1,dm
          call ml_edge_restriction_c(flux(n-1,i),1,flux(n,i),1,mla%mba%rr(n-1,:),i,1)
       end do
    end do

  end subroutine compute_flux

  subroutine compute_flux_2d(phi, ng_p, fluxx, fluxy, ng_f, lo, hi, dx, adv_bc)

    integer          :: lo(2), hi(2), ng_p, ng_f
    double precision ::   phi(lo(1)-ng_p:,lo(2)-ng_p:)
    double precision :: fluxx(lo(1)-ng_f:,lo(2)-ng_f:)
    double precision :: fluxy(lo(1)-ng_f:,lo(2)-ng_f:)
    double precision :: dx
    integer          :: adv_bc(:,:)

    ! local variables
    integer i,j

    ! x-fluxes
    !$omp parallel do private(i,j)
    do j=lo(2),hi(2)
       do i=lo(1),hi(1)+1
          fluxx(i,j) = ( phi(i,j) - phi(i-1,j) ) / dx
       end do
    end do
    !$omp end parallel do

    ! lo-x boundary conditions
    if (adv_bc(1,1) .eq. EXT_DIR) then
       i=lo(1)
       !$omp parallel do private(j)
       do j=lo(2),hi(2)
          ! divide by 0.5*dx since the ghost cell value represents
          ! the value at the wall, not the ghost cell-center
          fluxx(i,j) = ( phi(i,j) - phi(i-1,j) ) / (0.5d0*dx)
       end do
       !$omp end parallel do
    else if (adv_bc(1,1) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxx(lo(1),lo(2):hi(2)) = 0.d0
    end if

    ! hi-x boundary conditions
    if (adv_bc(1,2) .eq. EXT_DIR) then
       i=hi(1)+1
       !$omp parallel do private(j)
       do j=lo(2),hi(2)
          ! divide by 0.5*dx since the ghost cell value represents
          ! the value at the wall, not the ghost cell-center
          fluxx(i,j) = ( phi(i,j) - phi(i-1,j) ) / (0.5d0*dx)
       end do
       !$omp end parallel do
    else if (adv_bc(1,2) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxx(hi(1)+1,lo(2):hi(2)) = 0.d0
    end if

    ! y-fluxes
    !$omp parallel do private(i,j)
    do j=lo(2),hi(2)+1
       do i=lo(1),hi(1)
          fluxy(i,j) = ( phi(i,j) - phi(i,j-1) ) / dx
       end do
    end do
    !$omp end parallel do

    ! lo-y boundary conditions
    if (adv_bc(2,1) .eq. EXT_DIR) then
       j=lo(2)
       !$omp parallel do private(i)
       do i=lo(1),hi(1)
          ! divide by 0.5*dx since the ghost cell value represents
          ! the value at the wall, not the ghost cell-center
          fluxy(i,j) = ( phi(i,j) - phi(i,j-1) ) / (0.5d0*dx)
       end do
       !$omp end parallel do
    else if (adv_bc(2,1) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxy(lo(1):hi(1),lo(2)) = 0.d0
    end if

    ! hi-y boundary conditions
    if (adv_bc(2,2) .eq. EXT_DIR) then
       j=hi(2)+1
       !$omp parallel do private(i)
       do i=lo(1),hi(1)
          ! divide by 0.5*dx since the ghost cell value represents
          ! the value at the wall, not the ghost cell-center
          fluxy(i,j) = ( phi(i,j) - phi(i,j-1) ) / (0.5d0*dx)
       end do
       !$omp end parallel do
    else if (adv_bc(2,2) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxy(lo(1):hi(1),hi(2)+1) = 0.d0
    end if
    
  end subroutine compute_flux_2d

  subroutine compute_flux_3d(phi, ng_p, fluxx, fluxy, fluxz, ng_f, &
                             lo, hi, dx, adv_bc)

    integer          :: lo(3), hi(3), ng_p, ng_f
    double precision ::   phi(lo(1)-ng_p:,lo(2)-ng_p:,lo(3)-ng_p:)
    double precision :: fluxx(lo(1)-ng_f:,lo(2)-ng_f:,lo(3)-ng_f:)
    double precision :: fluxy(lo(1)-ng_f:,lo(2)-ng_f:,lo(3)-ng_f:)
    double precision :: fluxz(lo(1)-ng_f:,lo(2)-ng_f:,lo(3)-ng_f:)
    double precision :: dx
    integer          :: adv_bc(:,:)

    ! local variables
    integer i,j,k

    ! x-fluxes
    !$omp parallel do private(i,j,k)
    do k=lo(3),hi(3)
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)+1
             fluxx(i,j,k) = ( phi(i,j,k) - phi(i-1,j,k) ) / dx
          end do
       end do
    end do
    !$omp end parallel do

    ! lo-x boundary conditions
    if (adv_bc(1,1) .eq. EXT_DIR) then
       i=lo(1)
       !$omp parallel do private(j,k)
       do k=lo(3),hi(3)
          do j=lo(2),hi(2)
             ! divide by 0.5*dx since the ghost cell value represents
             ! the value at the wall, not the ghost cell-center
             fluxx(i,j,k) = ( phi(i,j,k) - phi(i-1,j,k) ) / (0.5d0*dx)
          end do
       end do
       !$omp end parallel do
    else if (adv_bc(1,1) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxx(lo(1),lo(2):hi(2),lo(3):hi(3)) = 0.d0
    end if

    ! hi-x boundary conditions
    if (adv_bc(1,2) .eq. EXT_DIR) then
       i=hi(1)+1
       !$omp parallel do private(j,k)
       do k=lo(3),hi(3)
          do j=lo(2),hi(2)
             ! divide by 0.5*dx since the ghost cell value represents
             ! the value at the wall, not the ghost cell-center
             fluxx(i,j,k) = ( phi(i,j,k) - phi(i-1,j,k) ) / (0.5d0*dx)
          end do
       end do
       !$omp end parallel do
    else if (adv_bc(1,2) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxx(hi(1)+1,lo(2):hi(2),lo(3):hi(3)) = 0.d0
    end if

    ! y-fluxes
    !$omp parallel do private(i,j,k)
    do k=lo(3),hi(3)
       do j=lo(2),hi(2)+1
          do i=lo(1),hi(1)
             fluxy(i,j,k) = ( phi(i,j,k) - phi(i,j-1,k) ) / dx
          end do
       end do
    end do
    !$omp end parallel do

    ! lo-y boundary conditions
    if (adv_bc(2,1) .eq. EXT_DIR) then
       j=lo(2)
       !$omp parallel do private(i,k)
       do k=lo(3),hi(3)
          do i=lo(1),hi(1)
             ! divide by 0.5*dx since the ghost cell value represents
             ! the value at the wall, not the ghost cell-center
             fluxy(i,j,k) = ( phi(i,j,k) - phi(i,j-1,k) ) / (0.5d0*dx)
          end do
       end do
       !$omp end parallel do
    else if (adv_bc(2,1) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxy(lo(1):hi(1),lo(2),lo(3):hi(3)) = 0.d0
    end if

    ! hi-y boundary conditions
    if (adv_bc(2,2) .eq. EXT_DIR) then
       j=hi(2)+1
       !$omp parallel do private(i,k)
       do k=lo(3),hi(3)
          do i=lo(1),hi(1)
             ! divide by 0.5*dx since the ghost cell value represents
             ! the value at the wall, not the ghost cell-center
             fluxy(i,j,k) = ( phi(i,j,k) - phi(i,j-1,k) ) / (0.5d0*dx)
          end do
       end do
       !$omp end parallel do
    else if (adv_bc(2,2) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxy(lo(1):hi(1),hi(2)+1,lo(3):hi(3)) = 0.d0
    end if

    ! z-fluxes
    !$omp parallel do private(i,j,k)
    do k=lo(3),hi(3)+1
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)
             fluxz(i,j,k) = ( phi(i,j,k) - phi(i,j,k-1) ) / dx
          end do
       end do
    end do
    !$omp end parallel do

    ! lo-z boundary conditions
    if (adv_bc(3,1) .eq. EXT_DIR) then
       k=lo(3)
       !$omp parallel do private(i,j)
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)
             ! divide by 0.5*dx since the ghost cell value represents
             ! the value at the wall, not the ghost cell-center
             fluxz(i,j,k) = ( phi(i,j,k) - phi(i,j,k-1) ) / (0.5d0*dx)
          end do
       end do
       !$omp end parallel do
    else if (adv_bc(3,1) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxz(lo(1):hi(1),lo(2):lo(3),lo(3)) = 0.d0
    end if

    ! hi-z boundary conditions
    if (adv_bc(3,2) .eq. EXT_DIR) then
       k=hi(3)+1
       !$omp parallel do private(i,j)
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)
             ! divide by 0.5*dx since the ghost cell value represents
             ! the value at the wall, not the ghost cell-center
             fluxz(i,j,k) = ( phi(i,j,k) - phi(i,j,k-1) ) / (0.5d0*dx)
          end do
       end do
       !$omp end parallel do
    else if (adv_bc(3,2) .eq. FOEXTRAP) then
       ! dphi/dn = 0
       fluxz(lo(1):hi(1),lo(2):hi(2),hi(3)+1) = 0.d0
    end if

  end subroutine compute_flux_3d

  subroutine update_phi(mla,phi,flux,dx,dt,the_bc_tower)

    type(ml_layout), intent(in   ) :: mla
    type(multifab) , intent(inout) :: phi(:)
    type(multifab) , intent(in   ) :: flux(:,:)
    real(kind=dp_t), intent(in   ) :: dx(:)
    real(kind=dp_t), intent(in   ) :: dt
    type(bc_tower) , intent(in   ) :: the_bc_tower

    ! local variables
    integer :: lo(mla%dim), hi(mla%dim)
    integer :: dm, ng_p, ng_f, i, n, nlevs

    real(kind=dp_t), pointer ::  pp(:,:,:,:)
    real(kind=dp_t), pointer :: fxp(:,:,:,:)
    real(kind=dp_t), pointer :: fyp(:,:,:,:)
    real(kind=dp_t), pointer :: fzp(:,:,:,:)

    dm    = mla%dim
    nlevs = mla%nlevel

    ng_p = phi(1)%ng
    ng_f = flux(1,1)%ng

    do n=1,nlevs

       do i=1,nboxes(phi(n))
          if ( multifab_remote(phi(n),i) ) cycle
          pp  => dataptr(phi(n),i)
          fxp => dataptr(flux(n,1),i)
          fyp => dataptr(flux(n,2),i)
          lo = lwb(get_box(phi(n),i))
          hi = upb(get_box(phi(n),i))
          select case(dm)
          case (2)
             call update_phi_2d(pp(:,:,1,1), ng_p, &
                                fxp(:,:,1,1), fyp(:,:,1,1), ng_f, &
                                lo, hi, dx(n), dt)
          case (3)
             fzp => dataptr(flux(n,3),i)
             call update_phi_3d(pp(:,:,:,1), ng_p, &
                                fxp(:,:,:,1), fyp(:,:,:,1), fzp(:,:,:,1), ng_f, &
                                lo, hi, dx(n), dt)
          end select
       end do

    end do

    if (nlevs .eq. 1) then

       ! fill ghost cells for two adjacent grids at the same level
       ! this includes periodic domain boundary ghost cells
       call multifab_fill_boundary(phi(nlevs))

       ! fill non-periodic domain boundary ghost cells
       call multifab_physbc(phi(nlevs),1,1,1,the_bc_tower%bc_tower_array(nlevs))

    else

       ! the loop over nlevs must count backwards to make sure the finer grids are done first
       do n=nlevs,2,-1
          ! set level n-1 data to be the average of the level n data covering it
          call ml_cc_restriction(phi(n-1),phi(n),mla%mba%rr(n-1,:))

          ! fill level n ghost cells using interpolation from level n-1 data
          ! note that multifab_fill_boundary and multifab_physbc are called for
          ! both levels n-1 and n
          call multifab_fill_ghost_cells(phi(n),phi(n-1),ng_p,mla%mba%rr(n-1,:), &
                                         the_bc_tower%bc_tower_array(n-1), &
                                         the_bc_tower%bc_tower_array(n), &
                                         1,1,1)
       end do

    end if

  end subroutine update_phi

  subroutine update_phi_2d(phi, ng_p, fluxx, fluxy, ng_f, lo, hi, dx, dt)

    integer          :: lo(2), hi(2), ng_p, ng_f
    double precision ::   phi(lo(1)-ng_p:,lo(2)-ng_p:)
    double precision :: fluxx(lo(1)-ng_f:,lo(2)-ng_f:)
    double precision :: fluxy(lo(1)-ng_f:,lo(2)-ng_f:)
    double precision :: dx, dt

    ! local variables
    integer i,j

    !$omp parallel do private(i,j)
    do j=lo(2),hi(2)
       do i=lo(1),hi(1)

          phi(i,j) = phi(i,j) + dt * &
               ( fluxx(i+1,j)-fluxx(i,j) + fluxy(i,j+1)-fluxy(i,j) ) / dx

       end do
    end do
    !$omp end parallel do

  end subroutine update_phi_2d

  subroutine update_phi_3d(phi, ng_p, fluxx, fluxy, fluxz, ng_f, lo, hi, dx, dt)

    integer          :: lo(3), hi(3), ng_p, ng_f
    double precision ::   phi(lo(1)-ng_p:,lo(2)-ng_p:,lo(3)-ng_p:)
    double precision :: fluxx(lo(1)-ng_f:,lo(2)-ng_f:,lo(3)-ng_f:)
    double precision :: fluxy(lo(1)-ng_f:,lo(2)-ng_f:,lo(3)-ng_f:)
    double precision :: fluxz(lo(1)-ng_f:,lo(2)-ng_f:,lo(3)-ng_f:)
    double precision :: dx, dt

    ! local variables
    integer i,j,k

    !$omp parallel do private(i,j,k)
    do k=lo(3),hi(3)
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)

             phi(i,j,k) = phi(i,j,k) + dt * &
                  ( fluxx(i+1,j,k)-fluxx(i,j,k) &
                   +fluxy(i,j+1,k)-fluxy(i,j,k) &
                   +fluxz(i,j,k+1)-fluxz(i,j,k) ) / dx

          end do
       end do
    end do
    !$omp end parallel do

  end subroutine update_phi_3d

end module advance_module

