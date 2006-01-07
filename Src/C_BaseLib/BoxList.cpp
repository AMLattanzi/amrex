//
//
//
#include <winstd.H>

#include <algorithm>
#include <iostream>

#include <BoxArray.H>
#include <BoxList.H>

void
BoxList::join (const BoxList& blist)
{
    BL_ASSERT(ixType() == blist.ixType());
    std::list<Box> lb = blist.lbox;
    lbox.splice(lbox.end(), lb);
}

void
BoxList::catenate (BoxList& blist)
{
    BL_ASSERT(ixType() == blist.ixType());
    lbox.splice(lbox.end(), blist.lbox);
    BL_ASSERT(blist.isEmpty());
}

bool
BoxList::contains (const Box& b) const
{
    BoxList bnew = BoxLib::complementIn(b,*this);

    return bnew.isEmpty();
}

BoxList&
BoxList::remove (const Box& bx)
{
    BL_ASSERT(ixType() == bx.ixType());
    lbox.remove(bx);
    return *this;
}

BoxList&
BoxList::remove (iterator bli)
{
    BL_ASSERT(ixType() == bli->ixType());
    lbox.erase(bli);
    return *this;
}

BoxList
BoxLib::intersect (const BoxList& bl,
		   const Box&     b)
{
    BoxList newbl(bl);
    return newbl.intersect(b);
}

BoxList
BoxLib::intersect (const BoxList& bl,
                   const BoxList& br)
{
    BoxList newbl(bl);
    return newbl.intersect(br);
}

BoxList
BoxLib::refine (const BoxList& bl,
		int            ratio)
{
    BoxList nbl(bl);
    return nbl.refine(ratio);
}

BoxList
BoxLib::coarsen (const BoxList& bl,
                 int            ratio)
{
    BoxList nbl(bl);
    return nbl.coarsen(ratio);
}

BoxList
BoxLib::accrete (const BoxList& bl,
                 int            sz)
{
    BoxList nbl(bl);
    return nbl.accrete(sz);
}

BoxList
BoxLib::removeOverlap (const BoxList& bl)
{
    BoxArray ba(bl);

    return ba.removeOverlap();
}

bool
BoxList::operator!= (const BoxList& rhs) const
{
    return !operator==(rhs);
}

BoxList::BoxList ()
    :
    lbox(),
    btype(IndexType::TheCellType())
{}

BoxList::BoxList (const Box& bx)
    : btype(bx.ixType())
{
    push_back(bx);
}

BoxList::BoxList (IndexType _btype)
    :
    lbox(),
    btype(_btype)
{}

BoxList::BoxList (const BoxArray &ba)
    :
    lbox(),
    btype()
{
    if (ba.size() > 0)
        btype = ba[0].ixType();
    for (int i = 0; i < ba.size(); ++i)
        push_back(ba[i]);
}

bool
BoxList::ok () const
{
    bool isok = true;
    const_iterator bli = begin();
    if ( bli != end() )
    {
        for (Box b(*bli); bli != end() && isok; ++bli)
	{
            isok = bli->ok() && bli->sameType(b);
	}
    }
    return isok;
}

bool
BoxList::isDisjoint () const
{
    bool isdisjoint = true;
    for (const_iterator bli = begin(); bli != end() && isdisjoint; ++bli)
    {
        const_iterator bli2 = bli;
        //
        // Skip the first element.
        //
        ++bli2; 
        for (; bli2 != end() && isdisjoint; ++bli2)
	{
            if (bli->intersects(*bli2))
	    {
                isdisjoint = false;
	    }
	}
    }
    return isdisjoint;
}

bool
BoxList::contains (const IntVect& v) const
{
    bool contained = false;
    for (const_iterator bli = begin(); bli != end() && !contained; ++bli)
    {
        if (bli->contains(v))
	{
            contained = true;
	}
    }
    return contained;
}

bool
BoxList::contains (const BoxList&  bl) const
{
    for (const_iterator bli = bl.begin(); bli != bl.end(); ++bli)
    {
	if ( !contains(*bli) )
	{
	    return false;
	}
    }
    return true;
}

bool
BoxList::contains (const BoxArray&  ba) const
{
    for (int i = 0; i < ba.size(); i++)
        if (!contains(ba[i]))
            return false;
    return true;
}

BoxList&
BoxList::intersect (const Box& b)
{
    for (iterator bli= begin(); bli != end(); )
    {
        if (bli->intersects(b))
        {
            *bli &= b;
            ++bli;
        }
        else
        {
            bli = lbox.erase(bli);
        }
    }
    return *this;
}

BoxList&
BoxList::intersect (const BoxList& b)
{
    BoxList bl(b.ixType());

    for (iterator lhs = begin(); lhs != end(); ++lhs)
    {
        for (const_iterator rhs = b.begin(); rhs != b.end(); ++rhs)
        {
            if ( lhs->intersects(*rhs) )
            {
                bl.push_back(*lhs & *rhs);
            }
        }
    }

    *this = bl;

    return *this;
}

BoxList
BoxLib::complementIn (const Box&     b,
                      const BoxList& bl)
{
    BoxList newb(b.ixType());
    newb.complementIn(b,bl);
    return newb;
}

BoxList&
BoxList::complementIn (const Box&     b,
                       const BoxList& bl)
{
    clear();

    Box minbox = bl.minimalBox();
    BoxList tmpbl = BoxLib::boxDiff(b,minbox);
    catenate(tmpbl);

    BoxList mesh;
    BoxArray ba(bl);
    mesh.push_back(minbox);
    IntVect maxext(D_DECL(0,0,0));
    for (int i = 0; i < ba.size(); i++)
        maxext = BoxLib::max(maxext, ba[i].length());
    maxext *= 2;
    mesh.maxSize(maxext);

    for (BoxList::const_iterator bli = mesh.begin(); bli != mesh.end(); ++bli)
    {
        std::vector< std::pair<int,Box> > isects = ba.intersections(*bli);

        if (!isects.empty())
        {
            tmpbl.clear();
            for (int i = 0; i < isects.size(); i++)
                tmpbl.push_back(isects[i].second);
            BoxList tm;
            tm.complementIn_base(*bli,tmpbl);
            catenate(tm);
        }
        else
        {
            push_back(*bli);
        }
    }

    return *this;
}


BoxList&
BoxList::complementIn_base (const Box&     b,
                            const BoxList& bl)
{
    clear();
    push_back(b);
    for (const_iterator bli = bl.begin(); bli != bl.end() && isNotEmpty(); ++bli)
    {
        for (iterator newbli = lbox.begin(); newbli != lbox.end(); )
        {
            if (newbli->intersects(*bli))
            {
                BoxList tm = BoxLib::boxDiff(*newbli, *bli);
                lbox.splice(lbox.begin(), tm.lbox);
                lbox.erase(newbli++);
            }
            else
            {
                ++newbli;
            }
        }
    }
    return *this;
}

BoxList&
BoxList::refine (int ratio)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->refine(ratio);
    }
    return *this;
}

BoxList&
BoxList::refine (const IntVect& ratio)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->refine(ratio);
    }
    return *this;
}

BoxList&
BoxList::coarsen (int ratio)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->coarsen(ratio);
    }
    return *this;
}

BoxList&
BoxList::coarsen (const IntVect& ratio)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->coarsen(ratio);
    }
    return *this;
}

BoxList&
BoxList::accrete (int sz)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->grow(sz);
    }
    return *this;
}

BoxList&
BoxList::shift (int dir,
                int nzones)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->shift(dir, nzones);
    }
    return *this;
}

BoxList&
BoxList::shiftHalf (int dir,
                    int num_halfs)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->shiftHalf(dir, num_halfs);
    }
    return *this;
}

BoxList&
BoxList::shiftHalf (const IntVect& iv)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->shiftHalf(iv);
    }
    return *this;
}

//
// Returns a list of boxes defining the compliment of b2 in b1in.
//

BoxList
BoxLib::boxDiff (const Box& b1in,
		 const Box& b2)
{
   Box b1(b1in);
   BoxList b_list(b1.ixType());

   if ( !b2.contains(b1) )
   {
       if ( !b1.intersects(b2) )
       {
           b_list.push_back(b1);
       }
       else
       {
           const int* b2lo = b2.loVect();
           const int* b2hi = b2.hiVect();

           for (int i = 0; i < BL_SPACEDIM; i++)
           {
               const int* b1lo = b1.loVect();
               const int* b1hi = b1.hiVect();

               if ((b1lo[i] < b2lo[i]) && (b2lo[i] <= b1hi[i]))
               {
                   Box bn(b1);
                   bn.setSmall(i,b1lo[i]);
                   bn.setBig(i,b2lo[i]-1);
                   b_list.push_back(bn);
                   b1.setSmall(i,b2lo[i]);
               }
               if ((b1lo[i] <= b2hi[i]) && (b2hi[i] < b1hi[i]))
               {
                   Box bn(b1);
                   bn.setSmall(i,b2hi[i]+1);
                   bn.setBig(i,b1hi[i]);
                   b_list.push_back(bn);
                   b1.setBig(i,b2hi[i]);
               }
           }
       }
   }
   return b_list;
}

int
BoxList::simplify ()
{
    //
    // Try to merge adjacent boxes.
    //
    int count = 0;
    int lo[BL_SPACEDIM];
    int hi[BL_SPACEDIM];

    for (iterator bla = begin(); bla != end(); )
    {
        const int* alo   = bla->loVect();
        const int* ahi   = bla->hiVect();
        bool       match = false;
        iterator blb = bla;
        ++blb;
        while ( blb != end() )
        {
            const int* blo = blb->loVect();
            const int* bhi = blb->hiVect();
            //
            // Determine of a and b can be coalasced.
            // They must have equal extents in all index direciton
            // except possibly one and must abutt in that direction.
            //
            bool canjoin = true;
            int  joincnt = 0;
            for (int i = 0; i < BL_SPACEDIM; i++)
            {
                if (alo[i]==blo[i] && ahi[i]==bhi[i])
                {
                    lo[i] = alo[i];
                    hi[i] = ahi[i];
                }
                else if (alo[i]<=blo[i] && blo[i]<=ahi[i]+1)
                {
                    lo[i] = alo[i];
                    hi[i] = std::max(ahi[i],bhi[i]);
                    joincnt++;
                }
                else if (blo[i]<=alo[i] && alo[i]<=bhi[i]+1)
                {
                    lo[i] = blo[i];
                    hi[i] = std::max(ahi[i],bhi[i]);
                    joincnt++;
                }
                else
                {
                    canjoin = false;
                    break;
                }
            }
            if (canjoin && (joincnt <= 1))
            {
                //
                // Modify b and remove a from the list.
                //
                blb->setSmall(IntVect(lo));
                blb->setBig(IntVect(hi));
                lbox.erase(bla++);
                count++;
                match = true;
                break;
            }
            else
            {
                //
                // No match found, try next element.
                //
                ++blb;
            }
        }
        //
        // If a match was found, a was already advanced in the list.
        //
        if (!match)
            ++bla;
    }
    return count;
}

int
BoxList::minimize ()
{
    int cnt = 0;
    for (int n; (n=simplify()) > 0; )
        cnt += n;
    return cnt;
}

Box
BoxList::minimalBox () const
{
    Box minbox;
    if ( !isEmpty() )
    {
        const_iterator bli = begin();
        minbox = *bli;
        while ( bli != end() )
	{
            minbox.minBox(*bli++);
	}
    }
    return minbox;
}

BoxList&
BoxList::maxSize (const IntVect& chunk)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        const int* len = bli->length().getVect();

        for (int i = 0; i < BL_SPACEDIM; i++)
        {
            if (len[i] > chunk[i])
            {
                //
                // Reduce by powers of 2.
                //
                int ratio = 1;
                int bs    = chunk[i];
                int nlen  = len[i];
                while ((bs%2 == 0) && (nlen%2 == 0))
                {
                    ratio *= 2;
                    bs    /= 2;
                    nlen  /= 2;
                }
                //
                // Determine number and size of (coarsened) cuts.
                //
                const int numblk = nlen/bs + (nlen%bs ? 1 : 0);
                const int size   = nlen/numblk;
                const int extra  = nlen%numblk;
                //
                // Number of cuts = number of blocks - 1.
                //
                for (int k = 0; k < numblk-1; k++)
                {
                    //
                    // Compute size of this chunk, expand by power of 2.
                    //
                    const int ksize = (k < extra ? size+1 : size) * ratio;
                    //
                    // Chop from high end.
                    //
                    const int pos = bli->bigEnd(i) - ksize + 1;

                    push_back(bli->chop(i,pos));
                }
            }
        }
        //
        // b has been chopped down to size and pieces split off
        // have been added to the end of the list so that they
        // can be checked for splitting (in other directions) later.
        //
    }
    return *this;
}

BoxList&
BoxList::maxSize (int chunk)
{
    return maxSize(IntVect(D_DECL(chunk,chunk,chunk)));
}

BoxList&
BoxList::surroundingNodes ()
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->surroundingNodes();
    }
    return *this;
}

BoxList&
BoxList::surroundingNodes (int dir)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->surroundingNodes(dir);
    }
    return *this;
}

BoxList&
BoxList::enclosedCells ()
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->enclosedCells();
    }
    return *this;
}

BoxList&
BoxList::enclosedCells (int dir)
{
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->enclosedCells(dir);
    }
    return *this;
}

BoxList&
BoxList::convert (IndexType typ)
{
    btype = typ;
    for (iterator bli = begin(); bli != end(); ++bli)
    {
        bli->convert(typ);
    }
    return *this;
}

std::ostream&
operator<< (std::ostream&  os,
            const BoxList& blist)
{
    BoxList::const_iterator bli = blist.begin();
    os << "(BoxList " << blist.size() << ' ' << blist.ixType() << '\n';
    for (int count = 1; bli != blist.end(); ++bli, ++count)
    {
        os << count << " : " << *bli << '\n';
    }
    os << ')' << '\n';

    if (os.fail())
        BoxLib::Error("operator<<(ostream&,BoxList&) failed");

    return os;
}

bool
BoxList::operator== (const BoxList& rhs) const
{
    bool rc = true;
    if (size() != rhs.size())
    {
        rc = false;
    }
    else
    {
        BoxList::const_iterator liter = begin(), riter = rhs.begin();
        for (; liter != end() && rc; ++liter, ++riter)
	{
            if ( !( *liter == *riter) )
	    {
                rc = false;
	    }
	}
    }
    return rc;
}
