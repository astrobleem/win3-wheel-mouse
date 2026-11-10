/* SPDX-License-Identifier: MIT
 * Windows 3.0 real-mode wheel diagnostic. Timer polling, no hooks.
 * /AUTO checks the loaded driver exports and backend, then exits.
 */
#define WINVER 0x0300
#include <windows.h>
typedef WORD (FAR PASCAL *GETWORD)(void);
typedef int (FAR PASCAL *GETDELTA)(void);
static GETWORD getVersion,getStatus,getLost;
static GETDELTA getDelta;
static HFILE logFile=-1;
static WORD status,version,lost;
static long total,events,moves,clicks;
static int lastDelta,autoMode,ticks,failures;
static void logline(LPSTR text) {
 if(logFile!=-1) { _lwrite(logFile,text,lstrlen(text)); _lwrite(logFile,"\r\n",2); }
}
static void number(LPSTR key,long value) {
 char buf[90]; wsprintf(buf,"%s=%ld",key,value); logline(buf);
}
static LPSTR backend(void) {
 if(status==0x0103)return "Direct PS/2 / wheel negotiated";
 if(status==3)return "Direct PS/2 / standard mouse";
 if(status==0x8003)return "STOPPED: PS/2 AUX not present";
 if(status==0x8004)return "STOPPED: PS/2 busy; cold reboot with no DOS mouse";
 if(status==0x8005)return "STOPPED: PS/2 command failed";
 if(status==0x8006)return "STOPPED: PS/2 cleanup failed; reboot";
 if(status==0x8007)return "STOPPED: remove DOS mouse and reboot";
 if(status==0x0102)return "DOS mouse / wheel advertised";
 if(status==2)return "DOS mouse / no wheel advertised";
 if(status==0x0101)return "Direct serial / wheel parser ready";
 if(status==0x8001)return "STOPPED: unsupported DOS mouse";
 if(status==0x8002)return "STOPPED: DOS mouse driver not found";
 return "Inactive or unavailable";
}
LONG FAR PASCAL WndProc(HWND w,UINT m,WPARAM a,LPARAM b) {
 PAINTSTRUCT ps; HDC dc; char text[100]; int d,i;
 switch(m) {
 case WM_CREATE:
  if(!SetTimer(w,1,55,NULL)){++failures;DestroyWindow(w);} return 0;
 case WM_TIMER:
  status=getStatus?getStatus():0;
  if(getDelta)for(i=0;i<31;i++){
   d=getDelta();if(!d)break;lastDelta=d;total+=d;++events;
   number("WHEEL_DELTA",d);
  }
  lost=getLost?getLost():0;
  InvalidateRect(w,NULL,TRUE);
  if(autoMode && ++ticks>=5)DestroyWindow(w);
  return 0;
 case WM_MOUSEMOVE: ++moves; return 0;
 case WM_LBUTTONDOWN: case WM_RBUTTONDOWN: ++clicks; return 0;
 case WM_PAINT:
  dc=BeginPaint(w,&ps);
  TextOut(dc,6,4,backend(),lstrlen(backend()));
  wsprintf(text,"Wheel: last %d / total %ld",lastDelta,total);
  TextOut(dc,6,22,text,lstrlen(text));
  wsprintf(text,"Events %ld  Lost %u",events,lost);
  TextOut(dc,6,40,text,lstrlen(text));
  wsprintf(text,"Moves %ld  Clicks %ld",moves,clicks);
  TextOut(dc,6,58,text,lstrlen(text));
  TextOut(dc,6,78,"Turn wheel; move and click here.",lstrlen("Turn wheel; move and click here."));
  TextOut(dc,6,96,"Alt+F4 closes. See WDIAG.LOG.",lstrlen("Alt+F4 closes. See WDIAG.LOG."));
  EndPaint(w,&ps);return 0;
 case WM_DESTROY:
  KillTimer(w,1);
  if(!(status==2 || status==0x0101 || status==0x0102 || status==3 || status==0x0103))++failures;
  number("VERSION",version);number("STATUS",status);
  number("WHEEL_EVENTS",events);number("WHEEL_TOTAL",total);
  number("MOVES",moves);number("CLICKS",clicks);number("LOST",lost);
  number("FAIL_COUNT",failures);logline("COMPLETE=1");
  if(logFile!=-1){_lclose(logFile);logFile=-1;}
  PostQuitMessage(failures?1:0);return 0;
 }
 return DefWindowProc(w,m,a,b);
}
int PASCAL WinMain(HINSTANCE hi,HINSTANCE prev,LPSTR cmd,int show) {
 WNDCLASS wc; HWND w; MSG msg; HMODULE module; char path[128];
 if(prev){MessageBox(NULL,"One diagnostic at a time.","Wheel diagnostic",MB_OK);return 1;}
 if(FindWindow("WindowsXTWheelBridge",NULL)){
  MessageBox(NULL,"Stop WXTWHL before running WDIAG. Both consume wheel events.","Wheel diagnostic",MB_OK);return 1;
 }
 logFile=_lcreat("WDIAG.LOG",0);
 if(logFile==-1){MessageBox(NULL,"Cannot create WDIAG.LOG in the working directory.","Wheel diagnostic",MB_OK);return 1;}
 autoMode=lstrcmpi(cmd,"/AUTO")==0;
 logline("WDIAG 0.2 - synthetic checks do not prove physical wheel delivery");
 module=GetModuleHandle("MOUSE");
 if(module){
  path[0]=0;GetModuleFileName(module,path,sizeof(path));logline(path);
  getVersion=(GETWORD)GetProcAddress(module,"WHEELAPIVERSION");
  getStatus=(GETWORD)GetProcAddress(module,"WHEELSTATUS");
  getDelta=(GETDELTA)GetProcAddress(module,"WHEELREADDELTA");
  getLost=(GETWORD)GetProcAddress(module,"WHEELLOSTPACKETS");
 }
 if(getVersion)version=getVersion();
 if(version!=0x0100 || !getStatus || !getDelta || !getLost)++failures;
 if(getStatus)status=getStatus();
 wc.style=0;wc.lpfnWndProc=WndProc;wc.cbClsExtra=0;wc.cbWndExtra=0;
 wc.hInstance=hi;wc.hIcon=NULL;wc.hCursor=LoadCursor(NULL,IDC_ARROW);
 wc.hbrBackground=(HBRUSH)(COLOR_WINDOW+1);wc.lpszMenuName=NULL;
 wc.lpszClassName="Win3WheelDiagnostic";
 if(!RegisterClass(&wc)){logline("FAIL: RegisterClass");_lclose(logFile);return 1;}
 w=CreateWindow(wc.lpszClassName,"Wheel mouse diagnostic",WS_OVERLAPPEDWINDOW,
  0,0,310,160,NULL,NULL,hi,NULL);
 if(!w){logline("FAIL: CreateWindow");_lclose(logFile);return 1;}
 ShowWindow(w,show);UpdateWindow(w);
 while(GetMessage(&msg,NULL,0,0)){TranslateMessage(&msg);DispatchMessage(&msg);}
 if(autoMode)ExitWindows(0,0);
 return msg.wParam;
}
