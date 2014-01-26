//
//  AppDelegate.m
//  any2ufmf
//
//  Created by John Bender on 12/26/13.
//  Copyright (c) 2013 Howard Hughes Medical Institute. All rights reserved.
//

#import "AppDelegate.h"

#include <opencv2/opencv.hpp>
#include <opencv2/highgui/highgui.hpp>

#include <opencv/cv.h>
#include <opencv/highgui.h>

#include "ufmfWriter.h"
#include "previewVideo.h"

#define ARRAYSIZE(a) \
    ((sizeof(a) / sizeof(*(a))) / \
    static_cast<size_t>(!(sizeof(a) % sizeof(*(a)))))

typedef NSArray* COMDLG_FILTERSPEC;

typedef enum {
    DialogTypeInput,
    DialogTypeOutput
} DialogType;

bool ChooseFile(char fileName[], const char dialogTitle[], const COMDLG_FILTERSPEC filterSpec[], int nFilters, DialogType dialogType);
bool ChooseFile(char fileName[], const char dialogTitle[], const COMDLG_FILTERSPEC filterSpec[], int nFilters, DialogType dialogType, char defaultFileName[]);

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSArray *args = [[NSProcessInfo processInfo] arguments];

    NSInteger argc = [args count];
	bool interactiveMode = argc <= 3;
    bool fileChoiceSuccess = true;;

    // first argument is the input AVI
	char aviFileName[512];
	if(argc > 1){
        const char *argv = [args[1] cStringUsingEncoding:NSUTF8StringEncoding];
		strcpy(aviFileName,argv);
        fprintf(stdout,"Input AVI file = %s\n",aviFileName);
	}
	else{
        const COMDLG_FILTERSPEC aviTypes[] =
        {
            @[@"Audio-video Interleave Files (*.avi)",   @"*.avi"],
            @[@"All Files (*.*)",    					@"*.*"]
        };
		fileChoiceSuccess = ChooseFile(aviFileName, "Choose AVI file", aviTypes, ARRAYSIZE(aviTypes), DialogTypeInput);
	}

    // test input file
    if( !fileChoiceSuccess || strlen( aviFileName ) == 0 ) {
        if( !interactiveMode )
            fprintf( stderr, "Empty input filename specified. Aborting.\n" );
        [NSApp terminate:self];
    }

	// input avi
    CvCapture* capture = cvCaptureFromAVI(aviFileName);
	if(capture==NULL){
		if(interactiveMode){
            [[NSAlert alertWithMessageText:@"Read Error"
                             defaultButton:nil
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"Error reading AVI. Exiting."]
             runModal];
		}
        else {
            fprintf(stderr,"Error reading AVI %s. Exiting.\n",aviFileName);
        }
        [NSApp terminate:self];
	}

	// output ufmf
	char ufmfFileName[512];
	if(argc > 2){
        const char *argv = [args[2] cStringUsingEncoding:NSUTF8StringEncoding];
		strcpy(ufmfFileName,argv);
        fprintf(stdout,"Output UFMF file = %s\n",ufmfFileName);
	}
	else{
        const COMDLG_FILTERSPEC ufmfTypes[] =
        {
            @[@"Micro Fly Movie Format Files (*.ufmf)",  @"*.ufmf"],
            @[@"All Files (*.*)",    					@"*.*"]
        };

        // choose default filename: (AVI filename substring between last backslash and last dot) + ".ufmf"
        char defaultFileName[512];
        strcpy( defaultFileName, aviFileName );
        char* strLastDot = strrchr( defaultFileName, '.' );
        if( strLastDot != NULL ) {
            strcpy( strLastDot, ".ufmf" );
            char *strLastBackslash = strrchr( defaultFileName, '\\' );
            if( strLastBackslash != NULL ) {
                char tmp[512];
                strcpy( tmp, &defaultFileName[strLastBackslash + 1 - defaultFileName] );
                strcpy( defaultFileName, tmp );
            }

            fileChoiceSuccess = ChooseFile(ufmfFileName, "Choose output file", ufmfTypes, ARRAYSIZE(ufmfTypes), DialogTypeOutput, defaultFileName);
        }
        else {
            fileChoiceSuccess = ChooseFile(ufmfFileName, "Choose output file", ufmfTypes, ARRAYSIZE(ufmfTypes), DialogTypeOutput);
        }
	}

    // test output file
    if( !fileChoiceSuccess || strlen( ufmfFileName ) == 0 ) {
        if( !interactiveMode )
            fprintf( stderr, "Empty output filename specified. Aborting.\n" );
        [NSApp terminate:self];
    }

    FILE *fp = fopen( ufmfFileName, "w" );
    if( fp == NULL ) {
        if(interactiveMode){
            [[NSAlert alertWithMessageText:@"Write Error"
                             defaultButton:nil
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"Error opening output file. Exiting."]
             runModal];
		}
        else {
            fprintf(stderr,"Error opening output file\n");
        }
        [NSApp terminate:self];
    }
    fclose( fp );

	// parameters
	char ufmfParamsFileName[512];
	if(argc > 3){
        const char *argv = [args[3] cStringUsingEncoding:NSUTF8StringEncoding];
		strcpy(ufmfParamsFileName,argv);
		fprintf(stdout,"UFMF Compression Parameters file = %s\n",ufmfParamsFileName);
	}
	else{
        NSInteger choice = [[NSAlert alertWithMessageText:@"Specify parameters?"
                                            defaultButton:@"Yes"
                                          alternateButton:@"No"
                                              otherButton:nil
                                informativeTextWithFormat:@"Select a custom parameters file?"]
         runModal];
        if( choice == NSAlertDefaultReturn ) {
            const COMDLG_FILTERSPEC ufmfParamTypes[] =
            {
                @[@"Text Files (*.txt)", @"*.txt"],
                @[@"All Files (*.*)",    @"*.*"]
            };
		    ChooseFile(ufmfParamsFileName, "Choose parameters file", ufmfParamTypes, ARRAYSIZE(ufmfParamTypes), DialogTypeInput);
        }
        else
            ufmfParamsFileName[0] = '\0';
	}

	// get avi frame size
	cvQueryFrame(capture); // this call is necessary to get correct capture properties
	uint32_t frameH = (uint32_t) cvGetCaptureProperty(capture, CV_CAP_PROP_FRAME_HEIGHT);
	uint32_t frameW = (uint32_t) cvGetCaptureProperty(capture, CV_CAP_PROP_FRAME_WIDTH);
	double nFrames = cvGetCaptureProperty(capture, CV_CAP_PROP_FRAME_COUNT);
	fprintf(stderr,"Number of frames in the video: %f\n",nFrames);

	// log file
	//FILE * logFID = fopen("C:\\Code\\imaq\\any2ufmf\\out\\log.txt","w");
	FILE * logFID = stderr;

	// output ufmf
	ufmfWriter * writer = new ufmfWriter(ufmfFileName, frameW, frameH, logFID, ufmfParamsFileName);
	if(!writer->startWrite()){
		if(interactiveMode){
            [[NSAlert alertWithMessageText:@"Write Error"
                             defaultButton:nil
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"Error initializing uFMF writer. Exiting."]
             runModal];
		}
        else {
            fprintf(stderr,"Error starting write\n");
        }
        [NSApp terminate:self];
	}

	// start preview thread
	NSLock *lock = [NSLock new];
	previewVideo * preview = new previewVideo(lock);

    IplImage * frame = NULL;
	uint64_t frameNumber;
	IplImage * frameWrite = NULL;
	IplImage * grayFrame = cvCreateImage(cvSize(frameW,frameH),IPL_DEPTH_8U,1);

    double timestamp;
	double frameRate = 1.0/30.0;

	fprintf(stderr,"Hit esc to stop playing\n");
	bool DEBUGFAST = false;
	for(frameNumber = 0, timestamp = 0.; ; frameNumber++, timestamp += frameRate){

		if(DEBUGFAST && frameNumber >= 3000)
			break;

		if((frameNumber % 100) == 0){
			fprintf(stderr,"** frame %llu\n",frameNumber);
		}

		if(!DEBUGFAST && ([lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:MAXWAITTIMEMS/1000.]]) != TRUE) {
			fprintf(stderr,"Error waiting for preview thread to unlock\n");
			break;
		}
		if(!DEBUGFAST || (frame == NULL))
			frame = cvQueryFrame(capture);
		//frameNumber++;
		if(!DEBUGFAST) [lock unlock];
		if(!frame){
			fprintf(stderr,"Last frame read = %llu\n",frameNumber);
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
			fprintf(stderr,"Error adding frame %llu\n",frameNumber);
			break;
		}

	}

	if(!writer->stopWrite()){
		fprintf(stderr,"Error stopping writing\n");
		if(interactiveMode){
			fprintf(stderr,"Hit enter to exit\n");
			getc(stdin);
		}
        [NSApp terminate:self];
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
    
	if(interactiveMode){
		fprintf(stderr,"Hit enter to exit\n");
		getc(stdin);
	}

    [NSApp terminate:self];
}


bool ChooseFile(char fileName[], const char dialogTitle[], const COMDLG_FILTERSPEC filterSpec[], int nFilters, DialogType dialogType)
{
    return ChooseFile( fileName, dialogTitle, filterSpec, nFilters, dialogType, NULL );
}

bool ChooseFile(char fileName[], const char dialogTitle[], const COMDLG_FILTERSPEC filterSpec[], int nFilters, DialogType dialogType, char defaultFileName[])
{
    return true;
}

@end
