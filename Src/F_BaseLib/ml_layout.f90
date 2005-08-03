module ml_layout_module

  use layout_module
  use multifab_module
  use ml_boxarray_module

  implicit none

  type ml_layout
     integer :: dim = 0
     integer :: nlevel = 0
     type(ml_boxarray) :: mba
     type(layout)   , pointer ::    la(:) => Null()
     type(lmultifab), pointer ::  mask(:) => Null() ! cell-centered mask
     logical        , pointer :: pmask(:) => Null() ! periodic mask
  end type ml_layout

  interface build
     module procedure ml_layout_build
  end interface
  interface destroy
     module procedure ml_layout_destroy
  end interface

  interface operator(.eq.)
     module procedure ml_layout_equal
  end interface
  interface operator(.ne.)
     module procedure ml_layout_not_equal
  end interface

  interface nlevels
     module procedure ml_layout_nlevels
  end interface


contains

  function ml_layout_nlevels(mla) result(r)
    integer :: r
    type(ml_layout), intent(in) :: mla
    r = mla%nlevel
  end function ml_layout_nlevels

  function ml_layout_equal(mla1, mla2) result(r)
    logical :: r
    type(ml_layout), intent(in) :: mla1, mla2
    r = associated(mla1%la, mla2%la)
  end function ml_layout_equal
  
  function ml_layout_not_equal(mla1, mla2) result(r)
    logical :: r
    type(ml_layout), intent(in) :: mla1, mla2
    r = .not. associated(mla1%la, mla2%la)
  end function ml_layout_not_equal

  function ml_layout_get_layout(mla, n) result(r)
    type(layout) :: r
    type(ml_layout), intent(in) :: mla
    integer, intent(in) :: n
    r = mla%la(n)
  end function ml_layout_get_layout

  function ml_layout_get_pd(mla, n) result(r)
    type(box) :: r
    type(ml_layout), intent(in) :: mla
    integer, intent(in) :: n
    r = ml_boxarray_get_pd(mla%mba, n)
  end function ml_layout_get_pd

  subroutine ml_layout_build(mla, mba, pmask)
    type(ml_layout), intent(inout) :: mla
    type(ml_boxarray), intent(in) :: mba
    logical, optional :: pmask(:)

    type(boxarray) :: bac
    integer :: n
    logical :: lpmask(mba%dim)

    lpmask = .false.; if (present(pmask)) lpmask = pmask
    allocate(mla%pmask(mba%dim))
    mla%pmask  = lpmask

    mla%nlevel = mba%nlevel
    mla%dim    = mba%dim
    call copy(mla%mba, mba)
    allocate(mla%la(mla%nlevel))
    allocate(mla%mask(mla%nlevel-1))
    call build(mla%la(1), mba%bas(1),pmask=lpmask)
    do n = 2, mba%nlevel
       call layout_build_pn(mla%la(n), mla%la(n-1), mba%bas(n), mba%rr(n-1,:))
    end do
    do n = mba%nlevel-1,  1, -1
       call lmultifab_build(mla%mask(n), mla%la(n), nc = 1, ng = 0)
       call setval(mla%mask(n), val = .TRUE.)
       call copy(bac, mba%bas(n+1))
       call boxarray_coarsen(bac, mba%rr(n,:))
       call setval(mla%mask(n), .false., bac)
       call destroy(bac)
    end do
  end subroutine ml_layout_build

  subroutine ml_layout_build_la(mla, la)
    type(ml_layout), intent(inout) :: mla
    type(layout), intent(inout) :: la(:)
    integer :: n
    type(boxarray) :: bac
    if ( size(la) == 0 ) then
       call bl_error("ML_LAYOUT_BUILD_LA: la array is empty!")
    end if
    mla%dim = layout_dim(la(1))
    mla%nlevel = size(la)

    allocate(mla%pmask(mla%dim))
    mla%pmask = get_pmask(la(1))
    do n = 1, mla%nlevel
       if ( any( mla%pmask .neqv. get_pmask(la(n))) ) then
          call bl_error("ML_LAYOUT_BUILD_LA: inconsistent pmask")
       end if
    end do

    ! copy the
    call build(mla%mba, mla%nlevel, mla%dim)
    do n = 1, mla%nlevel
       call copy(mla%mba%bas(n), get_boxarray(la(n)))
       mla%mba%pd(n) = get_pd(la(n))
       if ( n == 1 ) cycle
       mla%mba%rr(n-1,:) = extent(mla%mba%pd(n))/extent(mla%mba%pd(n-1))
    end do

    ! transfer the layouts...
    allocate(mla%la(mla%nlevel))
    do n = 1, mla%nlevel
       mla%la(n) = la(n)
    end do

    ! build the pmasks...
    allocate(mla%mask(mla%nlevel-1))
    do n = mla%nlevel-1, 1, -1
       call lmultifab_build(mla%mask(n), mla%la(n), nc = 1, ng = 0)
       call setval(mla%mask(n), val = .true.)
       call copy(bac, mla%mba%bas(n+1))
       call boxarray_coarsen(bac, mla%mba%rr(n,:))
       call setval(mla%mask(n), .false., bac)
       call destroy(bac)
    end do

  end subroutine ml_layout_build_la

  subroutine ml_layout_destroy(mla)
    type(ml_layout), intent(inout) :: mla
    integer :: n
    do n = 1, mla%nlevel-1
       call destroy(mla%mask(n))
    end do
    call destroy(mla%mba)
    !
    ! Recall that we need only delete the coarsest level layout
    ! since it 'owns' the refined levels.
    !
    call destroy(mla%la(1))
    deallocate(mla%la, mla%mask)
    mla%dim = 0
    mla%nlevel = 0
    deallocate(mla%pmask)
  end subroutine ml_layout_destroy

end module ml_layout_module
