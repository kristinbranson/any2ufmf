#ifndef __UFMF_WRITER_STATS
#define __UFMF_WRITER_STATS

#ifndef SQUARED
#define SQUARED(x) ((x)*(x))
#endif

#include <stdio.h>
#include <assert.h>
#include <vector>
#include "ufmfLogger.h"
#import <Foundation/Foundation.h>

#ifndef MAX
#define MAX(a,b)  ((a) < (b) ? (b) : (a))
#endif

#define BANDWIDTH_COMPUTATION_TIME_WINDOW_SEC 1
#define NUM_FOREGROUND_BINS 3

#define ERROR_FILTER_WIDTH 10

typedef enum {
	UTT_NONE = 0,
	UTT_START_WRITING,
	UTT_WRITE_HEADER,
	UTT_WRITE_FOOTER,
	UTT_ADD_FRAME,
	UTT_UPDATE_BACKGROUND,
	UTT_COMPUTE_BACKGROUND, 
	UTT_WRITE_KEYFRAME,
	UTT_COMPUTE_FRAME, 
	UTT_WRITE_FRAME,
	UTT_COMPUTE_STATS, 
	UTT_WAIT_FOR_COMPRESS_THREAD,
	UTT_WAIT_FOR_UNCOMPRESSED_FRAME,
	UTT_WAIT_FOR_COMPRESSED_FRAME,
	UTT_STOP_WRITE,
	UTT_NUM_TIMINGS
} ufmfTimingType;

typedef struct {
	double sum;
	int num;
	bool hasUpdate;
	double maxDur, lastDur;
	ufmfTimingType type;
	const char *name;
} ufmfTimingUpdate;

class ufmfWriterStats {
	int64_t maxFrameSizeBytes;
	int maxForegroundPixels;
	int maxNumWritten;
	int maxNumBoxes;
	double maxBytesPerSec;
	double sumFrameSizeBytes;
	double sumFrameSizeBytesSquared;
	double sumForegroundPixels;
	double sumForegroundPixelsSquared;
	double sumNumWritten;
	double sumNumWrittenSquared;
	double sumNumBoxes;
	double sumNumBoxesSquared;
	double duration;
	uint64_t numDropped;
	double maxFPS, minFPS, sigFPS;
	double sumFPS, sumFPSSquared;

	ufmfTimingUpdate timings[UTT_NUM_TIMINGS];


    int64_t foregroundBinCounts[NUM_FOREGROUND_BINS];
	double foregroundThresholds[NUM_FOREGROUND_BINS];
	
	double sumAverageErr, maxAverageErr, sumFilteredErr, maxFilteredErr, sumMaxPxErr, maxMaxPxErr;
	double sumAverageErrSquared, sumFilteredErrSquared, sumMaxPxErrSquared;
	int *pix_err, **line_err, *box_err;
	int width, height, numPixels;

	int streamPrintFreq, statComputeFrameErrorFreq;
	bool statPrintFrameErrors, statPrintTimings;
	double startTime;
	unsigned int numFrames;
	int64_t nFramesComputeFrameError;
	int64_t nFramesCompressed;
	int64_t nFramesBackSub;
	ufmfLogger *logger;
	bool freeLogger;
	bool printDebugMode;
	
	double lastAveErr; // mean per-pixel error over the last image
	double lastMaxFiltErr; // maximum filter error over the last image
	double lastMaxPxErr; // maximum per-pixel error over the last image
	double filterZ; // number of pixels in the filter -- normalize by this
	double lastFPS; // last estimate of FPS, based on a pair of frames
	double lastSPF; // last estimate of SPF, based on a pair of frames

public:

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wwrite-strings"

    ufmfWriterStats(ufmfLogger *logger, int width=-1, int height = -1, int streamPrintFreq=1, bool statPrintFrameErrors=true,
		bool statPrintTimings=true, int statComputeFrameErrorFreq=1, bool doOverwrite=true) { 
		printDebugMode = true;
		init(logger, width, height, streamPrintFreq, statPrintFrameErrors, statPrintTimings, statComputeFrameErrorFreq);
	}

	void printStreamHeader(){
		logger->log(UFMF_DEBUG_3, "streamStart\n"); 
		logger->log(UFMF_DEBUG_3, "frame,nFramesBuffered,timestamp,isCompressed,FPS,nFramesDropped,bytes,nForegroundPx,nPxWritten,nBoxes,meanPixelError,maxPixelError,maxFilterError");
		if(statPrintTimings){
			                      // START_WRITING,    WRITE_HEADER,   WRITE_FOOTER,   ADD_FRAME,   UPDATE_BACKGROUND,   COMPUTE_BACKGROUND,   WRITE_KEYFRAME,   COMPUTE_FRAME,    WRITE_FRAME,   COMPUTE_STATS,       WAIT_FOR_COMPRESS_THREAD,     WAIT_FOR_UNCOMPRESSED_FRAME, WAIT_FOR_COMPRESSED_FRAME, UTT_STOP_WRITE
			logger->log(UFMF_DEBUG_3,",startWritingTime,writeHeaderTime,writeFooterTime,addFrameTime,updateBackgroundTime,computeBackgroundTime,writeKeyFrameTime,compressFrameTime,writeFrameTime,computeStatisticsTime,waitForCompressionThreadTime,waitForUncompressedFrameTime,waitForCompressedFrameTime,stopWritingTime");
		}
		logger->log(UFMF_DEBUG_3,"\n");
	}
	void printStreamFooter(){
		logger->log(UFMF_DEBUG_3, "streamEnd\n");
	}
	void printSummaryHeader(){
		logger->log(UFMF_DEBUG_0, "summaryStart\n"); 
		logger->log(UFMF_DEBUG_0, "nFrames,nFramesDroppedTotal,nFramesUncompressed,nFramesNoBackSub,meanFPS,stdFPS,maxFPS,minFPS,meanBandWidth,maxBandWidth,meanFrameSize,stdFrameSize,maxFrameSize,meanCompressionRate,meanNForegroundPx,stdNForegroundPx,maxNForegroundPx,meanNPxWritten,stdNPxWritten,maxNPxWritten,meanNBoxes,stdNBoxes,maxNBoxes");
		for(int i = 0; i < NUM_FOREGROUND_BINS; i++){
			logger->log(UFMF_DEBUG_0,",fracFramesWithFracFgPx>%f",foregroundThresholds[i]);
		}
		if(statComputeFrameErrorFreq){
			logger->log(UFMF_DEBUG_0,",meanMeanPixelError,stdMeanPixelError,maxMeanPixelError,meanMaxPixelError,stdMaxPixelError,maxMaxPixelError,meanMaxFilterError,stdMaxFilterError,maxMaxFilterError");
		}
		if(statPrintTimings){
			//                         startWritingTime,                                           writeHeaderTime,                                         writeFooterTime,                                         addFrameTime,                                   updateBackgroundTime,                                                   computeBackgroundTime,                                                     writeKeyFrameTime,                                             compressFrameTime,                                             writeFrameTime,                                       computeStatisticsTime,                                                     waitForCompressionThreadTime,                                                                   waitForUncompressedFrameTime,                                                                   waitForCompressedFrameTime,                                                               stopWritingTime
			logger->log(UFMF_DEBUG_0,",meanStartWritingTime,maxStartWritingTime,nStartWritingCalls,meanWriteHeaderTime,maxWriteHeaderTime,nWriteHeaderCalls,meanWriteFooterTime,maxWriteFooterTime,nWriteFooterCalls,meanAddFrameTime,maxAddFrameTime,nAddFrameCalls,meanUpdateBackgroundTime,maxUpdateBackgroundTime,nUpdateBackgroundCalls,meanComputeBackgroundTime,maxComputeBackgroundTime,nComputeBackgroundCalls,meanWriteKeyFrameTime,maxWriteKeyFrameTime,nWriteKeyFrameCalls,meanCompressFrameTime,maxCompressFrameTime,nCompressFrameCalls,meanWriteFrameTime,maxWriteFrameTime,nWriteFrameCalls,meanComputeStatisticsTime,maxComputeStatisticsTime,nComputeStatisticsCalls,meanWaitForCompressionThreadTime,maxWaitForCompressionThreadTime,nWaitForCompressionThreadCalls,meanWaitForUncompressedFrameTime,maxWaitForUncompressedFrameTime,nWaitForUncompressedFrameCalls,meanWaitForCompressedFrameTime,maxWaitForCompressedFrameTime,nWaitForCompressedFrameCalls,meanStopWritingTime,maxStopWritingTime,nStopWritingCalls");
		}
		logger->log(UFMF_DEBUG_0,"\n");
	}
	void printSummaryFooter(){
		logger->log(UFMF_DEBUG_0, "summaryEnd\n");
	}

	ufmfWriterStats(const char *logName, int width=-1, int height = -1, int streamPrintFreq=1, bool statPrintFrameErrors=true, 
		bool statPrintTimings=true, int statComputeFrameErrorFreq=1, bool doOverWrite=true) {
		logger = new ufmfLogger(logName, UFMF_DEBUG_3, doOverWrite);
		printDebugMode = false;
		init(logger, width, height, streamPrintFreq, statPrintFrameErrors, statPrintTimings, statComputeFrameErrorFreq);
		if(streamPrintFreq>0){
			printStreamHeader();
		}
		freeLogger = true;
	}

	~ufmfWriterStats() {
		freeBuffers();
		if(freeLogger){
			delete logger;
			logger = NULL;
		}
	}

	void flushNow(){
		if(logger){
			logger->flushNow();
		}
	}

	void clear() {

		numFrames = 0; 
		nFramesComputeFrameError = 0;
		nFramesCompressed = 0;
		nFramesBackSub = 0;
		maxFrameSizeBytes = 0;
		maxForegroundPixels = maxNumWritten = maxNumBoxes = 0;
		maxBytesPerSec = sumFrameSizeBytes = sumForegroundPixels = sumNumWritten = sumNumBoxes = 0;
		sumFrameSizeBytesSquared = sumForegroundPixelsSquared = sumNumWrittenSquared = sumNumBoxesSquared = 0;
		maxFPS = -1.0; minFPS = 999999;
		sumFPS = 0.0; sumFPSSquared = 0;

		foregroundThresholds[0] = .05;  foregroundThresholds[1] = .1; foregroundThresholds[2] = .25;
		foregroundBinCounts[0] = foregroundBinCounts[1] = foregroundBinCounts[2] = 0;

		sumAverageErr = maxAverageErr = sumFilteredErr = maxFilteredErr = sumMaxPxErr = maxMaxPxErr = 0;
		sumAverageErrSquared = sumFilteredErrSquared = sumMaxPxErrSquared = 0;

		lastAveErr = -1.0;
		filterZ = (double)ERROR_FILTER_WIDTH*ERROR_FILTER_WIDTH;
		lastMaxFiltErr = -filterZ;
		lastMaxPxErr = -1.0;
		lastFPS = -1.0;
		lastSPF = -1.0;

		const char *updateNames[UTT_NUM_TIMINGS] = { "none", "Start Writing", "Write Header", "Write Footer", "Add Frame", "Update Background", "Compute Background", 
													 "Write Key Frame", "Compress Frame", "Write Frame", "Compute Statistics", "Wait For Compression Thread", 
													 "Wait For Uncompressed Frame", "Wait For Compressed Frame", "Stop Writing" };
		for(int i = 0; i < UTT_NUM_TIMINGS; i++) {
			timings[i].sum = timings[i].maxDur = timings[i].lastDur = 0;
			timings[i].num = 0;
			timings[i].hasUpdate = false;
			timings[i].type = (ufmfTimingType)i;
			timings[i].name = updateNames[i];
		}
	}
	void init(ufmfLogger *l, int width=-1, int height = -1, int streamPrintFreq=1, bool statPrintFrameErrors=true, 
		bool statPrintTimings=true, int statComputeFrameErrorFreq=1) {
		clear();
		line_err = NULL;
		box_err = pix_err = NULL;
		freeLogger = false;
		logger = l;
		this->streamPrintFreq = streamPrintFreq;
		this->statComputeFrameErrorFreq = statComputeFrameErrorFreq;
		this->statPrintFrameErrors = statPrintFrameErrors;
		this->statPrintTimings = statPrintTimings;
		if(statPrintFrameErrors)
			initFrameErrorImages(width, height);
		this->numPixels = width*height;
	}
	
	void initFrameErrorImages(int width, int height) {
		freeBuffers();
		this->width = width;
		this->height = height;
		pix_err = new int[width+ERROR_FILTER_WIDTH]+ERROR_FILTER_WIDTH;
		box_err = new int[width];
		line_err = new int*[ERROR_FILTER_WIDTH];
		for(int i = 0; i < ERROR_FILTER_WIDTH; i++)
			line_err[i] = new int[width+1]+1;
	}

	void freeBuffers() {
		if(pix_err) delete [] (pix_err-ERROR_FILTER_WIDTH);
		if(line_err) {
			for(int i = 0; i < ERROR_FILTER_WIDTH; i++)
				delete [] (line_err[i]-1);
			delete [] line_err;
		}
		if(box_err) delete [] box_err;
	}
	
	// Call this on every frame written to update stats
	void update(std::vector<int64_t> &index, std::vector<double> &index_timestamp, int64_t frameSize, bool isCompressedFrame, int numForeground, int numWritten, int numBoxes,
				uint64_t numBuffered, uint64_t numDropped, unsigned short *nWrites, int numPixels, uint8_t *frame, float *background,
				ufmfDebugLevel level) {

		if(numFrames == 0 && index_timestamp.size() > 0) { startTime = index_timestamp[0]; }
		unsigned int beg = numFrames;
		int i;
		double bandwidth=0;
		//__int64 frameSize=0;
		double currTime = 0;

		this->numDropped = numDropped;
		
		// Find the frame BANDWIDTH_COMPUTATION_TIME_WINDOW_SEC seconds backwards in time to compute the bandwidth
		// maxBytesPerSec: the maximum number of bytes written per second, smoothed over 
		// windows of length BANDWIDTH_COMPUTATION_TIME_WINDOW_SEC
		assert(numFrames == index.size()-1);
		// find the frame more than BANDWIDTH_COMPUTATION_TIME_WINDOW_SEC seconds before the current frame
		while(beg > 0 && index_timestamp[beg] > index_timestamp[numFrames]-BANDWIDTH_COMPUTATION_TIME_WINDOW_SEC)
			beg--;
		bandwidth = -1;
		// how long ago was this frame?
		double dt = beg < numFrames ? (index_timestamp[numFrames]-index_timestamp[beg]) : 0;
		if(dt) {
			// how many bytes were written, normalized by number of seconds
			bandwidth = (index[numFrames]-index[beg]) / dt;
			// update maximum if index_timestamp[numFrames] - index_timestamp[beg] < index_timestamp[numFrames] - BANDWIDTH
			// -> -index_timestamp[beg] < BANDWIDTH
			// -> index_timestamp[beg] > BANDWIDTH
			if(bandwidth > maxBytesPerSec && (dt >= BANDWIDTH_COMPUTATION_TIME_WINDOW_SEC)) {
				maxBytesPerSec = bandwidth;
			}
		}

		if(numFrames > 0){
			lastSPF = index_timestamp[numFrames]-index_timestamp[numFrames-1];
			lastFPS = 1.0/lastSPF;
			if(lastFPS > maxFPS) maxFPS = lastFPS;
			if(lastFPS < minFPS) minFPS = lastFPS;
			sumFPS += lastFPS;
			sumFPSSquared += SQUARED(lastFPS);
		}
		else{
			lastFPS = -1.0;
		}

		// Update counts of the fraction of foreground pixels above a particular threshold
		for(i = 0; i < NUM_FOREGROUND_BINS; i++)
			if(numForeground > numPixels*foregroundThresholds[i])
				foregroundBinCounts[i]++;

		// Update various sums and maxes

		// bytes for storing this frame
		//frameSize = (numFrames ? (index[numFrames]-index[numFrames-1]) : index[numFrames]);
		if(frameSize > maxFrameSizeBytes) maxFrameSizeBytes = frameSize;

		// update maximum number of foreground pixels
		if(numForeground > maxForegroundPixels) maxForegroundPixels = numForeground;

		if(isCompressedFrame){
			// update maximum number of pixels written
			if(numWritten > maxNumWritten) maxNumWritten = numWritten;
			// update maximum number of boxes
			if(numBoxes > maxNumBoxes) maxNumBoxes = numBoxes;
			// for computing average number of pixels written per frame
			sumNumWritten += (double)numWritten;
			sumNumWrittenSquared += SQUARED((double)numWritten);
			// for computing average number of boxes per frame
			sumNumBoxes += (double)numBoxes;
			sumNumBoxesSquared += SQUARED((double)numBoxes);
			nFramesCompressed++;
		}

		duration = index_timestamp[numFrames]-startTime;
		currTime = index_timestamp[numFrames];
		numFrames++; 

		// for computing average number of bytes per frame
		sumFrameSizeBytes += (double)frameSize;
		sumFrameSizeBytesSquared += SQUARED((double)frameSize);
		// numForeground will be -1 if background subtraction not done
		if(numForeground >= 0){
			// for computing average number of foreground pixels per frame
			sumForegroundPixels += (double)numForeground;
			sumForegroundPixelsSquared += SQUARED((double)numForeground);
			nFramesBackSub++;
		}
		
		uint64_t sumErr = 0;
		int maxFiltErr = 0, maxPxErrCurr = 0, x, y, *newest_line_err, *oldest_line_err;
		double aveErr = 0; //, unused;
		unsigned char *framePtr;
		float *backgroundPtr;
		unsigned short *nWritesPtr;
		if(logger && statPrintFrameErrors && (numFrames%statComputeFrameErrorFreq == 0)) {

			if(printDebugMode) logger->log(level, "computing compression error rate\n"); 

			// everything will stay the same if this is not a compressed frame
			if(isCompressedFrame){

				// Compute the sum error in a ERROR_FILTER_WIDTHXERROR_FILTER_WIDTH box around each pixel 
				int diff;//, *iPtr;
				assert(width*height == numPixels);

				// pix_err is the per-pixel error for an entire row of the image
				// line_err[i] is the summed per-pixel error for a horizontal patch of length ERROR_FILTER_WIDTH for line i (store ERROR_FILTER_WIDTH lines)
				// box_err is the summed per-pixel error for the box (what we're trying to compute)

				// aveErr is the mean per-pixel error over the current image
				// maxFiltErr is the maximum filter error over the current image

				// sumAverageErr is the summed mean per-pixel error over all images
				// maxAverageErr is the max mean per-pixel error over all images
				// sumFilteredErr is the summed max filter error over all images
				// maxFilteredErr is the max max filter error over all images

				// Initialize all buffers to 0.  This enables us to not have to use bounds checking when computing line and box sum errors, and
				// is equivalent to padding the images with zeros
				memset(pix_err-ERROR_FILTER_WIDTH, 0, (width+ERROR_FILTER_WIDTH)*sizeof(int));
				for(i = 0; i < ERROR_FILTER_WIDTH; i++)
					memset(line_err[i]-1, 0, (width+1)*sizeof(int));
				memset(box_err, 0, width*sizeof(int));

				for(y = 0, framePtr = frame, backgroundPtr = background, nWritesPtr = nWrites; 
					y < height; y++, framePtr += width, backgroundPtr += width, nWritesPtr += width) {
					newest_line_err = line_err[y%ERROR_FILTER_WIDTH];
					oldest_line_err = line_err[(y+1)%ERROR_FILTER_WIDTH];
					for(x = 0; x < width; x++) { 
						// Compute the error at pixel x,y
						if(nWritesPtr[x]==0) { 
							if(framePtr[x] >= backgroundPtr[x]){
								diff = (int)(framePtr[x] - (unsigned char)backgroundPtr[x]);
							}
							else{
								diff = (int)((unsigned char)backgroundPtr[x] - framePtr[x]);
							}
							//diff = (int)framePtr[x]-(int)backgroundPtr[x]; 
							//if(diff < 0) diff = -diff;

							// update average per-pixel error over the entire image
							sumErr += (uint64_t)diff;

							// update max per-pixel error over the entire image
							if(diff > maxPxErrCurr) maxPxErrCurr = diff;

						} else
							diff = 0;
						pix_err[x] = diff;  // pixel error at (x,y)

						// Store into newest_line[x] the sum error in the line strip (x-ERROR_FILTER_WIDTH...x,y)
						newest_line_err[x] = newest_line_err[x-1] + (diff-pix_err[x-ERROR_FILTER_WIDTH]);

						// Store into box_err[x] the sum error in the box from (x-ERROR_FILTER_WIDTH...x,y-ERROR_FILTER_WIDTH...y)
						box_err[x] += (newest_line_err[x]-oldest_line_err[x]); 

						// We are just interested in the maximum box error over the image.  Because of this, we don't need to compute the
						// box error on some of the border pixels
						if(box_err[x] > maxFiltErr) maxFiltErr = box_err[x];
					}
				}

				// compute average per-pixel error over entire image
				aveErr = (double)sumErr / (double)numPixels;
				// update mean mean per-pixel error over all images
				sumAverageErr += aveErr;
				sumAverageErrSquared += SQUARED(aveErr);
				// update max mean per-pixel error over all images
				if(aveErr > maxAverageErr) maxAverageErr = aveErr;
				// update mean max per-pixel error over all images
				sumMaxPxErr += (double)maxPxErrCurr;
				sumMaxPxErrSquared += SQUARED((double)maxPxErrCurr);
				// update max max per-pixel error over all images
				if((double)maxPxErrCurr > maxMaxPxErr) maxMaxPxErr = maxPxErrCurr;
				// update mean max filter error over all images
				sumFilteredErr += (double)maxFiltErr;
				sumFilteredErrSquared += SQUARED((double)maxFiltErr);
				// update max max filter error over all images
				if(maxFiltErr > maxFilteredErr) maxFilteredErr = (double)maxFiltErr;

			}

			lastAveErr = aveErr;
			lastMaxPxErr = (double)maxPxErrCurr;
			lastMaxFiltErr = (double)maxFiltErr;
			nFramesComputeFrameError++;

		}

		if(logger && streamPrintFreq && (numFrames%streamPrintFreq == 0)) { 
			if(printDebugMode){
				logger->log(level, "ufmf frame %d: buffered=%llu, dropped=%llu, timestamp=%f, is_compressed=%d, fps=%f, bytes=%d, foreground_pixels=%d, num_pixels_written=%d, num_boxes=%d, lastAveErr=%f, lastMaxPxErr=%f, lastMaxFiltErr=%f\n", 
					(int)numFrames, numBuffered, numDropped, currTime, (int)isCompressedFrame, lastFPS, (int)frameSize, numForeground, numWritten, numBoxes, (float)lastAveErr, (float)lastMaxPxErr, (float)(lastMaxFiltErr/filterZ)); 
			}
			else{
				logger->log(level, "%d,%llu,%f,%d,%f,%llu,%d,%d,%d,%d,%f,%f,%f",
					(int)numFrames, numBuffered, currTime, (int)isCompressedFrame, lastFPS, (int)numDropped, (int)frameSize, numForeground, numWritten, numBoxes, (float)lastAveErr, (float)lastMaxPxErr, (float)(lastMaxFiltErr/filterZ));
			}
			if(statPrintTimings){
				printTimings(level, false);
			}
			else{
				logger->log(level,"\n");
			}
			if(printDebugMode){
				print(level); 
			}
		}
	}

	static NSTimeInterval getTime(){

		return [NSDate timeIntervalSinceReferenceDate];

	}

	NSTimeInterval updateTimings(ufmfTimingType t, NSTimeInterval startTime) {

		NSTimeInterval uli = getTime();

		if(statPrintTimings) {
			// get the current time

            timings[t].lastDur = uli - startTime;
			if(timings[t].lastDur > timings[t].maxDur) timings[t].maxDur = timings[t].lastDur;
			timings[t].sum += timings[t].lastDur;
			timings[t].num++;
			timings[t].hasUpdate = true;

		}

		return uli;

	}

	void printTimings(ufmfDebugLevel level, bool printGlobal = false) {

		int num = 0;
		if(statPrintTimings) {
			char tmp[10000], str[10000];
			if(printDebugMode){
				strcpy(str, "Computation times: ");
			}
			else{
				strcpy(str,"");
			}
			for(int i = 1; i < UTT_NUM_TIMINGS; i++) {
				if(printGlobal) {
					if(printDebugMode){
						if(timings[i].num){
							sprintf(tmp, "%s'%s' took %.3fms on average over %d calls with a maximum value of %.3fms", 
								num++ ? ", " : "", timings[i].name, (timings[i].sum/10000.0/(double)timings[i].num), 
								timings[i].num, timings[i].maxDur/10000.0); 
						}
						else{
							sprintf(tmp,"");
						}
					}
					else{
						sprintf(tmp, ",%f,%f,%d", 
							timings[i].num ? (timings[i].sum/10000.0/(double)timings[i].num) : -1.0, 
							timings[i].num ? timings[i].maxDur/10000.0 : -1.0, 
							timings[i].num); 
					}
					strcat(str, tmp); 
				} else{
					if(printDebugMode){
						if(timings[i].hasUpdate) {
							sprintf(tmp, "%s'%s' took %.3fms", num++ ? ", " : "", timings[i].name, timings[i].lastDur/10000.0); 	
						}
						else{
							sprintf(tmp,"");
						}
					}
					else{
						if(timings[i].hasUpdate) {
							sprintf(tmp, ",%f",timings[i].lastDur/10000.0);
						}
						else{
							// print -1 if this function has not been called
							sprintf(tmp, ",%f",-1.0);
						}
					}
					strcat(str, tmp); 
					timings[i].hasUpdate = false; 
				}
			}
			if(logger){
				logger->log(level, "%s\n" , str);
			}
		}
	}

	void print(ufmfDebugLevel level) {
		char str[5000], tmp[5000];
		double muFPS = sumFPS / (double)(numFrames-1);
		sigFPS = sqrt(MAX(0,sumFPSSquared / (double)(numFrames-1) - muFPS*muFPS));
		double meanFrameSizeBytes;
		meanFrameSizeBytes = sumFrameSizeBytes/(double)numFrames;
		double stdFrameSizeBytes = sqrt( MAX(0,sumFrameSizeBytesSquared / (double)numFrames - meanFrameSizeBytes*meanFrameSizeBytes) );
		double compressionRate;
		compressionRate = meanFrameSizeBytes / (double)numPixels;
		double meanForegroundPixels = (sumForegroundPixels/(double)nFramesBackSub);
		double stdForegroundPixels = sqrt( MAX(0,sumForegroundPixelsSquared / (double)nFramesBackSub - meanForegroundPixels*meanForegroundPixels) );
		double meanNumWritten = (sumNumWritten/(double)nFramesCompressed);
		double stdNumWritten = sqrt( MAX(0,sumNumWrittenSquared / (double)nFramesCompressed - meanNumWritten*meanNumWritten) );
		double meanNumBoxes = (sumNumBoxes/(double)nFramesCompressed);
		double stdNumBoxes = sqrt( MAX(0,sumNumBoxesSquared / (double)nFramesCompressed - meanNumBoxes*meanNumBoxes) );
		double meanAverageErr = (sumAverageErr/(double)nFramesComputeFrameError);
		double stdAverageErr = sqrt( MAX(0,sumAverageErrSquared / (double)nFramesComputeFrameError - meanAverageErr*meanAverageErr) );
		double meanMaxPxErr = (sumMaxPxErr/(double)nFramesComputeFrameError);
		double stdMaxPxErr = sqrt( MAX(0,sumMaxPxErrSquared / (double)nFramesComputeFrameError - meanMaxPxErr*meanMaxPxErr) );
		double meanFilteredErr = sumFilteredErr/(double)nFramesComputeFrameError;
		double stdFilteredErr = sqrt( MAX(0,sumFilteredErrSquared / (double)nFramesComputeFrameError - meanFilteredErr*meanFilteredErr) );

		if(printDebugMode){
			sprintf(str, "num_frames=%u, num_dropped=%llu, num_frames_raw=%u, num_frames_nobacksub=%u, fps=(%f ave, %f std, %f max, %f min), bandwidth=(%f KB/s ave, %f KB/s peak), frame_size=(%f KB ave, %f std, %f KB peak), compression_rate=%f, foreground_pixels=(%f ave, %f std, %f peak), num_pixels_written=(%f ave, %f std, %f peak), num_boxes=(%f ave, %f std, %f peak)",
				numFrames, // nFrames
				numDropped, // nFramesDroppedTotal
				(numFrames-(unsigned int)nFramesCompressed), // nFramesUncompressed
				(numFrames-(unsigned int)nFramesBackSub), // nFramesNoBackSub
				((double)numFrames / duration), // average fps
				sigFPS,maxFPS,minFPS,
				(duration ? sumFrameSizeBytes/duration/1024.0 : 0.0),(maxBytesPerSec/1024.0), // meanBandWidth, maxBandWidth
				meanFrameSizeBytes,stdFrameSizeBytes,(double)(maxFrameSizeBytes), // meanFrameSize, stdFrameSize, maxFrameSize
				compressionRate,
				meanForegroundPixels, stdForegroundPixels, (double)maxForegroundPixels, // meanNForegroundPx, stdNForegroundPx, maxNForegroundPx
				meanNumWritten, stdNumWritten, (double)maxNumWritten,
				meanNumBoxes, stdNumBoxes, (double)maxNumBoxes); // meanNBoxes, stdNBoxes, maxNBoxes
		}
		else{
			sprintf(str,"%u,%llu,%u,%u,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f",
				numFrames, // nFrames
				numDropped, // nFramesDroppedTotal
				(numFrames-(unsigned int)nFramesCompressed), // nFramesUncompressed
				(numFrames-(unsigned int)nFramesBackSub), // nFramesNoBackSub
				((double)numFrames / duration), // average fps
				sigFPS,maxFPS,minFPS,
				(duration ? sumFrameSizeBytes/duration/1024.0 : 0.0),(maxBytesPerSec/1024.0), // meanBandWidth, maxBandWidth
				meanFrameSizeBytes,stdFrameSizeBytes,(double)(maxFrameSizeBytes), // meanFrameSize, stdFrameSize, maxFrameSize
				compressionRate,
				meanForegroundPixels, stdForegroundPixels, (double)maxForegroundPixels, // meanNForegroundPx, stdNForegroundPx, maxNForegroundPx
				meanNumWritten, stdNumWritten, (double)maxNumWritten,
				meanNumBoxes, stdNumBoxes, (double)maxNumBoxes); // meanNBoxes, stdNBoxes, maxNBoxes
		}

		for(int i = 0; i <NUM_FOREGROUND_BINS; i++) {
			if(printDebugMode){
				sprintf(tmp, ", %%foreground>%.03f=%f", foregroundThresholds[i],  ((double)foregroundBinCounts[i]/(double)nFramesBackSub)); 
			}
			else{
				sprintf(tmp, ",%f", ((double)foregroundBinCounts[i]/(double)nFramesBackSub));
			}
			strcat(str, tmp); 
		}
		if(statPrintFrameErrors) { 
			if(printDebugMode){
				sprintf(tmp, ", ave_ave_pixel_error=%f, std_ave_pixel_error=%f, max_ave_ave_pixel_error=%f, ave_max_pixel_error=%f, std_max_pixel_error=%f, max_max_pixel_error=%f",
					meanAverageErr, stdAverageErr, maxAverageErr, // meanMeanPixelError,stdMeanPixelError,maxMeanPixelError
					meanMaxPxErr, stdMaxPxErr, maxMaxPxErr); // meanMaxPixelError,stdMaxPixelError,maxMaxPixelError
			}
			else{
				sprintf(tmp, ",%f,%f,%f,%f,%f,%f",
					meanAverageErr, stdAverageErr, maxAverageErr, // meanMeanPixelError,stdMeanPixelError,maxMeanPixelError
					meanMaxPxErr, stdMaxPxErr, maxMaxPxErr); // meanMaxPixelError,stdMaxPixelError,maxMaxPixelError
			}
			strcat(str, tmp); 
			if(printDebugMode){
				sprintf(tmp, ", ave_max_filtered_pixel_error=%f, std_max_filtered_pixel_error=%f, max_max_filtered_pixel_error=%f", 
					(meanFilteredErr/filterZ), stdFilteredErr/filterZ, (maxFilteredErr/filterZ)); // meanMaxFilterError,stdMaxFilterError,maxMaxFilterError
			}
			else{
				sprintf(tmp, ",%f,%f,%f", 
					(meanFilteredErr/filterZ), stdFilteredErr/filterZ, (maxFilteredErr/filterZ)); // meanMaxFilterError,stdMaxFilterError,maxMaxFilterError
			}
			strcat(str, tmp); 
		}

		if(printDebugMode){
			strcat(str, "\n");
		}
		if(logger) {
			logger->log(level, "%s" , str);
		}
		//sumAverageErr = maxAverageErr = sumFilteredErr = maxFilteredErr = 0;

	}
	void printSummary(ufmfDebugLevel level=UFMF_DEBUG_0){
		if(!printDebugMode){
			if(streamPrintFreq>0){
				printStreamFooter();
			}
			printSummaryHeader();
		}
		print(level);
		printTimings(UFMF_DEBUG_0, true);
		if(!printDebugMode){
			printSummaryFooter();
		}
	}

	bool renameStatFile(const char *newfname){
		if(logger == NULL){
			return true;
		}
		return logger->renameLogFile(newfname);
	}
};

#pragma clang diagnostic pop

#endif
