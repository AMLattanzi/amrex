
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

namespace
{
    //
    // Set default values for these in Initialize()!!!
    //
    int    verbose;
    int    sfc_threshold;
    double max_efficiency;
    bool   do_full_knapsack;
};

DistributionMapping::Strategy DistributionMapping::m_Strategy;

DistributionMapping::PVMF DistributionMapping::m_BuildMap = 0;

const Array<int>&
DistributionMapping::ProcessorMap () const
{
    return m_ref->m_pmap;
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
    case SFC:
        m_BuildMap = &DistributionMapping::SFCProcessorMap;
        break;
    default:
        BoxLib::Error("Bad DistributionMapping::Strategy");
    }
}

bool
DistributionMapping::operator== (const DistributionMapping& rhs) const
{
    return m_ref->m_pmap == rhs.m_ref->m_pmap;
}

bool
DistributionMapping::operator!= (const DistributionMapping& rhs) const
{
    return !operator==(rhs);
}

void
DistributionMapping::Initialize ()
{
    //
    // Set defaults here!!!
    //
    verbose          = 1;
    sfc_threshold    = 4;
    max_efficiency   = 0.9;
    do_full_knapsack = false;

    ParmParse pp("DistributionMapping");

    pp.query("verbose",          verbose);
    pp.query("efficiency",       max_efficiency);
    pp.query("do_full_knapsack", do_full_knapsack);
    pp.query("sfc_threshold",    sfc_threshold);

    std::string theStrategy;

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
        else if (theStrategy == "SFC")
        {
            strategy(SFC);
        }
        else
        {
            std::string msg("Unknown strategy: ");
            msg += theStrategy;
            BoxLib::Warning(msg.c_str());
        }
    }
    else
    {
        //
        // We default to SFC.
        //
        strategy(SFC);
    }
}

void
DistributionMapping::Finalize ()
{
    DistributionMapping::m_BuildMap = 0;

    DistributionMapping::m_Cache.clear();
}

//
// Our cache of processor maps.
//
std::map< int,LnClassPtr<DistributionMapping::Ref> > DistributionMapping::m_Cache;

Array<int>
DistributionMapping::LeastUsedCPUs (int nprocs)
{
    Array<int> result(nprocs);

#ifdef BL_USE_MPI
    Array<long> bytes(nprocs);

    MPI_Allgather(&BoxLib::total_bytes_allocated_in_fabs,
                  1,
                  ParallelDescriptor::Mpi_typemap<long>::type(),
                  bytes.dataPtr(),
                  1,
                  ParallelDescriptor::Mpi_typemap<long>::type(),
                  ParallelDescriptor::Communicator());

    std::vector<LIpair> LIpairV;

    LIpairV.reserve(nprocs);

    for (int i = 0; i < nprocs; i++)
        LIpairV.push_back(LIpair(bytes[i],i));

    std::stable_sort(LIpairV.begin(), LIpairV.end(), LIpairComp());

    for (int i = 0; i < nprocs; i++)
    {
        result[i] = LIpairV[i].second;
    }
#else
    for (int i = 0; i < nprocs; i++)
    {
        result[i] = i;
    }
#endif

    return result;
}

bool
DistributionMapping::GetMap (const BoxArray& boxes)
{
    const int N = boxes.size();

    BL_ASSERT(m_ref->m_pmap.size() == N + 1);

    std::map< int,LnClassPtr<Ref> >::const_iterator it = m_Cache.find(N+1);

    if (it != m_Cache.end())
    {
        m_ref = it->second;

        BL_ASSERT(m_ref->m_pmap[N] == ParallelDescriptor::MyProc());

        return true;
    }

    return false;
}

DistributionMapping::Ref::Ref () {}

DistributionMapping::DistributionMapping ()
    :
    m_ref(new DistributionMapping::Ref)
{}

DistributionMapping::DistributionMapping (const DistributionMapping& rhs)
    :
    m_ref(rhs.m_ref)
{}

DistributionMapping&
DistributionMapping::operator= (const DistributionMapping& rhs)
{
    m_ref = rhs.m_ref;

    return *this;
}

DistributionMapping::Ref::Ref (const Array<int>& pmap)
    :
    m_pmap(pmap)
{}

DistributionMapping::DistributionMapping (const Array<int>& pmap)
    :
    m_ref(new DistributionMapping::Ref(pmap))
{}

DistributionMapping::Ref::Ref (int len)
    :
    m_pmap(len)
{}

DistributionMapping::DistributionMapping (const BoxArray& boxes, int nprocs)
    :
    m_ref(new DistributionMapping::Ref(boxes.size() + 1))
{
    define(boxes,nprocs);
}

DistributionMapping::Ref::Ref (const Ref& rhs)
    :
    m_pmap(rhs.m_pmap)
{}

DistributionMapping::DistributionMapping (const DistributionMapping& d1,
                                          const DistributionMapping& d2)
    :
    m_ref(new DistributionMapping::Ref(d1.size() + d2.size() - 1))

{
    const Array<int>& pmap_1 = d1.ProcessorMap();
    const Array<int>& pmap_2 = d2.ProcessorMap();

    const int L1 = pmap_1.size() - 1; // Length not including sentinel.
    const int L2 = pmap_2.size() - 1; // Length not including sentinel.

    for (int i = 0; i < L1; i++)
        m_ref->m_pmap[i] = pmap_1[i];

    for (int i = L1, j = 0; j < L2; i++, j++)
        m_ref->m_pmap[i] = pmap_2[j];
    //
    // Set sentinel equal to our processor number.
    //
    m_ref->m_pmap[m_ref->m_pmap.size()-1] = ParallelDescriptor::MyProc();
}

void
DistributionMapping::define (const BoxArray& boxes, int nprocs)
{
    if (m_ref->m_pmap.size() != boxes.size() + 1)
    {
        m_ref->m_pmap.resize(boxes.size() + 1);
    }

    if (nprocs == 1)
    {
        for (int i = 0; i < m_ref->m_pmap.size(); i++)
        {
            m_ref->m_pmap[i] = 0;
        }
    }
    else
    {
        if (!GetMap(boxes))
        {
            BL_ASSERT(m_BuildMap != 0);

            (this->*m_BuildMap)(boxes,nprocs);
            //
            // Add the new processor map to the cache.
            //
            m_Cache.insert(std::make_pair(m_ref->m_pmap.size(),m_ref));
        }
    }
}

DistributionMapping::~DistributionMapping () {}

void
DistributionMapping::FlushCache ()
{
    CacheStats(std::cout);
    //
    // Remove maps that aren't referenced anywhere else.
    //
    std::map< int,LnClassPtr<Ref> >::iterator it = m_Cache.begin();

    while (it != m_Cache.end())
    {
        if (it->second.linkCount() == 1)
        {
            m_Cache.erase(it++);
        }
        else
        {
            ++it;
        }
    }
}

void
DistributionMapping::RoundRobinDoIt (int                  nboxes,
                                     int                  nprocs,
                                     std::vector<LIpair>* LIpairV)
{
    Array<int> ord = LeastUsedCPUs(nprocs);

    if (LIpairV)
    {
        BL_ASSERT(LIpairV->size() == nboxes);

        for (int i = 0; i < nboxes; i++)
        {
            m_ref->m_pmap[(*LIpairV)[i].second] = ord[i%nprocs];
        }
    }
    else
    {
        for (int i = 0; i < nboxes; i++)
        {
            m_ref->m_pmap[i] = ord[i%nprocs];
        }
    }
    //
    // Set sentinel equal to our processor number.
    //
    m_ref->m_pmap[nboxes] = ParallelDescriptor::MyProc();
}

void
DistributionMapping::RoundRobinProcessorMap (int nboxes, int nprocs)
{
    BL_ASSERT(nboxes > 0);

    if (m_ref->m_pmap.size() != nboxes + 1)
    {
        m_ref->m_pmap.resize(nboxes + 1);
    }

    RoundRobinDoIt(nboxes, nprocs);
}

void
DistributionMapping::RoundRobinProcessorMap (const BoxArray& boxes, int nprocs)
{
    BL_ASSERT(boxes.size() > 0);
    BL_ASSERT(m_ref->m_pmap.size() == boxes.size() + 1);
    //
    // Create ordering of boxes from largest to smallest.
    // When we round-robin the boxes we want to go from largest
    // to smallest box, starting from the CPU having the least
    // amount of FAB data to the one having the most.  This "should"
    // help even out the FAB data distribution when running on large
    // numbers of CPUs, where the lower levels of the calculation are
    // using RoundRobin to lay out fewer than NProc boxes across
    // the CPUs.
    //
    std::vector<LIpair> LIpairV;

    LIpairV.reserve(boxes.size());

    for (int i = 0; i < boxes.size(); i++)
    {
        LIpairV.push_back(LIpair(boxes[i].numPts(),i));
    }
    //
    // This call does the sort() from least to most numPts().
    // Will need to reverse the order afterwards.
    //
    std::stable_sort(LIpairV.begin(), LIpairV.end(), LIpairComp());

    std::reverse(LIpairV.begin(), LIpairV.end());

    RoundRobinDoIt(boxes.size(), nprocs, &LIpairV);
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
knapsack (const std::vector<long>& wgts, int nprocs)
{
    BL_PROFILE("knapsack()");

    const Real strttime = ParallelDescriptor::second();
    //
    // Sort balls by size largest first.
    //
    std::vector< std::list<int> > result(nprocs);

    std::vector<WeightedBox> lb;
    lb.reserve(wgts.size());
    for (unsigned int i = 0; i < wgts.size(); ++i)
    {
        lb.push_back(WeightedBox(i, wgts[i]));
    }
    BL_ASSERT(lb.size() == wgts.size());
    std::sort(lb.begin(), lb.end());
    BL_ASSERT(lb.size() == wgts.size());
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
    for (unsigned int i = 0; i < wgts.size(); ++i)
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
    for (std::list<WeightedBoxList>::const_iterator end =  wblqg.end(); it != end; ++it)
    {
        long wgt = (*it).weight();
        sum_weight += wgt;
        max_weight = (wgt > max_weight) ? wgt : max_weight;
    }

    int    npasses            = 0;
    double efficiency         = sum_weight/(nprocs*max_weight);
    double initial_efficiency = efficiency;

top:

    std::list<WeightedBoxList>::iterator it_top = wblqg.begin();

    WeightedBoxList wbl_top = *it_top;
    //
    // For each ball in the heaviest box.
    //
    std::list<WeightedBox>::iterator it_wb = wbl_top.begin();

    if (efficiency > max_efficiency || !do_full_knapsack) goto bottom;

    npasses++;

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
        std::list<WeightedBox>::const_iterator it1 = wbl.begin(), end = wbl.end();
        for ( ; it1 != end; ++it1)
        {
            result[i].push_back((*it1).boxid());
        }
        ++cit;
    }

    if (verbose && ParallelDescriptor::IOProcessor())
    {
        const Real stoptime    = ParallelDescriptor::second() - strttime;
        const Real improvement =  (efficiency - initial_efficiency) / initial_efficiency * 100;

        std::cout << "KNAPSACK efficiency: " << efficiency
                  << ", passes: "            << npasses
                  << ", improvement: "       << improvement
                  << "%, time: "             << stoptime << '\n';
    }

    for (int i  = 0; i < nprocs; i++) delete vbbs[i];

    return result;
}

void
DistributionMapping::KnapSackDoIt (const std::vector<long>& wgts,
                                   int                      nprocs)
{
    Array<int> ord = LeastUsedCPUs(nprocs);

    std::vector< std::list<int> > vec = knapsack(wgts,nprocs);

    BL_ASSERT(vec.size() == nprocs);

    Array<long> wgts_per_cpu(nprocs,0);

    for (unsigned int i = 0; i < vec.size(); i++)
    {
        for (std::list<int>::iterator lit = vec[i].begin(), end = vec[i].end(); lit != end; ++lit)
            wgts_per_cpu[i] += wgts[*lit];
    }

    std::vector<LIpair> LIpairV;

    LIpairV.reserve(nprocs);

    for (int i = 0; i < nprocs; i++)
    {
        LIpairV.push_back(LIpair(wgts_per_cpu[i],i));
    }
    //
    // This call does the sort() from least to most weight.
    // Will need to reverse the order afterwards.
    //
    std::stable_sort(LIpairV.begin(), LIpairV.end(), LIpairComp());

    std::reverse(LIpairV.begin(), LIpairV.end());

    for (unsigned int i = 0; i < vec.size(); i++)
    {
        const int idx = LIpairV[i].second;
        const int cpu = ord[i%nprocs];

        for (std::list<int>::iterator lit = vec[idx].begin(), end = vec[idx].end(); lit != end; ++lit)
        {
            m_ref->m_pmap[*lit] = cpu;
        }
    }
    //
    // Set sentinel equal to our processor number.
    //
    m_ref->m_pmap[wgts.size()] = ParallelDescriptor::MyProc();
}

void
DistributionMapping::KnapSackProcessorMap (const std::vector<long>& wgts,
                                           int                      nprocs)
{
    BL_ASSERT(wgts.size() > 0);

    if (m_ref->m_pmap.size() !=  wgts.size() + 1)
    {
        m_ref->m_pmap.resize(wgts.size() + 1);
    }

    if (wgts.size() <= nprocs || nprocs < 2)
    {
        RoundRobinProcessorMap(wgts.size(),nprocs);
    }
    else
    {
        KnapSackDoIt(wgts, nprocs);
    }
}

void
DistributionMapping::KnapSackProcessorMap (const BoxArray& boxes,
					   int             nprocs)
{
    BL_ASSERT(boxes.size() > 0);
    BL_ASSERT(m_ref->m_pmap.size() == boxes.size()+1);

    if (boxes.size() <= nprocs || nprocs < 2)
    {
        RoundRobinProcessorMap(boxes,nprocs);
    }
    else
    {
        std::vector<long> wgts;

        wgts.reserve(boxes.size());

        for (unsigned int i = 0; i < boxes.size(); i++)
            wgts.push_back(boxes[i].numPts());

        KnapSackDoIt(wgts, nprocs);
    }
}

namespace
{
    struct SFCToken
    {
        class Compare
        {
        public:
            bool operator () (const SFCToken& lhs,
                              const SFCToken& rhs) const;
        };

        SFCToken (int box, const IntVect& idx, Real vol)
            :
            m_box(box), m_idx(idx), m_vol(vol) {}

        int     m_box;
        IntVect m_idx;
        Real    m_vol;

        static int MaxPower;
    };
}

int SFCToken::MaxPower = 64;

bool
SFCToken::Compare::operator () (const SFCToken& lhs,
                                const SFCToken& rhs) const
{
    for (int i = SFCToken::MaxPower - 1; i >= 0; --i)
    {
        const int N = (1<<i);

        for (int j = BL_SPACEDIM-1; j >= 0; --j)
        {
            int il = lhs.m_idx[j]/N;
            int ir = rhs.m_idx[j]/N;

            if (il < ir)
            {
                return true;
            }
            else if (il > ir)
            {
                return false;
            }
        }
    }

    return false;
}

static
std::vector< std::vector<int> >
Distribute (const std::vector<SFCToken>& tokens,
            int                          nprocs,
            Real                         volpercpu)

{
    int K         = 0;
    Real totalvol = 0;

    const int Navg = tokens.size() / nprocs;

    std::vector< std::vector<int> > v(nprocs);

    for (int i = 0; i < nprocs; i++)
    {
        int  cnt = 0;
        Real vol = 0;

        v[i].reserve(Navg + 2);

        for ( ;
              K < tokens.size() && (i == (nprocs-1) || vol < volpercpu);
              cnt++, K++)
        {
            vol += tokens[K].m_vol;

            v[i].push_back(tokens[K].m_box);
        }

        totalvol += vol;

        if ((totalvol/(i+1)) > volpercpu &&
            cnt > 1                      &&
            K < tokens.size())
        {
            K--;
            v[i].pop_back();
            totalvol -= tokens[K].m_vol;;
        }
    }

#ifndef NDEBUG
    int cnt = 0;
    for (int i = 0; i < nprocs; i++)
        cnt += v[i].size();
    BL_ASSERT(cnt == tokens.size());
#endif

    return v;
}

void
DistributionMapping::SFCProcessorMapDoIt (const BoxArray&          boxes,
                                          const std::vector<long>& wgts,
                                          int                      nprocs)
{
    const Real strttime = ParallelDescriptor::second();

    std::vector<SFCToken> tokens;

    tokens.reserve(boxes.size());

    int maxijk = 0;

    for (int i = 0; i < boxes.size(); i++)
    {
        tokens.push_back(SFCToken(i,boxes[i].smallEnd(),wgts[i]));

        for (int j = 0; j < BL_SPACEDIM; j++)
            maxijk = std::max(maxijk, tokens[i].m_idx[j]);
    }
    //
    // Set SFCToken::MaxPower for BoxArray.
    //
    int m = 0;
    for ( ; (1<<m) <= maxijk; m++)
        ;
    SFCToken::MaxPower = m;
    //
    // Put'm in Morton space filling curve order.
    //
    std::sort(tokens.begin(), tokens.end(), SFCToken::Compare());
    //
    // Split'm up as equitably as possible per CPU.
    //
    Real volpercpu = 0;
    for (int i = 0; i < tokens.size(); i++)
        volpercpu += tokens[i].m_vol;
    volpercpu /= nprocs;

    //std::cout << "volpercpu = " << volpercpu << '\n';

    std::vector< std::vector<int> > vec = Distribute(tokens,nprocs,volpercpu);

    Array<int> ord = LeastUsedCPUs(nprocs);

    Array<long> wgts_per_cpu(nprocs,0);

    for (unsigned int i = 0; i < vec.size(); i++)
    {
        //std::cout << "vec[" << i << "]: wgt: ";
        for (int j = 0; j < vec[i].size(); j++)
            wgts_per_cpu[i] += wgts[vec[i][j]];
        //std::cout << wgts_per_cpu[i] << '\n';
    }

    std::vector<LIpair> LIpairV;

    LIpairV.reserve(nprocs);

    for (int i = 0; i < nprocs; i++)
    {
        LIpairV.push_back(LIpair(wgts_per_cpu[i],i));
    }
    //
    // This call does the sort() from least to most weight.
    // Will need to reverse the order afterwards.
    //
    std::stable_sort(LIpairV.begin(), LIpairV.end(), LIpairComp());

    std::reverse(LIpairV.begin(), LIpairV.end());

    for (int i = 0; i < nprocs; i++)
    {
        const int cpu = ord[i%nprocs];
        const int idx = LIpairV[i].second;

        for (int j = 0; j < vec[idx].size(); j++)
        {
            m_ref->m_pmap[vec[idx][j]] = cpu;
        }
    }
    //
    // Set sentinel equal to our processor number.
    //
    m_ref->m_pmap[boxes.size()] = ParallelDescriptor::MyProc();

    if (verbose)
    {
        const Real stoptime = ParallelDescriptor::second() - strttime;

        std::vector<Real> wgt(nprocs,0);

        for (int i = 0; i < tokens.size(); i++)
            wgt[m_ref->m_pmap[tokens[i].m_box]] += tokens[i].m_vol;

        Real sum_wgt = 0, max_wgt = 0;
        for (int i = 0; i < wgt.size(); i++)
        {
            if (wgt[i] > max_wgt)
                max_wgt = wgt[i];
            sum_wgt += wgt[i];
        }

        if (ParallelDescriptor::IOProcessor())
        {
            std::cout << "SFC efficiency: " << (sum_wgt/(nprocs*max_wgt))
                      << "\nSFC time: "     << stoptime << '\n';
        }
    }
}

void
DistributionMapping::SFCProcessorMap (const BoxArray& boxes,
                                      int             nprocs)
{
    BL_ASSERT(boxes.size() > 0);

    if (m_ref->m_pmap.size() != boxes.size() + 1)
    {
        m_ref->m_pmap.resize(boxes.size()+1);
    }

    if (boxes.size() <= nprocs || nprocs < 2)
    {
        RoundRobinProcessorMap(boxes,nprocs);
    }
    else if (boxes.size() < sfc_threshold*nprocs)
    {
        KnapSackProcessorMap(boxes,nprocs);
    }
    else
    {
        std::vector<long> wgts;

        wgts.reserve(boxes.size());

        for (int i = 0; i < boxes.size(); i++)
            wgts.push_back(boxes[i].volume());

        SFCProcessorMapDoIt(boxes,wgts,nprocs);
    }
}

void
DistributionMapping::SFCProcessorMap (const BoxArray&          boxes,
                                      const std::vector<long>& wgts,
                                      int                      nprocs)
{
    BL_ASSERT(boxes.size() > 0);
    BL_ASSERT(boxes.size() == wgts.size());

    if (m_ref->m_pmap.size() != wgts.size() + 1)
    {
        m_ref->m_pmap.resize(wgts.size()+1);
    }

    if (boxes.size() <= nprocs || nprocs < 2)
    {
        RoundRobinProcessorMap(boxes,nprocs);
    }
    else if (boxes.size() < sfc_threshold*nprocs)
    {
        KnapSackProcessorMap(wgts,nprocs);
    }
    else
    {
        SFCProcessorMapDoIt(boxes,wgts,nprocs);
    }
}

void
DistributionMapping::CacheStats (std::ostream& os)
{
    if (verbose && ParallelDescriptor::IOProcessor() && m_Cache.size())
    {
        os << "DistributionMapping::m_Cache.size() = "
           << m_Cache.size()
           << " [ (refs,size): ";

        std::map< int,LnClassPtr<Ref> >::const_iterator it;

        for (it = m_Cache.begin(); it != m_Cache.end(); ++it)
        {
            os << '(' << it->second.linkCount() << ',' << it->second->m_pmap.size()-1 << ") ";
        }

        os << "]\n";
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
        os << "m_pmap[" << i << "] = " << pmap.ProcessorMap()[i] << '\n';
    }

    os << ')' << '\n';

    if (os.fail())
        BoxLib::Error("operator<<(ostream &, DistributionMapping &) failed");

    return os;
}
