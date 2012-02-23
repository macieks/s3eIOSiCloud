/*
 * windows-specific implementation of the s3eIOSiCloud extension.
 * Add any platform-specific functionality here.
 */
/*
 * NOTE: This file was originally written by the extension builder, but will not
 * be overwritten (unless --force is specified) and is intended to be modified.
 */
#include "s3eIOSiCloud_internal.h"

#include "IwDebug.h"
#include "s3eEdk.h"
#include "s3eFile.h"
#include <vector>
#include <algorithm>

struct s3eIOSiCloudDocument
{
	char m_Name[256];

	bool m_ReadScheduled;

	bool m_ConflictsCheckScheduled;

	bool m_WriteScheduled;
	bool m_WriteSucceeded;

	void* m_ToWriteData;
	int m_ToWriteDataSize;

	int m_Counter;

	bool m_SupportConflictResolution;

	s3eIOSiCloudDocument() :
		m_ReadScheduled(false),
		m_WriteScheduled(false),
		m_WriteSucceeded(false),
		m_ToWriteData(NULL),
		m_ToWriteDataSize(0),
		m_Counter(0),
		m_SupportConflictResolution(true)
	{}
};

s3eIOSiCloudDocument doc;

s3eResult s3eIOSiCloudInit_platform()
{
    return S3E_RESULT_SUCCESS;
}

void s3eIOSiCloudTerminate_platform()
{
}

s3eResult s3eIOSiCloudStart_platform(const char* fileName, s3eBool supportConflictResolution)
{
	strcpy(doc.m_Name, fileName);
	doc.m_ReadScheduled = true;
	doc.m_SupportConflictResolution = supportConflictResolution;
	if (supportConflictResolution)
		doc.m_ConflictsCheckScheduled = true;
	return S3E_RESULT_SUCCESS;
}

void s3eIOSiCloudStop_platform()
{
	if (doc.m_ToWriteData)
	{
		s3eEdkFreeOS(doc.m_ToWriteData);
		doc.m_ToWriteData = NULL;
	}
}

bool s3eIOSiCloud_LoadFile(const char* path, const void*& data, int& dataSize)
{
	s3eFile* f = s3eFileOpen(path, "rb");
	if (!f)
	{
		IwTrace(IOSICLOUD, ("File '%s' failed to open", path));
		return false;
	}

	// Get file size

	dataSize = s3eFileGetSize(f);

	// Load file

	void* _data = s3eEdkMallocOS(dataSize);
	if (!_data)
	{
		s3eFileClose(f);
		return false;
	}

	if (s3eFileRead(_data, dataSize, 1, f) != 1)
	{
		s3eEdkFreeOS(_data);
		s3eFileClose(f);
		return false;
	}

	// Close file

	s3eFileClose(f);

	data = _data;
	return true;
}

void s3eIOSiCloudMergeRelease(uint32 extID, int32 notification, void* systemData, void* instance, int32 returnCode, void* completeData)
{
	s3eIOSiCloudDataToMergeWith* dataToMergeWith = (s3eIOSiCloudDataToMergeWith*) systemData;
	s3eEdkFreeOS((void*) dataToMergeWith->m_Data);
}

void s3eIOSiCloud_SimulateRead()
{
	char path[256];
	sprintf(path, "%s_icloud", doc.m_Name);

	s3eIOSiCloudDataToMergeWith dataToMergeWith;
	const bool readSucceeded = s3eIOSiCloud_LoadFile(path, dataToMergeWith.m_Data, dataToMergeWith.m_DataSize);

	IwTrace(IOSICLOUD, ("Loading file '%s' %s", path, readSucceeded ? "succeeded" : "failed"));

	if (readSucceeded)
		s3eEdkCallbacksEnqueue(S3E_EXT_IOSICLOUD_HASH, S3E_IOSICLOUD_CALLBACK_MERGE, &dataToMergeWith, sizeof(s3eIOSiCloudDataToMergeWith), NULL, S3E_FALSE, s3eIOSiCloudMergeRelease, NULL);
}

void s3eIOSiCloud_SimulateWrite()
{
	char path[256];
	sprintf(path, "%s_icloud", doc.m_Name);
	s3eFile* f = s3eFileOpen(path, "wb");
	if (!f)
	{
		s3eEdkFreeOS(doc.m_ToWriteData);
		doc.m_WriteSucceeded = false;
		return;
	}

	if (s3eFileWrite(doc.m_ToWriteData, doc.m_ToWriteDataSize, 1, f) != 1)
	{
		s3eFileClose(f);
		s3eEdkFreeOS(doc.m_ToWriteData);
		doc.m_WriteSucceeded = false;
		return;
	}

	s3eFileClose(f);
	doc.m_WriteSucceeded = true;
	s3eEdkFreeOS(doc.m_ToWriteData);
}

void s3eIOSiCloud_SimulateConflictsCheck()
{
	// Process all versions

	int index = 0;
	char path[256];
	while (true)
	{
		// Determine file path

		if (index == 0)
			sprintf(path, "%s_icloud", doc.m_Name);
		else
			sprintf(path, "%s_icloud%d", doc.m_Name, index);

		// Load file content

		s3eIOSiCloudDataToMergeWith dataToMergeWith;
		if (!s3eIOSiCloud_LoadFile(path, dataToMergeWith.m_Data, dataToMergeWith.m_DataSize))
			break;

		// Invoke 'merge' callback

		s3eEdkCallbacksEnqueue(S3E_EXT_IOSICLOUD_HASH, S3E_IOSICLOUD_CALLBACK_MERGE, &dataToMergeWith, sizeof(s3eIOSiCloudDataToMergeWith), NULL, S3E_FALSE, s3eIOSiCloudMergeRelease, NULL);

		// Move to the next version

		index++;
	}
}

void s3eIOSiCloudTick_platform()
{
	// Simulate the actual operation every n-th tick

	doc.m_Counter++;
	if (doc.m_Counter < 10)
		return;
	doc.m_Counter = 0;

	// Simulate operations

	if (doc.m_WriteScheduled)
	{
		s3eIOSiCloud_SimulateWrite();
		doc.m_WriteScheduled = false;
		return;
	}

	if (doc.m_ConflictsCheckScheduled)
	{
		s3eIOSiCloud_SimulateConflictsCheck();
		doc.m_ConflictsCheckScheduled = false;
		return;
	}

	if (doc.m_ReadScheduled)
	{
		s3eIOSiCloud_SimulateRead();
		doc.m_ReadScheduled = false;
		return;
	}
}

s3eResult s3eIOSiCloudWrite_platform(const void* data, int32 dataSize)
{
	if (doc.m_WriteScheduled)
		return S3E_RESULT_ERROR;

	doc.m_WriteScheduled = true;
	doc.m_ToWriteData = s3eEdkMallocOS(dataSize);
	doc.m_ToWriteDataSize = dataSize;
	memcpy(doc.m_ToWriteData, data, dataSize);
    return S3E_RESULT_SUCCESS;
}