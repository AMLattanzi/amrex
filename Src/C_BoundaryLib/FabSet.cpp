//BL_COPYRIGHT_NOTICE

//
// $Id: FabSet.cpp,v 1.4 1998-02-18 21:36:07 vince Exp $
//

#include <FabSet.H>
#include <Looping.H>

FabSet::FabSet () {}

FabSet::~FabSet () {}

FabSet::FabSet (int _len)
{
    fabparray.resize(_len);
}

FabSet::FabSet (istream& is)
{
    readFrom(is);
}

void
FabSet::setFab (int        boxno,
                FArrayBox* fab)
{
    if (n_comp == 0)
    {
        n_comp = fab->nComp();
    }
    assert(n_comp == fab->nComp());
    assert(boxarray.ready());
    assert(!fabparray.defined(boxno));
    if (distributionMap.ProcessorMap()[boxno] == ParallelDescriptor::MyProc())
    {
        fabparray.set(boxno, fab);
    }
    else
    {
        BoxLib::Error("FabSet::setFab(): nonlocal set");
    }
    fabboxarray.convert(fab->box().ixType());
    fabboxarray.set(boxno, fab->box());
}

FabSet&
FabSet::copyFrom (const FArrayBox& src)
{
    for (FabSetIterator fsi(*this); fsi.isValid(false); ++fsi)
    {
        fsi().copy(src);
    }
    return *this;
}

FabSet&
FabSet::copyFrom (const FArrayBox& src,
                  int              src_comp,
                  int              dest_comp,
                  int              num_comp)
{
    for (FabSetIterator fsi(*this); fsi.isValid(false); ++fsi)
    {
        fsi().copy(src,src_comp,dest_comp,num_comp);
    }
    return *this;
}

FabSet&
FabSet::copyFrom (const FArrayBox& src,
                  const Box&       subbox,
                  int              src_comp,
                  int              dest_comp,
                  int              num_comp)
{
    const Box& sbox = src.box();
    assert(sbox.contains(subbox));
    for (FabSetIterator fsi(*this); fsi.isValid(false); ++fsi)
    {
        FArrayBox& fab = fsi();
        Box dbox = fab.box();
        dbox &= subbox;
        if (dbox.ok())
        {
            fsi().copy(src,dbox,src_comp,dbox,dest_comp,num_comp);
        }
    }
    return *this;
}

FabSet&
FabSet::copyFrom (const FabSet& src,
                  const Box&    subreg,
                  int           src_comp,
                  int           dest_comp,
                  int           num_comp)
{
    BoxLib::Error("FabSet::copyFrom(FabSet, Box, ...) not implemented");
    return *this;
}

FabSet&
FabSet::copyFrom (const MultiFab& src,
                  int             nghost,
                  int             src_comp,
                  int             dest_comp,
                  int             num_comp)
{
/*  original code vvvvvvvvvvvvvvvvvvvvvvvvvv
    assert (nghost <= src.nGrow());
    const BoxArray& sba = src.boxArray();
    for (int s = 0; s < src.length; s++) {
        const FArrayBox& sfab = src[s];
        Box sbox = grow(sba[s],nghost);
        for (int d = 0; d < length(); d++) {
            FArrayBox& dfab = (*this)[d];
            Box ovlp = dfab.box();
            ovlp &= sbox;
            if (ovlp.ok()) {
                dfab.copy(sfab,ovlp,src_comp,ovlp,dest_comp,num_comp);
            }
        }
    }
*/
    assert (nghost <= src.nGrow());

    FabSetCopyDescriptor fscd(true);
    MultiFabId srcmfid = fscd.RegisterFabArray((MultiFab *) &src);  // cast away
                                                 // const, this must be fixed
    List<FillBoxId> fillBoxIdList;

    const BoxArray& sba = src.boxArray();
    for (FabSetIterator fsi(*this); fsi.isValid(false); ++fsi)
    {
       FArrayBox &dfab = fsi();
       for (int s = 0; s < src.length(); ++s)
       {
           Box sbox = grow(sba[s],nghost);
            Box ovlp = dfab.box();
            ovlp &= sbox;
            if (ovlp.ok())
            {
              IndexType boxType(ovlp.ixType());
              BoxList unfilledBoxes(boxType);  // Unused here.
              FillBoxId fbid = fscd.AddBox(srcmfid, src.fabbox(s),
                                           unfilledBoxes, src_comp, dest_comp,
                                           num_comp, false);
              fillBoxIdList.append(fbid);
            }
        }
    }

    fscd.CollectData();

    ListIterator<FillBoxId> fbidli(fillBoxIdList);

    for (FabSetIterator fsi(*this); fsi.isValid(false); ++fsi)
    {
       FArrayBox &dfab = fsi();
       for (int s = 0; s < src.length(); ++s)
       {
           Box sbox = grow(sba[s],nghost);
            Box ovlp = dfab.box();
            ovlp &= sbox;
            if (ovlp.ok())
            {
              assert(fbidli);
              FillBoxId fbid = fbidli();
              ++fbidli;
              FArrayBox sfabTemp(fbid.box(), num_comp);
              fscd.FillFab(srcmfid, fbid, sfabTemp);
              int srcCompTemp = 0;  // Copy from temp src = 0
              dfab.copy(sfabTemp, ovlp, srcCompTemp, ovlp, dest_comp, num_comp);
            }
        }
    }

    return *this;
}

const FabSet&
FabSet::copyTo (MultiFab& dest,
                int       nghost,
                int       src_comp,
                int       dest_comp,
                int       num_comp) const
{
if(ParallelDescriptor::NProcs() > 1) {
  cerr << "FabSet::copyTo(MultiFab, nghost, ...) not implemented in parallel." << endl;
  ParallelDescriptor::Abort("Exiting.");
} else {
  cerr << "FabSet::copyTo(MultiFab, nghost, ...) not implemented in parallel." << endl;
}

    int dlen = dest.length();
    int slen = length();
    assert (nghost <= dest.nGrow());
    const BoxArray& dba = dest.boxArray();
    for (int d = 0; d < dlen; d++) {
        FArrayBox& dfab = dest[d];
        Box dbox = grow(dba[d],nghost);
        for (int s = 0; s < slen; s++) {
            const FArrayBox& sfab = (*this)[s];
            const Box& sbox = sfab.box();
            Box ovlp = dbox;
            ovlp &= sbox;
            if (ovlp.ok())
            {
                dfab.copy(sfab,ovlp,src_comp,ovlp,dest_comp,num_comp);
            }
        }
    }

    return *this;
}

FabSet&
FabSet::plusFrom (const MultiFab& src,
                  int             nghost,
                  int             src_comp,
                  int             dest_comp,
                  int             num_comp)
{
    //
    // This can be optimized by only communicating the components used in
    // the linComp--this implementation communicates all the components.
    //
    assert(nghost <= src.nGrow());

    const BoxArray& sba = src.boxArray();

    MultiFabCopyDescriptor mfcd(true);
    MultiFabId mfidsrc  = mfcd.RegisterFabArray((MultiFab *) &src);
    List<FillBoxId> fillBoxIdList;

    for (FabSetIterator thismfi(*this); thismfi.isValid(false); ++thismfi)
    {
        FArrayBox& dfab = thismfi();
        for (int isrc = 0; isrc < src.length(); ++isrc)
        {
            Box sbox = grow(sba[isrc], nghost);
            Box ovlp(dfab.box());
            ovlp &= sbox;
            if (ovlp.ok())
            {
                BoxList unfilledBoxes(ovlp.ixType()); // Unused here.
                FillBoxId fbidsrc;
                fbidsrc = mfcd.AddBox(mfidsrc,ovlp,unfilledBoxes,0,0,num_comp);
                fillBoxIdList.append(fbidsrc);
            }
        }
    }

    mfcd.CollectData();

    ListIterator<FillBoxId> fbidli(fillBoxIdList);

    for (FabSetIterator thismfi(*this); thismfi.isValid(false); ++thismfi)
    {
        FArrayBox& dfab = thismfi();
        for (int isrc = 0; isrc < src.length(); ++isrc)
        {
            Box sbox = grow(sba[isrc], nghost);
            Box ovlp(dfab.box());
            ovlp &= sbox;
            if (ovlp.ok())
            {
                assert(fbidli);
                FillBoxId fbidsrc = fbidli();
                ++fbidli;
                FArrayBox sfab(fbidsrc.box(), num_comp);
                mfcd.FillFab(mfidsrc, fbidsrc, sfab);
                dfab.plus(sfab,ovlp,src_comp,dest_comp,num_comp);
            }
        }
    }

    return *this;
}

//
// Linear combination this := a*this + b*src
// Note: corresponding fabsets must be commensurate.
//
FabSet&
FabSet::linComb (Real          a,
                 Real          b,
                 const FabSet& src,
                 int           src_comp,
                 int           dest_comp,
                 int           num_comp)
{
    assert(length() == src.length());

    for (FabSetIterator fsi(*this); fsi.isValid(false); ++fsi)
    {
        DependentFabSetIterator dfsi(fsi, src);
        FArrayBox &dfab = fsi();
        const FArrayBox& sfab = dfsi();
        const Box& dbox = dfab.box();
        const Box& sbox = sfab.box();
        assert(dbox == sbox);
        //
        // WARNING: same fab used as src and dest here.
        //
        dfab.linComb(dfab,dbox,dest_comp,sfab,sbox,src_comp,
                     a,b,dbox,dest_comp,num_comp);
    }
    return *this;
}

FabSet&
FabSet::linComb (Real            a,
                 const MultiFab& mfa,
                 int             a_comp,
                 Real            b,
                 const MultiFab& mfb,
                 int             b_comp,
                 int             dest_comp,
                 int             num_comp,
                 int             n_ghost)
{
    const BoxArray& bxa = mfa.boxArray();
    const BoxArray& bxb = mfb.boxArray();
    assert(bxa == bxb);
    assert(n_ghost <= mfa.nGrow());
    assert(n_ghost <= mfb.nGrow());
    //
    // This can be optimized by only communicating the components used in
    // the linComp--this implementation communicates all the components.
    //
    MultiFabCopyDescriptor mfcd(true);
    MultiFabId mfid_mfa = mfcd.RegisterFabArray((MultiFab *) &mfa);
    MultiFabId mfid_mfb = mfcd.RegisterFabArray((MultiFab *) &mfb);
    List<FillBoxId> fillBoxIdList_mfa;
    List<FillBoxId> fillBoxIdList_mfb;

    for (FabSetIterator thismfi(*this); thismfi.isValid(false); ++thismfi)
    {
        FArrayBox& reg_fab = thismfi();
        for (int grd = 0; grd < bxa.length(); grd++)
        {
            const Box &grd_box = grow(bxa[grd],n_ghost);
            Box ovlp(reg_fab.box());
            ovlp &= grd_box;
            if (ovlp.ok())
            {
                BoxList unfilledBoxes(ovlp.ixType()); // Unused here.
                FillBoxId fbid_mfa;
                fbid_mfa = mfcd.AddBox(mfid_mfa, mfa.fabbox(grd),
                                       unfilledBoxes, 0, 0, num_comp, false);
                fillBoxIdList_mfa.append(fbid_mfa);
                FillBoxId fbid_mfb;
                fbid_mfb = mfcd.AddBox(mfid_mfb, mfb.fabbox(grd),
                                       unfilledBoxes, 0, 0, num_comp, false);
                fillBoxIdList_mfb.append(fbid_mfb);
            }
        }
    }

    mfcd.CollectData();

    ListIterator<FillBoxId> fbidli_mfa(fillBoxIdList_mfa);
    ListIterator<FillBoxId> fbidli_mfb(fillBoxIdList_mfb);

    for (FabSetIterator thismfi(*this); thismfi.isValid(false); ++thismfi)
    {
        FArrayBox& reg_fab = thismfi();
        for (int grd = 0; grd < bxa.length(); grd++)
        {
            const Box& grd_box = grow(bxa[grd],n_ghost);
            Box ovlp(reg_fab.box());
            ovlp &= grd_box;
            if (ovlp.ok())
            {
                assert(fbidli_mfa);
                FillBoxId fbid_mfa = fbidli_mfa();
                ++fbidli_mfa;
                FArrayBox a_fab(fbid_mfa.box(), num_comp);
                mfcd.FillFab(mfid_mfa, fbid_mfa, a_fab);
                assert(fbidli_mfb);
                FillBoxId fbid_mfb = fbidli_mfb();
                ++fbidli_mfb;
                FArrayBox b_fab(fbid_mfb.box(), num_comp);
                mfcd.FillFab(mfid_mfb, fbid_mfb, b_fab);
                reg_fab.linComb(a_fab,ovlp,a_comp,b_fab,ovlp,b_comp,
                                a,b,ovlp,dest_comp,num_comp);
            }
        }
    }

    return *this;
}

ostream &
operator<< (ostream&      os,
            const FabSet& mf)
{
    BoxLib::Error("FabSet::operator<<() not yet implemented");
/*
    int nfab = mf.length();
    os << "(FabSet "
       << nfab << '\n';
    for (int i = 0; i < nfab; i++) {
        os << mf[i] << '\n';
    }
    os << ')';
*/
    return os;
}

ostream &
FabSet::writeOn (ostream& os) const
{
    BoxLib::Error("FabSet::writeOn() not yet implemented");
/*
    assert( ready() );
    int nfab = length();
    os << nfab << '\n';
    for (int i = 0; i < nfab; i++) {
        get(i).writeOn(os);
    }
*/
    return os;
}

istream&
FabSet::readFrom (istream& is)
{
    BoxLib::Error("FabSet::readFrom() not yet implemented");
/*
    if (ready()) {
        clear();
    }
    int ngrd;
    is >> ngrd;
    while (is.get() != '\n');
    resize(ngrd);
    for (int i = 0; i < ngrd; i++) {
        FArrayBox* tmp = new FArrayBox;
        tmp->readFrom(is);
        set(i,tmp);
    }
*/
    return is;
}
