/*
Usage in VIM:
On MSWin (use MinGW gcc to build):
make
(put the .dll in the search path) 
:echo libcall('vgdbc.dll', 'tcpcall', 'test')
(show "OK" if successful)

On Linux:
make -f Makefile.linux
put the .so in the lib path, e.g. /lib64 or /usr/lib64, OR set LD_LIBRARY_PATH path:
$ export LD_LIBRARY_PATH={libvgdbc.so path}
then run it in VIM:
:echo libcall('libvgdbc.so', 'tcpcall', 'test')
*/
#ifdef _WINDOWS
 #include <windows.h>
#else // _LINUX
 #include <unistd.h>
 #include <sys/types.h>
 #include <sys/socket.h>
 #include <sys/ioctl.h>
 #include <arpa/inet.h>
 //#define __USE_GNU
 #include <dlfcn.h>

 typedef struct sockaddr_in SOCKADDR_IN;
 typedef struct sockaddr SOCKADDR;
 typedef int SOCKET;
 #define closesocket(x) close(x)
 #define WSACleanup()

 #define SOCKET_ERROR -1
#endif

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/*
for VIM libcall/libcallnr.
Limitation:
1. cannot access VIM var or envvar
2. each call is stateless (VIM load it, exec it and then unload), cannot store state in global vars.
*/

#define ERR_RET(eno, estr) do {sprintf(RETBUF, "VGdbc Error [%d]: %s", eno, estr); return RETBUF;} while (0)

void *g_hModule;

static int BUFLEN = 4000;
static char *RETBUF;

struct InitLib 
{
	InitLib();
	~InitLib();
} g_initobj;

InitLib::InitLib() 
{
	if (RETBUF == NULL)
	{
#ifdef _WINDOWS
		g_hModule = LoadLibrary("vgdbc.dll");
#else // _LINUX
		Dl_info di;
		if (dladdr(RETBUF, &di)) {
			g_hModule = dlopen(di.dli_fname, RTLD_LAZY);
		}
#endif
		RETBUF = (char*)malloc(BUFLEN);
	}
}

InitLib::~InitLib() 
{
	free(RETBUF);
}

extern "C" {

const char *test(const char *cmd)
{
	static char lastcmd[100];
	char *portstr = getenv("VGDB_PORT");
	sprintf(RETBUF, "%s OK. $VGDB_PORT=%s. last test='%s'", cmd, portstr, lastcmd);
	strncpy(lastcmd, cmd, 100);
	return RETBUF;
}

const char *tcpcall(const char *cmd)
{
	int VGDB_PORT = 30899;
	SOCKET SOCK;

	int ret;
	strcpy(RETBUF, "OK");

#ifdef _WINDOWS
	WSADATA wsaData;
	WORD wVersionRequested = MAKEWORD(2, 2);
	
	ret = WSAStartup(wVersionRequested, &wsaData);
	if (ret != 0) 
	{
		ERR_RET(-1, "WSAStartup");
	}
#endif

	SOCK = socket(AF_INET, SOCK_STREAM, 0);
	if (SOCK < 0)
	{
		WSACleanup();
		ERR_RET(-1, "fail to create socket");
	}
	char *portstr = getenv("VGDB_PORT");
	if (portstr != NULL) {
		int port = atoi(portstr);
		if (port > 0) {
			VGDB_PORT = port;
		}
	}

	SOCKADDR_IN addrSrv;
	addrSrv.sin_addr.s_addr = inet_addr("127.0.0.1");
	addrSrv.sin_family = AF_INET;
	addrSrv.sin_port = htons(VGDB_PORT);

	ret = connect(SOCK, (SOCKADDR*)&addrSrv, sizeof(SOCKADDR));
	if (SOCKET_ERROR == ret)
	{
		closesocket(SOCK);
		WSACleanup();
		ERR_RET(ret, "fail to connect VGdb.");
	}
	sprintf(RETBUF, "%s\n", cmd);
	ret = send(SOCK, RETBUF, strlen(RETBUF), 0);
	if (SOCKET_ERROR == ret)
	{
		closesocket(SOCK);
		WSACleanup();
		ERR_RET(ret, "fail to send cmd");
	}

	int cnt = 0;
	char *p = RETBUF;
	int totalcnt = 0;
	while (1) {
		cnt=recv(SOCK, p, BUFLEN-totalcnt-1, 0);
		if (cnt <= 0)
			break;
		p += cnt;
		totalcnt += cnt;
		if (BUFLEN <= totalcnt+1) {
			char *tmpbuf = (char*)realloc(RETBUF, BUFLEN <<1);
			if (tmpbuf == NULL) {
				while (recv(SOCK, RETBUF-100, 100, 0) > 0); // clear the send buf of the server.
				strcpy(RETBUF-100, " ... (too long)\n");
				break;
			}
			RETBUF = tmpbuf;
			p = RETBUF +BUFLEN-1;
			BUFLEN <<=1;
		}
	}
	if (totalcnt >= 0)
		RETBUF[totalcnt] = 0;
	closesocket(SOCK);
	WSACleanup();
	return RETBUF;
}

} // extern "C"

int main(int argc, char *argv[])
{
	if (argc <= 1) {
		printf("Usage: %s {gdbcmd}\n", argv[0]);
		return -1;
	}
	const char *ret = tcpcall(argv[1]);
	printf("%s\n", ret);
	return 0;
}

