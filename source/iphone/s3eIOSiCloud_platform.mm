/*
 * iphone-specific implementation of the s3eIOSiCloud extension.
 * Add any platform-specific functionality here.
 */
/*
 * NOTE: This file was originally written by the extension builder, but will not
 * be overwritten (unless --force is specified) and is intended to be modified.
 */
#include "s3eIOSiCloud_internal.h"

#import <UIKit/UIKit.h>

#include "s3eEdk.h"
#include "s3eEdk_iphone.h"
#include "IwDebug.h"

// Miscellaneous data

struct s3eIOSiCloudData
{
	bool m_IsAvailable;				//!< Is iCloud available at all?
	char m_Name[256];				//!< Managed iCloud file name
    
    bool m_SupportConflictResolution; //!< Indicates whether to support conflict detection and resolution

	bool m_RetryRead;               //!< Did last read fail? If so, retry
	int m_RetryReadCounter;         //!< Counter/timer for read retrying
				
	void* m_ToWriteData;            //!< Data to write to iCloud file
	int m_ToWriteDataSize;          //!< Size of the data to write to iCloud
	bool m_ReadyForWriting;         //!< Indicates whether we're ready to write (either determined that the file in iCloud doesn't exist, or the file exists but hasn't been read yet)
	bool m_WriteInProgress;         //!< Indicates whether write operation is in progress (which prevents other reads)
	bool m_ScheduledWriting;        //!< Indicates whether write operation is scheduled to be done as soon as possible
	bool m_WriteSucceeded;          //!< Indicates whether last write attempt succeeded or failed (TODO: to be used for write retrying)
	
	s3eIOSiCloudData() :
		m_IsAvailable(false),
        m_SupportConflictResolution(true),
		m_RetryRead(false),
		m_RetryReadCounter(0),
		m_ToWriteData(NULL),
		m_ToWriteDataSize(0),
		m_ReadyForWriting(false),
		m_WriteInProgress(false),
		m_ScheduledWriting(false),
		m_WriteSucceeded(false)
	{
		m_Name[0] = 0;
	}
};

// Query observer interface

@interface s3eIOSiCloudQueryObserver : NSObject
- (void)queryDidFinishGathering: (NSNotification*) notification;
@end

// iCloud synchronized document interface

@interface s3eIOSiCloudDoc : UIDocument
- (void)documentStateChanged: (NSNotification*) notification;
- (void)resolveConflicts;
@end

// Variables

s3eIOSiCloudData g_data;
NSMetadataQuery* g_query = nil;
s3eIOSiCloudQueryObserver* g_queryObserver = nil;
s3eIOSiCloudDoc* g_doc = nil;
NSFileCoordinator* g_coordinator = nil;

// Misc

void s3eIOSiCloudStartReading()
{
    IwTrace(IOSICLOUD, ("Starting read"));

	[g_doc openWithCompletionHandler:^(BOOL success)
	{
		IwTrace(IOSICLOUD, ("Read %s", success ? "succeeded" : "failed"));
	}];
}

void s3eIOSiCloudCreateDoc(NSURL* url)
{
	IwTrace(IOSICLOUD, ("Creating document"));

    g_doc = [[s3eIOSiCloudDoc alloc] initWithFileURL:url];
    
    IwTrace(IOSICLOUD, ("Adding document state changed observer"));

    [[NSNotificationCenter defaultCenter]
		addObserver: g_doc
		selector: @selector(documentStateChanged:) 
		name: UIDocumentStateChangedNotification 
		object: g_doc];
}

// s3eIOSiCloudQueryObserver implementation

@implementation s3eIOSiCloudQueryObserver

- (void)queryDidFinishGathering: (NSNotification*) notification 
{
    IwTrace(IOSICLOUD, ("queryDidFinishGathering"));

    // Stop query
    
    IwTrace(IOSICLOUD, ("Stopping query"));
    
    [g_query disableUpdates];
    [g_query stopQuery];
    
    // Process query result
    
    IwTrace(IOSICLOUD, ("Query result contains %d entries", [g_query resultCount]));
    
    if ([g_query resultCount] == 1)
    {
        NSMetadataItem *item = [g_query resultAtIndex:0];
        NSURL *url = [item valueForAttribute:NSMetadataItemURLKey];
        s3eIOSiCloudCreateDoc(url);
        s3eIOSiCloudStartReading();
	}
	else
	{
		IwTrace(IOSICLOUD, ("Ready for writing"));
		g_data.m_ReadyForWriting = true;
	}
}

- (void) release
{
    // Remove query observer
    
    IwTrace(IOSICLOUD, ("Removing query observer"));
    
    [[NSNotificationCenter defaultCenter] removeObserver:self 
                                                    name:NSMetadataQueryDidFinishGatheringNotification
                                                  object:g_query];

    [super release];
}

@end

// Callback for when merging was completed

static void s3eIOSiCloudMergeReadComplete(uint32 deviceID, int32 notification, void* systemData, void* instance, int32 returnCode, void* completeData)
{
	IwTrace(IOSICLOUD, ("Merge(read) complete with %s - releasing NSData", returnCode ? "failure" : "success"));

    NSData* nsdata = (NSData*) completeData;
    [nsdata release];

    IwTrace(IOSICLOUD, ("Merge(read) complete - released NSData"));

    if (returnCode == 0)
    {
        g_data.m_ReadyForWriting = true;
        IwTrace(IOSICLOUD, ("Ready for writing"));
    }
    else
    {
        g_data.m_RetryRead = true;
        g_data.m_RetryReadCounter = 0;
        IwTrace(IOSICLOUD, ("Read retry scheduled"));
    }
    
}

// s3eIOSiCloudMergeConflictData interface and implementation

@interface s3eIOSiCloudMergeConflictData : NSObject
{
	@public NSFileVersion* version;
	@public NSData* data;
}
@end

@implementation s3eIOSiCloudMergeConflictData

@end

static void s3eIOSiCloudMergeConflictComplete(uint32 deviceID, int32 notification, void* systemData, void* instance, int32 returnCode, void* completeData)
{
	IwTrace(IOSICLOUD, ("Merge(conflict) complete with %s", returnCode ? "failure" : "success"));
	
	s3eIOSiCloudMergeConflictData* data = (s3eIOSiCloudMergeConflictData*) completeData;
    
	if (returnCode == 0)
    {
        IwTrace(IOSICLOUD, ("Setting conflicting document version to resolved"));
		data->version.resolved = YES;
    }
    else
    {
        IwTrace(IOSICLOUD, ("Conflicting document version stays as unresolved"));
    }
    
    IwTrace(IOSICLOUD, ("Merge(conflict) complete - releasing data"));

    [data->version release];
    [data->data release];
	[data release];
    
    IwTrace(IOSICLOUD, ("Merge(conflict) complete - released data"));
}

// s3eIOSiCloudDoc implementation

@implementation s3eIOSiCloudDoc

- (void)resolveConflicts
{
	IwTrace(IOSICLOUD, ("Started resolving conflict"));

	// We've got conflict! - first get all conflicting versions
	
	NSArray* versions = [NSFileVersion unresolvedConflictVersionsOfItemAtURL: [self fileURL]];
	IwTrace(IOSICLOUD, ("Found %d conflicting versions", [versions count]));
	
	// Merge all conflicting versions (one by one)

	if (!g_coordinator)
	{
		g_coordinator = [[NSFileCoordinator alloc] initWithFilePresenter: self];
		IwTrace(IOSICLOUD, ("File coordinator created"));
	}
    
	for (NSFileVersion* version in versions)
	{
		IwTrace(IOSICLOUD, ("Started coordinated read"));
		
		NSError* readError;
		[g_coordinator coordinateReadingItemAtURL: version.URL
			options:0
			error:&readError
			byAccessor:^(NSURL* url)
			{
				IwTrace(IOSICLOUD, ("Coordinated read - getting the data"));
				
				NSData* nsdata = [NSData dataWithContentsOfURL: url];

				s3eIOSiCloudDataToMergeWith merge;
				merge.m_Data = [nsdata bytes];
				merge.m_DataSize = [nsdata length];
				
				IwTrace(IOSICLOUD, ("Creating merge conflict data object"));
				
				s3eIOSiCloudMergeConflictData* data = [s3eIOSiCloudMergeConflictData alloc];
				data->data = nsdata;
				[nsdata retain];
				data->version = version;
				[version retain];

                IwTrace(IOSICLOUD, ("Enqueuing merge(conflict) callback"));

				s3eEdkCallbacksEnqueue(S3E_EXT_IOSICLOUD_HASH, S3E_IOSICLOUD_CALLBACK_MERGE, &merge, sizeof(s3eIOSiCloudDataToMergeWith), NULL, S3E_FALSE, s3eIOSiCloudMergeConflictComplete, data);
			}
		];
	}
	
	IwTrace(IOSICLOUD, ("Resolving conflict handling done (failed or succeeded)"));
}

- (void)documentStateChanged: (NSNotification*) notification 
{
	// Get document state
		
	UIDocumentState state = [self documentState];
	IwTrace(IOSICLOUD, ("Document state changed to %d", (int) state));
	
	// Check for conflict
    
	if ((state & UIDocumentStateInConflict) == 0)
		return;

    if (!g_data.m_SupportConflictResolution)
    {
        IwTrace(IOSICLOUD, ("Conflict detected - ignoring since s3eIOSiCloudStart wasn't invoked with conflict resolution support enabled"));
        return;
    }

    IwTrace(IOSICLOUD, ("Conflict detected - scheduling asynchronous conflict resolution"));
    
    // Schedule asynchronous conflict resolution
	
	dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(backgroundQueue, ^
	{
		[self resolveConflicts];
	});
}

- (void)dealloc
{
    IwTrace(IOSICLOUD, ("Removing document state changed observer"));
 
    [[NSNotificationCenter defaultCenter] removeObserver:self 
        name:UIDocumentStateChangedNotification
        object:self];
    [super dealloc];
}

- (BOOL)loadFromContents:(id)contents ofType:(NSString *)typeName error:(NSError **)outError
{
	IwTrace(IOSICLOUD, ("loadFromContents (received NSData)"));
	
	NSData* nsdata = (NSData*) contents;
	[nsdata retain];

	s3eIOSiCloudDataToMergeWith merge;
	merge.m_Data = [nsdata bytes];
	merge.m_DataSize = [nsdata length];
	
	IwTrace(IOSICLOUD, ("Enqueuing merge(read) callback (%d bytes)", [nsdata length]));
	
	s3eEdkCallbacksEnqueue(S3E_EXT_IOSICLOUD_HASH, S3E_IOSICLOUD_CALLBACK_MERGE, &merge, sizeof(s3eIOSiCloudDataToMergeWith), NULL, S3E_FALSE, s3eIOSiCloudMergeReadComplete, nsdata);

    return YES;
}

- (id)contentsForType:(NSString *)typeName error:(NSError **)outError 
{
	IwTrace(IOSICLOUD, ("contentsForType (saving NSData)"));

	// Nothing to write?
	
	if (!g_data.m_ToWriteData)
	{
		IwTrace(IOSICLOUD, ("Nothing to write"));
		return nil;
	}

	// Convert our data to NSData
	
	IwTrace(IOSICLOUD, ("Converting the data to NSData (%d bytes)", g_data.m_ToWriteDataSize));
    NSData* nsdata = [NSData dataWithBytes: g_data.m_ToWriteData length: g_data.m_ToWriteDataSize];
    IwTrace(IOSICLOUD, ("Data converted to NSData"));
    
    return nsdata;
}

@end

s3eResult s3eIOSiCloudInit_platform()
{
    NSURL* ubiq = [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier: nil];
	if (!ubiq)
	{
		g_data.m_IsAvailable = false;
		IwTrace(IOSICLOUD, ("No iCloud support"));
		return S3E_RESULT_SUCCESS;
	}

	g_data.m_IsAvailable = true;
	IwTrace(IOSICLOUD, ("iCloud access at '%s'", [[ubiq absoluteString] UTF8String]));
  
    return S3E_RESULT_SUCCESS;
}

void s3eIOSiCloudTerminate_platform()
{
}

s3eResult s3eIOSiCloudStart_platform(const char* fileName, s3eBool supportConflictResolution)
{
	if (!g_data.m_IsAvailable)
		return S3E_RESULT_ERROR;

    g_data.m_SupportConflictResolution = supportConflictResolution;
	strcpy(g_data.m_Name, fileName);
	
	// Create query observer
	
	g_queryObserver = [[s3eIOSiCloudQueryObserver alloc] init];
	
	// Create query
	
	IwTrace(IOSICLOUD, ("Creating query"));
	
	g_query = [[NSMetadataQuery alloc] init];
    [g_query setSearchScopes:[NSArray arrayWithObject: NSMetadataQueryUbiquitousDocumentsScope]];

	IwTrace(IOSICLOUD, ("Creating query predicate"));
    NSString* fileNameString = [[NSString alloc] initWithUTF8String: fileName];
    NSPredicate* pred = [NSPredicate predicateWithFormat: @"%K == %@", NSMetadataItemFSNameKey, fileNameString];
    [fileNameString release];
    [g_query setPredicate: pred];
    [[NSNotificationCenter defaultCenter]
        addObserver: g_queryObserver 
        selector: @selector(queryDidFinishGathering:) 
        name: NSMetadataQueryDidFinishGatheringNotification 
        object: g_query];

	// Start query
	
	IwTrace(IOSICLOUD, ("Starting query"));
        
    [g_query startQuery];
    
    IwTrace(IOSICLOUD, ("Query started"));

	return S3E_RESULT_SUCCESS;
}

void s3eIOSiCloudStop_platform()
{
    if (!g_data.m_IsAvailable)
		return;
    
    IwTrace(IOSICLOUD, ("Destroying query observer"));

	if (g_queryObserver)
	{
		[g_queryObserver release];
		g_queryObserver = nil;
	}

    IwTrace(IOSICLOUD, ("Destroying query"));

    if (g_query)
	{
		[g_query release];
		g_query = nil;
	}
    
    IwTrace(IOSICLOUD, ("Destroying file coordinator"));
    
	if (g_coordinator)
	{
		[g_coordinator cancel];
		[g_coordinator release];
		g_coordinator = nil;
	}
    
    IwTrace(IOSICLOUD, ("Destroying document"));
    
	if (g_doc)
	{
		[g_doc release];
		g_doc = nil;
	}
    
    IwTrace(IOSICLOUD, ("Destroying write data"));
    
    if (g_data.m_ToWriteData)
    {
        s3eEdkFreeOS(g_data.m_ToWriteData);
        g_data.m_ToWriteData = NULL;
    }
    
    IwTrace(IOSICLOUD, ("Clean up finished"));
}

void s3eIOSiCloudUpdateWriting()
{
	if (!g_data.m_ReadyForWriting || g_data.m_WriteInProgress || !g_data.m_ScheduledWriting)
		return;
		
	g_data.m_ScheduledWriting = false;
	g_data.m_WriteInProgress = true;
		
	// Create document if not done before
		
	if (!g_doc)
	{
		IwTrace(IOSICLOUD, ("Pre-writing: need to create document"));
	
		NSURL *ubiq = [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:nil];
		NSString* fileNameString = [[NSString alloc] initWithUTF8String: g_data.m_Name];
        NSURL *ubiquitousPackage = [[ubiq URLByAppendingPathComponent:@"Documents"] URLByAppendingPathComponent:fileNameString];
		[fileNameString release];
		
		s3eIOSiCloudCreateDoc(ubiquitousPackage);
		
		IwTrace(IOSICLOUD, ("Pre-writing: document created"));
	}
	
	// Start writing the document
	
	IwTrace(IOSICLOUD, ("Starting write"));

	[g_doc saveToURL:		[g_doc fileURL] 
		forSaveOperation:	UIDocumentSaveForCreating 
		completionHandler:	^(BOOL success)
		{
			g_data.m_WriteInProgress = false;
			g_data.m_WriteSucceeded = success;
		
			IwTrace(IOSICLOUD, ("Write %s", success ? "succeeded" : "failed"));
		}
	];
}

void s3eIOSiCloudUpdateReading()
{
	if (!g_data.m_RetryRead)
		return;
    
    // Retry to read if failed last time
		
	g_data.m_RetryRead++;
	if (g_data.m_RetryRead < 60 * 10) // Wait X ticks until next try
		return;
	g_data.m_RetryRead = false;

	s3eIOSiCloudStartReading();
}

void s3eIOSiCloudTick_platform()
{
	if (!g_data.m_IsAvailable)
		return;
	
	s3eIOSiCloudUpdateReading();	
	s3eIOSiCloudUpdateWriting();
}

s3eResult s3eIOSiCloudWrite_platform(const void* data, int32 dataSize)
{
	if (!g_data.m_IsAvailable)
		return S3E_RESULT_ERROR;
		
	// Read or verify that the document doesn't exist yet first
		
	if (!g_data.m_ReadyForWriting)
	{
		IwTrace(IOSICLOUD, ("Failed to write, reason: query or read operation didn't finish yet"));
		return S3E_RESULT_ERROR;
	}

	// Don't break current write
		
	if (g_data.m_WriteInProgress)
	{
		IwTrace(IOSICLOUD, ("Failed to write, reason: previous write in progress"));
		return S3E_RESULT_ERROR;
	}
		
	// Store data to write
	
	if (g_data.m_ToWriteDataSize != dataSize)
	{
		if (g_data.m_ToWriteData)
		{
			s3eEdkFreeOS(g_data.m_ToWriteData);
			g_data.m_ToWriteDataSize = 0;
		}

		g_data.m_ToWriteData = s3eEdkMallocOS(dataSize);
		if (!g_data.m_ToWriteData)
        {
            IwTrace(IOSICLOUD, ("Failed to write, reason: failed to allocate %d bytes for temporary buffer", dataSize));
			return S3E_RESULT_ERROR;
		}
        g_data.m_ToWriteDataSize = dataSize;
	}
	
	memcpy(g_data.m_ToWriteData, data, dataSize);
		
	// Write / schedule write

	g_data.m_ScheduledWriting = true;
	IwTrace(IOSICLOUD, ("Write scheduled"));

	s3eIOSiCloudUpdateWriting();

	return S3E_RESULT_SUCCESS;
}
