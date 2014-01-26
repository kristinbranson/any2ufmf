#include <stdio.h>
#include "ufmfWriter.h"

// ************************* BackgroundModel **************************

void BackgroundModel::init(){

	// parameters

	// defaults
	minNFramesReset = 200;

	// hard-coded
	BGBinSize = 1;
	BGNBins = (int)ceil(256.0 / (float)BGBinSize);
	BGHalfBin = ((float)BGBinSize - 1.0) / 2.0;

	// initialize counts to 0
	nFramesAdded = 0;
	BGZ = 0;

	// buffers haven't been allocated yet
	nPixels = 0;
	BGCounts = NULL;
	BGCenter = NULL;
	
}

BackgroundModel::BackgroundModel(){
	init();
}

BackgroundModel::BackgroundModel(uint32_t nPixels, int minNFramesReset){

	int i;

	init();

	this->nPixels = nPixels;
	this->minNFramesReset = minNFramesReset;

	// allocate
	BGCounts = new uint8_t*[nPixels];
	for(i = 0; i < nPixels; i++) {
		BGCounts[i] = new uint8_t[BGNBins];
		memset(BGCounts[i],0,BGNBins*sizeof(uint8_t));
	}
	BGCenter = new float[nPixels];
	memset(BGCenter,0,nPixels*sizeof(float));
}

BackgroundModel::~BackgroundModel(){
	
	if(BGCenter != NULL){
		delete [] BGCenter; BGCenter = NULL;
	}
	if(BGCounts != NULL){
		//for(int i = 0; i < nPixels; i++){
		//	if(BGCounts[i] != NULL){
		//		if((i%1000)==0) fprintf(stderr,"Deleting BGCounts[%d]\n",i);
		//		delete [] BGCounts[i]; BGCounts[i] = NULL;
		//	}
		//}
		delete [] BGCounts; BGCounts = NULL;
	}
	fprintf(stderr,"Deallocated bgcounts\n");
	nPixels = 0;
	BGZ = 0;
	nFramesAdded = 0;

}

bool BackgroundModel::addFrame(unsigned char * im, double timestamp){

	for(int i = 0; i < nPixels; i++){
		if(im[i] < 0 || im[i] >= BGNBins){
			// im out of bounds
			return false;
		}
		else{
			BGCounts[i][im[i]/BGBinSize]++;
		}
	}
	BGZ++;
	nFramesAdded++;
	return true;
}

bool BackgroundModel::updateModel(){

	int i, j;
	uint32_t countscurr;

	// compute the median
	uint8_t off = (uint8_t)(BGZ/2);
	for(i = 0; i < nPixels; i++){
		for(j = 0, countscurr = 0; j < BGNBins && countscurr <= off; j++){
			 countscurr+=(uint32_t)BGCounts[i][j];
		}
		BGCenter[i] = (float)((j-1)*BGBinSize) + BGHalfBin;
	}

	// lower the weight of the old counts
	//if(BGZ > MaxBGZ){
	if(nFramesAdded >= minNFramesReset){
		//float w = MaxBGZ / BGZ;
		for(i = 0; i < nPixels; i++){
			memset(BGCounts[i],0,BGNBins);
			//for(j = 0; j < BGNBins; j++){
				//BGCounts[i][j] = (uint8_t)(w*BGCounts[i][j]);
				//BGCounts[i][j] = BGCounts[i][j] >> 1; // divide by 2
			//}
		}
		//BGZ = MaxBGZ;
		BGZ = 0;
	}

	return true;
}

// ******************************** CompressedFrame **************************************

void CompressedFrame::init(){
	wWidth = 0;
	wHeight = 0;
	nPixels = 0;
	isFore = NULL;
	writeRowBuffer = NULL;
	writeColBuffer = NULL;
	writeWidthBuffer = NULL;
	writeHeightBuffer = NULL;
	writeDataBuffer = NULL;
	nWrites = NULL;
	timestamp = -1;
	ncc = 0;
	numFore = 0;
	isCompressed = false;
	numPxWritten = 0;
	frameNumber = 0;

	boxLength = 30; // length of foreground boxes to store
	boxArea = ((int)boxLength) * ((int)boxLength); // boxLength^2
	maxFracFgCompress = .25; // maximum fraction of pixels that can be foreground in order for us to compress
	maxNFgCompress = 0; // nPixels == 0 currently

}

CompressedFrame::CompressedFrame(){
	init();
}

CompressedFrame::CompressedFrame(unsigned short wWidth, unsigned short wHeight, uint32_t boxLength, double maxFracFgCompress){

	init();

	// frame size
	this->wWidth = wWidth;
	this->wHeight = wHeight;
	this->nPixels = ((int)wWidth) * ((int)wHeight);

	// compression parameters
	this->boxLength = boxLength;
	boxArea = ((int)boxLength) * ((int)boxLength); // boxLength^2
	this->maxFracFgCompress = maxFracFgCompress;
	maxNFgCompress = (int)((double)nPixels * maxFracFgCompress);

	// initialize backsub buffers
    isFore = new bool[nPixels]; // whether each pixel is foreground or not
	memset(isFore,0,nPixels*sizeof(bool));

	writeRowBuffer = new uint16_t[nPixels]; // ymins
	memset(writeRowBuffer,0,nPixels*sizeof(uint16_t));
	writeColBuffer = new uint16_t[nPixels]; // xmins
	memset(writeColBuffer,0,nPixels*sizeof(uint16_t));
	writeWidthBuffer = new uint16_t[nPixels]; // widths
	memset(writeWidthBuffer,0,nPixels*sizeof(uint16_t));
	writeHeightBuffer = new uint16_t[nPixels]; // heights
	memset(writeHeightBuffer,0,nPixels*sizeof(uint16_t));
	writeDataBuffer = new uint8_t[nPixels]; // image data
	memset(writeDataBuffer,0,nPixels*sizeof(uint8_t));
	nWrites = new uint16_t[nPixels]; // number of times we've written each pixel
	memset(nWrites,0,nPixels*sizeof(uint16_t));

}

CompressedFrame::~CompressedFrame(){

	if(isFore != NULL){
		delete[] isFore; isFore = NULL;
	}
	if(writeRowBuffer != NULL){
		delete[] writeRowBuffer; writeRowBuffer = NULL;
	}
	if(writeColBuffer != NULL){
		delete[] writeColBuffer; writeColBuffer = NULL;
	}
	if(writeWidthBuffer != NULL){
		delete[] writeWidthBuffer; writeWidthBuffer = NULL;
	}
	if(writeHeightBuffer != NULL){
		delete[] writeHeightBuffer; writeHeightBuffer = NULL;
	}
	if(writeDataBuffer != NULL){
		delete[] writeDataBuffer; writeDataBuffer = NULL;
	}
	if(nWrites != NULL){
		delete [] nWrites; nWrites = NULL;
	}
	nPixels = 0;
	ncc = 0;
	timestamp = -1;
	frameNumber = 0;

}

bool CompressedFrame::setData(uint8_t * im, double timestamp, uint64_t frameNumber, 
	uint8_t * BGLowerBound, uint8_t * BGUpperBound){

	// grab foreground boxes
	uint16_t r, c, r1, c1;
	int i;
	int j;
	int i1;
	numFore = 0;
	numPxWritten = -1;

	//int64_t filePosStart;
	//int64_t filePosEnd;
	//_int64 frameSizeBytes;
	//bool isCompressed;

	this->timestamp = timestamp;
	this->frameNumber = frameNumber;

	// background subtraction
	for(i = 0; i < nPixels; i++){
		isFore[i] = (im[i] < BGLowerBound[i]) || (im[i] > BGUpperBound[i]);
		if(isFore[i]) {
			numFore++;
		}
	}

	if(numFore > maxNFgCompress){
		// don't compress if too many foreground pixels
		writeRowBuffer[0] = 0;
		writeColBuffer[0] = 0;
		writeWidthBuffer[0] = wWidth;
		writeHeightBuffer[0] = wHeight;
		for(j = 0; j < nPixels; j++){
			writeDataBuffer[j] = im[j];
		}

		// each pixel is written -- for statistics
		for(j = 0; j < nPixels; j++){
			nWrites[j] = 1;
		}
		numPxWritten = nPixels;
		ncc = 1;
		isCompressed = false;
	}
	else{

		//for(i = 0; i < nPixels; i++){
		//	debugWasFore[i] = isFore[i];
		//}

		bool doStopEarly = 0;
		for(i1 = 0; i1 < nPixels; i1++) nWrites[i1] = 0;

		i = 0; j = 0; ncc = 0;
		for(r = 0; r < wHeight; r++){
			for(c = 0; c < wWidth; c++, i++){

				// start a new box if this pixel is foreground
				if(!isFore[i]) continue;

				// store everything in box with corner at (r,c)
				writeRowBuffer[ncc] = r;
				writeColBuffer[ncc] = c;
				writeWidthBuffer[ncc] = MIN((unsigned short)boxLength,wWidth-c);
				writeHeightBuffer[ncc] = MIN((unsigned short)boxLength,wHeight-r);

				// loop through pixels to store
				for(r1 = r; r1 < r + writeHeightBuffer[ncc]; r1++){

					// check if we've already written something in this column
					doStopEarly = 0;
					for(c1 = c, i1 = r1*wWidth+c; c1 < c + writeWidthBuffer[ncc]; c1++, i1++){
						if(nWrites[i1] > 0){
							doStopEarly = 1;
							break;
						}
					}

					if(doStopEarly){
						if(r1 == r){
							// if this is the first row, then shorten the width and write as usual
							writeWidthBuffer[ncc] = c1 - c;
						}
						else{
							// otherwise, shorten the height, and don't write any of this row
							writeHeightBuffer[ncc] = r1 - r;
							break;
						}
					}

					for(c1 = c, i1 = r1*wWidth+c; c1 < c + writeWidthBuffer[ncc]; c1++, i1++){
						nWrites[i1]++;
						writeDataBuffer[j] = im[i1];
						isFore[i1] = 0;
						j++;
					}
				}

				ncc++;
			}
		}
		numPxWritten = j;
		isCompressed = true;
		//int nForeMissed = 0;
		//for(i1 = 0; i1 < nPixels; i1++){
		//	if(debugWasFore[i1] && nWrites[i1] == 0) nForeMissed++;
		//}
		//if(logger && nForeMissed > 0) logger->log(UFMF_DEBUG_3,"nForeMissed = %d\n",nForeMissed);
	}

	return true;

}

// ************************* ufmfWriter **************************

// ***** public API *****

// constructors

// common code for both the empty constructor and the parameter-filled constructor
void ufmfWriter::init(){

	// *** output ufmf state ***
	pFile = NULL;
	logger = NULL;
	indexLocation = 0;
	indexPtrLocation = 0;

	// *** writing state ***
	isWriting = false;
	nGrabbed = 0;
	nWritten = 0;
	nBGKeyFramesWritten = 0;

	// *** threading/buffering state ***
	uncompressedFrames = NULL;
	compressedFrames = NULL;
	threadTimestamps = NULL;
	nUncompressedFramesBuffered = 0;
	nCompressedFramesBuffered = 0;
	readyToWrite = NULL;

	_compressionThreads = NULL;
	compressionThreadReadySignals = NULL;
	compressionThreadStartSignals = NULL;
	compressionThreadDoneSignals = NULL;
	threadCount = 0;
	threadFrameNumbers = NULL;

	// *** background subtraction state ***
	bg = NULL;
	minFrameBGModel0 = 0;
	minFrameBGModel1 = 0;
	BGLowerBound0 = NULL;
	BGUpperBound0 = NULL;
	BGCenter0 = NULL;
	keyframeTimestamp0 = -1;
	BGLowerBound1 = NULL;
	BGUpperBound1 = NULL;
	BGCenter1 = NULL;
	keyframeTimestamp1 = -1;
	lastBGUpdateTime = -1;
	lastBGKeyFrameTime = -1;

	// *** logging state ***
	stats = NULL;
	logFID = stderr;

	// *** threading parameter defaults ***
	nThreads = 4;

	// *** video parameter defaults ****
	strcpy(fileName,"");
	wWidth = 0;
	wHeight = 0;
	nPixels = 0;
	// hardcode color format to grayscale
	strcpy(colorCoding,"MONO8");
	colorCodingLength = 5;

	// *** compression parameters ***

	// * background subtraction parameters *

	//hard code parameters for now
	MaxBGNFrames = 100; // approximate number of frames used in background computation
	// the last NFramesPerKeyFrame = BGKeyFramePeriod / BGUpdatePeriod should have weight
	// so we should reweight so that the total sum is MaxBGNFrames - NBGUpdatesPerKeyFrame
	BGUpdatePeriod = 1; // seconds between updates to the background model
	BGKeyFramePeriod = 100; // seconds between background keyframes
	backSubThresh = 10; // threshold for storing foreground pixels
	nFramesInit = 100; // for the first nFramesInit, we will always update the background model
	BGKeyFramePeriodInitLength = 0;
	nBGUpdatesPerKeyFrame = (int)floor(BGKeyFramePeriod / BGUpdatePeriod);
	float NBGUpdatesPerKeyFrame = (float)(BGKeyFramePeriod / BGUpdatePeriod);
	MaxBGZ = MAX(0.0,(float)MaxBGNFrames - NBGUpdatesPerKeyFrame);

	// * ufmf parameters *
	isFixedSize = 0; // patches are not of a fixed size
	boxLength = 30; // length of foreground boxes to store
	maxFracFgCompress = .25; // maximum fraction of pixels that can be foreground in order for us to compress

   // *** statistics parameters ***

	strcpy(statFileName,"");
	printStats = true;
	statStreamPrintFreq = 1;
	statPrintFrameErrors = true;
	statPrintTimings = true;
	statComputeFrameErrorFreq = 1;

	// *** logging parameters ***
	UFMFDEBUGLEVEL = UFMF_DEBUG_3;

}

// empty constructor:
// initializes values to defaults
ufmfWriter::ufmfWriter(){
	init();
}

void ufmfWriter::init(const char * fileName, uint32_t pWidth, uint32_t pHeight, 
	int MaxBGNFrames, double BGUpdatePeriod, double BGKeyFramePeriod, uint32_t boxLength,
	double backSubThresh, uint32_t nFramesInit, double* BGKeyFramePeriodInit, int BGKeyFramePeriodInitLength, double maxFracFgCompress, 
	const char *statFileName, bool printStats, int statStreamPrintFreq, bool statPrintFrameErrors, bool statPrintTimings, 
	int statComputeFrameErrorFreq, uint32_t nThreads){

    int i;

		// ***** parameters *****

		// *** threading parameters ***
		this->nThreads = nThreads;

		// *** video parameters ***
		strcpy(this->fileName, fileName);
		//capture height/width
		this->wWidth = pWidth;
		this->wHeight = pHeight;
		nPixels = (unsigned int)wWidth*(unsigned int)wHeight;

		// *** compression parameters ***

		// * background subtraction parameters *
		this->MaxBGNFrames = MaxBGNFrames;
		this->BGUpdatePeriod = BGUpdatePeriod;
		this->BGKeyFramePeriod = BGKeyFramePeriod;
		this->boxLength = boxLength;
		this->backSubThresh = (float)backSubThresh;
		this->nFramesInit = nFramesInit;
		for(int i = 0; i < BGKeyFramePeriodInitLength; i++){
			this->BGKeyFramePeriodInit[i] = BGKeyFramePeriodInit[i];
		}
		this->BGKeyFramePeriodInitLength = BGKeyFramePeriodInitLength;
		float NBGUpdatesPerKeyFrame = (float)(BGKeyFramePeriod / BGUpdatePeriod);
		nBGUpdatesPerKeyFrame = (int)floor(BGKeyFramePeriod / BGUpdatePeriod);
		MaxBGZ = MAX(0.0,(float)MaxBGNFrames - NBGUpdatesPerKeyFrame);

		// * ufmf parameters *
		this->maxFracFgCompress = maxFracFgCompress;

		// *** statistics parameters ***
		if(statFileName == NULL){
			strcpy(this->statFileName,"");
		}
		else{
			strcpy(this->statFileName,statFileName);
		}
		this->printStats = printStats;
		this->statStreamPrintFreq = statStreamPrintFreq;
		this->statPrintFrameErrors = statPrintFrameErrors;
		this->statPrintTimings = statPrintTimings;
		this->statComputeFrameErrorFreq = statComputeFrameErrorFreq;

		// ***** allocate stuff *****

		// *** threading/buffering state ***
		uncompressedFrames = new unsigned char*[nThreads];
		for(i = 0; i < (int)nThreads; i++){
			uncompressedFrames[i] = new unsigned char[nPixels];
			memset(uncompressedFrames[i],0,nPixels*sizeof(char));
		}
		compressedFrames = new CompressedFrame*[nThreads];
		for(i = 0; i < (int)nThreads; i++){
			compressedFrames[i] = new CompressedFrame(wWidth,wHeight,boxLength,maxFracFgCompress);
		}
		threadTimestamps = new double[nThreads];
		memset(threadTimestamps,0,nThreads*sizeof(double));
		threadFrameNumbers = new uint64_t[nThreads];
		memset(threadFrameNumbers,0,nThreads*sizeof(uint64_t));

		readyToWrite = new int[nThreads];
		memset(readyToWrite,0,nThreads*sizeof(int));

		// allocate compression thread stuff
    _compressionThreads = [NSMutableArray new];
    compressionThreadReadySignals = [NSMutableArray new];
    compressionThreadStartSignals = [NSMutableArray new];
    compressionThreadDoneSignals = [NSMutableArray new];

		//// *** background subtraction state ***
		bg = new BackgroundModel(nPixels,nBGUpdatesPerKeyFrame);
		BGLowerBound0 = new uint8_t[nPixels]; // per-pixel lower bound on background
		memset(BGLowerBound0,0,nPixels*sizeof(uint8_t));
		BGUpperBound0 = new uint8_t[nPixels]; // per-pixel upper bound on background
		memset(BGUpperBound0,0,nPixels*sizeof(uint8_t));
		if(printStats){
			BGCenter0 = new float[nPixels]; 
			memset(BGCenter0,0,nPixels*sizeof(float));
		}

		BGLowerBound1 = new uint8_t[nPixels]; // per-pixel lower bound on background
		memset(BGLowerBound1,0,nPixels*sizeof(uint8_t));
		BGUpperBound1 = new uint8_t[nPixels]; // per-pixel upper bound on background
		memset(BGUpperBound1,0,nPixels*sizeof(uint8_t));
		if(printStats){
			BGCenter1 = new float[nPixels]; 
			memset(BGCenter1,0,nPixels*sizeof(float));
		}

		// *** logging state ***
		if(printStats) {
			if(statFileName && strcmp(statFileName,""))
				stats = new ufmfWriterStats(statFileName, wWidth, wHeight, statStreamPrintFreq, statPrintFrameErrors, statPrintTimings, statComputeFrameErrorFreq, true);
			else
				stats = new ufmfWriterStats(logger, wWidth, wHeight, statStreamPrintFreq, statPrintFrameErrors, statPrintTimings, statComputeFrameErrorFreq, true);
		}

}


// parameters:
// [video parameters:]
// fileName: name of video to write to
// pWidth: width of frame
// pHeight: height of frame
// [acquisition parameters:]
// MaxBGNFrames: approximate number of frames used in background computation
// BGUpdatePeriod: seconds between updates to the background model
// BGKeyFramePeriod: seconds between background keyframes
// boxLength: length of foreground boxes to store
// backSubThresh: threshold for storing foreground pixels
// nFramesInit: for the first nFramesInit, we will always update the background model
// maxFracFgCompress: maximum fraction of pixels that can be foreground in order for us to try to compress the frame
// [compression stats parameters:]
// statFileName: name of file to write compression statistics to. If NULL, then statistics are combined into debug file
// printStats: whether to print compression statistics
// statStreamPrintFreq: number of frames between outputting per-frame compression statistics
// statPrintFrameErrors: whether to compute and print statistics of compression error. Currently, box-averaged and per-pixel errors are either both
// computed or both not computed. 
// statPrintTimings: whether to print information about the time each part of the computation takes. 
// nThreads: number of threads to allocate to compress frames simultaneously

ufmfWriter::ufmfWriter(const char * fileName, uint32_t pWidth, uint32_t pHeight, FILE * logFID, 
	int MaxBGNFrames, double BGUpdatePeriod, double BGKeyFramePeriod, uint32_t boxLength,
	double backSubThresh, uint32_t nFramesInit, double* BGKeyFramePeriodInit, int BGKeyFramePeriodInitLength, double maxFracFgCompress, 
	const char *statFileName, bool printStats, int statStreamPrintFreq, bool statPrintFrameErrors, bool statPrintTimings, 
	int statComputeFrameErrorFreq, uint32_t nThreads){

	init();
	// *** logging state ***
	this->logFID = logFID;
	logger = new ufmfLogger(logFID,UFMFDEBUGLEVEL);

	init(fileName, pWidth, pHeight, MaxBGNFrames, BGUpdatePeriod, BGKeyFramePeriod,
		boxLength, backSubThresh, nFramesInit, BGKeyFramePeriodInit, BGKeyFramePeriodInitLength, 
		maxFracFgCompress, statFileName, printStats, statStreamPrintFreq, statPrintFrameErrors, 
		statPrintTimings, statComputeFrameErrorFreq, nThreads);

 }

// parameter file constructor
ufmfWriter::ufmfWriter(const char * fileName, uint32_t pWidth, uint32_t pHeight, FILE* logFID, const char * paramsFile){
	// initialize state, set default parameters
	init();
	// *** logging state ***
	this->logFID = logFID;
	logger = new ufmfLogger(logFID,UFMFDEBUGLEVEL);
	readParamsFile(paramsFile);
	init(fileName, pWidth, pHeight, MaxBGNFrames, BGUpdatePeriod, BGKeyFramePeriod,
		boxLength, backSubThresh, nFramesInit, BGKeyFramePeriodInit, BGKeyFramePeriodInitLength, 
		maxFracFgCompress, statFileName, printStats, statStreamPrintFreq, statPrintFrameErrors, 
		statPrintTimings, statComputeFrameErrorFreq, nThreads);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wwrite-strings"

 // destructor
 ufmfWriter::~ufmfWriter(){

	 logger->log(UFMF_DEBUG_3,"Destructor\n");

	 // stop writing if writing

	 // SHOULD WE LOCK FIRST?
	 if(isWriting){
		stopWrite();
		logger->log(UFMF_DEBUG_3,"stopped writing in destructor\n");
	 }

	 // deallocate stuff

	 // buffers for compressed, uncompressed frames
	 deallocateBuffers();

	 logger->log(UFMF_DEBUG_3,"Deallocated buffers\n");

	 // background model
	 deallocateBGModel();

	 logger->log(UFMF_DEBUG_3,"Deallocated bg model\n");

	 // threading stuff
	 deallocateThreadStuff();

	 logger->log(UFMF_DEBUG_3,"Deallocated thread stuff\n");

	 nGrabbed = 0;
	 nWritten = 0;
	 isWriting = false;

	 if(stats){
		delete stats;
		stats = NULL;
		logger->log(UFMF_DEBUG_3,"deleted stats in destructor\n");
	}

	 logger->log(UFMF_DEBUG_3,"done with destructor\n");

}

bool ufmfWriter::startWrite(){

	NSTimeInterval stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	int i;

	nGrabbed = 0;
	nWritten = 0;
	nBGKeyFramesWritten = 0;
	lastBGUpdateTime = -1;
	lastBGKeyFrameTime = -1;

	logger->log(UFMF_DEBUG_3,"starting to write\n");

	// open File
	pFile = fopen(fileName,"wb");
	if(pFile == NULL){
		logger->log(UFMF_ERROR,"Error opening file %s for writing\n",fileName);
		return false;
	}

	// write header
	if(!writeHeader()){
		logger->log(UFMF_ERROR,"Error writing header\n");
		return false;
	}

	// initialize semaphores
	lock = [NSLock new];

	// compression semaphores
	for(i = 0; i < (int)nThreads; i++){

		// initialize that compression threads are not ready for processing
		[compressionThreadReadySignals addObject:[NSLock new]];

		// initialize not ready to start compression threads
		[compressionThreadStartSignals addObject:[NSLock new]];

		// initialize value to 0 to signify not finished compressing
		[compressionThreadDoneSignals addObject:[NSLock new]];
	}

	// writing thread semaphore
	writeThreadReadySignal = [NSLock new];

	// bg semaphore
	keyFrameWritten = [NSLock new];

	isWriting = true;

	// start compression threads
	for(i = 0; i < (int)nThreads; i++){
		//_compressionThreads[i] = CreateThread(NULL,0,compressionThread,this,0,&_compressionThreadIDs[i]);
        [_compressionThreads addObject:[NSOperationQueue new]];
        [_compressionThreads[i] addOperation:<#(NSOperation *)#>
		if(WaitForSingleObject(compressionThreadReadySignals[i], MAXWAITTIMEMS) != WAIT_OBJECT_0) {
			logger->log(UFMF_ERROR, "Error starting compression thread %d\n",i); 
			return false; 
		}
		ReleaseSemaphore(compressionThreadReadySignals[i],1,NULL);
	}

	// start write thread
	_writeThread = CreateThread(NULL,0,writeThread,this,0,&_writeThreadID);
	if ( _writeThread == NULL ){ 
		return false; 
	}
	if(WaitForSingleObject(writeThreadReadySignal, MAXWAITTIMEMS) != WAIT_OBJECT_0) { 
		logger->log(UFMF_ERROR,"Error Starting Write Thread\n"); 
		return false; 
	}

	if(stats){
		stats->updateTimings(UTT_START_WRITING,stats_t0);
	}

	return true;
}

uint64_t ufmfWriter::stopWrite(){

	ULARGE_INTEGER stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	logger->log(UFMF_DEBUG_3,"Stopping writing\n");

	// no need to lock since stopThreads is the only thing that will be writing to isWriting
	if(!isWriting){
		logger->log(UFMF_DEBUG_3,"Stop writing called while not writing, nothing to do.\n");

		return 0;
	}

	// stop all the writing and compressing threads
	stopThreads(true);

	// finish writing the movie -- write the indexes, close the file, etc.
	if(!finishWriting()){
		logger->log(UFMF_ERROR,"Error finishing writing the video file\n");
		return 0;
	}

	logger->log(UFMF_DEBUG_3,"Stopped all threads, wrote footer, closed video.\n");

	if(stats){
		stats->updateTimings(UTT_STOP_WRITE,stats_t0);
		stats->printSummary();
		stats->flushNow();
	}

	return nWritten;
}

// add a frame to the processing queue
bool ufmfWriter::addFrame(unsigned char * frame, double timestamp, uint64_t nFramesDroppedExternal, uint64_t nFramesBufferedExternal){

	int threadIndex;
	uint64_t frameNumber;
	ULARGE_INTEGER stats_t0, stats_t1;

	if(stats){
		stats_t1 = ufmfWriterStats::getTime();
	}

	nGrabbed++;
	frameNumber = nGrabbed;

	logger->log(UFMF_DEBUG_7,"Adding frame %llu\n",frameNumber);

	// update background counts if necessary
	if(!addToBGModel(frame,timestamp,frameNumber)){
		logger->log(UFMF_ERROR,"Error adding frame to background model\n");
		return false;
	}

	// reset background model if necessary, signal to write key frame
	if(!updateBGModel(frame,timestamp,frameNumber)){
		logger->log(UFMF_ERROR,"Error computing new background model\n");
		return false;
	}

	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	// wait for a compression thread to be ready
	threadIndex = (int)WaitForMultipleObjects((DWORD)nThreads,compressionThreadReadySignals,false,MAXWAITTIMEMS);
	if(threadIndex < 0 || threadIndex >= (int)nThreads){
		logger->log(UFMF_ERROR,"Error waiting for a thread to be ready when adding a frame: %x\n",threadIndex+WAIT_OBJECT_0);
		return false;
	}

	if(stats){
		stats_t0 = stats->updateTimings(UTT_WAIT_FOR_COMPRESS_THREAD,stats_t0);
	}

	// store this frame for this thread
	threadFrameNumbers[threadIndex] = frameNumber;
	logger->log(UFMF_DEBUG_7,"Adding frame %d to thread %d\n",frameNumber,threadIndex);
	Lock();
	nUncompressedFramesBuffered++;
	this->nFramesDroppedExternal = nFramesDroppedExternal;
	this->nFramesBufferedExternal = nFramesBufferedExternal;
	Unlock();

	// copy over the data
	memcpy(uncompressedFrames[threadIndex],frame,nPixels*sizeof(unsigned char));
	threadTimestamps[threadIndex] = timestamp;

	// signal that the compression thread can start
	logger->log(UFMF_DEBUG_7,"Signaling that thread %d can start compressing frame %llu\n",threadIndex,frameNumber);
	ReleaseSemaphore(compressionThreadStartSignals[threadIndex],1,NULL);

	if(stats){
		stats->updateTimings(UTT_ADD_FRAME,stats_t1);
	}

	return true;
}

// set video file name, width, height
// todo: resize buffers, background model if already allocated
void ufmfWriter::setVideoParams(char * fileName, int wWidth, int wHeight){
	strcpy(this->fileName, fileName);
	this->wWidth = wWidth;
	this->wHeight = wHeight;
	this->nPixels = wWidth * wHeight;

}

// parameters:
// [compression parameters:]
// MaxBGNFrames: approximate number of frames used in background computation
// BGUpdatePeriod: seconds between updates to the background model
// BGKeyFramePeriod: seconds between background keyframes
// boxLength: length of foreground boxes to store
// backSubThresh: threshold for storing foreground pixels
// nFramesInit: for the first nFramesInit, we will always update the background model
// maxFracFgCompress: maximum fraction of pixels that can be foreground in order for us to try to compress the frame
bool ufmfWriter::readParamsFile(const char * paramsFile){

	FILE * fp = fopen(paramsFile,"r");
	bool failure = false;
	const size_t maxsz = 1000;
	char line[maxsz];
	char * paramName;
	char * paramValueStr;
	double paramValue;
	char * s;

	if(logger) logger->log(UFMF_ERROR,"Reading parameters from file %s\n",paramsFile);

	if(fp == NULL){
		if(logger == NULL)
			fprintf(stderr,"Error opening parameter file %s for reading.\n",paramsFile);
		else
			logger->log(UFMF_ERROR,"Error opening parameter file %s for reading.\n",paramsFile);
		return failure;
	}

	while(true){
		if(fgets(line,maxsz,fp) == NULL) break;

		paramValueStr = strchr(line,'=');

		if(paramValueStr == NULL){
			continue;
		}

        paramValueStr[0] = '\0';
        paramValueStr++;    
    
        paramName = strtrim(line);
        paramValueStr = strtrim(paramValueStr);

		// comment
		if(strlen(paramName) > 0 && paramName[0] == '#')
			continue;
        
        if(strlen(paramName) == 0 || strlen(paramValueStr) == 0){
			if(logger) 
				logger->log(UFMF_WARNING,"could not parse line %s\n",line);
			else
				fprintf(stderr,"could not parse line %s\n",line);
			continue;
		}

		paramValue = atof(paramValueStr);
		if(logger)
			logger->log(UFMF_DEBUG_3,"paramName = %s, paramValue = %lf\n",paramName,paramValue);

		// maximum fraction of pixels that can be foreground to try compressing frame
		if(strcmp(paramName,"UFMFNBuffers") == 0){
			//this->nBuffers = (uint32_t)paramValue;
		}
		else if(strcmp(paramName,"UFMFMaxFracFgCompress") == 0){
			this->maxFracFgCompress = paramValue;
		}
		// number of frames the background model should be based on 
		else if(strcmp(paramName,"UFMFMaxBGNFrames") == 0){
			this->MaxBGNFrames = (int)paramValue;
		}
		// number of seconds between updates to the background model
		else if(strcmp(paramName,"UFMFBGUpdatePeriod") == 0){
			this->BGUpdatePeriod = paramValue;
		}
		// number of seconds between spitting out a new background model
		else if(strcmp(paramName,"UFMFBGKeyFramePeriod") == 0){
			this->BGKeyFramePeriod = paramValue;
		}
		// max length of box stored during compression
		else if(strcmp(paramName,"UFMFMaxBoxLength") == 0){
			this->boxLength = (int)paramValue;
		}
		// threshold for background subtraction
		else if(strcmp(paramName,"UFMFBackSubThresh") == 0){
			this->backSubThresh = (float)paramValue;
		}
		// first nFramesInit will be output raw
		else if(strcmp(paramName,"UFMFNFramesInit") == 0){
			this->nFramesInit = (int)paramValue;
		}
		else if(strcmp(paramName,"UFMFBGKeyFramePeriodInit") == 0){
			s = paramValueStr;
			if(logger) logger->log(UFMF_DEBUG_7,"UFMFBGKeyFramePeriodInit: ");
			for(s = strtok(s,","), BGKeyFramePeriodInitLength = 0; s != NULL; s = strtok(NULL,","), BGKeyFramePeriodInitLength++){
				sscanf(s,"%lf",&this->BGKeyFramePeriodInit[BGKeyFramePeriodInitLength]);
				if(logger) logger->log(UFMF_DEBUG_7,"%lf,",this->BGKeyFramePeriodInit[BGKeyFramePeriodInitLength]);
			}
			if(logger) logger->log(UFMF_DEBUG_7," length = %d\n",BGKeyFramePeriodInitLength);
		}
		// Whether to compute UFMF diagnostics
		else if(strcmp(paramName,"UFMFPrintStats") == 0){
			this->printStats = paramValue != 0;
		}
		// number of frames between outputting per-frame compression statistics: 0 means don't print, 1 means every frame
		else if(strcmp(paramName,"UFMFStatStreamPrintFreq") == 0){
			this->statStreamPrintFreq = (int)paramValue;
		}
		// number of frames between computing statistics of compression error. 0 means don't compute, 1 means every frame
		else if(strcmp(paramName,"UFMFStatComputeFrameErrorFreq") == 0){
			this->statComputeFrameErrorFreq = (int)paramValue;	
		}
		// whether to print information about the time each part of the computation takes
		else if(strcmp(paramName,"UFMFStatPrintTimings") == 0){
			this->statPrintTimings = paramValue != 0;
		}
		else if(strcmp(paramName,"UFMFStatFileName") == 0){
			strcpy(this->statFileName,paramValueStr);
		}
		else if(strcmp(paramName,"UFMFStatPrintFrameErrors") == 0){
			this->statPrintFrameErrors = paramValue != 0;
		}
		else if(strcmp(paramName,"UFMFNThreads") == 0){
			this->nThreads = (uint32_t)paramValue;
		}
		else{
			if(logger) logger->log(UFMF_WARNING,"Unknown parameter %s with value %f skipped\n",paramName,paramValue);
			else fprintf(stderr,"Unknown parameter %s with value %f skipped\n",paramName,paramValue);
		}


	}

	fclose(fp);

	return !failure;

}

// read stats params from a file
void ufmfWriter::setStatsParams(const char * statsName){
	strcpy(this->statFileName,statsName);
	// TODO: update stats parameters
}

// ***** private helper functions *****

// *** writing tools ***

// write a frame
int8_t ufmfWriter::writeFrame(CompressedFrame * im){

	ULARGE_INTEGER stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	int i;
	_int64 filePosStart;
	_int64 filePosEnd;
	_int64 frameSizeBytes;
	//bool isCompressed;

	logger->log(UFMF_DEBUG_7,"writing compressed frame %d\n",im->frameNumber);

	// location of this frame
	filePosStart = _ftelli64(pFile);

	// add current location to index
	index.push_back(filePosStart);
	index_timestamp.push_back(im->timestamp);

	// write chunk type: 1
	fwrite(&FRAMECHUNK,1,1,pFile);
	// write timestamp: 8
	fwrite(&im->timestamp,8,1,pFile);
	// number of connected components
	fwrite(&im->ncc,4,1,pFile);

	// write each box
	i = 0;
	int area = 0;
	for(unsigned int cc = 0; cc < im->ncc; cc++){
		area = im->writeWidthBuffer[cc]*im->writeHeightBuffer[cc];
		fwrite(&im->writeColBuffer[cc],2,1,pFile);
		fwrite(&im->writeRowBuffer[cc],2,1,pFile);
		fwrite(&im->writeWidthBuffer[cc],2,1,pFile);
		fwrite(&im->writeHeightBuffer[cc],2,1,pFile);
		fwrite(&im->writeDataBuffer[i],1,area,pFile);
		i += area;
	}

	filePosEnd = _ftelli64(pFile);
	frameSizeBytes = filePosEnd - filePosStart;

	//if(logger) logger->log(UFMF_DEBUG_5, "timestamp = %f\n",timestamp);

	//if(stats) {
	//	stats->updateTimings(UTT_COMPUTE_STATS);
	//	stats->update(index, index_timestamp, frameSizeBytes, isCompressed, im->numFore, im->numPxWritten, im->ncc, nUncompressedFramesBuffered, 0, im->nWrites, nPixels, uncompressedFrame, BGCenter, UFMF_DEBUG_3);
	//}

	if(stats){
		stats->updateTimings(UTT_WRITE_FRAME,stats_t0);
	}

	return frameSizeBytes;
}

// write the video header
bool ufmfWriter::writeHeader(){

	ULARGE_INTEGER stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	logger->log(UFMF_DEBUG_7,"Writing video header\n");

	// location of index
	indexLocation = 0;

	uint32_t ufmfVersion = 4; // UFMF version 4

	uint64_t bytesPerChunk = (uint64_t)wHeight*(uint64_t)wWidth+(uint64_t)8;

	// write "ufmf"
	const char ufmfString[] = "ufmf";
	fwrite(ufmfString,1,4,pFile); 
	// write version
	fwrite(&ufmfVersion,4,1,pFile);
	// this is where we write the index location
	indexPtrLocation = ftell(pFile);
	// write index location. 0 for now
	fwrite(&indexLocation,8,1,pFile);

	// max width, height: 2, 2
	if(isFixedSize){
		fwrite(&boxLength,2,1,pFile);
		fwrite(&boxLength,2,1,pFile);
	}
	else{
		fwrite(&wWidth,2,1,pFile);
		fwrite(&wHeight,2,1,pFile);
	}

	// whether it is fixed size patches: 1
	fwrite(&isFixedSize,1,1,pFile);

	// raw coding string length: 1
	fwrite(&colorCodingLength,1,1,pFile);
	// coding: length(coding)
	fwrite(colorCoding,1,colorCodingLength,pFile);

	if(stats){
		stats->updateTimings(UTT_WRITE_HEADER,stats_t0);
	}

	return true;

}

// write the indexes, pointers, close the movie
bool ufmfWriter::finishWriting(){

	ULARGE_INTEGER stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	logger->log(UFMF_DEBUG_3, "writing video footer and closing %s\n", fileName);

	// write the index at the end of the file
	_fseeki64(pFile,0,SEEK_END);

	// write index chunk identifier
	fwrite(&INDEX_DICT_CHUNK,1,1,pFile);

	// save location of index
	indexLocation = _ftelli64(pFile);

	// write index dictionary

	// write a 'd' for dict
	char d = 'd';
	fwrite(&d,1,1,pFile);

	// write the number of keys
	uint8_t nkeys = 2;
	fwrite(&nkeys,1,1,pFile);

		// write index->frame

		const char frameString[] = "frame";
		uint16_t frameStringLength = sizeof(frameString) - 1;

		// write the length of the key
		fwrite(&frameStringLength,2,1,pFile);
		// write the key
		fwrite(frameString,1,frameStringLength,pFile);

		// write a 'd' for dict
		fwrite(&d,1,1,pFile);

		// write the number of keys
		nkeys = 2;
		fwrite(&nkeys,1,1,pFile);

			// write index->frame->loc
			const char locString[] = "loc";
			uint16_t locStringLength = sizeof(locString) - 1;

			// write the length of the key
			fwrite(&locStringLength,2,1,pFile);
			// write the key
			fwrite(locString,1,locStringLength,pFile);

			// write a for array
			char a = 'a';
			fwrite(&a,1,1,pFile);

			// write the data type
			char datatype = 'q';
			fwrite(&datatype,1,1,pFile);

			// write the number of bytes
			uint32_t nbytes = 8*index.size();
			fwrite(&nbytes,4,1,pFile);

			// write the array
			uint64_t loc;
			for (unsigned int i = 0 ; i < index.size(); i++ ){
				loc = index[i];
				fwrite(&loc,8,1,pFile);
			}

			// end of index->frame->loc

			// write index->frame->timestamp
			const char timestampString[] = "timestamp";
			uint16_t timestampStringLength = sizeof(timestampString) - 1;

			// write the length of the key
			fwrite(&timestampStringLength,2,1,pFile);
			// write the key
			fwrite(timestampString,1,timestampStringLength,pFile);

			// write a for array
			fwrite(&a,1,1,pFile);

			// write the data type
			datatype = 'd';
			fwrite(&datatype,1,1,pFile);

			// write the number of bytes
			nbytes = 8*index.size();
			fwrite(&nbytes,4,1,pFile);

			// write the array
			double timestamp;
			for (unsigned int i = 0 ; i < index.size(); i++ ){
				timestamp = index_timestamp[i];
				fwrite(&timestamp,8,1,pFile);
			}

			// end index->frame->timestamp

		// end index->frame

		// write index->keyframe
		const char keyframeString[] = "keyframe";
		uint16_t keyframeStringLength = sizeof(keyframeString) - 1;

		// write the length of the key
		fwrite(&keyframeStringLength,2,1,pFile);
		// write the key
		fwrite(keyframeString,1,keyframeStringLength,pFile);
	
		// write a 'd' for dict
		fwrite(&d,1,1,pFile);

		// write the number of keys
		nkeys = 1;
		fwrite(&nkeys,1,1,pFile);

			// write index->keyframe->mean
			const char meanString[] = "mean";
			uint16_t meanStringLength = sizeof(meanString) - 1;

			// write the length of the key
			fwrite(&meanStringLength,2,1,pFile);
			// write the key
			fwrite(meanString,1,meanStringLength,pFile);

			// write a 'd' for dict
			fwrite(&d,1,1,pFile);

			// write the number of keys
			nkeys = 2;
			fwrite(&nkeys,1,1,pFile);

				// write index->keyframe->mean->loc

				// write the length of the key
				fwrite(&locStringLength,2,1,pFile);
				// write the key
				fwrite(locString,1,locStringLength,pFile);

				// write a for array
				fwrite(&a,1,1,pFile);

				// write the data type
				datatype = 'q';
				fwrite(&datatype,1,1,pFile);
	
				// write the number of bytes
				nbytes = 8*meanindex.size();
				fwrite(&nbytes,4,1,pFile);

				// write the array
				for (unsigned int i = 0 ; i < meanindex.size(); i++ ){
					loc = meanindex[i];
					fwrite(&loc,8,1,pFile);
				}

				// end of index->frame->loc

				// write index->keyframe->mean->timestamp

				// write the length of the key
				fwrite(&timestampStringLength,2,1,pFile);
				// write the key
				fwrite(timestampString,1,timestampStringLength,pFile);

				// write a for array
				fwrite(&a,1,1,pFile);

				// write the data type
				datatype = 'd';
				fwrite(&datatype,1,1,pFile);
	
				// write the number of bytes
				nbytes = 8*meanindex.size();
				fwrite(&nbytes,4,1,pFile);

				// write the array
				for (unsigned int i = 0 ; i < meanindex_timestamp.size(); i++ ){
					timestamp = meanindex_timestamp[i];
					fwrite(&timestamp,8,1,pFile);
				}

				// end index->keyframe->mean->timestamp

			// end index->keyframe->mean

		// end index->keyframe

	// end index

	// write the index location
	_fseeki64(pFile,indexPtrLocation,SEEK_SET);
	fwrite(&indexLocation,8,1,pFile);

	//Close the file
	fclose(pFile);
	pFile = NULL;

	if(stats){
		stats->updateTimings(UTT_WRITE_FOOTER,stats_t0);
	}

	meanindex.clear();
	meanindex_timestamp.clear();
	index.clear();
	index_timestamp.clear();

	return true;
}

bool ufmfWriter::writeBGKeyFrame(float* BGCenter,double keyframeTimestamp){

	ULARGE_INTEGER stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	int i, j;
	uint32_t countscurr;

	logger->log(UFMF_DEBUG_7,"writing keyframe\n");

	// add to keyframe index
	meanindex.push_back(_ftelli64(pFile));
	meanindex_timestamp.push_back(keyframeTimestamp);

	// write keyframe chunk identifier
	fwrite(&KEYFRAMECHUNK,1,1,pFile);

	// write the keyframe type
	const char keyFrameType[] = "mean";
	uint8_t keyFrameTypeLength = sizeof(keyFrameType) - 1;
	fwrite(&keyFrameTypeLength,1,1,pFile);
	fwrite(keyFrameType,1,keyFrameTypeLength,pFile);

	// write the data type
	const char dataType = 'f';
	fwrite(&dataType,1,1,pFile);

	// width, height
	fwrite(&wWidth,2,1,pFile);
	fwrite(&wHeight,2,1,pFile);

	// timestamp
	fwrite(&keyframeTimestamp,8,1,pFile);

	Lock();

	// write the frame
	fwrite(BGCenter,4,nPixels,pFile);

	nBGKeyFramesWritten++;
	Unlock();

	if(stats){
		stats->updateTimings(UTT_WRITE_KEYFRAME,stats_t0);
	}

	return true;
}

// *** compression tools ***

bool ufmfWriter::addToBGModel(uint8_t * frame, double timestamp, uint64_t frameNumber){

	double dt = timestamp - lastBGUpdateTime;

	if((dt < BGUpdatePeriod) && (frameNumber >= nFramesInit)) {
		return true;
	}

	ULARGE_INTEGER stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	logger->log(UFMF_DEBUG_7,"Adding frame %d to background model counts\n",frameNumber);

	bg->addFrame(frame,timestamp);
	// store update time
	lastBGUpdateTime = timestamp;

	if(stats){
		stats->updateTimings(UTT_UPDATE_BACKGROUND,stats_t0);
	}

	return true;
}

bool ufmfWriter::updateBGModel(uint8_t * frame, double timestamp, uint64_t frameNumber){

	// if the background hasn't been updated, no need to write a new keyframe
	if(lastBGUpdateTime <= lastBGKeyFrameTime){
		return true;
	}

	// time since last keyframe
	double dt = timestamp - lastBGKeyFrameTime;
	double BGKeyFramePeriodCurr = BGKeyFramePeriod;
	uint64_t nBGKeyFramesWrittenCurr;
	uint64_t minFrameBGModel1Copy;

	Lock();
	nBGKeyFramesWrittenCurr = nBGKeyFramesWritten;
	minFrameBGModel1Copy = minFrameBGModel1;
	Unlock();

	if(nBGKeyFramesWrittenCurr > 0 && nBGKeyFramesWrittenCurr <= BGKeyFramePeriodInitLength){
		BGKeyFramePeriodCurr = BGKeyFramePeriodInit[nBGKeyFramesWrittenCurr-1];
	}

	// no need to write a new keyframe if it hasn't been long enough
	// TODO: change nInput != nFramesInit to nInput != BGKeyFramePeriodInit
	if((nBGKeyFramesWrittenCurr > 0) && (dt < BGKeyFramePeriodCurr)){// && (nInput != nFramesInit)){
		return true;
	}

	ULARGE_INTEGER stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	logger->log(UFMF_DEBUG_7,"Updating background model at frame %d\n",frameNumber);
	//logger->log(UFMF_DEBUG_7,"waiting for keyframe %llu to be written\n",minFrameBGModel1Copy);
	
	// wait until the last key frame has been written
	//if(WaitForSingleObject(keyFrameWritten,MAXWAITTIMEMS) != WAIT_OBJECT_0){
	//	logger->log(UFMF_ERROR,"Timeout waiting for last keyframe to be written.\n");
	//	return false;
	//}

	// update the model
	if(!bg->updateModel()){
		logger->log(UFMF_ERROR,"Error computing background model\n");
		return false;
	}

	Lock();

	// sanity check: no frames should need to be written that are still using bound0
	time_t startTime = time(NULL);
	while(nWritten < minFrameBGModel1){
		logger->log(UFMF_DEBUG_7,"Waiting for all frames using BGModel0 to be written\n");
		Unlock();
		Sleep(100);
		if(difftime(time(NULL),startTime) > MAXWAITTIMEMS/1000.0){
			logger->log(UFMF_ERROR,"Timeout waiting for all frames using background model 0 to be written");
			return false;
		}
		Lock();
	}

	lastBGKeyFrameTime = timestamp;

	// update using old buffer, which is bound0
	float tmp;
	int i;
	for(i = 0; i < nPixels; i++){
		tmp = ceil(bg->BGCenter[i] - backSubThresh);
		if(tmp < 0) BGLowerBound0[i] = 0;
		else if(tmp > 255) BGLowerBound0[i] = 255;
		else BGLowerBound0[i] = (uint8_t)tmp;
	}
	for(i = 0; i < nPixels; i++){
		tmp = floor(bg->BGCenter[i] + backSubThresh);
		if(tmp < 0) BGUpperBound0[i] = 0;
		else if(tmp > 255) BGUpperBound0[i] = 255;
		else BGUpperBound0[i] = (uint8_t)tmp;
	}
	if(stats){
		memcpy(BGCenter0,bg->BGCenter,nPixels*sizeof(float));
	}

	// swap the background subtraction images
	unsigned char * tmpSwap;
	tmpSwap = BGLowerBound0;
	BGLowerBound0 = BGLowerBound1;
	BGLowerBound1 = tmpSwap;
	tmpSwap = BGUpperBound0;
	BGUpperBound0 = BGUpperBound1;
	BGUpperBound1 = tmpSwap;
	if(stats){
		float * tmpSwapFloat;
		tmpSwapFloat = BGCenter0;
		BGCenter0 = BGCenter1;
		BGCenter1 = tmpSwapFloat;
		double tmpSwapDouble = keyframeTimestamp0;
		keyframeTimestamp0 = keyframeTimestamp1;
		keyframeTimestamp1 = tmpSwapDouble;
		uint64_t tmpSwap64;
		tmpSwap64 = minFrameBGModel0;
		minFrameBGModel0 = minFrameBGModel1;
		minFrameBGModel1 = tmpSwap64;
	}

	// we start using model 1 at this frame
	minFrameBGModel1 = frameNumber;
	keyframeTimestamp1 = timestamp;

	Unlock();

	if(stats){
		stats->updateTimings(UTT_COMPUTE_BACKGROUND,stats_t0);
	}

	return true;

}

// *** threading tools ***

// create write thread
DWORD WINAPI ufmfWriter::writeThread(void* param){
	ufmfWriter* writer = reinterpret_cast<ufmfWriter*>(param);
	//MSG msg;
	//bool didwrite;

	SetThreadPriority(GetCurrentThread(),THREAD_PRIORITY_TIME_CRITICAL);
	
	// Signal that we are ready to begin writing
	ReleaseSemaphore(writer->writeThreadReadySignal, 1, NULL);  

	// Continuously capture and write frames to disk
	while(writer->ProcessNextWriteFrame())
		;

	//writer->Lock();
	//writer->finishWrite();
	//writer->Unlock();
	
	return 0;
}

// create compression thread
DWORD WINAPI ufmfWriter::compressionThread(void* param){
	ufmfWriter* writer = reinterpret_cast<ufmfWriter*>(param);
	int threadIndex;
	//MSG msg;
	//bool didwrite;

	// get index for this thread
	threadIndex = writer->threadCount++;

	SetThreadPriority(GetCurrentThread(),THREAD_PRIORITY_TIME_CRITICAL);
	
	// Signal that we are ready to begin writing
	ReleaseSemaphore(writer->compressionThreadReadySignals[threadIndex], 1, NULL);  

	// Continuously capture and write frames to disk
	while(writer->ProcessNextCompressFrame(threadIndex))
		;

	//writer->Lock();
	//writer->finishWrite();
	//writer->Unlock();
	
	return 0;
}

// compress frame queued for this thread
bool ufmfWriter::ProcessNextCompressFrame(int threadIndex) {
	
	ULARGE_INTEGER stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	uint64_t frameNumber;
	bool res;

	// wait for start signal
	WaitForSingleObject(compressionThreadStartSignals[threadIndex],INFINITE);

	if(stats){
		stats_t0 = stats->updateTimings(UTT_WAIT_FOR_UNCOMPRESSED_FRAME,stats_t0);
	}

	logger->log(UFMF_DEBUG_7,"starting compression thread %d on frame %u\n",threadIndex,threadFrameNumbers[threadIndex]);

	// Check if we were signalled to stop compressing
	Lock();
	if(nUncompressedFramesBuffered == 0) {
		if(isWriting) {
			Unlock();
			logger->log(UFMF_ERROR, "Something went wrong in thread %d... Got signal to compress frame but no frames buffered and compress flag is still on\n",threadIndex);
		}
		else{
			Unlock(); 
		}
		logger->log(UFMF_DEBUG_3,"nUncompressedFramesBuffered == 0, stopping compression thread %d\n",threadIndex);
		return false;
	}
	nUncompressedFramesBuffered--;
	Unlock();

	// compress this frame
	uint8_t * BGLowerBoundCurr;
	uint8_t * BGUpperBoundCurr;
	//uint8_t * BGCenterCurr;
	frameNumber = threadFrameNumbers[threadIndex];
	Lock();
	if(frameNumber < minFrameBGModel0){
		logger->log(UFMF_ERROR,"Error: frameNumber %llu < minFrameBGModel0 %llu\n",frameNumber,minFrameBGModel0);
		return false;
	}
	else if(frameNumber < minFrameBGModel1){
		logger->log(UFMF_DEBUG_7,"using bg model 0 to compress frame %d\n",frameNumber);
		BGLowerBoundCurr = BGLowerBound0;
		BGUpperBoundCurr = BGUpperBound0;
		//BGCenterCurr = BGCenter0;
	}
	else{
		logger->log(UFMF_DEBUG_7,"using bg model 1 to compress frame %d\n",frameNumber);
		BGLowerBoundCurr = BGLowerBound1;
		BGUpperBoundCurr = BGUpperBound1;
		//BGCenterCurr = BGCenter1;
	}
	Unlock();

	compressedFrames[threadIndex]->setData(uncompressedFrames[threadIndex],threadTimestamps[threadIndex],
		frameNumber,BGLowerBoundCurr,BGUpperBoundCurr);

	Lock(); // lock for nCompressedFramesBuffered
	nCompressedFramesBuffered++;
	logger->log(UFMF_DEBUG_7,"set nCompressedFramesBuffered to %d after compressing frame %llu\n",nCompressedFramesBuffered,frameNumber);
	Unlock();

	// signal that the compression thread is finished
	ReleaseSemaphore(compressionThreadDoneSignals[threadIndex],1,NULL);

	Lock();
	res = isWriting || nUncompressedFramesBuffered > 0;
	Unlock();

	if(stats){
		stats->updateTimings(UTT_COMPUTE_FRAME,stats_t0);
	}

	return(res);
}

bool ufmfWriter::ProcessNextWriteFrame(){

	ULARGE_INTEGER stats_t0;
	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
	}

	int threadIndex;
	uint64_t frameNumber;
	int i;
	int nReadyToWrite = 0;
	time_t startTime = time(NULL);

	Lock();
	nWritten++;
	frameNumber = nWritten;
	Unlock();

	logger->log(UFMF_DEBUG_7,"waiting for frame number %u to be compressed so that we can write it\n",frameNumber);

	while(true){

		if(nReadyToWrite >= nThreads){
			logger->log(UFMF_ERROR,"Found too many frames that need to be written! Something is wrong!\n");
			return false;
		}

		// wait for any compressed frame to be filled
		threadIndex = (int)WaitForMultipleObjects((DWORD)nThreads,compressionThreadDoneSignals,false,MAXWAITTIMEMS) - (int)WAIT_OBJECT_0;

		if(threadIndex > nThreads || threadIndex < 0){
			logger->log(UFMF_ERROR,"Error waiting for compressionThreadDoneSignals in write thread\n");
			return false;
		}
		// Check if we were signalled to stop writing
		Lock(); // lock because we are accessing isWriting and nCompressedFramesBuffered
		if(nCompressedFramesBuffered == 0) {
			if(isWriting) {
				logger->log(UFMF_ERROR, "Something went wrong... Got signal to write frame for thread %d containing frame %llu but no compressed frames buffered and write flag is still on\n",threadIndex,compressedFrames[threadIndex]->frameNumber);
			}
			Unlock(); 
			return false;
		}
		Unlock();

		logger->log(UFMF_DEBUG_7,"got frame %u when waiting to write frame %u\n",compressedFrames[threadIndex]->frameNumber,frameNumber);

		readyToWrite[nReadyToWrite++] = threadIndex;

		// is this the next frame to write?
		if(compressedFrames[threadIndex]->frameNumber == frameNumber){
			break;
		}
		if(compressedFrames[threadIndex]->frameNumber < frameNumber){
			logger->log(UFMF_ERROR,"Got frame %llu when waiting for frame %llu -- we should have already written this frame.\n",compressedFrames[threadIndex]->frameNumber,frameNumber);
			return false;
		}

		if(difftime(time(NULL),startTime) > MAXWAITTIMEMS/1000.0){
			logger->log(UFMF_ERROR,"Timeout waiting for a compressed frame");
			return false;
		}
	}

	if(stats){
		stats->updateTimings(UTT_WAIT_FOR_COMPRESSED_FRAME,stats_t0);
	}

	// replace the semaphores for future frames
	for(i = 0; i < nReadyToWrite-1; i++){
		logger->log(UFMF_DEBUG_7,"Putting buffer %d, frame %llu back in the queue to be written when waiting for frame %llu.\n",readyToWrite[i],compressedFrames[readyToWrite[i]]->frameNumber,frameNumber);
		ReleaseSemaphore(compressionThreadDoneSignals[readyToWrite[i]],1,NULL);
	}

	// update timings

	// write background model if nec
	Lock();
	bool isBGModel1 = frameNumber >= minFrameBGModel1;
	bool writeKeyFrame1 = frameNumber == minFrameBGModel1;
	bool writeKeyFrame0 = frameNumber == minFrameBGModel0;
	double keyframeTimestamp0Copy = keyframeTimestamp0;
	double keyframeTimestamp1Copy = keyframeTimestamp1;
	Unlock();
	if(writeKeyFrame0){
		writeBGKeyFrame(BGCenter0,keyframeTimestamp0Copy);
		logger->log(UFMF_DEBUG_3,"Wrote key frame 0 for frame %llu, releasing semaphore\n",frameNumber);
		//ReleaseSemaphore(keyFrameWritten,1,NULL);
	}
	if(writeKeyFrame1){
		writeBGKeyFrame(BGCenter1,keyframeTimestamp1Copy);
		logger->log(UFMF_DEBUG_3,"Wrote key frame 1 for frame %llu, releasing semaphore\n",frameNumber);
		//ReleaseSemaphore(keyFrameWritten,1,NULL);
	}


	// write the compressed frame
	threadIndex = readyToWrite[nReadyToWrite-1];

	int8_t frameSizeBytes = writeFrame(compressedFrames[threadIndex]);
	if(frameSizeBytes <= 0){
		logger->log(UFMF_ERROR,"Error writing frame %u from thread %d\n",frameNumber,threadIndex);
		return false;
	}

	Lock(); // lock to access isWriting and nCompressedFramesBuffered
	nCompressedFramesBuffered--;
	uint64_t nFramesDroppedExternalCopy = nFramesDroppedExternal;
	uint64_t nFramesBufferedExternalCopy = nFramesBufferedExternal;
	logger->log(UFMF_DEBUG_7,"set nCompressedFramesBuffered to %d after writing frame %llu\n",nCompressedFramesBuffered,frameNumber);
	bool res = isWriting || nCompressedFramesBuffered > 0;
	Unlock();

	if(stats){
		stats_t0 = ufmfWriterStats::getTime();
		float * BGCenterCurr;
		if(isBGModel1)
			BGCenterCurr = BGCenter1;
		else
			BGCenterCurr = BGCenter0;
		stats->update(index, index_timestamp, frameSizeBytes, compressedFrames[threadIndex]->isCompressed, 
			compressedFrames[threadIndex]->numFore, compressedFrames[threadIndex]->numPxWritten, 
			compressedFrames[threadIndex]->ncc, nFramesBufferedExternal, nFramesDroppedExternal, 
			compressedFrames[threadIndex]->nWrites, nPixels, uncompressedFrames[threadIndex], 
			BGCenterCurr, UFMF_DEBUG_3);
		stats->updateTimings(UTT_COMPUTE_STATS,stats_t0);
	}

	// signal that we've written the key frame
	//if(writeKeyFrame)
	//	ReleaseSemaphore(keyFrameWritten,1,NULL);

	// signal that the compression thread can be used again
	ReleaseSemaphore(compressionThreadReadySignals[threadIndex],1,NULL);
	logger->log(UFMF_DEBUG_7,"Released compressionThreadReadySignals[%d]\n",threadIndex);

	return(res);

}

bool ufmfWriter::stopThreads(bool waitForFinish){

	long value;

	logger->log(UFMF_DEBUG_7,"stopping threads\n");

	// no need to lock when reading isWriting as this is the only thread that will write to it
	if(isWriting){

		Lock();
		isWriting = false;
		Unlock();

		// stop each compression thread
		for(int i = 0; i < (int)nThreads; i++){
			logger->log(UFMF_DEBUG_7,"stopping compression thread %d\n",i);
			ReleaseSemaphore(compressionThreadStartSignals[i],1,NULL);
			if(_compressionThreads[i]){
				if(!waitForFinish){
					// set number of frames buffered to 0
					Lock();
					nUncompressedFramesBuffered = 0;
					Unlock();
					// increment semaphores so that the compression threads don't block forever. 
					// since nUncompressedFramesBuffered == 0 and isWriting == false, we won't try to 
					// compress a frame
					ReleaseSemaphore(compressionThreadStartSignals[i], 1, NULL);
				}
				else{
					Lock();
					if(nUncompressedFramesBuffered == 0){
						Unlock();
						ReleaseSemaphore(compressionThreadStartSignals[i], 1, NULL);
					}
					else{
						Unlock();
					}
				}
				if(WaitForSingleObject(_compressionThreads[i],MAXWAITTIMEMS) != WAIT_OBJECT_0){
					logger->log(UFMF_ERROR,"Error shutting down compression thread %d\n",i);
				}
				CloseHandle(_compressionThreads[i]);
				_compressionThreads[i] = NULL;
			}
		}

		logger->log(UFMF_DEBUG_7,"stopping write thread\n");
		if(_writeThread){
			if(!waitForFinish){
				// set number of frames buffered to 0
				Lock(); // lock for nCompressedFramesBuffered
				nCompressedFramesBuffered = 0;
				Unlock();
				// increment semaphores so that the compression threads don't block forever. 
				// since nCompressedFramesBuffered == 0 and isWriting == false, we won't try to 
				// compress a frame
				for(int j = 0; j < (int)nThreads; j++){
					ReleaseSemaphore(compressionThreadDoneSignals[j], 1, NULL);
				}
				if(WaitForSingleObject(_writeThread, MAXWAITTIMEMS) != WAIT_OBJECT_0){
					logger->log(UFMF_ERROR,"Error shutting down write thread\n");
				}
			}
			else{
				Lock();
				if(nCompressedFramesBuffered == 0){
					Unlock();
					for(int j = 0; j < (int)nThreads; j++){
						ReleaseSemaphore(compressionThreadDoneSignals[j], 1, NULL);
					}
				}
				else{
					Unlock();
				}
			}

			//Close thread handle
			CloseHandle(_writeThread);
			_writeThread = NULL;

		}
	}

	return true;

}

// lock when accessing global data
bool ufmfWriter::Lock() { 
	if(WaitForSingleObject(lock, MAXWAITTIMEMS) != WAIT_OBJECT_0) { 
		logger->log(UFMF_ERROR,"Waited Too Long For Write Lock\n"); 
		return false;
	} 
	return true;
}
bool ufmfWriter::Unlock() { 
	ReleaseSemaphore(lock, 1, NULL); 
	return true;
}


void ufmfWriter::deallocateBuffers(){

	int i;
	if(uncompressedFrames != NULL){
		for(i = 0; i < (int)nThreads; i++){
			if(uncompressedFrames[i] != NULL){
				delete [] uncompressedFrames[i];
				uncompressedFrames[i] = NULL;
			}
		}
		delete [] uncompressedFrames;
		uncompressedFrames = NULL;
	}
	nUncompressedFramesBuffered = 0;

	if(compressedFrames != NULL){
		for(i = 0; i < (int)nThreads; i++){
			if(compressedFrames[i] != NULL){
				delete compressedFrames[i];
				compressedFrames[i] = NULL;
			}
		}
		delete [] compressedFrames;
		compressedFrames = NULL;
	}
	nCompressedFramesBuffered = 0;

	if(threadTimestamps != NULL){
		delete [] threadTimestamps;
		threadTimestamps = NULL;
	}

	if(threadFrameNumbers != NULL){
		delete [] threadFrameNumbers;
		threadFrameNumbers = NULL;
	}

	if(readyToWrite != NULL){
		delete [] readyToWrite;
		readyToWrite = NULL;
	}
}

void ufmfWriter::deallocateBGModel(){

	if(bg != NULL){
		delete bg;
		bg = NULL;
	}
	if(BGLowerBound0 != NULL){
		delete [] BGLowerBound0;
		BGLowerBound0 = NULL;
	}
	if(BGUpperBound0 != NULL){
		delete [] BGUpperBound0;
		BGUpperBound0 = NULL;
	}
	if(BGLowerBound1 != NULL){
		delete [] BGLowerBound1;
		BGLowerBound1 = NULL;
	}
	if(BGUpperBound1 != NULL){
		delete [] BGUpperBound1;
		BGUpperBound1 = NULL;
	}
}

void ufmfWriter::deallocateThreadStuff(){

	int i;
	if(_compressionThreads != NULL){
		for(i = 0; i < (int)nThreads; i++){
			if(_compressionThreads[i]){
				CloseHandle(_compressionThreads[i]);
				_compressionThreads[i] = NULL;
			}
		}
		delete [] _compressionThreads;
		_compressionThreads = NULL;
	}

	if(_compressionThreadIDs != NULL){
		delete [] _compressionThreadIDs;
		_compressionThreadIDs = NULL;
	}

	if(compressionThreadReadySignals != NULL){
		for(i = 0; i < (int)nThreads; i++){
			if(compressionThreadReadySignals[i]){
				CloseHandle(compressionThreadReadySignals[i]);
				compressionThreadReadySignals[i] = NULL;
			}
		}
		delete [] compressionThreadReadySignals;
		compressionThreadReadySignals = NULL;
	}

	 if(compressionThreadStartSignals != NULL){
		 for(i = 0; i < (int)nThreads; i++){
			 if(compressionThreadStartSignals[i]){
				 CloseHandle(compressionThreadStartSignals[i]);
				 compressionThreadStartSignals[i] = NULL;
			 }
		 }
		 delete [] compressionThreadStartSignals;
		 compressionThreadStartSignals = NULL;
	 }

	 if(compressionThreadDoneSignals != NULL){
		 for(i = 0; i < (int)nThreads; i++){
			 if(compressionThreadDoneSignals[i]){
				 CloseHandle(compressionThreadDoneSignals[i]);
				 compressionThreadDoneSignals[i] = NULL;
			 }
		 }
		 delete [] compressionThreadDoneSignals;
		 compressionThreadDoneSignals = NULL;
	 }

	 if(lock){
		 CloseHandle(lock);
		 lock = NULL;
	 }

	 if(keyFrameWritten != NULL){
		 CloseHandle(keyFrameWritten);
		 keyFrameWritten = NULL;
	 }

	 if(stats){
		 delete stats;
		 stats = NULL;
		 logger->log(UFMF_DEBUG_3,"deleted stats\n");
	 }
}

#pragma clang diagnostic pop


// ************** helper functions *************************

char* ufmfWriter::strtrim(char *aString)
{
    int i;
    int lLength = strlen(aString);
    char* lOut = aString;
    
    // trim right
    for(i=lLength-1;i>=0;i--)   
        if(isspace(aString[i]))
            aString[i]='\0';
        else
            break;
                
    lLength = strlen(aString);    
        
    // trim left
    for(i=0;i<lLength;i++)
        if(isspace(aString[i]))
            lOut = &aString[i+1];    
        else
            break;    
    
    return lOut;
}