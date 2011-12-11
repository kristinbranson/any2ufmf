#include "cv.h"
#include "highgui.h"
#include <stdio.h>
#include "ufmfWriter.h"
#include "previewVideo.h"

int main(int argc, char * argv){


	double timestamp;
	double frameRate = 1.0/30.0;

	fprintf(stderr,"Driving!\n");

	// input avi
	CvCapture* capture = cvCaptureFromAVI("C:\\Code\\imaq\\any2ufmf\\out\\test1.avi");

	// get avi frame size
	cvQueryFrame(capture); // this call is necessary to get correct capture properties
	unsigned __int32 frameH = (unsigned __int32) cvGetCaptureProperty(capture, CV_CAP_PROP_FRAME_HEIGHT);
	unsigned __int32 frameW = (unsigned __int32) cvGetCaptureProperty(capture, CV_CAP_PROP_FRAME_WIDTH);

	// log file
	//FILE * logFID = fopen("C:\\Code\\imaq\\any2ufmf\\out\\log.txt","w");
	FILE * logFID = stderr;

	// output ufmf
	ufmfWriter * writer = new ufmfWriter("C:\\Code\\imaq\\any2ufmf\\out\\test1.ufmf", frameW, frameH, logFID, "C:\\Code\\imaq\\gige_record_x64\\testVideoParams.txt");

	// start preview thread
	HANDLE lock = CreateSemaphore(NULL,1,1,NULL);
	previewVideo * preview = new previewVideo(lock);

	// start writing
	if(!writer->startWrite()){
		fprintf(stderr,"Error starting write\n");
		fprintf(stderr,"Hit enter to exit\n");
		getc(stdin);
		return 1;
	}

	IplImage * frame = NULL;
	unsigned __int64 frameNumber;
	IplImage * frameWrite = NULL;
	IplImage * grayFrame = cvCreateImage(cvSize(frameW,frameH),IPL_DEPTH_8U,1);

	fprintf(stderr,"Hit esc to stop playing\n");
	bool DEBUGFAST = true;
	for(frameNumber = 0, timestamp = 0; ; timestamp += frameRate){

		if(DEBUGFAST && frameNumber >= 3000)
			break;

		if((frameNumber % 100) == 0){
			fprintf(stderr,"** frame %lu\n",frameNumber);
		}

		if(!DEBUGFAST && (WaitForSingleObject(lock, MAXWAITTIMEMS) != WAIT_OBJECT_0)) { 
			fprintf(stderr,"Error waiting for preview thread to unlock\n");
			break;
		}
		if(!DEBUGFAST || (frame == NULL))
			frame = cvQueryFrame(capture);
		frameNumber++;
		if(!DEBUGFAST) ReleaseSemaphore(lock,1,NULL);
		if(!frame){
			break;
		}
		if(!DEBUGFAST && !preview->setFrame(frame,frameNumber)){
			break;
		}
		
		if(!DEBUGFAST || frameWrite == NULL){
			if(frame->nChannels > 1){
				cvCvtColor(frame,grayFrame,CV_RGB2GRAY);
				frameWrite = grayFrame;
			}
			else{
				frameWrite = frame;
			}
		}
		if(!writer->addFrame((unsigned char*) frameWrite->imageData,timestamp)){
			fprintf(stderr,"Error adding frame %d\n",frameNumber);
			break;
		}

	}

	if(!writer->stopWrite()){
		fprintf(stderr,"Error stopping writing\n");
		fprintf(stderr,"Hit enter to exit\n");
		getc(stdin);
		return 1;
	}

	if(!preview->stop()){
		fprintf(stderr,"Error waiting for preview thread to unlock\n");
	}

	// clean up
	if(preview != NULL){
		delete preview;
		preview = NULL;
	}
	if(lock){
		CloseHandle(lock);
		lock = NULL;
	}
	if(capture != NULL){
		cvReleaseCapture(&capture);
		capture = NULL;
		frame = NULL;
	}
	if(grayFrame != NULL){
		cvReleaseImage(&grayFrame);
		grayFrame = NULL;
	}
	if(writer != NULL){
		delete writer;
	}

	fprintf(stderr,"Hit enter to exit\n");
	getc(stdin);

	return 0;
}