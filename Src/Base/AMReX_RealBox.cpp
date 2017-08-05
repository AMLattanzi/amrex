
#include <iostream>
#include <string>

#include <AMReX_RealBox.H>
#include <AMReX_CArena.H>

namespace amrex {

#ifdef AMREX_USE_CUDA
int RealBox_init::m_cnt = 0;

namespace
{
    Arena* the_realbox_arena = 0;
}

RealBox_init::RealBox_init ()
{
    if (m_cnt++ == 0)
    {
        BL_ASSERT(the_realbox_arena == 0);

        const std::size_t hunk_size = 64 * 1024;

        the_realbox_arena = new CArena(hunk_size);

	the_realbox_arena->SetHostAlloc();
    }
}

RealBox_init::~RealBox_init ()
{
    if (--m_cnt == 0)
        delete the_realbox_arena;
}

Arena*
The_RealBox_Arena ()
{
    BL_ASSERT(the_realbox_arena != 0);

    return the_realbox_arena;
}
#endif

//
// The definition of lone static data member.
//
Real RealBox::eps = 1.0e-8;

RealBox::RealBox (const Box&  bx,
                  const Real* dx,
                  const Real* base)
{
    const int* lo = bx.loVect();
    const int* hi = bx.hiVect();
    for (int i = 0; i < BL_SPACEDIM; i++)
    {
        xlo[i] = base[i] + dx[i]*lo[i];
        int shft = (bx.type(i) == IndexType::CELL ? 1 : 0);
        xhi[i] = base[i] + dx[i]*(hi[i]+ shft);
    }
    nullify_device_memory();
}

RealBox::RealBox ()
{
    AMREX_D_TERM(xlo[0] , = xlo[1] , = xlo[2] ) = 0.;
    AMREX_D_TERM(xhi[0] , = xhi[1] , = xhi[2] ) = -1.;
    nullify_device_memory();
}

RealBox::RealBox (const Real* lo,
                  const Real* hi)
{
    AMREX_D_EXPR(xlo[0] = lo[0] , xlo[1] = lo[1] , xlo[2] = lo[2]);
    AMREX_D_EXPR(xhi[0] = hi[0] , xhi[1] = hi[1] , xhi[2] = hi[2]);
    nullify_device_memory();
}

RealBox::RealBox (const std::array<Real,BL_SPACEDIM>& lo,
                  const std::array<Real,BL_SPACEDIM>& hi)
{
    AMREX_D_EXPR(xlo[0] = lo[0] , xlo[1] = lo[1] , xlo[2] = lo[2]);
    AMREX_D_EXPR(xhi[0] = hi[0] , xhi[1] = hi[1] , xhi[2] = hi[2]);
    nullify_device_memory();
}

RealBox::RealBox (AMREX_D_DECL(Real x0, Real y0, Real z0),
                  AMREX_D_DECL(Real x1, Real y1, Real z1))
{
    AMREX_D_EXPR(xlo[0] = x0 , xlo[1] = y0 , xlo[2] = z0);
    AMREX_D_EXPR(xhi[0] = x1 , xhi[1] = y1 , xhi[2] = z1);
    nullify_device_memory();
}

void
RealBox::nullify_device_memory() const
{
#ifdef AMREX_USE_CUDA
    xlo_d = nullptr;
    xhi_d = nullptr;
#endif
}

void
RealBox::initialize_device_memory() const
{
#ifdef AMREX_USE_CUDA
    initialize_lo();
    initialize_hi();
#endif
}

void
RealBox::initialize_lo() const
{
#ifdef AMREX_USE_CUDA
    const size_t sz = 3 * sizeof(Real);

    Real* xlo_temp = static_cast<Real*>(amrex::The_RealBox_Arena()->alloc(sz));
    xlo_d.reset(xlo_temp, [](Real* ptr) { amrex::The_RealBox_Arena()->free(ptr); });
    copy_xlo();
#endif
}

void
RealBox::initialize_hi() const
{
#ifdef AMREX_USE_CUDA
    const size_t sz = 3 * sizeof(Real);

    Real* xhi_temp = static_cast<Real*>(amrex::The_RealBox_Arena()->alloc(sz));
    xhi_d.reset(xhi_temp, [](Real* ptr) { amrex::The_RealBox_Arena()->free(ptr); });
    copy_xhi();
#endif
}

void
RealBox::copy_device_memory() const
{
  copy_xlo();
  copy_xhi();
}

void
RealBox::copy_xlo() const
{
#ifdef AMREX_USE_CUDA
    for (int i = 0; i < BL_SPACEDIM; ++i)
	xlo_d.get()[i] = xlo[i];
    for (int i = BL_SPACEDIM; i < 3; ++i)
	xlo_d.get()[i] = 0;
#endif
}

void
RealBox::copy_xhi() const
{
#ifdef AMREX_USE_CUDA
    for (int i = 0; i < BL_SPACEDIM; ++i)
	xhi_d.get()[i] = xhi[i];
    for (int i = BL_SPACEDIM; i < 3; ++i)
	xhi_d.get()[i] = 0;
#endif
}

const Real*
RealBox::loF() const& {
#ifdef AMREX_USE_CUDA
    if (xlo_d.get() == nullptr)
        initialize_lo();

    return (Real*) Device::get_host_pointer(xlo_d.get());
#else
    return xlo;
#endif
}

const Real*
RealBox::hiF() const& {
#ifdef AMREX_USE_CUDA
    if (xhi_d.get() == nullptr)
        initialize_hi();

    return (Real*) Device::get_host_pointer(xhi_d.get());
#else
    return xhi;
#endif
}

bool
RealBox::contains (const RealBox& rb) const
{
    return contains(rb.xlo) && contains(rb.xhi);
}

bool
RealBox::ok () const
{
    return (length(0) > eps)
#if (BL_SPACEDIM > 1)
        && (length(1) > eps)
#endif   
#if (BL_SPACEDIM > 2)
        && (length(2) > eps)
#endif
   ;
}

bool
RealBox::contains (const Real* point) const
{
    return  AMREX_D_TERM((xlo[0]-eps < point[0]) && (point[0] < xhi[0]+eps),
                   && (xlo[1]-eps < point[1]) && (point[1] < xhi[1]+eps),
                   && (xlo[2]-eps < point[2]) && (point[2] < xhi[2]+eps));
}

std::ostream&
operator << (std::ostream &os, const RealBox& b)
{
    os << "(RealBox ";
    for (int i = 0; i < BL_SPACEDIM; i++)
        os << b.lo(i) << ' ' << b.hi(i) << ' ';
    os << ')';
    return os;
}

//
// Copied from <Utility.H>
//
#define BL_IGNORE_MAX 100000

std::istream&
operator >> (std::istream &is, RealBox& b)
{
    is.ignore(BL_IGNORE_MAX,'(');

    std::string s;

    is >> s;

    if (s != "RealBox")
    {
        std::cerr << "unexpected token in RealBox: " << s << '\n';
        amrex::Abort();
    }

    Real lo[BL_SPACEDIM];
    Real hi[BL_SPACEDIM];
#ifdef BL_USE_FLOAT
    double dlotemp, dhitemp;
    for (int i = 0; i < BL_SPACEDIM; i++) {
        is >> dlotemp >> dhitemp;
        lo[i] = dlotemp;
        hi[i] = dhitemp;
    }
#else
    for (int i = 0; i < BL_SPACEDIM; i++)
        is >> lo[i] >> hi[i];
#endif

    is.ignore(BL_IGNORE_MAX, ')');

    b = RealBox(lo,hi);

    return is;
}

}
