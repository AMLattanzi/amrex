
#include <winstd.H>

#include <Profiler.H>
#include <BoxArray.H>
#include <DistributionMapping.H>
#include <ParallelDescriptor.H>
#include <ParmParse.H>

#include <iostream>
#include <cstdlib>
#include <list>
#include <map>
#include <vector>
#include <queue>
#include <algorithm>
#include <numeric>

#ifdef BL_USE_METIS
//#include <metis.h>
extern "C"
{
void METIS_PartGraphKway(int *, int *, int *, int *, int *, int *, int *, int *, int *, int *, int *); 
void METIS_PartGraphRecursive(int *, int *, int *, int *, int *, int *, int *, int *, int *, int *, int *); 
}
#endif

static int    metis_opt                  = 0;
static int    verbose                    = 0;
static double max_efficiency             = 0.95;
static bool   do_not_minimize_comm_costs = true;
//
// Everyone uses the same Strategy -- defaults to KNAPSACK.
//
DistributionMapping::Strategy
DistributionMapping::m_Strategy = DistributionMapping::KNAPSACK;

DistributionMapping::PVMF
DistributionMapping::m_BuildMap = &DistributionMapping::KnapSackProcessorMap;

const Array<int>&
DistributionMapping::ProcessorMap () const
{
    return m_procmap;
}

DistributionMapping::Strategy
DistributionMapping::strategy ()
{
    return DistributionMapping::m_Strategy;
}

int
DistributionMapping::CacheSize ()
{
    return m_Cache.size();
}

void
DistributionMapping::strategy (DistributionMapping::Strategy how)
{
    DistributionMapping::m_Strategy = how;

    switch (how)
    {
    case ROUNDROBIN:
        m_BuildMap = &DistributionMapping::RoundRobinProcessorMap;
        break;
    case KNAPSACK:
        m_BuildMap = &DistributionMapping::KnapSackProcessorMap;
        break;
    case METIS:
	m_BuildMap = &DistributionMapping::MetisProcessorMap;
    	break;
    default:
        BoxLib::Error("Bad DistributionMapping::Strategy");
    }
}

//
// We start out uninitialized.
//
bool DistributionMapping::m_Initialized = false;

bool
DistributionMapping::operator== (const DistributionMapping& rhs) const
{
    return m_procmap == rhs.m_procmap;
}

bool
DistributionMapping::operator!= (const DistributionMapping& rhs) const
{
    return !operator==(rhs);
}

void
DistributionMapping::Initialize ()
{
    DistributionMapping::m_Initialized = true;
        
    ParmParse pp("DistributionMapping");

    pp.query("verbose", verbose);

    pp.query("efficiency", max_efficiency);

    pp.query("do_not_minimize_comm_costs", do_not_minimize_comm_costs);

    std::string theStrategy;

    pp.query("metis_opt", metis_opt);

    if (pp.query("strategy", theStrategy))
    {
        if (theStrategy == "ROUNDROBIN")
        {
            strategy(ROUNDROBIN);
        }
        else if (theStrategy == "KNAPSACK")
        {
            strategy(KNAPSACK);
        }
	else if (theStrategy == "METIS")
	{
	    strategy(METIS);
	}
        else
        {
            std::string msg("Unknown strategy: ");
            msg += theStrategy;
            BoxLib::Warning(msg.c_str());
        }
    }
}

void
DistributionMapping::Finalize ()
{}

//
// Our cache of processor maps.
//
std::vector< Array<int> > DistributionMapping::m_Cache;

int
DistributionMapping::WhereToStart (int nprocs)
{
    if (m_Cache.size() == 0) return 0;
    //
    // What's the largest proc_map in our cache?
    //
    int N = m_Cache[0].size();
    for (int i = 1; i < m_Cache.size(); i++)
        if (N < m_Cache[i].size())
            N = m_Cache[i].size();

    N--; // Subtract off the extra space reserved for the sentinel value.

    BL_ASSERT(N > 0);

    if (N < nprocs)
        //
        // We've got idle CPU(s); start distribution from there.
        //
        return N;
    //
    // We don't have any idle CPUs; find the one with the fewest boxes.
    //
    std::vector<int> count(nprocs,0);

    for (int i = 0; i < m_Cache.size(); i++)
        for (int j = 0; j < m_Cache[i].size() - 1; j++)
            count[m_Cache[i][j]]++;

    N = 0;
    for (int i = 1; i < count.size(); i++)
        if (count[N] > count[i])
            N = i;

    BL_ASSERT(N >= 0 && N < nprocs);

    return N;
}

bool
DistributionMapping::GetMap (const BoxArray& boxes)
{
    const int N = boxes.size();

    BL_ASSERT(m_procmap.size() == N + 1);
    //
    // Search from back to front ...
    //
    for (int i = m_Cache.size() - 1; i >= 0; i--)
    {
        if (m_Cache[i].size() == N + 1)
        {
            const Array<int>& cached_procmap = m_Cache[i];

            for (int j = 0; j <= N; j++)
                m_procmap[j] = cached_procmap[j];

            BL_ASSERT(m_procmap[N] == ParallelDescriptor::MyProc());

            return true;
        }
    }

    return false;
}

DistributionMapping::DistributionMapping ()
{}

DistributionMapping::DistributionMapping (const Array<int>& pmap)
    :
    m_procmap(pmap)
{}

DistributionMapping::DistributionMapping (const BoxArray& boxes, int nprocs)
    :
    m_procmap(boxes.size()+1)
{
    define(boxes,nprocs);
}

DistributionMapping::DistributionMapping (const DistributionMapping& d1,
                                          const DistributionMapping& d2)
{
    const Array<int>& pmap_1 = d1.ProcessorMap();
    const Array<int>& pmap_2 = d2.ProcessorMap();

    const int L1 = pmap_1.size() - 1; // Length not including sentinel.
    const int L2 = pmap_2.size() - 1; // Length not including sentinel.

    m_procmap.resize(L1+L2+1);

    for (int i = 0; i < L1; i++)
        m_procmap[i] = pmap_1[i];

    for (int i = L1, j = 0; j < L2; i++, j++)
        m_procmap[i] = pmap_2[j];
    //
    // Set sentinel equal to our processor number.
    //
    m_procmap[m_procmap.size()-1] = ParallelDescriptor::MyProc();
}

void
DistributionMapping::define (const BoxArray& boxes, int nprocs)
{
    if (!(m_procmap.size() == boxes.size()+1))
        m_procmap.resize(boxes.size()+1);

    if (!GetMap(boxes))
    {
        (this->*m_BuildMap)(boxes,nprocs);

#if defined(BL_USE_MPI)
        //
        // We always append new processor maps.
        //
        DistributionMapping::m_Cache.push_back(m_procmap);
#endif
    }
}

DistributionMapping::~DistributionMapping () {}

void
DistributionMapping::FlushCache ()
{
    DistributionMapping::m_Cache.clear();
}

void
DistributionMapping::AddToCache (const DistributionMapping& dm)
{
    //
    // No need to maintain a cache when running in serial.
    //
    if (ParallelDescriptor::NProcs() < 2) return;

    bool              doit = true;
    const Array<int>& pmap = dm.ProcessorMap();

    if (pmap.size() > 0)
    {
        BL_ASSERT(pmap[pmap.size()-1] == ParallelDescriptor::MyProc());

        for (unsigned int i = 0; i < m_Cache.size() && doit; i++)
        {
            if (pmap.size() == m_Cache[i].size())
            {
                BL_ASSERT(pmap == m_Cache[i]);

                doit = false;
            }
        }

        if (doit)
            m_Cache.push_back(pmap);
    }
}

#ifndef BL_USE_METIS
void
DistributionMapping::MetisProcessorMap (const BoxArray& boxes, int nprocs)
{
    BoxLib::Error("METIS not available on this processor");
}
#else
void
DistributionMapping::MetisProcessorMap (const BoxArray& boxes, int nprocs)
{
    BL_PROFILE(BL_PROFILE_THIS_NAME() + "::MetisProcessorMap");
    BL_ASSERT(boxes.size() > 0);
    BL_ASSERT(m_procmap.size() == boxes.size()+1);
    if (boxes.size() <= nprocs || nprocs < 2)
    {
	RoundRobinProcessorMap(boxes, nprocs);
	return;
    }
    int nboxes = boxes.size();
    std::vector<int> xadj(nboxes+1);
    std::vector<int> adjncy;
    std::vector<int> vwgt(nboxes);
    std::vector<int> adjwgt;
    int wgtflag = 2;
    int numflag = 0;
    int nparts  = nprocs;
    int options[5] = {0, 0, 0, 0, 0};
    int edgecut;
    for ( int i = 0; i < nboxes; ++i ) 
    {
	vwgt[i] = boxes[i].volume();
    }
    int cnt = 0;
    for ( int i = 0; i < nboxes; ++i ) 
    {
	Box bx = BoxLib::grow(boxes[i], 1);
	xadj[i] = cnt;
	for ( int j = 0; j < nboxes; ++j )
	{
	    if ( j == i ) continue;
	    if ( bx.intersects(boxes[j]) )
	    {
		Box b = bx & boxes[j];
		adjncy.push_back(j);
		adjwgt.push_back(b.volume());
		cnt++;
	    }
	}
    }
    xadj[nboxes] = cnt;

    const Real strttime = ParallelDescriptor::second();

    if ( metis_opt != 0 ) wgtflag = 3;

    if ( nparts <= 8 )
    {
	METIS_PartGraphRecursive(
	    &nboxes, &xadj[0], &adjncy[0], &vwgt[0], &adjwgt[0],
	    &wgtflag, &numflag,  &nparts, options,
	    &edgecut, &m_procmap[0]);
    }
    else
    {
	METIS_PartGraphKway(
	    &nboxes, &xadj[0], &adjncy[0], &vwgt[0], &adjwgt[0],
	    &wgtflag, &numflag,  &nparts, options,
	    &edgecut, &m_procmap[0]);
    }

    const int  IOProc   = ParallelDescriptor::IOProcessorNumber();
    Real       stoptime = ParallelDescriptor::second() - strttime;

    if (verbose)
    {
        ParallelDescriptor::ReduceRealMax(stoptime,IOProc);

        double total = 0;
        std::vector<double> wgts(nprocs,0);
        for (int i = 0; i < nboxes; i++)
        {
            total += vwgt[i];
            wgts[m_procmap[i]] += vwgt[i];
        }
        double mx = wgts[0];
        for (int i = 1; i < nprocs; i++)
            if (wgts[i] > mx) mx = wgts[i];

        double efficiency = total/(nprocs*mx);

        if (ParallelDescriptor::IOProcessor())
        {
            std::cout << "METIS_PartGraphKway efficiency: " << efficiency << '\n';
            std::cout << "METIS_PartGraphKway time: " << stoptime << '\n';
            std::cout << "METIS_PartGraphKway edgecut: " << edgecut << '\n';
        }
    }

    m_procmap[nboxes] = ParallelDescriptor::MyProc();
}
#endif

void
DistributionMapping::RoundRobinProcessorMap (int nboxes, int nprocs)
{
    BL_ASSERT(nboxes > 0);

    m_procmap.resize(nboxes+1);

    int N = WhereToStart(nprocs);

    for (int i = 0; i < nboxes; i++)
        //
        // Start the round-robin at processor N.
        //
        m_procmap[i] = (i + N) % nprocs;
    //
    // Set sentinel equal to our processor number.
    //
    m_procmap[nboxes] = ParallelDescriptor::MyProc();
}

void
DistributionMapping::RoundRobinProcessorMap (const BoxArray& boxes, int nprocs)
{
    BL_ASSERT(boxes.size() > 0);
    BL_ASSERT(m_procmap.size() == boxes.size()+1);

    int N = WhereToStart(nprocs);

    for (int i = 0; i < boxes.size(); i++)
        //
        // Start the round-robin at processor N.
        //
        m_procmap[i] = (i + N) % nprocs;
    //
    // Set sentinel equal to our processor number.
    //
    m_procmap[boxes.size()] = ParallelDescriptor::MyProc();
}

class WeightedBox
{
    int  m_boxid;
    long m_weight;
public:
    WeightedBox () {}
    WeightedBox (int b, int w) : m_boxid(b), m_weight(w) {}
    long weight () const { return m_weight; }
    int  boxid ()  const { return m_boxid;  }

    bool operator< (const WeightedBox& rhs) const
    {
        return weight() > rhs.weight();
    }
};

class WeightedBoxList
{
    std::list<WeightedBox>* m_lb;
    long                    m_weight;
public:
    WeightedBoxList (std::list<WeightedBox>* lb) : m_lb(lb), m_weight(0) {}
    long weight () const
    {
        return m_weight;
    }
    void erase (std::list<WeightedBox>::iterator& it)
    {
        m_weight -= it->weight();
        m_lb->erase(it);
    }
    void push_back (const WeightedBox& bx)
    {
        m_weight += bx.weight();
        m_lb->push_back(bx);
    }
    std::list<WeightedBox>::const_iterator begin () const { return m_lb->begin(); }
    std::list<WeightedBox>::iterator begin ()             { return m_lb->begin(); }
    std::list<WeightedBox>::const_iterator end () const   { return m_lb->end();   }
    std::list<WeightedBox>::iterator end ()               { return m_lb->end();   }

    bool operator< (const WeightedBoxList& rhs) const
    {
        return weight() > rhs.weight();
    }
};

static
std::vector< std::list<int> >
knapsack (const std::vector<long>& pts, int nprocs)
{
    BL_PROFILE("knapsack()");

    const Real strttime = ParallelDescriptor::second();
    //
    // Sort balls by size largest first.
    //
    static std::list<int> empty_list;  // Work-around MSVC++ bug :-(

    std::vector< std::list<int> > result(nprocs, empty_list);

    std::vector<WeightedBox> lb;
    lb.reserve(pts.size());
    for (unsigned int i = 0; i < pts.size(); ++i)
    {
        lb.push_back(WeightedBox(i, pts[i]));
    }
    BL_ASSERT(lb.size() == pts.size());
    std::sort(lb.begin(), lb.end());
    BL_ASSERT(lb.size() == pts.size());
    //
    // For each ball, starting with heaviest, assign ball to the lightest box.
    //
    std::priority_queue<WeightedBoxList>   wblq;
    std::vector< std::list<WeightedBox>* > vbbs(nprocs);
    for (int i  = 0; i < nprocs; ++i)
    {
        vbbs[i] = new std::list<WeightedBox>;
        wblq.push(WeightedBoxList(vbbs[i]));
    }
    BL_ASSERT(int(wblq.size()) == nprocs);
    for (unsigned int i = 0; i < pts.size(); ++i)
    {
        WeightedBoxList wbl = wblq.top();
        wblq.pop();
        wbl.push_back(lb[i]);
        wblq.push(wbl);
    }
    BL_ASSERT(int(wblq.size()) == nprocs);
    std::list<WeightedBoxList> wblqg;
    while (!wblq.empty())
    {
        wblqg.push_back(wblq.top());
        wblq.pop();
    }
    BL_ASSERT(int(wblqg.size()) == nprocs);
    wblqg.sort();
    //
    // Compute the max weight and the sum of the weights.
    //
    double max_weight = 0;
    double sum_weight = 0;
    std::list<WeightedBoxList>::iterator it = wblqg.begin();
    for ( ; it != wblqg.end(); ++it)
    {
        long wgt = (*it).weight();
        sum_weight += wgt;
        max_weight = (wgt > max_weight) ? wgt : max_weight;
    }

    double efficiency = sum_weight/(nprocs*max_weight);

    if (verbose && ParallelDescriptor::IOProcessor())
        std::cout << "knapsack initial efficiency: " << efficiency << '\n';
top:

    std::list<WeightedBoxList>::iterator it_top = wblqg.begin();

    WeightedBoxList wbl_top = *it_top;
    //
    // For each ball in the heaviest box.
    //
    std::list<WeightedBox>::iterator it_wb = wbl_top.begin();

    if (efficiency > max_efficiency) goto bottom;

    for ( ; it_wb != wbl_top.end(); ++it_wb )
    {
        //
        // For each ball not in the heaviest box.
        //
        std::list<WeightedBoxList>::iterator it_chk = it_top;
        it_chk++;
        for ( ; it_chk != wblqg.end(); ++it_chk)
        {
            WeightedBoxList wbl_chk = *it_chk;
            std::list<WeightedBox>::iterator it_owb = wbl_chk.begin();
            for ( ; it_owb != wbl_chk.end(); ++it_owb)
            {
                //
                // If exchanging these two balls reduces the load balance,
                // then exchange them and go to top.  The way we are doing
                // things, sum_weight cannot change.  So the efficiency will
                // increase if after we switch the two balls *it_wb and
                // *it_owb the max weight is reduced.
                //
                double w_tb = (*it_top).weight() + (*it_owb).weight() - (*it_wb).weight();
                double w_ob = (*it_chk).weight() + (*it_wb).weight() - (*it_owb).weight();
                //
                // If the other ball reduces the weight of the top box when
                // swapped, then it will change the efficiency.
                //
                if (w_tb < (*it_top).weight() && w_ob < (*it_top).weight())
                {
                    //
                    // Adjust the sum weight and the max weight.
                    //
                    WeightedBox wb = *it_wb;
                    WeightedBox owb = *it_owb;
                    wblqg.erase(it_top);
                    wblqg.erase(it_chk);
                    wbl_top.erase(it_wb);
                    wbl_chk.erase(it_owb);
                    wbl_top.push_back(owb);
                    wbl_chk.push_back(wb);
                    std::list<WeightedBoxList> tmp;
                    tmp.push_back(wbl_top);
                    tmp.push_back(wbl_chk);
                    tmp.sort();
                    wblqg.merge(tmp);
                    max_weight = (*wblqg.begin()).weight();
                    efficiency = sum_weight/(nprocs*max_weight);
                    goto top;
                }
            }
        }
    }

 bottom:
    //
    // Here I am "load-balanced".
    //
    std::list<WeightedBoxList>::const_iterator cit = wblqg.begin();
    for (int i = 0; i < nprocs; ++i)
    {
        const WeightedBoxList& wbl = *cit;
        std::list<WeightedBox>::const_iterator it1 = wbl.begin();
        for ( ; it1 != wbl.end(); ++it1)
        {
            result[i].push_back((*it1).boxid());
        }
        ++cit;
    }

    if (verbose && ParallelDescriptor::IOProcessor())
    {
        const Real stoptime = ParallelDescriptor::second() - strttime;

        std::cout << "knapsack final efficiency: " << efficiency << '\n';
        std::cout << "knapsack time: " << stoptime << '\n';
    }

    for (int i  = 0; i < nprocs; i++) delete vbbs[i];

    return result;
}

static
void
SwapAndTest (const std::map< int,std::vector<int>,std::greater<int> >& samesize,
             const std::vector< std::vector<int> >&                    nbrs,
             std::vector<int>&                                         procmap,
             std::vector<long>&                                        percpu)
{
    for (std::map< int,std::vector<int>,std::greater<int> >::const_iterator it = samesize.begin();
         it != samesize.end();
         ++it)
    {
        for (std::vector<int>::const_iterator lit1 = it->second.begin();
             lit1 != it->second.end();
             ++lit1)
        {
            std::vector<int>::const_iterator lit2 = lit1;

            const int ilit1 = *lit1;

            lit2++;

            for ( ; lit2 != it->second.end(); ++lit2)
            {
                const int ilit2 = *lit2;

                BL_ASSERT(ilit1 != ilit2);
                //
                // Don't consider Boxes on the same CPU.
                //
                if (procmap[ilit1] == procmap[ilit2]) continue;
                //
                // Will swapping these boxes decrease latency?
                //
                const long percpu_lit1 = percpu[procmap[ilit1]];
                const long percpu_lit2 = percpu[procmap[ilit2]];
                //
                // Now change procmap & redo necessary calculations ...
                //
                std::swap(procmap[ilit1],procmap[ilit2]);

                const int pmap1 = procmap[ilit1];
                const int pmap2 = procmap[ilit2];
                //
                // Update percpu[] in place.
                //
                std::vector<int>::const_iterator end1 = nbrs[ilit1].end();

                for (std::vector<int>::const_iterator it = nbrs[ilit1].begin(); it != end1; ++it)
                {
                    const int pmapstar = procmap[*it];

                    if (pmapstar == pmap2)
                    {
                        percpu[pmap1]++;
                        percpu[pmap2]++;
                    }
                    else if (pmapstar == pmap1)
                    {
                        percpu[pmap1]--;
                        percpu[pmap2]--;
                    }
                    else
                    {
                        percpu[pmap2]--;
                        percpu[pmap1]++;
                    }
                }

                std::vector<int>::const_iterator end2 = nbrs[ilit2].end();

                for (std::vector<int>::const_iterator it = nbrs[ilit2].begin(); it != end2; ++it)
                {
                    const int pmapstar = procmap[*it];

                    if (pmapstar == pmap1)
                    {
                        percpu[pmap1]++;
                        percpu[pmap2]++;
                    }
                    else if (pmapstar == pmap2)
                    {
                        percpu[pmap1]--;
                        percpu[pmap2]--;
                    }
                    else
                    {
                        percpu[pmap1]--;
                        percpu[pmap2]++;
                    }
                }

                const long cost_old = percpu_lit1  + percpu_lit2;
                const long cost_new = percpu[pmap1]+ percpu[pmap2];

                if (cost_new >= cost_old)
                {
                    //
                    // Undo our changes ...
                    //
                    std::swap(procmap[ilit1],procmap[ilit2]);

                    percpu[procmap[ilit1]] = percpu_lit1;
                    percpu[procmap[ilit2]] = percpu_lit2;
                }
            }
        }
    }
}

//
// Try to "improve" the knapsack()d procmap ...
//

static
void
MinimizeCommCosts (std::vector<int>&        procmap,
                   const BoxArray&          ba,
                   const std::vector<long>& pts,
                   int                      nprocs)
{
    BL_PROFILE("MinimizeCommCosts()");

    BL_ASSERT(ba.size() == pts.size());
    BL_ASSERT(procmap.size() >= ba.size());

    if (nprocs < 2 || do_not_minimize_comm_costs) return;

    const Real strttime = ParallelDescriptor::second();
    //
    // Build a data structure that'll tell us who are our neighbors.
    //
    std::vector< std::vector<int> > nbrs(ba.size());
    //
    // Our "grow" factor; i.e. how far our tentacles grope for our neighbors.
    //
    const int Ngrow = 1;

    BoxArray grown(ba.size());

    for (int i = 0; i < ba.size(); i++)
        grown.set(i,BoxLib::grow(ba[i],Ngrow));

    for (int i = 0; i < grown.size(); i++)
    {
        std::list<int> li;

        std::vector< std::pair<int,Box> > isects = ba.intersections(grown[i]);

        for (int j = 0; j < isects.size(); j++)
            if (isects[j].first != i)
                li.push_back(isects[j].first);

        nbrs[i].resize(li.size());

        int k = 0;
        for (std::list<int>::const_iterator it = li.begin();
             it != li.end();
             ++it, ++k)
        {
            nbrs[i][k] = *it;
        }
    }

    if (verbose > 1 && ParallelDescriptor::IOProcessor())
    {
        std::cout << "The neighbors list:\n";

        for (int i = 0; i < nbrs.size(); i++)
        {
            std::cout << i << "\t:";

            for (std::vector<int>::const_iterator it = nbrs[i].begin();
                 it != nbrs[i].end();
                 ++it)
            {
                std::cout << *it << ' ';
            }

            std::cout << "\n";
        }
    }
    //
    // Want lists of box IDs having the same size.
    //
    std::map< int,std::vector<int>,std::greater<int> > samesize;

    for (int i = 0; i < pts.size(); i++)
        samesize[pts[i]].push_back(i);

    if (verbose > 1 && ParallelDescriptor::IOProcessor())
    {
        std::cout << "Boxes sorted via numPts():\n";

        for (std::map< int,std::vector<int>,std::greater<int> >::const_iterator it = samesize.begin();
             it != samesize.end();
             ++it)
        {
            std::cout << it->first << "\t:";

            for (std::vector<int>::const_iterator lit = it->second.begin();
                 lit != it->second.end();
                 ++lit)
            {
                std::cout << *lit << ' ';
            }

            std::cout << "\n";
        }
    }
    //
    // Build a data structure to maintain the latency count on a per-CPU basis.
    //
    std::vector<long> percpu(nprocs,0L);

    for (int i = 0; i < nbrs.size(); i++)
    {
        for (std::vector<int>::const_iterator it = nbrs[i].begin();
             it != nbrs[i].end();
             ++it)
        {
            if (procmap[i] != procmap[*it]) percpu[procmap[*it]]++;
        }
    }

    if (verbose && ParallelDescriptor::IOProcessor())
    {
        long cnt = 0;
        for (int i = 0; i < percpu.size(); i++) cnt += percpu[i];
        std::cout << "Initial off-CPU connection count: " << cnt << '\n';
    }
    //
    // Originally I called SwapAndTest() until no links were changed.
    // This turned out to be very costly.  Next I tried calling it no
    // more than three times, or until no links were changed.  But after
    // testing a bunch of quite large meshes, it appears that the first
    // call gets "most" of the benefit of multiple calls.
    //
    SwapAndTest(samesize,nbrs,procmap,percpu);

    if (verbose && ParallelDescriptor::IOProcessor())
    {
        long cnt = 0;
        for (int i = 0; i < percpu.size(); i++) cnt += percpu[i];
        std::cout << "Final   off-CPU connection count: " << cnt << '\n';
    }

    if (verbose && ParallelDescriptor::IOProcessor())
    {
        const Real stoptime = ParallelDescriptor::second() - strttime;

        std::cout << "MinimizeCommCosts() time: " << stoptime << '\n';
    }
}

void
DistributionMapping::KnapSackProcessorMap (const std::vector<long>& pts,
                                           int                      nprocs)
{
    BL_PROFILE(BL_PROFILE_THIS_NAME() + "::KnapSackProcessorMap(vector,");

    BL_ASSERT(pts.size() > 0);

    m_procmap.resize(pts.size()+1);

    if (int(pts.size()) <= nprocs || nprocs < 2)
    {
        RoundRobinProcessorMap(pts.size(),nprocs);
    }
    else
    {
        int N = WhereToStart(nprocs);

        std::vector< std::list<int> > vec = knapsack(pts,nprocs);

        BL_ASSERT(int(vec.size()) == nprocs);

        std::list<int>::iterator lit;

        for (unsigned int i = 0; i < vec.size(); i++)
        {
            int where = (i + N) % nprocs;

            for (lit = vec[i].begin(); lit != vec[i].end(); ++lit)
                m_procmap[*lit] = where;
        }
        //
        // Set sentinel equal to our processor number.
        //
        m_procmap[pts.size()] = ParallelDescriptor::MyProc();
    }
}

void
DistributionMapping::KnapSackProcessorMap (const BoxArray& boxes,
					   int             nprocs)
{
    BL_PROFILE(BL_PROFILE_THIS_NAME() + "::KnapSackProcessorMap");
    BL_ASSERT(boxes.size() > 0);
    BL_ASSERT(m_procmap.size() == boxes.size()+1);

    if (boxes.size() <= nprocs || nprocs < 2)
    {
        RoundRobinProcessorMap(boxes,nprocs);
    }
    else
    {
        int N = WhereToStart(nprocs);

        std::vector<long> pts(boxes.size());

        for (unsigned int i = 0; i < pts.size(); i++)
            pts[i] = boxes[i].numPts();

        std::vector< std::list<int> > vec = knapsack(pts,nprocs);

        BL_ASSERT(int(vec.size()) == nprocs);

        std::list<int>::iterator lit;

        for (unsigned int i = 0; i < vec.size(); i++)
        {
            int where = (i + N) % nprocs;

            for (lit = vec[i].begin(); lit != vec[i].end(); ++lit)
                m_procmap[*lit] = where;
        }

	MinimizeCommCosts(m_procmap,boxes,pts,nprocs);
        //
        // Set sentinel equal to our processor number.
        //
        m_procmap[boxes.size()] = ParallelDescriptor::MyProc();
    }
}

void
DistributionMapping::CacheStats (std::ostream& os)
{
    os << "The DistributionMapping cache contains "
       << DistributionMapping::m_Cache.size()
       << " Processor Map(s):\n";

    if (!DistributionMapping::m_Cache.empty())
    {
        for (unsigned int i = 0; i < m_Cache.size(); i++)
        {
            os << "\tMap #"
               << i
               << " is of length "
               << m_Cache[i].size()
               << '\n';
        }
        os << '\n';
    }
}

std::ostream&
operator<< (std::ostream&              os,
            const DistributionMapping& pmap)
{
    os << "(DistributionMapping" << '\n';
    //
    // Do not print the sentinel value.
    //
    for (int i = 0; i < pmap.ProcessorMap().size() - 1; i++)
    {
        os << "m_procmap[" << i << "] = " << pmap.ProcessorMap()[i] << '\n';
    }

    os << ')' << '\n';

    if (os.fail())
        BoxLib::Error("operator<<(ostream &, DistributionMapping &) failed");

    return os;
}
