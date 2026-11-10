; SPDX-License-Identifier: MIT
; WHEELCHK - first-party DOS INT 33h wheel capability diagnostic.
; MASM 5.1, LINK4.EXE; 8086 instructions only. No reset or callback install.
.8086
.MODEL SMALL
.STACK 256
.DATA
banner DB 'WHEELCHK 1.0 - DOS INT 33h wheel diagnostic',13,10,'$'
vectorMsg DB 'INT 33h vector: $'
versionMsg DB 'AX=0024h version BX (major/minor hex): $'
capsMsg DB 'AX=0011h reply AX / CX (hex): $'
noDriver DB 'No usable INT 33h vector (null or IRET). No driver calls made.',13,10,'$'
oldDriver DB 'Version below 6.00 or unavailable. Wheel query skipped for safety.',13,10,'$'
noWheel DB 'Wheel not advertised (requires AX=574Dh and CX bit 0). No polling.',13,10,'$'
yesWheel DB 'Wheel advertised. This alone does not prove physical wheel delivery.',13,10,'$'
quietMsg DB 'Capabilities-only mode: no wheel counters read.',13,10,'$'
pollMsg DB 'Roll the wheel now. Any key exits; timeout is about 30 seconds.',13,10
        DB 'Each line is signed BH from AX=0003h; zero polls are omitted.',13,10,'$'
deltaMsg DB 'Wheel delta: $'
doneMsg DB 'Finished. Nonzero samples (hex): $'
usageMsg DB 'Usage: WHEELCHK [ /Q ]  (/Q = capabilities only)',13,10,'$'
crlf DB 13,10,'$'
sep DB ' / $'
quiet DB 0
version DW 0
versionAX DW 0
capsAX DW 0
capsCX DW 0
startTick DW 0
samples DW 0
.CODE
start:
        mov ax,@data
        mov ds,ax
; ES initially addresses PSP. Accept no option, or exactly /Q (case-insensitive).
        xor cx,cx
        mov cl,es:[80h]
        mov si,81h
skipSpace:
        jcxz argsDone
        mov al,es:[si]
        cmp al,' '
        jne haveArg
        inc si
        loop skipSpace
haveArg:
        cmp cx,2
        jb argError
        cmp BYTE PTR es:[si],'/'
        jne argError
        mov al,es:[si+1]
        and al,0DFh
        cmp al,'Q'
        jne argError
        mov quiet,1
        add si,2
        sub cx,2
trailSpace:
        jcxz argsDone
        cmp BYTE PTR es:[si],' '
        jne argError
        inc si
        loop trailSpace
        jmp SHORT argsDone
argError:
        jmp badArgs
argsDone:
        mov dx,OFFSET banner
        call puts
        mov ax,3533h
        int 21h
        mov ax,es
        or ax,bx
        jnz checkOpcode
        jmp missing
checkOpcode:
        cmp BYTE PTR es:[bx],0CFh
        jne vectorOkay
        jmp missing
vectorOkay:
        push bx
        push es
        mov dx,OFFSET vectorMsg
        call puts
        pop ax
        call hexWord
        mov dl,':'
        call putchar
        pop ax
        call hexWord
        call newline
; 0024h is a version query on 6.0+ drivers. Unsupported calls generally
; leave registers unchanged; zero BX first so they fail the safety gate.
        mov ax,24h
        xor bx,bx
        xor cx,cx
        xor dx,dx
        call mouse
        mov versionAX,ax
        mov version,bx
        mov dx,OFFSET versionMsg
        call puts
        mov ax,version
        call hexWord
        call newline
        cmp versionAX,0FFFFh
        je versionBad
        cmp version,0600h
        jae queryWheel
versionBad:
        mov dx,OFFSET oldDriver
        call puts
        mov al,2
        jmp terminate
queryWheel:
; On some old drivers 0011h has unrelated semantics: hence version gate.
        mov ax,11h
        xor bx,bx
        xor cx,cx
        xor dx,dx
        call mouse
        mov capsAX,ax
        mov capsCX,cx
        mov dx,OFFSET capsMsg
        call puts
        mov ax,capsAX
        call hexWord
        mov dx,OFFSET sep
        call puts
        mov ax,capsCX
        call hexWord
        call newline
        cmp capsAX,574Dh
        jne unsupported
        test capsCX,1
        jz unsupported
        mov dx,OFFSET yesWheel
        call puts
        cmp quiet,0
        je beginPoll
        mov dx,OFFSET quietMsg
        call puts
        xor al,al
        jmp terminate
beginPoll:
        mov dx,OFFSET pollMsg
        call puts
        xor ah,ah
        int 1Ah
        mov startTick,dx
poll:
        mov ah,1
        int 16h
        jnz keyExit
        xor ah,ah
        int 1Ah
        sub dx,startTick
        cmp dx,546
        jae finish
        mov ax,3
        xor bx,bx
        call mouse
        or bh,bh
        jz poll
        inc samples
        mov al,bh
        cbw
        push ax
        mov dx,OFFSET deltaMsg
        call puts
        pop ax
        call signedDecimal
        call newline
        jmp poll
keyExit:
        xor ah,ah
        int 16h
finish:
        mov dx,OFFSET doneMsg
        call puts
        mov ax,samples
        call hexWord
        call newline
        xor al,al
        jmp terminate
unsupported:
        mov dx,OFFSET noWheel
        call puts
        mov al,3
        jmp terminate
missing:
        mov dx,OFFSET noDriver
        call puts
        mov al,1
        jmp terminate
badArgs:
        mov dx,OFFSET usageMsg
        call puts
        mov al,4
terminate:
        mov ah,4Ch
        int 21h

mouse PROC NEAR
        push ds
        push es
        push bp
        push si
        push di
        int 33h
        pop di
        pop si
        pop bp
        pop es
        pop ds
        ret
mouse ENDP
puts PROC NEAR
        push ax
        mov ah,9
        int 21h
        pop ax
        ret
puts ENDP
putchar PROC NEAR
        push ax
        mov ah,2
        int 21h
        pop ax
        ret
putchar ENDP
newline PROC NEAR
        push dx
        mov dx,OFFSET crlf
        call puts
        pop dx
        ret
newline ENDP
hexWord PROC NEAR
        push ax
        push bx
        push cx
        push dx
        mov bx,ax
        mov cx,4
hexLoop:
        push cx
        mov cl,4
        rol bx,cl
        mov dl,bl
        and dl,0Fh
        add dl,'0'
        cmp dl,'9'
        jbe hexDigit
        add dl,7
hexDigit:
        call putchar
        pop cx
        loop hexLoop
        pop dx
        pop cx
        pop bx
        pop ax
        ret
hexWord ENDP
signedDecimal PROC NEAR
        push ax
        push bx
        push cx
        push dx
        mov dl,'+'
        or ax,ax
        jns signReady
        neg ax
        mov dl,'-'
signReady:
        call putchar
        mov bx,10
        xor cx,cx
splitDigit:
        xor dx,dx
        div bx
        push dx
        inc cx
        or ax,ax
        jnz splitDigit
emitDigit:
        pop dx
        add dl,'0'
        call putchar
        loop emitDigit
        pop dx
        pop cx
        pop bx
        pop ax
        ret
signedDecimal ENDP
END start
