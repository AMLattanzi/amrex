
#include <new>
#include <iostream>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <cmath>
using std::ios;
using std::set_new_handler;

#include <unistd.h>

#include "ComputeAmrDataNorms.H"
#include "ParmParse.H"
#include "ParallelDescriptor.H"
#include "DataServices.H"
#include "Utility.H"

#ifndef NDEBUG
#include "TV_TempWrite.H"
#endif

static
void
PrintUsage (const char* progName)
{
    std::cout << '\n';
    std::cout << "This routine reads a pltfile and calculates the Linfty," << std::endl
         << "L1 and L2 norms ov every component.                    " << std::endl
         << std::endl;
    std::cout << "Usage:" << '\n';
    std::cout << progName << '\n';
    std::cout << "    infile=inputFileName" << '\n';
    std::cout << "   [outfile=outputFileName]" << '\n';
    std::cout << "   [-help]" << '\n';
    std::cout << "   [-verbose]" << '\n';
    std::cout << '\n';
    std::cout << " Note: outfile required if verbose used" << '\n';
    exit(1);
}

int
main (int   argc,
      char* argv[])
{
    if (argc == 1)
        PrintUsage(argv[0]);
    //
    // Make sure to catch new failures.
    //
    set_new_handler(Utility::OutOfMemory);

    ParallelDescriptor::StartParallel(&argc, &argv);

    ParmParse pp(argc-1,argv+1);

    if (pp.contains("help"))
        PrintUsage(argv[0]);

    FArrayBox::setFormat(FABio::FAB_IEEE_32);
    //
    // Scan the arguments.
    //
    aString iFile;

    bool verbose = false;
    if (pp.contains("verbose"))
    {
        verbose = true;
        AmrData::SetVerbose(true);
    }
    pp.query("infile", iFile);
    if (iFile.isNull())
        BoxLib::Abort("You must specify `infile'");

    Array<Real> norm0, norm1, norm2;

    DataServices::SetBatchMode();
    FileType fileType(NEWPLT);
    
    DataServices dataServices(iFile, fileType);

    if (!dataServices.AmrDataOk())
        //
        // This calls ParallelDescriptor::EndParallel() and exit()
        //
        DataServices::Dispatch(DataServices::ExitRequest, NULL);

    AmrData& amrData = dataServices.AmrDataRef();

    ComputeAmrDataNorms(amrData, norm0, norm1, norm2, verbose);

    // Write norms to screen
    if (ParallelDescriptor::IOProcessor())
    {
	const Array<aString>& names = amrData.PlotVarNames();
	int maxl = 0;
	for (int i=0; i<names.length(); ++i)
	    maxl = Max(maxl,names[i].length());
	char sbuf[128];
	sprintf(sbuf,"%d",maxl);
	aString formatStr =
	    aString("\t%") + sbuf + aString("s |  %10e   %10e   %10e\n");
	aString sformatStr =
	    aString("\t%") + sbuf + aString("s |  %10s   %10s   %10s\n");
	
	std::cout << '\n' << "Norms for pltfile = " << iFile << ": " << '\n' << '\n';
	printf(sformatStr.c_str(),"Derived","L-inf","L1","L2");
	std::cout << '\t'
	     << "--------------+------------------------------------------" << '\n';
	
	for (int i=0; i<names.length(); ++i)
	{
	    printf(formatStr.c_str(),names[i].c_str(),norm0[i],norm1[i],norm2[i]);
	}
	std::cout << '\n';
	
    }
    
    //
    // This calls ParallelDescriptor::EndParallel() and exit()
    //
    DataServices::Dispatch(DataServices::ExitRequest, NULL);
}


