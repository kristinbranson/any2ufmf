#include "previewVideo.h"

@interface PreviewThread : NSThread

@property (nonatomic, assign) previewVideo *pv;
@property (nonatomic, weak) NSLock *previewThreadReadySignal;

@end


previewVideo::previewVideo(NSLock *lock){

	this->lock = lock;
	this->frame = NULL;
	frameNumber = 0;
	frameCopy = NULL;
	frameSize = 0;
	lastFrameNumber = 0;

	previewThreadReadySignal = [NSLock new];
    _previewThread = [PreviewThread new];
    ((PreviewThread*)_previewThread).pv = this;
    ((PreviewThread*)_previewThread).previewThreadReadySignal = previewThreadReadySignal;
    [(PreviewThread*)_previewThread start];

	if (_previewThread == NULL){
		fprintf(stderr,"Error starting Preview Thread\n"); 
		return;
	}
	if( [previewThreadReadySignal lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]] != TRUE ) {
		fprintf(stderr,"Error Starting Preview Thread\n");
		return; 
	}

	isRunning = true;
}

bool previewVideo::stop(){
	if(!Lock()){
		return false;
	}
	isRunning = false;
	Unlock();
    NSTimeInterval waitTime = 0.;
    NSDate *startWaitDate = [NSDate date];
    while( waitTime < 1. && ![_previewThread isFinished] ) {
        usleep( 1000. );
        waitTime = [[NSDate date] timeIntervalSinceDate:startWaitDate];
    }
    if( ![_previewThread isFinished] ) {
		fprintf(stderr,"timeout waiting for preview thread to finish\n");
		return false;
	}
	return true;
}

bool previewVideo::Lock(){
	return( [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]] == TRUE );
}

bool previewVideo::Unlock(){
	[lock unlock];
	return true;
}

bool previewVideo::setFrame(IplImage * frame, uint64_t frameNumber){

	Lock();
	this->frame = frame;
	this->frameNumber = frameNumber;
	Unlock();
	return isRunning;
}

previewVideo::~previewVideo(){
	isRunning = false;
	if(frameCopy){
		cvReleaseImage(&frameCopy);
		frameCopy = NULL;
	}
}
	
bool previewVideo::ProcessNextPreview(){

	if(!Lock()){
		fprintf(stderr,"preview timeout\n");
		return isRunning;
	}

	if(!isRunning){
		fprintf(stderr,"not compressing\n");
		Unlock();
		return false;
	}

	if(frame == NULL || frameNumber == lastFrameNumber){
		Unlock();
		return true;
	}

	if(frameCopy == NULL){
		frameCopy = cvCloneImage(frame);
		frameSize = frame->imageSize;
	}
	else if(frameCopy->imageSize != frame->imageSize){
		cvReleaseImage(&frameCopy);
		frameCopy = cvCloneImage(frame);
	}
	else{
		memcpy(frameCopy->imageData,frame->imageData,frameSize);
	}
	lastFrameNumber = frameNumber;
	Unlock();

	//if(frameNumber % 100 == 0) fprintf(stderr,"Showing frame %llu\n",frameNumber);
	cvShowImage( "Preview", frameCopy );
	char c = cvWaitKey(1);
	if(c == 27){
		if(!Lock()){
			fprintf(stderr,"preview stop timeout\n");
			return false;
		}
		isRunning = false;
		Unlock();
		return false;
	}

	return true;

}

// create preview thread
@implementation PreviewThread

-(void) main
{
    self.threadPriority = 0.;

	cvNamedWindow( "Preview", CV_WINDOW_AUTOSIZE );

	// Signal that we are ready to begin writing
    [self.previewThreadReadySignal unlock];

	// Continuously capture and write frames to disk
	while((self.pv)->ProcessNextPreview())
		;

	fprintf(stderr,"preview thread terminated\n");
	
	cvDestroyWindow("Preview");
}

@end
