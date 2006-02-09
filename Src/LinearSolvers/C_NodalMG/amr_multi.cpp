#include <winstd.H>

#include <iostream>

#include <cmath>

#include "amr_multi.H"

#include <Profiler.H>

//#if BL_SPACEDIM==2
//int amr_multigrid::c_sys = 0; // default is Cartesian, 1 is RZ
//#endif

#if defined( BL_FORT_USE_UNDERSCORE )
#define FORT_FILL_INIT    hgfinit_
#elif defined( BL_FORT_USE_UPPERCASE )
#define FORT_FILL_INIT    HGFINIT
#elif defined( BL_FORT_USE_LOWERCASE )
#define FORT_FILL_INIT    hgfinit
#else
#error "none of BL_FORT_USE_{UNDERSCORE,UPPERCASE,LOWERCASE} defined"
#endif

extern "C"
{
  void FORT_FILL_INIT(Real*, const int*, const int*, const int*, const int*, const int*);
}

void
MF_FILL_INIT (MultiFab& mf)
{
  for (MFIter mfi(mf); mfi.isValid(); ++mfi)
    {
      Box bx = mfi.validbox();
      int nc = mf.nComp();
      FArrayBox& f = mf[mfi];
      FORT_FILL_INIT(
		     f.dataPtr(), f.loVect(), f.hiVect(), &nc,
		     bx.loVect(), bx.hiVect());
    }
}



#ifdef HG_DEBUG
static
Real
mfnorm_0 (const MultiFab& mf)
{
    Real r = 0;
    for (MFIter cmfi(mf); cmfi.isValid(); ++cmfi)
    {
	Real s = mf[cmfi].norm(mf[cmfi].box(), 0, 0, mf[cmfi].nComp());
	r = (r > s) ? r : s;
    }
    ParallelDescriptor::ReduceRealMax(r);
    return r;
}

static
Real
mfnorm_2 (const MultiFab& mf)
{
    Real r = 0;
    for (MFIter cmfi(mf); cmfi.isValid(); ++cmfi)
    {
	Real s = mf[cmfi].norm(mf[cmfi].box(), 2, 0, mf[cmfi].nComp());
	r += s*s;
    }
    ParallelDescriptor::ReduceRealSum(r);
    return std::sqrt(r);
}

static
Real
mfnorm_0_valid (const MultiFab& mf)
{
    Real r = 0;
    for (MFIter cmfi(mf); cmfi.isValid(); ++cmfi)
    {
	Real s = mf[cmfi].norm(cmfi.validbox(), 0, 0, mf[cmfi].nComp());
	r = (r > s) ? r : s;
    }
    ParallelDescriptor::ReduceRealMax(r);
    return r;
}

static
Real
mfnorm_2_valid (const MultiFab& mf)
{
    Real r = 0;
    for (MFIter cmfi(mf); cmfi.isValid(); ++cmfi)
    {
	Real s = mf[cmfi].norm(cmfi.validbox(), 2, 0, mf[cmfi].nComp());
	r += s*s;
    }
    ParallelDescriptor::ReduceRealSum(r);
    return std::sqrt(r);
}

static
const char*
mf_centeredness (const MultiFab& m)
{
    if (type(m) == IntVect::TheCellVector()) return "C";
    if (type(m) == IntVect::TheNodeVector()) return "N";
    return "?";
}

void
hg_debug_norm_2 (const MultiFab& d,
                 const char*     str1,
                 const char*     str2)
{
    double dz[4] = { mfnorm_2(d), mfnorm_2_valid(d),
		     mfnorm_0(d), mfnorm_0_valid(d)};
    debug_out << str1;
    if (ParallelDescriptor::IOProcessor())
    {
	debug_out << " : Norm[" << d.size() << ","
	<< mf_centeredness(d) << ","
	<< d.nComp() << ","
	<< d.nGrow() << "]( " << str2 << " ) = ("
	<< dz[0] << "/" << dz[1] << ", "
	<< dz[2] << "/" << dz[3] << " )";
    }
    debug_out << std::endl;

}
#endif

//
// Norm helper function:
//

static
Real
mfnorm (const MultiFab& mf)
{
    Real r = 0;
    BL_ASSERT(mf.nComp() == 1);
    for (MFIter cmfi(mf); cmfi.isValid(); ++cmfi)
    {
	Real s = mf[cmfi].norm(0);
	r = (r > s) ? r : s;
    }
    ParallelDescriptor::ReduceRealMax(r);
    return r;
}

amr_multigrid::CoordSys
amr_multigrid::setCoordSys (CoordSys c_sys_)
{
    CoordSys o_c_sys = c_sys;
    c_sys = c_sys_;
    return o_c_sys;
}

amr_multigrid::CoordSys
amr_multigrid::getCoordSys () const
{
    return c_sys;
}

int
amr_multigrid::get_amr_level (int mglev) const
{
  int result = -1;
  for (int i = lev_min; i <= lev_max; i++)
    {
      if (ml_index[i] == mglev)
	{
	  result = i;
	  break;
	}
    }
  return result;
}

amr_multigrid::amr_multigrid (const Array<BoxArray>&    Mesh,
			      const Array<IntVect>&     Gen_ratio,
			      int                       Lev_min_min,
			      int                       Lev_min_max,
			      int                       Lev_max_max,
			      const amr_boundary* Boundary,
			      int                       Pcode)
  : ml_mesh(Mesh),
    gen_ratio(Gen_ratio),
    lev_min_min(Lev_min_min),
    lev_min_max(Lev_min_max),
    lev_max_max(Lev_max_max),
    mg_boundary(Boundary),
    pcode(Pcode),
    integrate(0),
    c_sys(cartesian)
{}

void
amr_multigrid::mesh_read (Array<BoxArray>& m,
                          Array<IntVect>&  r,
                          Array<Box>&      d,
                          std::istream&    is)
{
    int ilev;
    is >> ilev;
    m.resize(ilev);
    r.resize(ilev-1);
    d.resize(ilev);
    for (int ilev = 0; ilev < m.size(); ilev++)
    {
	Box b;
	int igrid;
	is >> b >> igrid;
	if (is.fail())
	{
	    BoxLib::Abort("amr_multigrid::mesh_read(): failed to read box");
	}
	d.set(ilev, b);
	if (ilev > 0)
	{
	    r.set(ilev-1, d[ilev].length() / d[ilev-1].length());
	}
	m[ilev].resize(igrid);
	for (int igrid = 0; igrid < m[ilev].size(); igrid++)
	{
	    is >> b;
	    if (is.fail())
	    {
                BoxLib::Abort("amr_multigrid::mesh_read(): failed to read box");
	    }
	    m[ilev].set(igrid, b);
	}
    }
}

void
amr_multigrid::mesh_write (const Array<BoxArray>& m,
                           const Array<Box>&      d,
                           std::ostream&          os)
{
    os << m.size() << std::endl;
    for (int ilev = 0; ilev < m.size(); ilev++)
    {
	os << "    " << d[ilev] << " " << m[ilev].size() << std::endl;
	for (int igrid = 0; igrid < m[ilev].size(); igrid++)
	{
	    os << '\t' << m[ilev][igrid] << std::endl;
	}
    }
}

void
amr_multigrid::mesh_write (const Array<BoxArray>& m,
                           const Array<IntVect>&  r,
                           Box                    fd,
                           std::ostream&          os)
{
    for (int ilev = m.size() - 2; ilev >= 0; ilev--)
    {
	fd.coarsen(r[ilev]);
    }
    os << m.size() << std::endl;
    for (int ilev = 0; ilev < m.size(); ilev++)
    {
	os << "    " << fd << " " << m[ilev].size() << std::endl;
	for (int igrid = 0; igrid < m[ilev].size(); igrid++)
	{
	    os << '\t' << m[ilev][igrid] << std::endl;
	}
	if (ilev <= m.size() - 2)
	{
	    fd.refine(r[ilev]);
	}
    }
}

amr_multigrid::~amr_multigrid ()
{
    //
    // Note: lev_min is a class member.
    //
    for (lev_min = lev_min_min; lev_min <= lev_min_max; lev_min++)
    {
	delete [] interface_array[lev_min - lev_min_min];
    }
    delete [] interface_array;
}

void
amr_multigrid::build_mesh (const Box& fdomain)
{
    mg_domain_array.resize(lev_min_max + 1);
    mg_mesh_array.resize(lev_min_max + 1);
    interface_array = new level_interface*[lev_min_max - lev_min_min + 1];

    if (pcode >= 2 && ParallelDescriptor::IOProcessor())
    {
	mesh_write(ml_mesh, gen_ratio, fdomain, std::cout);
    }

    lev_max = lev_max_max;
    for (lev_min = lev_min_min; lev_min <= lev_min_max; lev_min++)
    {
        //
	// first, build mg_mesh
        //
	int nlev =
	    build_down(ml_mesh[lev_max], fdomain,
		       lev_max, IntVect::TheUnitVector(), 0);
#ifndef NDEBUG
	for (int i = 0; i < mg_mesh.size(); i++)
	    BL_ASSERT(mg_mesh[i].ok());
#endif

	if (pcode >= 2 && ParallelDescriptor::IOProcessor())
	{
	    mesh_write(mg_mesh, mg_domain, std::cout);
	}

	mg_domain_array.set(lev_min, mg_domain);
	mg_mesh_array.set(lev_min, mg_mesh);
	//
	// Initialize lev_interface.
	//
	int ldiff, mglev_common = mg_mesh.size();
	if (lev_min > lev_min_min)
	{
	    ldiff = mg_mesh_array[lev_min - 1].size() - mg_mesh.size();
	    //
	    // ml_index here is still the index for the previous mg_mesh:
            //
	    mglev_common = ml_index[lev_min] - ldiff;
	    /*
	    Before IntVect refinement ratios we used

	      mglev_common = ml_index[lev_min - 1] + 1 - ldiff;

		This can no longer be counted on to work since in a (4,1) case
		the intermediate levels no longer match.
	    */
	    mglev_common = (mglev_common > 0) ? mglev_common : 0;
	}
	//
	// ml_index now becomes the index for the current mg_mesh,
	// will be used below and on the next loop:
	build_index();

	const int imgl = mg_mesh.size();
	lev_interface = new level_interface[imgl];

	for (int mglev = mg_mesh.size() - 1, lev = lev_max + 1;
	     mglev >= 0; mglev--)
	{
	    if (lev > lev_min && mglev == ml_index[lev - 1])
	    {
		lev--;
	    }
	    if (mglev >= mglev_common)
	    {
		lev_interface[mglev].copy(
		    interface_array[lev_min - 1 - lev_min_min][mglev+ldiff]);
	    }
	    else
	    {
		if (mglev == ml_index[lev])
		{
		    lev_interface[mglev].alloc(
			mg_mesh[mglev], mg_domain[mglev], mg_boundary);
		}
		else
		{
		    IntVect rat = mg_domain[mglev+1].length()
			/ mg_domain[mglev].length();
		    lev_interface[mglev].alloc_coarsened(
			mg_mesh[mglev], mg_boundary,
			lev_interface[mglev + 1], rat);
		}
	    }
	}
	interface_array[lev_min - lev_min_min] = lev_interface;
    }
}

void
amr_multigrid::build_index ()
{
    ml_index.resize(lev_max + 1);
    for (int i = 0, lev = lev_min; lev <= lev_max; i++)
    {
	if (mg_mesh[i] == ml_mesh[lev])
	{
	    ml_index[lev] = i;
	    lev++;
	}
    }
}

int
amr_multigrid::build_down (const BoxArray& l_mesh,
                           const Box&      l_domain,
                           int             flev,
                           IntVect         rat,
                           int             nlev)
{
    if (l_mesh.size() == 0)
    {
	mg_mesh.resize(nlev);
	mg_domain.resize(nlev);
	nlev = 0;
    }
    else
    {
	nlev++;
	BoxArray c_mesh = l_mesh;
	Box c_domain = l_domain;
	make_coarser_level(c_mesh, c_domain, flev, rat);
	nlev = build_down(c_mesh, c_domain, flev, rat, nlev);
	mg_mesh.set(nlev, l_mesh);
	mg_domain.set(nlev, l_domain);
	nlev++;
    }
    return nlev;
}

void
amr_multigrid::make_coarser_level (BoxArray& mesh,
                                   Box&      domain,
                                   int&      flev,
                                   IntVect&  rat)
{
    if ( flev > lev_min )
    {
	if ((rat * 2) >= gen_ratio[flev-1])
	{
	    mesh = ml_mesh[flev-1];
	    domain.coarsen(gen_ratio[flev-1] / rat);
	    flev--;
	    rat = IntVect::TheUnitVector();
	}
	else
	{
	    IntVect trat = rat;
	    rat *= 2;
	    rat.min(gen_ratio[flev-1]);
	    trat = (rat / trat);
	    mesh.coarsen(trat);
	    domain.coarsen(trat);
	}
    }
    else if ( can_coarsen(mesh, domain) )
    {
	rat *= 2;
	mesh.coarsen(2);
	domain.coarsen(2);
    }
    else
    {
	mesh.clear();
    }
}

void
amr_multigrid::alloc_amr_multi (PArray<MultiFab>& Dest,
                      PArray<MultiFab>& Source,
                      PArray<MultiFab>& Coarse_source,
                      int               Lev_min,
                      int               Lev_max)
{
    lev_min = Lev_min;
    lev_max = Lev_max;

    BL_ASSERT(lev_min <= lev_max);
    BL_ASSERT(lev_min >= lev_min_min
	      && lev_min <= lev_min_max
	      && lev_max <= lev_max_max);

    BL_ASSERT(type(Source[lev_min]) == type(Dest[lev_min]));
#ifndef NDEBUG
    for (int i = lev_min; i <= lev_max; i++)
	BL_ASSERT(Source[i].boxArray() == Dest[i].boxArray());
#endif
    //
    // old version checked that these matched ml_mesh, but that's
    // harder to do with pure BoxLib.
    //if (source.mesh() != ml_mesh || dest.mesh() != ml_mesh)
    //  error("alloc---meshes no match");
    //
    dest.resize(lev_max + 1);
    source.resize(lev_max + 1);
    coarse_source.resize(lev_max + 1);

    for (int i = lev_min; i <= lev_max; i++)
    {
	dest.set(i, &Dest[i]);
	source.set(i, &Source[i]);
	if (i < Coarse_source.size() && Coarse_source.defined(i))
	{
	    coarse_source.set(i, &Coarse_source[i]);
	}
    }

    mg_domain = mg_domain_array[lev_min];
    mg_mesh = mg_mesh_array[lev_min];
    lev_interface = interface_array[lev_min - lev_min_min];

    build_index();

    mglev_max = ml_index[lev_max];

    resid.resize(mglev_max + 1);
    corr.resize(mglev_max + 1);
    work.resize(mglev_max + 1);
    save.resize(lev_max + 1);

    for (int i = 0; i <= mglev_max; i++)
    {
	BoxArray mesh = mg_mesh[i];
	mesh.convert(IndexType(type(source[lev_min])));
	resid.set(i, new MultiFab(mesh, 1, source[lev_min].nGrow()));
	corr.set(i, new MultiFab(mesh, 1, dest[lev_min].nGrow()));
	if (type(dest[lev_min]) == IntVect::TheCellVector())
	{
	    work.set(i, new MultiFab(mesh, 1, 0));
	}
	else
	{
	    work.set(i, new MultiFab(mesh, 1, 1));
	}

	resid[i].setVal(0.0);
        //
	// to clear border cells, which will be assigned into corr:
        //
	if (work[i].nGrow() > 0)
	{
	    work[i].setVal(0.0);
	}
    }

    for (int i = lev_min + 1; i <= lev_max - 1; i++)
    {
	save.set(i, new MultiFab(dest[i].boxArray(), 1, 0));
    }
}

void
amr_multigrid::clear_amr_multi ()
{
    for (int i = 0; i <= mglev_max; i++)
    {
	if (resid.defined(i)) delete resid.remove(i);
	if (corr.defined(i))  delete corr.remove(i);
	if (work.defined(i))  delete work.remove(i);
    }
    for (int i = lev_min; i <= lev_max; i++)
    {
	if (save.defined(i))  delete save.remove(i);
	dest.clear(i);
	source.clear(i);
	coarse_source.clear(i);
    }
    mg_mesh.clear();
}

void
amr_multigrid::solve (Real reltol,
                      Real abstol,
                      int  i1,
                      int  i2)
{
    BL_PROFILE(BL_PROFILE_THIS_NAME() + "::solve()");

    if (lev_max > lev_min)
	sync_interfaces();

    Real norm = 0.0;

    for (int lev = lev_min; lev <= lev_max; lev++)
    {
	const Real lev_norm = mfnorm(source[lev]);
	norm = (lev_norm > norm) ? lev_norm : norm;
    }
    if (coarse_source.size())
    {
	for (int lev = lev_min; lev < lev_max; lev++)
	{
	    if (coarse_source.defined(lev))
	    {
		const Real crse_lev_norm = mfnorm(coarse_source[lev]);
		norm = (crse_lev_norm > norm) ? crse_lev_norm : norm;
	    }
	}
    }
    if (pcode >= 1 && ParallelDescriptor::IOProcessor())
    {
	std::cout << "HG: Source norm is " << norm << std::endl;
    }

    Real err = ml_cycle(lev_max, mglev_max, i1, i2, abstol, 0.0);
    if (pcode >= 2 && ParallelDescriptor::IOProcessor())
    {
	std::cout << "HG: Err from ml_cycle is " << err << std::endl;
    }
    norm = (err > norm) ? err : norm;
    Real tol = reltol * norm;
    tol = (tol > abstol) ? tol : abstol;

    int it = 0;
    while (err > tol)
    {
	err = ml_cycle(lev_max, mglev_max, i1, i2, tol, 0.0);
	if ( pcode >= 2 && ParallelDescriptor::IOProcessor())
	{
	    std::cout << "HG: Err from "
                      << it + 1 << "th ml_cycle is " << err << std::endl;
	}
	if (++it > HG::multigrid_maxiter)
	{
	    BoxLib::Error( "amr_multigrid::solve:"
			   "multigrid iteration failed" );
	}
    }
    if (pcode >= 1 && ParallelDescriptor::IOProcessor())
    {
	std::cout << "HG: " << it << " cycles required" << std::endl;
    }
    //
    //This final restriction not needed unless you want coarse and fine
    //potentials to match up for use by the calling program.  Coarse
    //and fine values of dest already match at interfaces, and coarse
    //values under the fine grids have no effect on subsequent calls to
    //this solver.

    //for (lev = lev_max; lev > lev_min; lev--) {
    //  dest[lev].restrict_level(dest[lev-1]);
    //}
}

Real
amr_multigrid::ml_cycle (int  lev,
                         int  mglev,
                         int  i1,
                         int  i2,
                         Real tol,
                         Real res_norm_fine)
{
    HG_DEBUG_OUT( "ml_cycle: lev = " << lev << ", mglev = " << mglev << std::endl );
    MultiFab& dtmp = dest[lev];
    MultiFab& ctmp = corr[mglev];
    //
    // If level lev+1 exists, resid should be up to date there.
    // Includes restriction from next finer level.
    //
    Real res_norm = ml_residual(mglev, lev);

    if (pcode >= 2  && ParallelDescriptor::IOProcessor())
    {
	std::cout << "HG: Residual at level " << lev << " is " << res_norm << std::endl;
    }

    res_norm = (res_norm_fine > res_norm) ? res_norm_fine : res_norm;
    //
    // resid now correct on this level---relax.
    //
    ctmp.setVal(0.0); // ctmp.setBndry(0.0); // is necessary?
    if (lev > lev_min || res_norm > tol)
    {
	mg_cycle(mglev, (lev == lev_min) ? i1 : 0, i2);
	dtmp.plus(ctmp, 0, 1, 0);
    }

    if (lev > lev_min)
    {
	HG_TEST_NORM( source[lev], "ml_cycle");
	HG_TEST_NORM( resid[mglev], "ml_cycle");
	HG_TEST_NORM( work[mglev], "ml_cycle");
	MultiFab& stmp = source[lev];
	MultiFab& rtmp = resid[mglev];
	MultiFab& wtmp = work[mglev];
	if (lev < lev_max)
	{
	    save[lev].copy(ctmp);
	    level_residual(wtmp, rtmp, ctmp, mglev, false, 0);
	    rtmp.copy(wtmp);
	}
	else
	{
	    level_residual(rtmp, stmp, dtmp, mglev, false, 0);
	}
	interface_residual(mglev, lev);
	const int mgc = ml_index[lev-1];
	res_norm = ml_cycle(lev-1, mgc, i1, i2, tol, res_norm);
        //
	// This assignment is only done to clear the borders of work,
	// so that garbage will not make it into corr and dest.  In
	// some experiments this garbage grew exponentially, creating
	// an overflow danger even though the legitimate parts of the
	// calculation were not affected:
        //
	wtmp.setVal(0.0); // wtmp.setBndry(0.0); // Is necessary?
	HG_DEBUG_OUT("ml_cycle: lev > lev_min\n");
	mg_interpolate_level(mglev, mgc);
	ctmp.copy(wtmp);
	dtmp.plus(ctmp, 0, 1, 0);
	if (lev < lev_max)
	{
	    save[lev].plus(ctmp, 0, 1, 0);
	    level_residual(wtmp, rtmp, ctmp, mglev, false, 0);
	    rtmp.copy(wtmp);
	}
	else
	{
	    level_residual(rtmp, stmp, dtmp, mglev, false, 0);
	}
	ctmp.setVal(0.0);
	mg_cycle(mglev, 0, i2);
	dtmp.plus(ctmp, 0, 1, 0);
	if (lev < lev_max)
	{
	    ctmp.plus(save[lev], 0, 1, 0);
	}
	HG_TEST_NORM( source[lev], "ml_cycle a");
	HG_TEST_NORM( resid[mglev], "ml_cycle a");
	HG_TEST_NORM( work[mglev], "ml_cycle a");
    }

    return res_norm;
}

Real
amr_multigrid::ml_residual (int mglev,
                            int lev)
{
    HG_TEST_NORM( resid[mglev], "ml_residual 1");
    if (lev > lev_min)
    {
        //
	// This call is necessary to clear garbage values on outside edges that
	// will not be touched by level_residual, even with the clear flag set.
	// The restriction routine is responsible for only passing correct
	// values down from the fine level.  Garbage values in dead cells are
	// a problem because the norm routine sees them.
        //
	resid[mglev].setVal(0.0);
    }
    //
    // Clear flag set here because we want to compute a norm, and to
    // kill a feedback loop by which garbage in the border of dest
    // could grow exponentially.
    //
    level_residual(resid[mglev], source[lev], dest[lev], mglev, true, 0);
    if (lev < lev_max)
    {
	const int mgf = ml_index[lev+1];
	work[mgf].copy(resid[mgf]);
	HG_TEST_NORM( work[mgf], "ml_residual 3");
	mg_restrict_level(mglev, mgf);
	if (coarse_source.size() && coarse_source.defined(lev))
	{
	    resid[mglev].plus(coarse_source[lev], 0, 1, 0);
	}
    }
    HG_TEST_NORM( resid[mglev], "ml_residual 2");
    return mfnorm(resid[mglev]);
}

void
amr_multigrid::mg_cycle (int mglev,
			 int i1,
			 int i2)
{
    if (mglev == 0)
    {
	cgsolve(mglev);
    }
    else if (get_amr_level(mglev - 1) == -1)
    {
	MultiFab& ctmp = corr[mglev];
	MultiFab& wtmp = work[mglev];

	relax(mglev, i1, true);

	HG_TEST_NORM(wtmp, "mg_cycle a");
	if (pcode >= 4 )
	{
	    wtmp.setVal(0.0);
	    level_residual(wtmp, resid[mglev], ctmp, mglev, true, 0);
	    double nm = mfnorm(wtmp);
	    if ( ParallelDescriptor::IOProcessor() )
	    {
		std::cout << "HG: Residual at multigrid level "
                          << mglev << " is " << nm << std::endl;
	    }
	}
	else
	{
	    level_residual(wtmp, resid[mglev], ctmp, mglev, false, 0);
	}
	HG_TEST_NORM(wtmp, "mg_cycle a1");

	mg_restrict_level(mglev-1, mglev);
	corr[mglev-1].setVal(0.0);
	mg_cycle(mglev-1, i1, i2);
	//wtmp.assign(0.0);
	mg_interpolate_level(mglev, mglev-1);
        //
	// Pitfall?  If corr and work both have borders, crud there will
	// now be put into corr.  This does not appear to be a problem,
	// but if it is it can be avoided by clearing work before
	// interpolating.
        //
	ctmp.plus(wtmp, 0, 1, 0);
    }
    relax(mglev, i2, false);
    // ::exit(0);
}
