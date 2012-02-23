/*
Generic implementation of the s3eIOSiCloud extension.
This file should perform any platform-indepedentent functionality
(e.g. error checking) before calling platform-dependent implementations.
*/

/*
 * NOTE: This file was originally written by the extension builder, but will not
 * be overwritten (unless --force is specified) and is intended to be modified.
 */


#include "s3eIOSiCloud_internal.h"
s3eResult s3eIOSiCloudInit()
{
    //Add any generic initialisation code here
    return s3eIOSiCloudInit_platform();
}

void s3eIOSiCloudTerminate()
{
    //Add any generic termination code here
    s3eIOSiCloudTerminate_platform();
}

s3eResult s3eIOSiCloudStart(const char* fileName, s3eBool supportConflictResolution)
{
	return s3eIOSiCloudStart_platform(fileName, supportConflictResolution);
}

void s3eIOSiCloudStop()
{
	s3eIOSiCloudStop_platform();
}

void s3eIOSiCloudTick()
{
	s3eIOSiCloudTick_platform();
}

s3eResult s3eIOSiCloudWrite(const void* data, int32 dataSize)
{
	return s3eIOSiCloudWrite_platform(data, dataSize);
}
