#ifndef __UFMF_LOGGER
#define __UFMF_LOGGER

#include <stdio.h>
#include <Foundation/Foundation.h>

typedef enum {
	UFMF_CRITICAL_ERROR=0,
	UFMF_ERROR,
	UFMF_CRITICAL_WARNING,
	UFMF_WARNING,
	UFMF_DEBUG_0,UFMF_DEBUG_1,UFMF_DEBUG_2,UFMF_DEBUG_3,UFMF_DEBUG_4,UFMF_DEBUG_5,UFMF_DEBUG_6,UFMF_DEBUG_7,UFMF_DEBUG_8
} ufmfDebugLevel;

class ufmfLogger {
	ufmfDebugLevel level;
	FILE *fout;
	NSLock *lock;
	bool flush, threadSafe, openedFile, keepOpen, hasBeenOpened, doWrite;
	char fileName[1000];

public:
	void Init(FILE *fout=stdout, ufmfDebugLevel level=UFMF_WARNING, bool threadSafe=true, bool flush=false) { 
		this->openedFile = false;
		this->fout = fout; 
		this->level = level;  
		this->threadSafe = threadSafe;  
		this->flush = flush; 
		this->keepOpen = true;
		if(fout){
			this->doWrite = true;
		}
		else{
			this->doWrite = false;
		}

		if(threadSafe) lock = [NSLock new];
	}
	ufmfLogger(FILE *fout=stdout, ufmfDebugLevel level=UFMF_WARNING, bool threadSafe=true, bool flush=false, bool doOverwrite=true) {
		hasBeenOpened = true;
		Init(fout, level, threadSafe, flush);
	}
	ufmfLogger(const char *fname, ufmfDebugLevel level=UFMF_WARNING, bool threadSafe=true, bool flush=false, bool doOverwrite=true) {
		hasBeenOpened = false;
		if(fname){
			printf("constructing logger with filename = %s\n",fname);
		}
		else{
			printf("constructing logger with filename = NULL\n");
		}
		if(fname && strcmp(fname,"")){
			if(doOverwrite){
				Init(fopen(fname, "w"), level, threadSafe, flush);
			}
			else{
				Init(fopen(fname, "a"), level, threadSafe, flush);
			}
			hasBeenOpened = true;
			openedFile = true;
			strcpy(fileName,fname);
		}
		else{
			Init(NULL,level,threadSafe,flush);
			openedFile = false;
			strcpy(fileName,"");
		}
	}
	~ufmfLogger() {
		if(openedFile && fout && keepOpen) fclose(fout);
	}

	void log(ufmfDebugLevel l, char *fmt, ...) {
		if(!doWrite) return;
		if(l <= level) {
			va_list argp;
			if(threadSafe) [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.]];
			if(!keepOpen){
				if(hasBeenOpened){
					fout = fopen(fileName,"a");
				}
				else{
					fout = fopen(fileName,"w");
					hasBeenOpened = true;
				}
			}
			if(fout) { 
				va_start(argp, fmt); 
				vfprintf(fout, fmt, argp); 
				va_end(argp); 
				if(flush || l<=UFMF_ERROR) fflush(fout); 
			}
			if(!keepOpen){
				fclose(fout);
				fout = NULL;
				openedFile = false;
			}
			if(threadSafe) [lock unlock];
		}
	}

	void flushNow(){
		if(!doWrite) return;
		if(!keepOpen) return;
        if(threadSafe) [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.]];
		fflush(fout);
		if(threadSafe) [lock unlock];
	}

	// change the name of the log file
	bool renameLogFile(const char *newfname){
		bool failed = false;

		// same name, then do nothing
		if(!strcmp(newfname,fileName)){
			return false;
		}

		// if file name has been sent to the empty string, then don't log stuff
		if(!strcmp(newfname,"")){

			if(threadSafe) [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.]];
			// if a file is already open, close it
			if(keepOpen && openedFile && fout){
				fclose(fout);
				fout = NULL;
				openedFile = false;
			}
			strcpy(fileName,newfname);
			hasBeenOpened = false;
			doWrite = false;
			if(threadSafe) [lock unlock];

		}
		else{
			// file name is something real
			doWrite = true;

			if(keepOpen){

				// if a file is already open
				if(openedFile && fout){

					// get lock
                    if(threadSafe) [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.]];

					// close the file
					fclose(fout);
					openedFile = false;

					// copy old file to new filename
					failed = rename(fileName,newfname) != 0;
					if(!failed){
						strcpy(fileName,newfname);
					}

					// open the new file for appending
					fout = fopen(fileName,"a");
					openedFile = true;
					hasBeenOpened = true;

					// release lock
					if(threadSafe) [lock unlock];
				}
				else{

					// no file open yet, open the file and call init

					Init(fopen(newfname, "w"), level, threadSafe, flush);
					openedFile = true;
					hasBeenOpened = true;
					strcpy(fileName,newfname);
					if(threadSafe) [lock unlock];

				}
			}
			else{

                if(threadSafe) [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.]];
				if(hasBeenOpened){
					failed = rename(fileName,newfname) != 0;
				}
				strcpy(fileName,newfname);
				if(threadSafe) [lock unlock];

			}
		}
		return failed;
	}
	void closeFile(){
		if(!openedFile) return;
		if(!keepOpen) return;
        if(threadSafe) [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.]];
		if(openedFile && fout){
			fclose(fout);
			fout = NULL;
			openedFile = false;
		}
		keepOpen = false;
		if(threadSafe) [lock unlock];
	}

	void openFile(){
		if(keepOpen) return;
        if(threadSafe) [lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.]];
		if(hasBeenOpened){
			fout = fopen(fileName,"a");
		}
		else{
			fout = fopen(fileName,"w");
			hasBeenOpened = false;
		}
		openedFile = true;
		keepOpen = true;
		if(threadSafe) [lock unlock];
	}

};

#endif