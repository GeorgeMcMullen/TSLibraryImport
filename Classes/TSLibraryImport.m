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
- (void)extractQuicktimeMovie:(NSURL*)movieURL toFile:(NSURL*)destURL;

@end


@implementation TSLibraryImport

+ (BOOL)validIpodLibraryURL:(NSURL*)url {
	NSString* IPOD_SCHEME = @"ipod-library";
	if (nil == url) return NO;
	if (nil == url.scheme) return NO;
	if ([url.scheme compare:IPOD_SCHEME] != NSOrderedSame) return NO;
	if ([url.pathExtension compare:@"mp3"] != NSOrderedSame &&
		[url.pathExtension compare:@"aif"] != NSOrderedSame &&
		[url.pathExtension compare:@"m4a"] != NSOrderedSame &&
		[url.pathExtension compare:@"wav"] != NSOrderedSame) {
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

- (void)doMp3ImportToFile:(NSURL*)destURL completionBlock:(void (^)(TSLibraryImport* import))completionBlock {
	//TODO: instead of putting this in the same directory as the dest file, we should probably stuff
	//this in tmp
	NSURL* tmpURL = [[destURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"mov"];
	[[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];
	exportSession.outputURL = tmpURL;
	
	exportSession.outputFileType = AVFileTypeQuickTimeMovie;
	[exportSession exportAsynchronouslyWithCompletionHandler:^(void) {
		if (exportSession.status == AVAssetExportSessionStatusFailed) {
			completionBlock(self);
		} else if (exportSession.status == AVAssetExportSessionStatusCancelled) {
			completionBlock(self);
		} else {
			@try {
				[self extractQuicktimeMovie:tmpURL toFile:destURL];
			}
			@catch (NSException * e) {
				OSStatus code = noErr;
				if ([e.name compare:TSUnknownError]) code = kTSUnknownError;
				else if ([e.name compare:TSFileExistsError]) code = kTSFileExistsError;
				NSDictionary* errorDict = [NSDictionary dictionaryWithObject:e.reason forKey:NSLocalizedDescriptionKey];
				
				movieFileErr = [[NSError alloc] initWithDomain:TSLibraryImportErrorDomain code:code userInfo:errorDict];
			}
			//clean up the tmp .mov file
			[[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];
			completionBlock(self);
		}
		[exportSession release];
		exportSession = nil;
	}];	
}

- (void)importAsset:(NSURL*)assetURL toURL:(NSURL*)destURL completionBlock:(void (^)(TSLibraryImport* import))completionBlock {
	if (nil == assetURL || nil == destURL)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"nil url" userInfo:nil];
	if (![TSLibraryImport validIpodLibraryURL:assetURL])
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Invalid iPod Library URL: %@", assetURL] userInfo:nil];

	if ([[NSFileManager defaultManager] fileExistsAtPath:[destURL path]])
		 @throw [NSException exceptionWithName:TSFileExistsError reason:[NSString stringWithFormat:@"File already exists at url: %@", destURL] userInfo:nil];
	
	NSDictionary * options = [[NSDictionary alloc] init];
	AVURLAsset* asset = [AVURLAsset URLAssetWithURL:assetURL options:options];	
	if (nil == asset) 
		@throw [NSException exceptionWithName:TSUnknownError reason:[NSString stringWithFormat:@"Couldn't create AVURLAsset with url: %@", assetURL] userInfo:nil];
	
	exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetPassthrough];
	if (nil == exportSession)
		@throw [NSException exceptionWithName:TSUnknownError reason:@"Couldn't create AVAssetExportSession" userInfo:nil];
	
	if ([[assetURL pathExtension] compare:@"mp3"] == NSOrderedSame) {
		[self doMp3ImportToFile:destURL completionBlock:completionBlock];
		return;
	}

	exportSession.outputURL = destURL;
	
	// set the output file type appropriately based on asset URL extension
	if ([[assetURL pathExtension] compare:@"m4a"] == NSOrderedSame) {
		exportSession.outputFileType = AVFileTypeAppleM4A;
	} else if ([[assetURL pathExtension] compare:@"wav"] == NSOrderedSame) {
		exportSession.outputFileType = AVFileTypeWAVE;
	} else if ([[assetURL pathExtension] compare:@"aif"] == NSOrderedSame) {
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

- (void)extractQuicktimeMovie:(NSURL*)movieURL toFile:(NSURL*)destURL {
	FILE* src = fopen([[movieURL path] cStringUsingEncoding:NSUTF8StringEncoding], "r");
	if (NULL == src) {
		@throw [NSException exceptionWithName:TSUnknownError reason:@"Couldn't open source file" userInfo:nil];
		return;
	}
	char atom_name[5];
	atom_name[4] = '\0';
	unsigned long atom_size = 0;
	while (true) {
		if (feof(src)) {
			break;
		}
		fread((void*)&atom_size, 4, 1, src);
		fread(atom_name, 4, 1, src);
		atom_size = ntohl(atom_size);
        const size_t bufferSize = 1024*100;
		if (strcmp("mdat", atom_name) == 0) {
			FILE* dst = fopen([[destURL path] cStringUsingEncoding:NSUTF8StringEncoding], "w");
			unsigned char buf[bufferSize];
			if (NULL == dst) {
				fclose(src);
				@throw [NSException exceptionWithName:TSUnknownError reason:@"Couldn't open destination file" userInfo:nil];
			}
            // Thanks to Rolf Nilsson/Roni Music for pointing out the bug here:
            // Quicktime atom size field includes the 8 bytes of the header itself.
            atom_size -= 8;
            while (atom_size != 0) {
                size_t read_size = (bufferSize < atom_size)?bufferSize:atom_size;
                if (fread(buf, read_size, 1, src) == 1) {
                    fwrite(buf, read_size, 1, dst);
                }
                atom_size -= read_size;
            }
			fclose(dst);
			fclose(src);
			return;
		}
		if (atom_size == 0)
			break; //0 atom size means to the end of file... if it's not the mdat chunk, we're done
		fseek(src, atom_size, SEEK_CUR);
	}
	fclose(src);
	@throw [NSException exceptionWithName:TSUnknownError reason:@"Didn't find mdat chunk"  userInfo:nil];
}

- (NSError*)error {
	if (movieFileErr) {
		return movieFileErr;
	}
	return exportSession.error;
}

- (AVAssetExportSessionStatus)status {
	if (movieFileErr) {
		return AVAssetExportSessionStatusFailed;
	}
	return exportSession.status;
}

- (float)progress {
	return exportSession.progress;
}

- (void)dealloc {
	[exportSession release];
	[movieFileErr release];
	[myOutput release];
	[myAssetReader release];
	[super dealloc];
}

- (void)dumpAsset:(AVURLAsset*)asset {
	TSLILog(@"asset.url: %@", asset.URL);
	for (AVMetadataItem* item in asset.commonMetadata) {
		TSLILog(@"metadata: %@", item);
	}
	for (AVAssetTrack* track in asset.tracks) {
		TSLILog(@"track.id: %d", track.trackID);
		TSLILog(@"track.mediaType: %@", track.mediaType);
		TSLILog(@"track.formatDescriptions count: %d",[track.formatDescriptions count]);
		CMFormatDescriptionRef fmt = (CMFormatDescriptionRef)[track.formatDescriptions objectAtIndex:0];
		AudioStreamBasicDescription *desc = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);

		AudioChannelLayout *channelLayout;
		size_t sizeOfLayout = sizeof(channelLayout);

		channelLayout=CMAudioFormatDescriptionGetChannelLayout(fmt, &sizeOfLayout);

		TSLILog(@"mSampleRate: %0.2f",desc->mSampleRate);
		TSLILog(@"mFormatID: %d",desc->mFormatID);
		TSLILog(@"mFormatFlags: %d",desc->mFormatFlags);
		TSLILog(@"mBytesPerPacket: %d",desc->mBytesPerPacket);
		TSLILog(@"mFramesPerPacket: %d",desc->mFramesPerPacket);
		TSLILog(@"mBytesPerFrame: %d",desc->mBytesPerFrame);
		TSLILog(@"mChannelsPerFrame: %d",desc->mChannelsPerFrame);
		TSLILog(@"mBitsPerChannel: %d",desc->mBitsPerChannel);

		TSLILog(@"track.enabled: %d", track.enabled);
		TSLILog(@"track.selfContained: %d", track.selfContained);
	}
}

static char *MyFormatError(char *str, OSStatus error)
{
    // see if it appears to be a 4-char-code
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4]))
	{
        str[0] = str[5] = '\'';
        str[6] = '\0';
    }
	else
	{
        // no, format it as an integer
        sprintf(str, "%d", (int)error);
    }
	return str;
}

- (void)importAVAssetReader:(NSURL*)assetURL toURL:(NSURL*)destURL completionBlock:(void (^)(TSLibraryImport* import))completionBlock
{
	if (nil == assetURL || nil == destURL)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"nil url" userInfo:nil];

	if (![TSLibraryImport validIpodLibraryURL:assetURL])
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Invalid iPod Library URL: %@", assetURL] userInfo:nil];

	if ([[NSFileManager defaultManager] fileExistsAtPath:[destURL path]]) completionBlock(self);;

	NSDictionary * options = [[NSDictionary alloc] init];
	AVURLAsset* asset = [AVURLAsset URLAssetWithURL:assetURL options:options];

	[self dumpAsset:asset];

	if (nil == asset)
		@throw [NSException exceptionWithName:TSUnknownError reason:[NSString stringWithFormat:@"Couldn't create AVURLAsset with url: %@", assetURL] userInfo:nil];

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
				//[self performSelector:@selector(importAVAssetReaderToURL:completionBlock:) withObject:[NSArray arrayWithObjects:destURL,completionBlock,nil] afterDelay:0.1];
				CMSampleBufferRef myBuff;

				AudioStreamPacketDescription aspd;
				CMBlockBufferRef blockBufferOut;
				AudioBufferList buffList;
				CFAllocatorRef structAllocator;
				CFAllocatorRef memoryAllocator;

				UInt32 myFlags = 0;

				FILE* dst = fopen([[destURL path] cStringUsingEncoding:NSUTF8StringEncoding], "w");

				if (NULL == dst)
				{
					@throw [NSException exceptionWithName:TSUnknownError reason:@"Couldn't open destination file" userInfo:nil];
				}

				do
				{
					myBuff = [myOutput copyNextSampleBuffer];
					//CMItemCount numSamples = CMSampleBufferGetNumSamples(myBuff);
					OSStatus err = noErr;

					size_t sizeNeeded = sizeof(aspd);

					err = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(myBuff,&sizeNeeded,&buffList,sizeof(buffList),structAllocator,memoryAllocator,myFlags,&blockBufferOut);
					//TSLILog(@"CMSampleBufferGetAudioBufferList mDataByteSize: %d error: %d (%s)",buffList.mBuffers[0].mDataByteSize, err, MyFormatError(errorString, err));

					if (buffList.mBuffers[0].mData)
					{
						fwrite(buffList.mBuffers[0].mData, buffList.mBuffers[0].mDataByteSize, 1, dst);
					}
				} while (myBuff || [myAssetReader status] == AVAssetReaderStatusReading);

				fclose(dst);

				completionBlock(self);
			}
		}
		else
		{
			TSLILog(@"AVAssetReader failed");
		}
	}
}

- (AVAssetReaderStatus)avStatus {
	return myAssetReader.status;
}

- (void)importAVAssetReaderNew:(NSURL*)assetURL toURL:(NSURL*)destURL completionBlock:(void (^)(TSLibraryImport* import))completionBlock
{
	char errorString[256];

	if (nil == assetURL || nil == destURL)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"nil url" userInfo:nil];

	if (![TSLibraryImport validIpodLibraryURL:assetURL])
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Invalid iPod Library URL: %@", assetURL] userInfo:nil];

	if ([[NSFileManager defaultManager] fileExistsAtPath:[destURL path]]) completionBlock(self);;

	NSDictionary * options = [[NSDictionary alloc] init];
	AVURLAsset* asset = [AVURLAsset URLAssetWithURL:assetURL options:options];

	[self dumpAsset:asset];

	if (nil == asset)
		@throw [NSException exceptionWithName:TSUnknownError reason:[NSString stringWithFormat:@"Couldn't create AVURLAsset with url: %@", assetURL] userInfo:nil];

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
				//[self performSelector:@selector(importAVAssetReaderToURL:completionBlock:) withObject:[NSArray arrayWithObjects:destURL,completionBlock,nil] afterDelay:0.1];
				CMSampleBufferRef myBuff;

				AudioStreamPacketDescription aspd;
				CMBlockBufferRef blockBufferOut;
				AudioBufferList buffList;
				CFAllocatorRef structAllocator;
				CFAllocatorRef memoryAllocator;

				UInt32 myFlags = 0;

				//FILE* dst = fopen([[destURL path] cStringUsingEncoding:NSUTF8StringEncoding], "w");

				AVAssetTrack* track=[[asset tracks] objectAtIndex:0];
				CMFormatDescriptionRef fmt = (CMFormatDescriptionRef)[track.formatDescriptions objectAtIndex:0];
				AudioStreamBasicDescription *inFormat= CMAudioFormatDescriptionGetStreamBasicDescription(fmt);

				const kMP4Audio_AAC_LC_ObjectType = 2;
				inFormat->mFormatFlags=kMP4Audio_AAC_LC_ObjectType;
				AudioChannelLayout *channelLayout;
				size_t sizeOfLayout = sizeof(channelLayout);

				channelLayout=CMAudioFormatDescriptionGetChannelLayout(fmt, &sizeOfLayout);


				OSStatus							audioFileCreateWithURLStatus=noErr;
				OSStatus							audioFileWriteBytesStatus=noErr;

				CFURLRef                          inFileRef=destURL;//CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)[[destURL path] cStringUsingEncoding:NSUTF8StringEncoding]0, NULL);
				//AudioFileTypeID                   inFileType=kAudioFileAAC_ADTSType;
				//AudioFileTypeID                   inFileType=kAudioFileM4AType;
				AudioFileTypeID                   inFileType=kAudioFileCAFType;
				//AudioFileTypeID                   inFileType=kAudioFileMPEG4Type;
				UInt32                            inFlags=kAudioFileFlags_EraseFile;
				AudioFileID                       outAudioFile;

				TSLILog(@"AudioFileCreateWithURL: %@",inFileRef);
				audioFileCreateWithURLStatus= AudioFileCreateWithURL (
																	  inFileRef,
																	  inFileType,
																	  inFormat,
																	  inFlags,
																	  &outAudioFile
																	  );

				//if (NULL == dst)
				if (audioFileCreateWithURLStatus!=noErr)
				{
					TSLILog(@"Error: %d (%s)", audioFileCreateWithURLStatus, MyFormatError(errorString, audioFileCreateWithURLStatus));
					@throw [NSException exceptionWithName:TSUnknownError reason:@"Couldn't open destination file" userInfo:nil];
				}


				size_t cookieSizeOut = 0;
				CMAudioFormatDescriptionGetMagicCookie (fmt,&cookieSizeOut);
				if (cookieSizeOut)
				{
					void *cookie=malloc(cookieSizeOut);

					cookie=CMAudioFormatDescriptionGetMagicCookie(fmt,&cookieSizeOut);

					OSStatus audioFileSetPropertyStatus=noErr;
					audioFileSetPropertyStatus = AudioFileSetProperty (outAudioFile, kAudioFilePropertyMagicCookieData, cookieSizeOut, cookie);

					TSLILog(@"Error: %d (%s)", audioFileSetPropertyStatus, MyFormatError(errorString, audioFileSetPropertyStatus));

					// even though some formats have cookies, some files don't take them
					free(cookie);
				}

				SInt64      inStartingByte=0;
				SInt64      inStartingPacket=0;

				do {
					myBuff = [myOutput copyNextSampleBuffer];

					/*
                     // Extract bytes from buffer
                     CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(myBuff);

                     size_t bufLen = CMBlockBufferGetDataLength(dataBuffer);
                     UInt8 buf[bufLen];

                     CMBlockBufferCopyDataBytes(dataBuffer, 0, bufLen, buf);

                     OSStatus audioFileSetPropertyStatus=noErr;
                     audioFileSetPropertyStatus = AudioFileSetProperty(outAudioFile, kAudioFilePropertyAudioDataByteCount, sizeof(SInt64), inStartingByte+bufLen);

                     TSLILog(@"Error: %d (%s)", audioFileSetPropertyStatus, MyFormatError(errorString, audioFileSetPropertyStatus));

                     audioFileWriteBytesStatus=AudioFileWriteBytes (
                     outAudioFile,
                     false,
                     inStartingByte,
                     &bufLen,
                     (void *)buf
                     );
                     inStartingByte+=bufLen;
                     TSLILog(@"buffer size: %d error: %d (%s)", bufLen, audioFileWriteBytesStatus, MyFormatError(errorString, audioFileWriteBytesStatus));

                     // Invalidate buffer
                     CMSampleBufferInvalidate(myBuff);
                     */

					//CMItemCount numSamples = CMSampleBufferGetNumSamples(myBuff);
					OSStatus err = noErr;
					TSLILog(@"noErr: %d",noErr);

					size_t sizeNeeded = sizeof(aspd);

					err = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(myBuff,&sizeNeeded,&buffList,sizeof(buffList),structAllocator,memoryAllocator,myFlags,&blockBufferOut);
					TSLILog(@"CMSampleBufferGetAudioBufferList mDataByteSize: %d error: %d (%s)",buffList.mBuffers[0].mDataByteSize, err, MyFormatError(errorString, err));

					if (buffList.mBuffers[0].mData)
					{

						void *mBuffersData;
						mBuffersData=malloc(buffList.mBuffers[0].mDataByteSize);
						memcpy(mBuffersData, buffList.mBuffers[0].mData, buffList.mBuffers[0].mDataByteSize);

						UInt32      ioNumBytes=buffList.mBuffers[0].mDataByteSize;
						Boolean     inUseCache=NO;
						UInt32      ioNumPackets=1;

						AudioStreamPacketDescription inPacketDescriptions;
						size_t packetDescriptionsSize=1680;//sizeof(inPacketDescriptions);
						size_t packetDescriptionsSizeNeededOut;
						TSLILog(@"packetDescriptionsSize: %d",packetDescriptionsSize);
						err = CMSampleBufferGetAudioStreamPacketDescriptions (
																			  myBuff,
																			  packetDescriptionsSize,
																			  &inPacketDescriptions,
																			  &packetDescriptionsSizeNeededOut
																			  );
						TSLILog(@"packetDescriptionsSize: %d mVariableFramesInPacket: %d mDataByteSize: %d packetDescriptionsSizeNeededOut: %d error: %d (%s)",
                                packetDescriptionsSize,
                                inPacketDescriptions.mVariableFramesInPacket,
                                inPacketDescriptions.mDataByteSize,
                                packetDescriptionsSizeNeededOut,
                                err, MyFormatError(errorString, err));

						ioNumPackets=0;//inPacketDescriptions.mDataByteSize;
						err=AudioFileWritePackets (
												   outAudioFile,
												   inUseCache,
												   ioNumBytes,
												   NULL, //&inPacketDescriptions,
												   inStartingPacket,
												   &ioNumPackets,
												   mBuffersData
												   );
						inStartingPacket+=ioNumPackets;
						TSLILog(@"ioNumPackets: %d error: %d (%s)", ioNumPackets, err, MyFormatError(errorString, err));

						/*		audioFileWriteBytesStatus=AudioFileWriteBytes (
						 outAudioFile,
						 inUseCache,
						 inStartingByte,
						 &ioNumBytes,
						 &buffList.mBuffers[0].mData
						 );
						 inStartingByte+=ioNumBytes;
						 TSLILog(@"buffer size: %d error: %d (%s)", buffList.mBuffers[0].mDataByteSize, audioFileWriteBytesStatus, MyFormatError(errorString, audioFileWriteBytesStatus));
						 */
						free(mBuffersData);
					}

				} while (myBuff || [myAssetReader status] == AVAssetReaderStatusReading);

				//fclose(dst);
				AudioFileClose(outAudioFile);
				completionBlock(self);
			}
		}
		else
		{
			TSLILog(@"AVAssetReader failed");
		}
	}
}

- (void)importAVAssetReaderWriter:(NSURL*)assetURL toURL:(NSURL*)destURL completionBlock:(void (^)(TSLibraryImport* import))completionBlock
{
	char errorString[256];

	if (nil == assetURL || nil == destURL)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"nil url" userInfo:nil];

	if (![TSLibraryImport validIpodLibraryURL:assetURL])
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Invalid iPod Library URL: %@", assetURL] userInfo:nil];

	if ([[NSFileManager defaultManager] fileExistsAtPath:[destURL path]]) completionBlock(self);;

	NSDictionary * options = [[NSDictionary alloc] init];
	AVURLAsset* asset = [AVURLAsset URLAssetWithURL:assetURL options:options];

	[self dumpAsset:asset];

	if (nil == asset)
		@throw [NSException exceptionWithName:TSUnknownError reason:[NSString stringWithFormat:@"Couldn't create AVURLAsset with url: %@", assetURL] userInfo:nil];

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

				AVAssetTrack* track=[[asset tracks] objectAtIndex:0];
				CMFormatDescriptionRef fmt = (CMFormatDescriptionRef)[track.formatDescriptions objectAtIndex:0];
				AudioStreamBasicDescription *inFormat= CMAudioFormatDescriptionGetStreamBasicDescription(fmt);

				const kMP4Audio_AAC_LC_ObjectType = 2;

				inFormat->mFormatFlags=kMP4Audio_AAC_LC_ObjectType;
				AudioChannelLayout *channelLayout;
				size_t sizeOfLayout = sizeof(channelLayout);

				channelLayout=CMAudioFormatDescriptionGetChannelLayout(fmt, &sizeOfLayout);

				AVAssetWriter *assetWriter = [[AVAssetWriter alloc] initWithURL:destURL fileType:AVFileTypeAppleM4A error:&avError];
				if (avError)
				{
					@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Error creating assetWriter: %@",[avError localizedDescription]] userInfo:nil];
				}

				NSDictionary *audioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
											   [NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey,
											   [NSNumber numberWithFloat:inFormat->mSampleRate], AVSampleRateKey,
											   [NSNumber numberWithInt:inFormat->mChannelsPerFrame], AVNumberOfChannelsKey,
											   [NSData dataWithBytes: &channelLayout length:sizeof(channelLayout)], AVChannelLayoutKey,
											   [NSNumber numberWithInt:inFormat->mBitsPerChannel],AVEncoderBitRateKey,
											   nil];
				AVAssetWriterInput* writerInput = [[AVAssetWriterInput
													assetWriterInputWithMediaType:AVMediaTypeAudio
													outputSettings:audioSettings] retain];

				if (!writerInput)
				{
					TSLILog(@"Could not initialize the AVAssetWriterInput.");
				}
				else
				{

					if ([assetWriter canAddInput:writerInput])
					{
						[assetWriter addInput:writerInput];

						[assetWriter startWriting];
						//[assetWriter startSessionAtSourceTime:0];

						dispatch_queue_t dispatch_queue = dispatch_get_main_queue();

						[writerInput requestMediaDataWhenReadyOnQueue:dispatch_queue usingBlock:^{
							while ([writerInput isReadyForMoreMediaData]) {
								CMSampleBufferRef sample = [myOutput copyNextSampleBuffer];
								if (sample) {
									//presentationTime = CMSampleBufferGetPresentationTimeStamp(sample);

									[writerInput appendSampleBuffer:sample];
									CFRelease(sample);
								}
								else
								{
									[writerInput markAsFinished];
									//[assetWriter endSessionAtSourceTime:presentationTime];
									if (![assetWriter finishWriting]) {
										NSLog(@"[assetWriter finishWriting] failed, status=%@ error=%@", assetWriter.status, assetWriter.error);
									}
									break;
								}
							}
						}];

						//[assetWriter endSessionAtSourceTime:…];
						[assetWriter finishWriting];

					}
				}


				completionBlock(self);
			}
		}
		else
		{
			TSLILog(@"AVAssetReader failed");
		}
	}
}

- (void)importAVAssetReaderToURL:(NSURL*)destURL completionBlock:(void (^)(TSLibraryImport* import))completionBlock
{
	CMSampleBufferRef myBuff;

	AudioStreamPacketDescription aspd;
	CMBlockBufferRef blockBufferOut;
	AudioBufferList buffList;
	CFAllocatorRef structAllocator;
	CFAllocatorRef memoryAllocator;

	UInt32 myFlags = 0;

	FILE* dst = fopen([[destURL path] cStringUsingEncoding:NSUTF8StringEncoding], "w");
	if (NULL == dst) {
		@throw [NSException exceptionWithName:TSUnknownError reason:@"Couldn't open destination file" userInfo:nil];
	}
    
	do {
		myBuff = [myOutput copyNextSampleBuffer];
		//CMItemCount numSamples = CMSampleBufferGetNumSamples(myBuff);
		OSStatus err = noErr;
		
		size_t sizeNeeded = sizeof(aspd);
		
		err = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(myBuff,&sizeNeeded,&buffList,sizeof(buffList),structAllocator,memoryAllocator,myFlags,&blockBufferOut);
		
		if (buffList.mBuffers[0].mData)
		{
			fwrite(buffList.mBuffers[0].mData, buffList.mBuffers[0].mDataByteSize, 1, dst);
		}
	} while (myBuff || [myAssetReader status] == AVAssetReaderStatusReading);
    
	fclose(dst);
	completionBlock(self);
}

@end
