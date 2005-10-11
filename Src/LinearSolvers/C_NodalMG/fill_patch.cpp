
#include "fill_patch.H"
#include <Profiler.H>

#if defined( BL_FORT_USE_UNDERSCORE )
#define FORT_FIPRODC   iprodc_
#define FORT_FIPRODN   iprodn_
#elif defined( BL_FORT_USE_UPPERCASE )
#define FORT_FIPRODC   IPRODC
#define FORT_FIPRODN   IPRODN
#elif defined( BL_FORT_USE_LOWERCASE )
#define FORT_FIPRODC   iprodc
#define FORT_FIPRODN   iprodn
#else
#error "none of BL_FORT_USE_{UNDERSCORE,UPPERCASE,LOWERCASE} defined"
#endif

extern "C"
{
    void FORT_FIPRODC(const Real*, intS, const Real*, intS, intS, Real*);
    void FORT_FIPRODN(const Real*, intS, const Real*, intS, intS, Real*);
}

Real
inner_product (const MultiFab& r,
               const MultiFab& s)
{
    BL_ASSERT(r.ok() && s.ok());
    BL_ASSERT(r.nComp() == 1);
    BL_ASSERT(s.nComp() == 1);
    BL_ASSERT(type(r) == type(s));

    Real sum = 0.0;

    if (type(r) == IntVect::TheCellVector())
    {
	for (MFIter rcmfi(r); rcmfi.isValid(); ++rcmfi)
	{
	    const Box& rbox = r[rcmfi].box();
	    const Box& sbox = s[rcmfi].box();
	    const Box& reg  = rcmfi.validbox();
	    FORT_FIPRODC(r[rcmfi].dataPtr(), DIMLIST(rbox),
			 s[rcmfi].dataPtr(), DIMLIST(sbox),
                         DIMLIST(reg), &sum);
	}
    }
    else if (type(r) == IntVect::TheNodeVector())
    {
	for (MFIter rcmfi(r); rcmfi.isValid(); ++rcmfi)
	{
	    const Box& rbox = r[rcmfi].box();
	    const Box& sbox = s[rcmfi].box();
	    const Box& reg  = rcmfi.validbox();
	    FORT_FIPRODN(r[rcmfi].dataPtr(), DIMLIST(rbox),
			 s[rcmfi].dataPtr(), DIMLIST(sbox), DIMLIST(reg), &sum);
	}
    }
    else
    {
	BoxLib::Abort( "inner_product():"
		       "only supported for CELL- or NODE-based data" );
    }

    ParallelDescriptor::ReduceRealSum(sum);

    return sum;
}

task_fill_patch::task_fill_patch (task_list&                tl_,
                                  const MultiFab&           t_,
                                  int                       tt_,
                                  const Box&                region_,
                                  const MultiFab&           r_,
                                  const level_interface&    lev_interface_,
                                  const amr_boundary* bdy_,
                                  int                       idim_,
                                  int                       index_,
                                  char*                     did_work)
    :
    task_fab(tl_, t_, tt_, region_, r_.nComp(), did_work),
    r(r_),
    lev_interface(lev_interface_),
    bdy(bdy_),
    idim(idim_),
    index(index_)
{
    fill_patch();
}

task_fill_patch::~task_fill_patch () {}

bool
task_fill_patch::fill_patch_blindly ()
{
    const BoxArray& r_ba = r.boxArray();

    for (int igrid = 0; igrid < r.size(); igrid++)
    {
	if (is_local(r, igrid))
	{
	    BL_ASSERT(BoxLib::grow(r[igrid].box(), -r.nGrow()) == r_ba[igrid]);
	}
	if (r_ba[igrid].contains(region))
	{
	    depend_on(m_task_list.add_task(new task_copy_local(m_task_list,
                                                               target,
                                                               target_proc_id(),
                                                               region,
                                                               r,
                                                               igrid,
                                                               m_did_work)));
	    return true;
	}
    }
    for (int igrid = 0; igrid < r.size(); igrid++)
    {
	if (is_local(r, igrid))
	{
	    BL_ASSERT(BoxLib::grow(r[igrid].box(), -r.nGrow()) == r_ba[igrid]);
	}
	if (r_ba[igrid].intersects(region))
	{
            Box tb = r_ba[igrid] & region;

	    depend_on(m_task_list.add_task(new task_copy_local(m_task_list,
                                                               target,
                                                               target_proc_id(),
                                                               tb,
                                                               r,
                                                               igrid,
                                                               m_did_work)));
	}
    }
    return false;
}

bool
task_fill_patch::fill_exterior_patch_blindly ()
{
    const BoxArray& em = lev_interface.exterior_mesh();

    for (int igrid = 0; igrid < em.size(); igrid++)
    {
	const int jgrid = lev_interface.direct_exterior_ref(igrid);

	if (jgrid >= 0)
	{
	    Box tb = em[igrid];
	    tb.convert(type(r));
	    if (tb.contains(region))
	    {
		depend_on(m_task_list.add_task(new task_bdy_fill(m_task_list,
                                                                 bdy,
                                                                 target,
                                                                 target_proc_id(),
                                                                 region,
                                                                 r,
                                                                 jgrid,
                                                                 lev_interface.domain(),
                                                                 m_did_work)));
		return true;
	    }
	    if (tb.intersects(region))
	    {
		tb &= region;
		depend_on(m_task_list.add_task(new task_bdy_fill(m_task_list,
                                                                 bdy,
                                                                 target,
                                                                 target_proc_id(),
                                                                 tb,
                                                                 r,
                                                                 jgrid,
                                                                 lev_interface.domain(),
                                                                 m_did_work)));
	    }
	}
    }

    return false;
}

void
task_fill_patch::fill_patch ()
{
    if (!region.ok()) return;

    if (target != 0)
    {
	BL_ASSERT(target->box() == region);
	BL_ASSERT(target->nComp() == r.nComp());
	BL_ASSERT(type(*target) == type(r));
    }
    BL_ASSERT(lev_interface.ok());
    BL_ASSERT(idim >= -1 && idim < BL_SPACEDIM);

    Box tdomain = lev_interface.domain();
    tdomain.convert(region.type());
    BL_ASSERT(target == 0 || type(*target) == region.type());
    Box idomain = BoxLib::grow(tdomain, IntVect::TheZeroVector() - type(r));

    if (idim == -1)
    {
	if (idomain.contains(region) || bdy == 0)
	{
	    fill_patch_blindly();
	}
	else if (!tdomain.intersects(region))
	{
	    fill_exterior_patch_blindly();
	}
	else if (idomain.intersects(region) && !fill_patch_blindly())
	{
            fill_exterior_patch_blindly();
	}
	else if (!fill_exterior_patch_blindly())
	{
            fill_patch_blindly();
	}
    }
    else
    {
        const BoxArray& r_ba = r.boxArray();
	Array<int> gridnum(lev_interface.ngrids(idim)+1);
	gridnum[0] = -1;
	for (int i = 0; i < lev_interface.ngrids(idim); i++)
	{
            int igrid = lev_interface.grid(idim, index, i);

	    if (igrid != -1)
	    {
		for (int j = 0; gridnum[j] != igrid; j++)
		{
		    if (gridnum[j] == -1)
		    {
			gridnum[j] = igrid;
			gridnum[j+1] = -1;
			if (igrid >= 0)
			{
			    Box tb = r_ba[igrid] & region;
			    depend_on(m_task_list.add_task(new task_copy_local(m_task_list,
                                                                               target,
                                                                               target_proc_id(),
                                                                               tb,
                                                                               r,
                                                                               igrid,
                                                                               m_did_work)));
			}
			else
			{
			    igrid = -2 - igrid;
			    Box tb = lev_interface.exterior_mesh()[igrid];
			    tb.convert(type(r));
			    tb &= region;
                            depend_on(m_task_list.add_task(new task_bdy_fill(m_task_list,
                                                                             bdy,
                                                                             target,
                                                                             target_proc_id(),
                                                                             tb,
                                                                             r,
                                                                             lev_interface.direct_exterior_ref(igrid),
                                                                             lev_interface.domain(),
                                                                             m_did_work)));
			}
			break;
		    }
		}
	    }
	}
    }
}

static
void
sync_internal_borders (MultiFab&              r,
                       const level_interface& lev_interface)
{
    BL_PROFILE("sync_internal_borders()");

    BL_ASSERT(type(r) == IntVect::TheNodeVector());

    task_list tl;
    for (int iface = 0;
	 iface < lev_interface.nboxes(level_interface::FACEDIM); iface++)
    {
	const int igrid = lev_interface.grid(level_interface::FACEDIM, iface, 0);
	const int jgrid = lev_interface.grid(level_interface::FACEDIM, iface, 1);
        //
	// Only do interior faces with fine grid on both sides.
        //
	if (igrid < 0
	    || jgrid < 0
	    || lev_interface.geo(level_interface::FACEDIM, iface) != level_interface::ALL)
	    break;
	tl.add_task(new task_copy(tl,
                                  r,
                                  jgrid,
                                  r,
                                  igrid,
                                  lev_interface.node_box(level_interface::FACEDIM, iface)));
    }
#if (BL_SPACEDIM == 2)
    for (int icor = 0; icor < lev_interface.nboxes(0); icor++)
    {
	const int igrid = lev_interface.grid(0, icor, 0);
	const int jgrid = lev_interface.grid(0, icor, 3);
        //
	// Only do interior corners with fine grid on all sides.
        //
	if (igrid < 0
	    || jgrid < 0
	    || lev_interface.geo(0, icor) != level_interface::ALL)
	    break;
	if (jgrid == lev_interface.grid(0, icor, 1))
	    tl.add_task(new task_copy(tl,
                                      r,
                                      jgrid,
                                      r,
                                      igrid,
                                      lev_interface.box(0, icor)));
    }
#else
    for (int iedge = 0; iedge < lev_interface.nboxes(1); iedge++)
    {
	const int igrid = lev_interface.grid(1, iedge, 0);
	const int jgrid = lev_interface.grid(1, iedge, 3);
        //
	// Only do interior edges with fine grid on all sides.
        //
	if (igrid < 0
	    || jgrid < 0
	    || lev_interface.geo(1, iedge) != level_interface::ALL)
	    break;
	if (jgrid == lev_interface.grid(1, iedge, 1))
	    tl.add_task(new task_copy(tl,
                                      r,
                                      jgrid,
                                      r,
                                      igrid,
                                      lev_interface.node_box(1, iedge)));
    }
    for (int icor = 0; icor < lev_interface.nboxes(0); icor++)
    {
        int igrid = lev_interface.grid(0, icor, 0);
        int jgrid = lev_interface.grid(0, icor, 7);
        //
	// Only do interior corners with fine grid on all sides.
        //
	if (igrid < 0
	    || jgrid < 0
	    || lev_interface.geo(0, icor) != level_interface::ALL)
	    break;
	if (lev_interface.grid(0, icor, 3) == lev_interface.grid(0, icor, 1))
	{
	    if (jgrid != lev_interface.grid(0, icor, 3))
	    {
		tl.add_task(new task_copy(tl,
                                          r,
                                          jgrid,
                                          r,
                                          igrid,
                                          lev_interface.box(0, icor)));
		jgrid = lev_interface.grid(0, icor, 5);
		if (jgrid != lev_interface.grid(0, icor, 7))
		    tl.add_task(new task_copy(tl,
                                              r,
                                              jgrid,
                                              r,
                                              igrid,
                                              lev_interface.box(0, icor)));
	    }
	}
	else if (lev_interface.grid(0, icor, 5) == lev_interface.grid(0, icor, 1))
	{
	    if (jgrid != lev_interface.grid(0, icor, 5))
	    {
		tl.add_task(new task_copy(tl,
                                          r,
                                          jgrid,
                                          r,
                                          igrid,
                                          lev_interface.box(0, icor)));
		jgrid = lev_interface.grid(0, icor, 3);
		if (jgrid != lev_interface.grid(0, icor, 7))
		{
		    tl.add_task(new task_copy(tl,
                                              r,
                                              jgrid,
                                              r,
                                              igrid,
                                              lev_interface.box(0, icor)));
		    if (jgrid == lev_interface.grid(0, icor, 2))
		    {
			jgrid = lev_interface.grid(0, icor, 6);
			if (jgrid != lev_interface.grid(0, icor, 7))
			    tl.add_task(
				new task_copy(tl,
					      r,
					      jgrid,
					      r,
					      igrid,
					      lev_interface.box(0, icor)));
		    }
		}
	    }
	}
    }
#endif
    tl.execute("sync_internal_borders");
}

void
sync_borders (MultiFab&                 r,
              const level_interface&    lev_interface,
              const amr_boundary* bdy)
{
    sync_internal_borders(r, lev_interface);
    BL_ASSERT(bdy != 0);
    bdy->sync_borders(r, lev_interface);
}

#if BL_SPACEDIM == 3
//
// Local function used only by fill_internal_borders:
//
inline
void
node_dirs (int            dir[2],
           const IntVect& typ)
{
    if (typ[0] == IndexType::NODE)
    {
	dir[0] = 0;
        dir[1] = (typ[1] == IndexType::NODE) ? 1 : 2;
    }
    else
    {
	dir[0] = 1;
	dir[1] = 2;
    }
}
#endif

//
// The sequencing used in fill_internal_borders, fcpy2 and set_border_cache
// (narrow x, medium y, wide z) is necessary to avoid overwrite problems
// like those seen in the sync routines.  Boundary copies are all wide
// regardless of direction and come after interior copies---overwrite
// difficulties are avoided since grids can't bridge a boundary.

// Modifications are necessary in 3D to deal with lack of diagonal
// communication across edges at the coarse-fine lev_interface.  These
// modifications take the form of narrowing certain copies to avoid
// overwriting good values with bad ones.
//

static
void
fill_internal_borders (MultiFab&              r,
                       const level_interface& lev_interface,
                       int                    w,
                       bool                   hg_dense)
{
    BL_PROFILE("fill_internal_borders()");

    BL_ASSERT(type(r) == IntVect::TheCellVector()
	      || type(r) == IntVect::TheNodeVector() );

    w = (w < 0 || w > r.nGrow()) ? r.nGrow() : w;

    BL_ASSERT(w == 1 || w == 0);

    task_list tl;

    if (type(r) == IntVect::TheNodeVector())
    {
#if (BL_SPACEDIM == 3)
	if (hg_dense)
	{
            //
	    // Attempt to deal with corner-coupling problem with 27-point stencils
            //
	    for (int iedge = 0; iedge < lev_interface.nboxes(1); iedge++)
	    {
                if (lev_interface.geo(1, iedge) == level_interface::ALL) continue;

                int igrid = lev_interface.grid(1, iedge, 0);
                int jgrid = lev_interface.grid(1, iedge, 3);
                if (igrid >= 0 && jgrid >= 0)
                {
                    int kgrid = lev_interface.grid(1, iedge, 1);
                    if (kgrid == -1) kgrid = lev_interface.grid(1, iedge, 2);
                    if (kgrid != -1 && kgrid != igrid && kgrid != jgrid)
                    {
                        int dir[2];
                        node_dirs(dir, lev_interface.box(1, iedge).type());
                        if (kgrid == lev_interface.grid(1, iedge, 1))
                        {
                            Box b = lev_interface.node_box(1, iedge);
                            tl.add_task(new task_copy(tl, r, jgrid, r, igrid, b.shift(dir[0], -1)));
                            b = lev_interface.node_box(1, iedge);
                            tl.add_task(new task_copy(tl, r, igrid, r, jgrid, b.shift(dir[1], 1)));
                        }
                        else
                        {
                            Box b = lev_interface.node_box(1, iedge);
                            tl.add_task(new task_copy(tl, r, jgrid, r, igrid, b.shift(dir[1], -1)));
                            b = lev_interface.node_box(1, iedge);
                            tl.add_task(new task_copy(tl, r, igrid, r, jgrid, b.shift(dir[0], 1)));
                        }
                    }
                }

                igrid = lev_interface.grid(1, iedge, 1);
                jgrid = lev_interface.grid(1, iedge, 2);
                if (igrid >= 0 && jgrid >= 0)
                {
                    int kgrid = lev_interface.grid(1, iedge, 0);
                    if (kgrid == -1) kgrid = lev_interface.grid(1, iedge, 3);
                    if (kgrid != -1 && kgrid != igrid && kgrid != jgrid)
                    {
                        int dir[2];
                        node_dirs(dir, lev_interface.box(1, iedge).type());
                        if (kgrid == lev_interface.grid(1, iedge, 0))
                        {
                            Box b = lev_interface.node_box(1, iedge);
                            tl.add_task(new task_copy(tl, r, jgrid, r, igrid, b.shift(dir[0], 1)));
                            b = lev_interface.node_box(1, iedge);
                            tl.add_task(new task_copy(tl, r, igrid, r, jgrid, b.shift(dir[1], 1)));
                        }
                        else
                        {
                            Box b = lev_interface.node_box(1, iedge);
                            tl.add_task(new task_copy(tl, r, jgrid, r, igrid, b.shift(dir[1], -1)));
                            b = lev_interface.node_box(1, iedge);
                            tl.add_task(new task_copy(tl, r, igrid, r, jgrid, b.shift(dir[0], -1)));
                        }
                    }
                }
            }
	}
#endif /*BL_SPACEDIM == 3*/

        const BoxArray& r_ba = r.boxArray();

	for (int iface = 0; iface < lev_interface.nboxes(level_interface::FACEDIM); iface++)
	{
            if (lev_interface.m_fill_internal_borders_fn[iface])
            {
                char* did_work = &lev_interface.m_fill_internal_borders_fn[iface];

                *did_work = 0;

                const int igrid = lev_interface.grid(level_interface::FACEDIM, iface, 0);
                const int jgrid = lev_interface.grid(level_interface::FACEDIM, iface, 1);
                if (igrid < 0
                    || jgrid < 0
                    || lev_interface.geo(level_interface::FACEDIM, iface) != level_interface::ALL)
                    break;
                const Box& b = lev_interface.node_box(level_interface::FACEDIM, iface);
                const int idim = lev_interface.fdim(iface);
                Box bj = lev_interface.node_box(level_interface::FACEDIM, iface);
                Box bi = lev_interface.node_box(level_interface::FACEDIM, iface);
                for (int i = 0; i < idim; i++)
                {
                    if (r_ba[jgrid].smallEnd(i) == bj.smallEnd(i)) bj.growLo(i, w);
                    if (r_ba[jgrid].bigEnd(i)   == bj.bigEnd(i))   bj.growHi(i, w);
                    if (r_ba[igrid].smallEnd(i) == bi.smallEnd(i)) bi.growLo(i, w);
                    if (r_ba[igrid].bigEnd(i)   == bi.bigEnd(i))   bi.growHi(i, w);
                }
                bj.shift(idim, -1).growLo(idim, w-1);
                bi.shift(idim,  1).growHi(idim, w-1);
                tl.add_task(new task_copy(tl, r, jgrid, r, igrid, bj, did_work));
                tl.add_task(new task_copy(tl, r, igrid, r, jgrid, bi, did_work));
            }
        }
    }
    else if (type(r) == IntVect::TheCellVector())
    {
        const BoxArray& r_ba = r.boxArray();

	for (int iface = 0; iface < lev_interface.nboxes(level_interface::FACEDIM); iface++)
	{
            if (lev_interface.m_fill_internal_borders_fc[iface])
            {
                char* did_work = &lev_interface.m_fill_internal_borders_fc[iface];

                *did_work = 0;

                const int igrid = lev_interface.grid(level_interface::FACEDIM, iface, 0);
                const int jgrid = lev_interface.grid(level_interface::FACEDIM, iface, 1);
                if (igrid < 0
                    || jgrid < 0
                    || lev_interface.geo(level_interface::FACEDIM, iface) != level_interface::ALL)
                    break;
                const int idim = lev_interface.fdim(iface);
#if (BL_SPACEDIM == 2)
                Box b = lev_interface.box(level_interface::FACEDIM, iface);
                if (idim == 1) b.grow(0, w);
                b.growLo(idim, w).convert(IntVect::TheCellVector());
                tl.add_task(new task_copy(tl, r, jgrid, r, igrid, b, did_work));
                tl.add_task(new task_copy(tl, r, igrid, r, jgrid, b.shift(idim, w), did_work));
#else
                Box bj = lev_interface.box(level_interface::FACEDIM, iface);
                Box bi = lev_interface.box(level_interface::FACEDIM, iface);
                for (int i = 0; i < idim; i++)
                {
                    if (r_ba[jgrid].smallEnd(i) == bj.smallEnd(i)) bj.growLo(i, w);
                    if (r_ba[jgrid].bigEnd(i)   == bj.bigEnd(i))   bj.growHi(i, w);
                    if (r_ba[igrid].smallEnd(i) == bi.smallEnd(i)) bi.growLo(i, w);
                    if (r_ba[igrid].bigEnd(i)   == bi.bigEnd(i))   bi.growHi(i, w);
                }
                bj.growLo(idim, w).convert(IntVect::TheCellVector());
                bi.growHi(idim, w).convert(IntVect::TheCellVector());
                tl.add_task(new task_copy(tl, r, jgrid, r, igrid, bj, did_work));
                tl.add_task(new task_copy(tl, r, igrid, r, jgrid, bi, did_work));
#endif
            }
	}
    }

    tl.execute("fill_internal_borders");

    if (ParallelDescriptor::IOProcessor() && false)
    {
        int sum_2 = 0, sum_3 = 0;

        for (int i = 0; i < lev_interface.m_fill_internal_borders_fn.size(); i++)
            if (lev_interface.m_fill_internal_borders_fn[i]) sum_2++;
        for (int i = 0; i < lev_interface.m_fill_internal_borders_fc.size(); i++)
            if (lev_interface.m_fill_internal_borders_fc[i]) sum_3++;

        std::cout << "m_fill_internal_borders_fn: used " << sum_2 << " out of " << lev_interface.m_fill_internal_borders_fn.size() << "\n";
        std::cout << "m_fill_internal_borders_fc: used " << sum_3 << " out of " << lev_interface.m_fill_internal_borders_fc.size() << "\n";
    }
}

void
fill_borders (MultiFab&              r,
              const level_interface& lev_interface,
              const amr_boundary*    bdy,
              int                    w,
              bool                   hg_dense)
{
    HG_TEST_NORM(r, "fill_borders 0");
    fill_internal_borders(r, lev_interface, w, hg_dense);
    HG_TEST_NORM(r, "fill_borders 1");
    BL_ASSERT(bdy != 0);
    bdy->fill_borders(r, lev_interface, w);
    HG_TEST_NORM(r, "fill_borders 2");
}

void
clear_part_interface (MultiFab&              r,
                      const level_interface& lev_interface)
{
    BL_ASSERT(r.nComp() == 1);
    BL_ASSERT(type(r) == IntVect::TheNodeVector());

    for (int i = 0; i < BL_SPACEDIM; i++)
    {
	for (int ibox = 0; ibox < lev_interface.nboxes(i); ibox++)
	{
            //
	    // coarse-fine face contained in part_fine grid, or orphan edge/corner
            //
	    const int igrid = lev_interface.aux(i, ibox);
	    if (igrid < 0  || is_remote(r, igrid))
                continue;
	    BL_ASSERT(is_local(r, igrid));
	    r[igrid].setVal(0.0, lev_interface.node_box(i, ibox), 0);
	}
    }
    HG_TEST_NORM( r, "clear_part_interface");
}

class task_restric_fill
    :
    public task
{
public:

    task_restric_fill (task_list&            tl_,
                       const amr_restrictor& restric,
                       MultiFab&             dest,
                       int                   dgrid,
                       const MultiFab&       r,
                       int                   rgrid,
                       const Box&            box,
                       const IntVect&        rat);

    virtual ~task_restric_fill ();
    virtual bool ready ();
    virtual void hint () const;
    virtual bool startup (long& sndcnt, long& rcvcnt);
    virtual bool need_to_communicate (int& with) const;

private:
    //
    // The data.
    //
    MPI_Request           m_request;
    const amr_restrictor& m_restric;
    FArrayBox*            m_tmp;
    MultiFab&             m_d;
    const MultiFab&       m_r;
    const int             m_dgrid;
    const int             m_rgrid;
    const Box             m_box;
    const IntVect         m_rat;
    bool                  m_local;
};

task_restric_fill::task_restric_fill (task_list&                  tl_,
                                      const amr_restrictor& restric,
                                      MultiFab&                   dest,
                                      int                         dgrid,
                                      const MultiFab&             r,
                                      int                         rgrid,
                                      const Box&                  box,
                                      const IntVect&              rat)
    :
    task(tl_),
    m_restric(restric),
    m_d(dest),
    m_r(r),
    m_dgrid(dgrid),
    m_rgrid(rgrid),
    m_tmp(0),
    m_box(box),
    m_rat(rat),
    m_local(false)
{
    if (is_local(m_d, m_dgrid) && is_local(m_r, m_rgrid))
    {
	m_local = true;

	m_restric.fill(m_d[m_dgrid], m_box, m_r[m_rgrid], m_rat);

        m_finished = true;
    }
    else if (!is_local(m_d, m_dgrid) && !is_local(m_r, m_rgrid))
    {
        m_finished = true;
    }
}

task_restric_fill::~task_restric_fill ()
{
    delete m_tmp;
}

bool
task_restric_fill::need_to_communicate (int& with) const
{
    bool result = false;

    if (!m_local)
    {
        if (is_local(m_d, m_dgrid))
        {
            with   = processor_number(m_r, m_rgrid);
            result = true;
        }
        else if (is_local(m_r, m_rgrid))
        {
            with   = processor_number(m_d, m_dgrid);
            result = true;
        }
    }

    return result;
}

bool
task_restric_fill::startup (long& sndcnt, long& rcvcnt)
{
    m_started = true;

    bool result = true;

    if (!m_local)
    {
        if (is_local(m_d, m_dgrid))
        {
            m_tmp = new FArrayBox(m_box, m_d.nComp());
            rcvcnt = m_tmp->box().numPts()*m_tmp->nComp();

            m_request = ParallelDescriptor::Arecv(m_tmp->dataPtr(),
                                                  rcvcnt,
                                                  processor_number(m_r,m_rgrid),
                                                  m_sno,
                                                  HG::mpi_comm).req();
            rcvcnt *= sizeof(double);

            BL_ASSERT(m_request != MPI_REQUEST_NULL);
        }
        else if (is_local(m_r, m_rgrid))
        {
            m_tmp = new FArrayBox(m_box, m_d.nComp());
	    m_restric.fill(*m_tmp, m_box, m_r[m_rgrid], m_rat);
            sndcnt = m_tmp->box().numPts()*m_tmp->nComp();

            m_request = ParallelDescriptor::Asend(m_tmp->dataPtr(),
                                                  sndcnt,
                                                  processor_number(m_d, m_dgrid),
                                                  m_sno,
                                                  HG::mpi_comm).req();
            sndcnt *= sizeof(double);

            BL_ASSERT(m_request != MPI_REQUEST_NULL);
        }
        else
        {
            result = false;
        }
    }

    return result;
}

bool
task_restric_fill::ready ()
{
    BL_ASSERT(is_started());

    if (m_local) return true;

    int flag;
    MPI_Status status;

    ParallelDescriptor::Test(m_request, flag, status);

    if (flag)
    {
	if (is_local(m_d, m_dgrid))
	{
            m_d[m_dgrid].copy(*m_tmp);
	}
	return true;
    }

    return false;
}

void
task_restric_fill::hint () const
{
    task::_hint();
    if (is_local(m_r, m_rgrid) && is_local(m_d, m_dgrid))
    {
	HG_DEBUG_OUT( "L" );
    }
    else if (is_local(m_r, m_rgrid))
    {
	HG_DEBUG_OUT( "S" );
    }
    else if (is_local(m_d, m_dgrid))
    {
    	HG_DEBUG_OUT( "R" );
    }
    else
    {
	HG_DEBUG_OUT( "?" );
    }
    HG_DEBUG_OUT( ' ' << m_box  << ' ' << m_dgrid << ' '; );
    HG_DEBUG_OUT( ")" << std::endl );
}

void
restrict_level (MultiFab&                   dest,
                MultiFab&                   r,
                const IntVect&              rat)
{
  restrict_level(dest, r, rat, default_restrictor(), default_level_interface, 0);
}

void
restrict_level (MultiFab&                   dest,
                MultiFab&                   r,
                const IntVect&              rat,
                const amr_restrictor&       restric,
                const level_interface&      lev_interface,
                const amr_boundary*         bdy)
{
    BL_PROFILE("restrict_level()");

    BL_ASSERT(type(dest) == type(r));

    HG_TEST_NORM( dest, "restrict_level a");
    HG_TEST_NORM(    r, "restrict_level r");

    const BoxArray& r_ba    = r.boxArray();
    const BoxArray& dest_ba = dest.boxArray();

    task_list tl;
    for (int igrid = 0; igrid < r.size(); igrid++)
    {
        const Box rbox = restric.box(r_ba[igrid], rat);

        std::vector< std::pair<int,Box> > isects = dest_ba.intersections(rbox);

        for (int i = 0; i < isects.size(); i++)
        {
            const int jgrid  = isects[i].first;

	    if ( ! ( is_local(dest, jgrid) || is_local(r, igrid) ) ) continue;

            const Box cbox = isects[i].second;

            tl.add_task(new task_restric_fill(tl, restric, dest, jgrid, r, igrid, cbox, rat));
        }
    }
    tl.execute("restrict_level");
    HG_TEST_NORM( dest, "restrict_level a1");
    HG_TEST_NORM(    r, "restrict_level r1");
    if (lev_interface.ok())
    {
	restric.fill_interface( dest, r, lev_interface, bdy, rat);
    }

    HG_TEST_NORM( dest, "restrict_level a2");
    HG_TEST_NORM(    r, "restrict_level r2");
}
