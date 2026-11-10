; Synthetic emulator-only fixture. Never ship or run on a real DOS installation.
.8086
CODE SEGMENT
ASSUME CS:CODE,DS:CODE
ORG 100h
start: jmp setup
mode DB 0
index DB 0
values DB 1,255,127,128
handler:
        cmp ax,24h
        jne capability
        mov bx,0600h
        cmp BYTE PTR cs:mode,'F'
        jne versionNormal
        mov ax,0FFFFh
        iret
versionNormal:
        cmp BYTE PTR cs:mode,'O'
        jne handled
        mov bx,0500h
        iret
capability:
        cmp ax,11h
        jne wheel
        mov ax,574Dh
        mov cx,1
        cmp BYTE PTR cs:mode,'S'
        jne flags
        xor ax,ax
flags:
        cmp BYTE PTR cs:mode,'C'
        jne handled
        xor cx,cx
handled: iret
wheel:
        cmp ax,3
        jne handled
        xor bx,bx
        cmp BYTE PTR cs:index,4
        jae handled
        push si
        xor si,si
        mov bl,cs:index
        mov si,bx
        mov bh,cs:values[si]
        xor bl,bl
        inc BYTE PTR cs:index
        pop si
        iret
iretOnly: iret
setup:
        mov si,81h
scanArg:
        lodsb
        cmp al,32
        je scanArg
        mov mode,al
        mov dx,OFFSET handler
        cmp al,'I'
        jne notIret
        mov dx,OFFSET iretOnly
notIret:
        cmp al,'N'
        jne install
        xor dx,dx
        mov ds,dx
install:
        mov ax,2533h
        int 21h
        mov dx,OFFSET setup
        add dx,15
        mov cl,4
        shr dx,cl
        mov ax,3100h
        int 21h
CODE ENDS
END start
