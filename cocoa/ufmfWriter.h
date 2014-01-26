#ifndef __UFMFWRITER_H
#define __UFMFWRITER_H

#import <Foundation/Foundation.h>
#include "ufmfWriterStats.h"
#include "ufmfLogger.h"
#include <vector>
#include <math.h>
#include <time.h>
#define MAXWAITTIMEMS 10000

class BackgroundModel {

public:

	void init();
	BackgroundModel();
	BackgroundModel(uint32_t nPixels, int minNFramesReset = 200);
	~BackgroundModel();
	bool addFrame(unsigned char * im, double timestamp);
	bool updateModel();

private:

	// parameters
	int minNFramesReset; // minimum number of frames that must have been added to the model before we reset the counts
	int BGNBins;
	int BGBinSize;
	float BGHalfBin;

	int nPixels; // frame size

	// counts
	uint64_t nFramesAdded; // Number of frames added to the background model

	// buffers
	uint8_t ** BGCounts; // counts per bin: note the limited resolution
	float * BGCenter; // current background model
	float BGZ;

	friend class ufmfWriter;

};

// class to hold buffered compressed frames
class CompressedFrame {

public:

	void init();
	CompressedFrame();
	CompressedFrame(unsigned short wWidth, unsigned short wHeight, uint32_t boxLength = 30, double maxFracFgCompress = 1.0);
	bool setData(uint8_t * im, double timestamp, uint64_t,
		uint8_t * BGLowerBound, uint8_t * BGUpperBound);
	~CompressedFrame();

private:

	unsigned short wWidth; //Image Width
	unsigned short wHeight; //Image Height
	int nPixels;
	bool * isFore; // whether each pixel is foreground or not
	int numFore;
	int numPxWritten;
	bool isCompressed;
	//bool * debugWasFore; // TODO: remove after debugging
	uint16_t * writeRowBuffer; // ymins
	uint16_t * writeColBuffer; // xmins
	uint16_t * writeHeightBuffer; // heights
	uint16_t * writeWidthBuffer; // widths
	uint8_t * writeDataBuffer; // image data
	uint16_t * nWrites; // number of times a pixel has been written
	uint32_t ncc;
	double timestamp;
	uint64_t frameNumber;

	// parameters
	uint32_t boxLength; // length of boxes of foreground pixels to store
	int boxArea; // boxLength^2
	double maxFracFgCompress; // max fraction of pixels that can be foreground in order for us to compress
	int maxNFgCompress; // max number of pixels that can be foreground in order for us to compress

	friend class ufmfWriter;

};

// main ufmf writer class
class ufmfWriter {
public:

	// constructors

	// common code for both the empty constructor and the parameter-filled constructor
	void init();

	// common code for parameter-filled constructors
	void init(const char * fileName, uint32_t pWidth, uint32_t pHeight,
		int MaxBGNFrames = 100, double BGUpdatePeriod = 1.0, double BGKeyFramePeriod = 100, uint32_t boxLength = 30,
		double backSubThresh = 10.0, uint32_t nFramesInit = 100, double* BGKeyFramePeriodInit = NULL, int BGKeyFramePeriodInitLength = 0,
		double maxFracFgCompress = 1.0, const char *statFileName=NULL, bool printStats=true, int statStreamPrintFreq=1, bool statPrintFrameErrors=true, 
		bool statPrintTimings=true, int statComputeFrameErrorFreq=1, uint32_t nThreads=4);

	// empty constructor:
	// initializes values to defaults
	ufmfWriter();

	// parameter-filled constructor
	// set parameters
	// allocate buffers
	//
	// parameters:
	// [video parameters:]
	// fileName: name of video to write to
	// pWidth: width of frame
	// pHeight: height of frame
	// [acquisition parameters:]
	// [compression parameters:]
	// MaxBGNFrames: approximate number of frames used in background computation
	// BGUpdatePeriod: seconds between updates to the background model
	// BGKeyFramePeriod: seconds between background keyframes
	// boxLength: length of foreground boxes to store
	// backSubThresh: threshold for storing foreground pixels
	// nFramesInit: for the first nFramesInit, we will always update the background model
	// [compression stats parameters:]
	// statFileName: name of file to write compression statistics to. If NULL, then statistics are combined into debug file
	// printStats: whether to print compression statistics
	// statStreamPrintFreq: number of frames between outputting per-frame compression statistics
	// statPrintFrameErrors: whether to compute and print statistics of compression error. Currently, box-averaged and per-pixel errors are either both
	// computed or both not computed. 
	// statPrintTimings: whether to print information about the time each part of the computation takes. 
	ufmfWriter(const char * fileName, uint32_t pWidth, uint32_t pHeight, FILE* logFID,
		int MaxBGNFrames = 100, double BGUpdatePeriod = 1.0, double BGKeyFramePeriod = 100, uint32_t boxLength = 30,
		double backSubThresh = 10.0, uint32_t nFramesInit = 100, double* BGKeyFramePeriodInit = NULL, int BGKeyFramePeriodInitLength = 0, 
		double maxFracFgCompress = 1.0, const char *statFileName=NULL, bool printStats=true, int statStreamPrintFreq=1, bool statPrintFrameErrors=true, 
		bool statPrintTimings=true, int statComputeFrameErrorFreq=1, uint32_t nThreads=4);

	ufmfWriter(const char * fileName, uint32_t pWidth, uint32_t pHeight, FILE* logFID, const char * paramsFile);

	// destructor
	~ufmfWriter();

	// public API

	// start writing
	// open file
	// write header
	// start threads
	bool startWrite();

	// stop writing
	// close all threads
	// deallocate buffers
	// write footers
	// close file
	uint64_t stopWrite();

	// add a frame to be processed
	bool addFrame(unsigned char * frame, double timestamp, uint64_t nFramesDroppedExternal=0, uint64_t nFramesBufferedExternal=0);

	// set video file name, width, height
	// todo: resize buffers if already allocated
	void setVideoParams(char * fileName, int wWidth, int wHeight);

	// set video compression parameters
	bool readParamsFile(const char * paramsFile);

	// read stats params from a file
	void setStatsParams(const char * statsName);

    // get number of frames written
	uint64_t NumWritten() { return nWritten; }

private:

	// ***** helper functions *****

	// *** writing tools ***

	// write a frame
	int64_t writeFrame(CompressedFrame * im);

	// write the video header
	bool writeHeader();

	// finish writing
	bool finishWriting();

	// write a background keyframe to file
	bool writeBGKeyFrame(float* BGCenter,double keyframeTimestamp);

	// *** compression tools ***

	// add to bg model counts
	bool addToBGModel(uint8_t * frame, double timestamp, uint64_t frameNumber);

	// reset background model
	bool updateBGModel(uint8_t * frame, double timestamp, uint64_t frameNumber);

	// *** threading tools ***

	// compress frame with thread threadIndex 
	bool ProcessNextCompressFrame(int threadIndex);

	// write next frame
	bool ProcessNextWriteFrame();

	// stop all threads
	bool stopThreads(bool waitForFinish);

	// lock when accessing global data
	bool Lock();
	bool Unlock();

	// deallocate buffers
	void deallocateBuffers();

	// deallocate background model
	void deallocateBGModel();

	// deallocate and release all thread stuff
	void deallocateThreadStuff();

	// helper function
	static char * strtrim(char *aString);

	// ***** state *****

	// *** output ufmf state ***

	FILE * pFile; //File Target
	uint64_t indexLocation; // Location of index in file
	uint64_t indexPtrLocation; // Location in file of pointer to index location
	std::vector<int64_t> index; // Location of each frame in the file
	std::vector<int64_t> meanindex; // Location of each bg center in the file
	std::vector<double> index_timestamp; // timestamp of each frame in the file
	std::vector<double> meanindex_timestamp; // timestamp for each bg center in the file

	// *** writing state ***

	uint64_t nGrabbed; // Number of frames for which addframe  has been called
	uint64_t nWritten; //Track number of frames written to disk
	uint64_t nBGKeyFramesWritten; // Number of background images written
	uint64_t nFramesDroppedExternal; // Number of frames dropped by the external process
	uint64_t nFramesBufferedExternal; // Number of frames buffered by the external process
	bool isWriting; // Whether we are still compressing, still writing

	// *** threading/buffering state ***

	// buffer for grabbed, uncompressed frames
	unsigned char ** uncompressedFrames;
	// timestamps of buffered frames
	double * threadTimestamps;
	// buffer for compressed frames
	CompressedFrame ** compressedFrames;
	// buffers grabbed while waiting for the next frame to write
	int * readyToWrite;
	// number of uncompressed frames buffered
	int nUncompressedFramesBuffered;
	// number of compressed frames buffered
	int nCompressedFramesBuffered;
	uint64_t * threadFrameNumbers; // which grabbed frame is processed by each thread -- used for writing frames in order

	id _writeThread; // write ThreadVariable
	NSMutableArray* _compressionThreads; // compression ThreadVariables
	int threadCount; // current number of compression threads
	NSLock *writeThreadReadySignal; // signal that write thread is set up
	NSMutableArray* compressionThreadReadySignals; // signals that compression threads are set up and ready to process a frame
	NSMutableArray* compressionThreadStartSignals; // signals to compression threads to start processing a frame
	NSMutableArray* compressionThreadDoneSignals; // signal that the compression frame has finished processing a frame and the frame is ready to be written
	NSLock *lock; // semaphore for keeping different threads from accessing the same global variables at the same time

	NSLock *keyFrameWritten; // whether the last computed key frame has been written

	// *** background subtraction state ***

	//uint64_t nBGUpdates; // Number of updates the background model
	//int BGNFrames; // approx number of frames in background computation so far
	double lastBGUpdateTime; // last time the background was updated
	double lastBGKeyFrameTime; // last time a keyframe was written
	BackgroundModel * bg;
	// lower and upper bounds available for thresholding
	uint8_t * BGLowerBound0; // per-pixel lower bound on background
	uint8_t * BGUpperBound0; // per-pixel upper bound on background
	float * BGCenter0; 
	uint8_t * BGLowerBound1; // per-pixel lower bound on background
	uint8_t * BGUpperBound1; // per-pixel upper bound on background
	float * BGCenter1; 
	uint64_t minFrameBGModel0; // first frame that can be used with background model 0
	uint64_t minFrameBGModel1; // first frame that can be used with background model 1
	double keyframeTimestamp0; // timestamp for key frame in buffer 0
	double keyframeTimestamp1; // timestamp for key frame in buffer 1
	//uint8_t ** BGCounts; // counts per bin: note the limited resolution
	//float * BGCenter; // current background model
	//uint8_t * BGLowerBound; // per-pixel lower bound on background
	//uint8_t * BGUpperBound; // per-pixel upper bound on background
	//float BGZ;

	// *** logging state ***

	ufmfWriterStats * stats;
	FILE * logFID;
	ufmfLogger * logger;

	// ***** parameters *****

	// *** threading parameters ***

	uint32_t nThreads; // number of compression threads

	// *** video parameters ***

	char fileName[1000]; // output video file name
	unsigned short wWidth; //Image Width
	unsigned short wHeight; //Image Height
	int nPixels; // Number of pixels in image
	char colorCoding[10]; // video color format
	uint8_t colorCodingLength;

	// *** compression parameters ***

	// * background subtraction parameters *

	int MaxBGNFrames; // approximate number of frames used in background computation
	double BGUpdatePeriod; // seconds between updates to the background model
	double BGKeyFramePeriod; // seconds between background keyframes
	float backSubThresh; // threshold above which we store a pixel
	uint32_t nFramesInit; // for the first nFramesInit, we will always update the background model
	double BGKeyFramePeriodInit[100]; // seconds before we output a new background model initially while ramping up the background model
	int BGKeyFramePeriodInitLength;
	int nBGUpdatesPerKeyFrame;
	float MaxBGZ;
	//int BGBinSize;
	//int BGNBins; 
	//float BGHalfBin;

	// * ufmf parameters *
	uint8_t isFixedSize; // whether patches are of a fixed size
	uint32_t boxLength; // length of boxes of foreground pixels to store
	double maxFracFgCompress; // max fraction of pixels that can be foreground in order for us to compress

	// chunk identifiers
	static const uint8_t KEYFRAMECHUNK = 0;
	static const uint8_t FRAMECHUNK = 1;
	static const uint8_t INDEX_DICT_CHUNK = 2;

	// *** statistics parameters ***
	char statFileName[256];
	bool printStats;
	int statStreamPrintFreq;
	bool statPrintFrameErrors;
	bool statPrintTimings; 
	int statComputeFrameErrorFreq;

	// *** logging parameters ***
	ufmfDebugLevel UFMFDEBUGLEVEL;


};

#endif