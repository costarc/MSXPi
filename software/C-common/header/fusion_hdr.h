/* Which Fusion-C header a source sees: fusion.h (SDCC 4.6 path, built with -DMSXPI_FUSION46 by
 * make.bat/make.sh for the programs in ABI1_PROGRAMS) or the original msx_fusion.h. */
#ifdef MSXPI_FUSION46
#include "fusion.h"
#else
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#endif
