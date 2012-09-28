//
//The MIT License
//
//Copyright (c) 2010 tapsquare, llc., (http://www.tapsquare.com, art@tapsquare.com)
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in
//all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//THE SOFTWARE.
//

#import "TSLibraryImport.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioFile.h>

@interface TSLibraryImport()

+ (BOOL)validIpodLibraryURL:(NSURL*)url;

@end


@implementation TSLibraryImport

+ (BOOL)validIpodLibraryURL:(NSURL*)url {
	NSString* IPOD_SCHEME = @"ipod-library";
	if (nil == url) return NO;
	if (nil == url.scheme) return NO;
	if ([url.scheme compare:IPOD_SCHEME] != NSOrderedSame) return NO;
	if ([url.pathExtension caseInsensitiveCompare:@"mp3"] != NSOrderedSame &&
		[url.pathExtension caseInsensitiveCompare:@"aif"] != NSOrderedSame &&
		[url.pathExtension caseInsensitiveCompare:@"m4a"] != NSOrderedSame &&
		[url.pathExtension caseInsensitiveCompare:@"wav"] != NSOrderedSame) {
		return NO;
	}
	return YES;
}

+ (NSString*)extensionForAssetURL:(NSURL*)assetURL {
	if (nil == assetURL)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"nil assetURL" userInfo:nil];
	if (![TSLibraryImport validIpodLibraryURL:assetURL])
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Invalid iPod Library URL: %@", assetURL] userInfo:nil];
	return assetURL.pathExtension;
}

- (void)importAsset:(NSURL*)assetURL toURL:(NSURL*)destURL completionBlock:(void (^)(TSLibraryImport* import))completionBlock
{
	if (nil == assetURL || nil == destURL)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"nil url" userInfo:nil];

	if (![TSLibraryImport validIpodLibraryURL:assetURL])
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Invalid iPod Library URL: %@", assetURL] userInfo:nil];

    // We should always check whether the file exists in the calling method and handle it there, depending on the needs of the app at the time.
	if ([[NSFileManager defaultManager] fileExistsAtPath:[destURL path]])
        @throw [NSException exceptionWithName:TSFileExistsError reason:[NSString stringWithFormat:@"File already exists at url: %@", destURL] userInfo:nil];
    
	NSDictionary * options = [[[NSDictionary alloc] init] autorelease];
	AVURLAsset* asset = [AVURLAsset URLAssetWithURL:assetURL options:options];

	if (nil == asset)
		@throw [NSException exceptionWithName:TSUnknownError reason:[NSString stringWithFormat:@"Couldn't create AVURLAsset with url: %@", assetURL] userInfo:nil];

	if ([[assetURL pathExtension] caseInsensitiveCompare:@"mp3"] == NSOrderedSame) {
        NSError *avError;
        myAssetReader = [[AVAssetReader alloc] initWithAsset:asset error:&avError];

        if (avError)
        {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Error creating assetReader: %@",[avError localizedDescription]] userInfo:nil];
        }

        myOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:[[asset tracks] objectAtIndex:0] outputSettings:nil];

        if (!myOutput)
        {
            TSLILog(@"Could not initialize the AVAssetReaderTrackOutput.");
        }
        else
        {
            if ([myAssetReader canAddOutput:myOutput])
            {
                [myAssetReader addOutput:myOutput];
            }
            else
            {
                TSLILog(@"Error: Cannot add output!!!");
            }

            if ([myAssetReader status] != AVAssetReaderStatusFailed)
            {
                if (![myAssetReader startReading])
                {
                    TSLILog(@"Error: Asset reader cannot start reading. Error: %@",[myAssetReader.error localizedDescription]);
                }
                else
                {
                    // Start the loop to read through the file
                    CMSampleBufferRef myBuff;

                    AudioStreamPacketDescription aspd;
                    CMBlockBufferRef blockBufferOut;
                    AudioBufferList buffList;
                    CFAllocatorRef structAllocator;
                    CFAllocatorRef memoryAllocator;

                    UInt32 myFlags = 0;

                    [[NSFileManager defaultManager] createFileAtPath:[destURL path] contents:nil attributes:nil];
                    NSFileHandle *outputFileHandle = [NSFileHandle fileHandleForWritingAtPath:[destURL path]];
                    [outputFileHandle seekToEndOfFile];
                    //FILE* outputFileHandle = fopen([[destURL path] cStringUsingEncoding:NSUTF8StringEncoding], "w");

                    if (outputFileHandle == nil) // (outputFileHandle == NULL)
                    {
                        @throw [NSException exceptionWithName:TSUnknownError reason:@"Couldn't open destination file" userInfo:nil];
                    }

                    BOOL myBuffCopiedNextSampleBuffer=NO;
                    do
                    {
                        myBuff = [myOutput copyNextSampleBuffer];

                        if (myBuff)
                        {
                            //CMItemCount numSamples = CMSampleBufferGetNumSamples(myBuff);
                            OSStatus err = noErr;

                            size_t sizeNeeded = sizeof(aspd);

                            err = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(myBuff,&sizeNeeded,&buffList,sizeof(buffList),structAllocator,memoryAllocator,myFlags,&blockBufferOut);
                            //if (err) TSLILog(@"CMSampleBufferGetAudioBufferList mDataByteSize: %d error: %d",buffList.mBuffers[0].mDataByteSize, err);

                            if (!err && blockBufferOut && buffList.mBuffers[0].mData && (buffList.mBuffers[0].mDataByteSize > 0))
                            {
                                [outputFileHandle writeData:[NSData dataWithBytes:buffList.mBuffers[0].mData length:buffList.mBuffers[0].mDataByteSize]];
                                //fwrite(buffList.mBuffers[0].mData, buffList.mBuffers[0].mDataByteSize, 1, outputFileHandle);
                            }

                            myBuffCopiedNextSampleBuffer=YES;

                            if (blockBufferOut)
                            {
                                // Little known fact, you must release the CMBlockBufferRef and do it before releasing the CMSampleBufferRef
                                CFRelease(blockBufferOut);
                                blockBufferOut=nil; // NULL?
                            }

                            CMSampleBufferInvalidate(myBuff);
                            CFRelease(myBuff);
                            myBuff = nil; // NULL?
                        }
                        else
                            myBuffCopiedNextSampleBuffer=NO;
                        
                    } while (myBuffCopiedNextSampleBuffer || [myAssetReader status] == AVAssetReaderStatusReading);

                    [outputFileHandle closeFile];
                    //fclose(outputFileHandle);

                    completionBlock(self);
                }
            }
            else
            {
                TSLILog(@"AVAssetReader failed");
            }
        }
		return;
	}
    
	exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetPassthrough];
	if (nil == exportSession)
		@throw [NSException exceptionWithName:TSUnknownError reason:@"Couldn't create AVAssetExportSession" userInfo:nil];
	
	exportSession.outputURL = destURL;
	
	// set the output file type appropriately based on asset URL extension
	if ([[assetURL pathExtension] caseInsensitiveCompare:@"m4a"] == NSOrderedSame) {
		exportSession.outputFileType = AVFileTypeAppleM4A;
	} else if ([[assetURL pathExtension] caseInsensitiveCompare:@"wav"] == NSOrderedSame) {
		exportSession.outputFileType = AVFileTypeWAVE;
	} else if ([[assetURL pathExtension] caseInsensitiveCompare:@"aif"] == NSOrderedSame) {
		exportSession.outputFileType = AVFileTypeAIFF;
	} else {
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"unrecognized file extension" userInfo:nil];
	}
    
	[exportSession exportAsynchronouslyWithCompletionHandler:^(void) {
		completionBlock(self);
		[exportSession release];
		exportSession = nil;
	}];
}

- (NSError*)error {
    return exportSession.error;
}

- (AVAssetExportSessionStatus)status {
	return exportSession.status;
}

- (AVAssetReaderStatus)avStatus {
	return myAssetReader.status;
}

- (float)progress {
	return exportSession.progress;
}

- (void)dealloc {
	[exportSession release];
	[myOutput release];
	[myAssetReader release];
	[super dealloc];
}

- (void)dumpAssetInfo:(AVURLAsset*)asset {
	TSLILog(@"asset.url: %@", asset.URL);
	for (AVMetadataItem* item in asset.commonMetadata) {
		TSLILog(@"metadata: %@", item);
	}
	for (AVAssetTrack* track in asset.tracks) {
		TSLILog(@"track.id: %d", track.trackID);
		TSLILog(@"track.mediaType: %@", track.mediaType);
		TSLILog(@"track.formatDescriptions count: %d",[track.formatDescriptions count]);
		CMFormatDescriptionRef fmt = (CMFormatDescriptionRef)[track.formatDescriptions objectAtIndex:0];
		const AudioStreamBasicDescription *desc = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);

		const AudioChannelLayout *channelLayout;
		size_t sizeOfLayout = sizeof(channelLayout);

		channelLayout=CMAudioFormatDescriptionGetChannelLayout(fmt, &sizeOfLayout);

		TSLILog(@"mSampleRate: %0.2f",desc->mSampleRate);
		TSLILog(@"mFormatID: %ld",desc->mFormatID);
		TSLILog(@"mFormatFlags: %ld",desc->mFormatFlags);
		TSLILog(@"mBytesPerPacket: %ld",desc->mBytesPerPacket);
		TSLILog(@"mFramesPerPacket: %ld",desc->mFramesPerPacket);
		TSLILog(@"mBytesPerFrame: %ld",desc->mBytesPerFrame);
		TSLILog(@"mChannelsPerFrame: %ld",desc->mChannelsPerFrame);
		TSLILog(@"mBitsPerChannel: %ld",desc->mBitsPerChannel);

		TSLILog(@"track.enabled: %d", track.enabled);
		TSLILog(@"track.selfContained: %d", track.selfContained);
	}
}

@end
