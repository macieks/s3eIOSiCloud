/*
 * Internal header for the s3eIOSiCloud extension.
 *
 * This file should be used for any common function definitions etc that need to
 * be shared between the platform-dependent and platform-indepdendent parts of
 * this extension.
 */

/*
 * NOTE: This file was originally written by the extension builder, but will not
 * be overwritten (unless --force is specified) and is intended to be modified.
 */


#ifndef S3EIOSICLOUD_INTERNAL_H
#define S3EIOSICLOUD_INTERNAL_H

#include "s3eTypes.h"
#include "s3eIOSiCloud.h"
#include "s3eIOSiCloud_autodefs.h"


/**
 * Initialise the extension.  This is called once then the extension is first
 * accessed by s3eregister.  If this function returns S3E_RESULT_ERROR the
 * extension will be reported as not-existing on the device.
 */
s3eResult s3eIOSiCloudInit();

/**
 * Platform-specific initialisation, implemented on each platform
 */
s3eResult s3eIOSiCloudInit_platform();

/**
 * Terminate the extension.  This is called once on shutdown, but only if the
 * extension was loader and Init() was successful.
 */
void s3eIOSiCloudTerminate();

/**
 * Platform-specific termination, implemented on each platform
 */
void s3eIOSiCloudTerminate_platform();
s3eResult s3eIOSiCloudStart_platform(const char* fileName, s3eBool supportConflictResolution);

void s3eIOSiCloudStop_platform();

void s3eIOSiCloudTick_platform();

s3eResult s3eIOSiCloudWrite_platform(const void* data, int32 dataSize);


#endif /* !S3EIOSICLOUD_INTERNAL_H */