#ifndef AMREX_FFT_POISSON_H_
#define AMREX_FFT_POISSON_H_

#include <AMReX_FFT.H>
#include <AMReX_Geometry.H>

namespace amrex::FFT
{

/**
 * \brief Poisson solver for all periodic boundaries using FFT
 */
template <typename MF>
class Poisson
{
public:

    template <typename FA=MF, std::enable_if_t<IsFabArray_v<FA>,int> = 0>
    explicit Poisson (Geometry const& geom)
        : m_geom(geom), m_r2c(geom.Domain())
    {
        AMREX_ALWAYS_ASSERT(geom.isAllPeriodic());
    }

    void solve (MF& soln, MF const& rhs);

private:
    Geometry m_geom;
    R2C<typename MF::value_type, Direction::both> m_r2c;
};

/**
 * \brief 3D Poisson solver for periodic boundaries in the first two
 * dimensions and Neumann in the last dimension.
 */
template <typename MF>
class PoissonHybrid
{
public:

    template <typename FA=MF, std::enable_if_t<IsFabArray_v<FA>,int> = 0>
    explicit PoissonHybrid (Geometry const& geom)
        : m_geom(geom), m_r2c(geom.Domain(), Info().setBatchMode(true))
    {
#if (AMREX_SPACEDIM == 3)
        AMREX_ALWAYS_ASSERT(geom.isPeriodic(0) && geom.isPeriodic(1));
#else
        amrex::Abort("FFT::PoissonHybrid: 1D & 2D todo");
#endif
    }

    void solve (MF& soln, MF const& rhs);

private:
    Geometry m_geom;
    R2C<typename MF::value_type, Direction::both> m_r2c;
};

template <typename MF>
void Poisson<MF>::solve (MF& soln, MF const& rhs)
{
    using T = typename MF::value_type;

    GpuArray<T,AMREX_SPACEDIM> fac
        {AMREX_D_DECL(T(2)*Math::pi<T>()/T(m_geom.ProbLength(0)),
                      T(2)*Math::pi<T>()/T(m_geom.ProbLength(1)),
                      T(2)*Math::pi<T>()/T(m_geom.ProbLength(2)))};
    GpuArray<T,AMREX_SPACEDIM> dx
        {AMREX_D_DECL(T(m_geom.CellSize(0)),
                      T(m_geom.CellSize(1)),
                      T(m_geom.CellSize(2)))};
    auto scale = T(1.0/m_geom.Domain().d_numPts());
#if (AMREX_SPACEDIM > 1)
    auto const& len = m_geom.Domain().length();
#endif

    m_r2c.forwardThenBackward(rhs, soln,
                              [=] AMREX_GPU_DEVICE (int i, int j, int k,
                                                    GpuComplex<T>& spectral_data)
    {
        amrex::ignore_unused(i,j,k);
        // the values in the upper-half of the spectral array in y and z
        // are here interpreted as negative wavenumbers
        AMREX_D_TERM(T a = fac[0]*i;,
                     T b = (j < len[1]/2) ? fac[1]*j : fac[1]*(len[1]-j);,
                     T c = (k < len[2]/2) ? fac[2]*k : fac[2]*(len[2]-k));
        T k2 = AMREX_D_TERM(T(2)*(std::cos(a*dx[0])-T(1))/(dx[0]*dx[0]),
                           +T(2)*(std::cos(b*dx[1])-T(1))/(dx[1]*dx[1]),
                           +T(2)*(std::cos(c*dx[2])-T(1))/(dx[2]*dx[2]));
        if (k2 != T(0)) {
            spectral_data /= k2;
        } else {
            // interpretation here is that the average value of the
            // solution is zero
            spectral_data = 0;
        }
        spectral_data *= scale;
    });
}

template <typename MF>
void PoissonHybrid<MF>::solve (MF& soln, MF const& rhs)
{
#if (AMREX_SPACEDIM < 3)
    amrex::ignore_unused(soln, rhs);
#else
    using T = typename MF::value_type;

    auto facx = T(2)*Math::pi<T>()/T(m_geom.ProbLength(0));
    auto facy = T(2)*Math::pi<T>()/T(m_geom.ProbLength(1));
    auto dx = T(m_geom.CellSize(0));
    auto dy = T(m_geom.CellSize(1));
    auto scale = T(1.0)/(T(m_geom.Domain().length(0)) *
                         T(m_geom.Domain().length(1)));
    auto ny = m_geom.Domain().length(1);
    auto nz = m_geom.Domain().length(2);

    Gpu::DeviceVector<T> delzv(nz, T(m_geom.CellSize(2)));
    auto const* delz = delzv.data();

    Box cdomain = m_geom.Domain();
    cdomain.setBig(0,cdomain.length(0)/2);
    auto cba = amrex::decompose(cdomain, ParallelContext::NProcsSub(),
                                {AMREX_D_DECL(true,true,false)});
    DistributionMapping dm = detail::make_iota_distromap(cba.size());
    FabArray<BaseFab<GpuComplex<T> > > spmf(cba, dm, 1, 0);

    m_r2c.forward(rhs, spmf);

    for (MFIter mfi(spmf); mfi.isValid(); ++mfi)
    {
        auto const& spectral = spmf.array(mfi);
        auto const& box = mfi.validbox();
        auto const& xybox = amrex::makeSlab(box, 2, 0);

#ifdef AMREX_USE_GPU
        // xxxxx TODO: We need to explore how to optimize this
        // function. Maybe we can use cusparse. Maybe we should make
        // z-direction to be the unit stride direction.

        FArrayBox tridiag_workspace(box,4);
        auto const& ald = tridiag_workspace.array(0);
        auto const& bd = tridiag_workspace.array(1);
        auto const& cud = tridiag_workspace.array(2);
        auto const& scratch = tridiag_workspace.array(3);

        amrex::ParallelFor(xybox, [=] AMREX_GPU_DEVICE (int i, int j, int)
        {
            T a = facx*i;
            T b = (j < ny/2) ? facy*j : facy*(ny-j);

            T k2 = T(2)*(std::cos(a*dx)-T(1))/(dx*dx)
                +  T(2)*(std::cos(b*dy)-T(1))/(dy*dy);

            // Tridiagonal solve with homogeneous Neumann
            for(int k=0; k < nz; k++) {
                if(k==0) {
                    ald(i,j,k) = 0.;
                    cud(i,j,k) = 2.0 /(delz[k]*(delz[k]+delz[k+1]));
                    bd(i,j,k) = k2 -ald(i,j,k)-cud(i,j,k);
                } else if (k == nz-1) {
                    ald(i,j,k) = 2.0 /(delz[k]*(delz[k]+delz[k-1]));
                    cud(i,j,k) = 0.;
                    bd(i,j,k) = k2 -ald(i,j,k)-cud(i,j,k);
                    if (i == 0 && j == 0) {
                        bd(i,j,k) *= 2.0;
                    }
                } else {
                    ald(i,j,k) = 2.0 /(delz[k]*(delz[k]+delz[k-1]));
                    cud(i,j,k) = 2.0 /(delz[k]*(delz[k]+delz[k+1]));
                    bd(i,j,k) = k2 -ald(i,j,k)-cud(i,j,k);
                }
            }

            scratch(i,j,0) = cud(i,j,0)/bd(i,j,0);
            spectral(i,j,0) = spectral(i,j,0)/bd(i,j,0);

            for (int k = 1; k < nz; k++) {
                if (k < nz-1) {
                    scratch(i,j,k) = cud(i,j,k) / (bd(i,j,k) - ald(i,j,k) * scratch(i,j,k-1));
                }
                spectral(i,j,k) = (spectral(i,j,k) - ald(i,j,k) * spectral(i,j,k - 1))
                    / (bd(i,j,k) - ald(i,j,k) * scratch(i,j,k-1));
            }

            for (int k = nz - 2; k >= 0; k--) {
                spectral(i,j,k) -= scratch(i,j,k) * spectral(i,j,k + 1);
            }

            for (int k = 0; k < nz; ++k) {
                spectral(i,j,k) *= scale;
            }
        });
        Gpu::streamSynchronize();

#else

        Gpu::DeviceVector<GpuComplex<Real>> ald(nz);
        Gpu::DeviceVector<GpuComplex<Real>> bd(nz);
        Gpu::DeviceVector<GpuComplex<Real>> cud(nz);
        Gpu::DeviceVector<GpuComplex<Real>> scratch(nz);

        amrex::LoopOnCpu(xybox, [&] (int i, int j, int)
        {
            T a = facx*i;
            T b = (j < ny/2) ? facy*j : facy*(ny-j);

            T k2 = T(2)*(std::cos(a*dx)-T(1))/(dx*dx)
                +  T(2)*(std::cos(b*dy)-T(1))/(dy*dy);

            // Tridiagonal solve with homogeneous Neumann
            for(int k=0; k < nz; k++) {
                if(k==0) {
                    ald[k] = 0.;
                    cud[k] = 2.0 /(delz[k]*(delz[k]+delz[k+1]));
                    bd[k] = k2 -ald[k]-cud[k];
                } else if (k == nz-1) {
                    ald[k] = 2.0 /(delz[k]*(delz[k]+delz[k-1]));
                    cud[k] = 0.;
                    bd[k] = k2 -ald[k]-cud[k];
                    if (i == 0 && j == 0) {
                        bd[k] *= 2.0;
                    }
                } else {
                    ald[k] = 2.0 /(delz[k]*(delz[k]+delz[k-1]));
                    cud[k] = 2.0 /(delz[k]*(delz[k]+delz[k+1]));
                    bd[k] = k2 -ald[k]-cud[k];
                }
            }

            scratch[0] = cud[0]/bd[0];
            spectral(i,j,0) = spectral(i,j,0)/bd[0];

            for (int k = 1; k < nz; k++) {
                if (k < nz-1) {
                    scratch[k] = cud[k] / (bd[k] - ald[k] * scratch[k-1]);
                }
                spectral(i,j,k) = (spectral(i,j,k) - ald[k] * spectral(i,j,k - 1))
                    / (bd[k] - ald[k] * scratch[k-1]);
            }

            for (int k = nz - 2; k >= 0; k--) {
                spectral(i,j,k) -= scratch[k] * spectral(i,j,k + 1);
            }

            for (int k = 0; k < nz; ++k) {
                spectral(i,j,k) *= scale;
            }
        });
#endif
    }

    m_r2c.backward(spmf, soln);
#endif
}

}

#endif
