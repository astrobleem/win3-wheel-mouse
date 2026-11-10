; SPDX-License-Identifier: MIT
; EMULATOR ONLY. Exercises actual 8042 commands, IRQ12 and driver lifecycle.
; Use DOSBox-X with INT33 disabled, AT controller, AUX device present.
.8086
.model small
.stack 4096
.data
extrn active:byte, backend_status:word, ps2_wheel:byte
oldirq dd 0
old33 dd 0
oldpic1 db 0
oldpic2 db 0
calls dw 0
lastflags dw 0
lastx dw 0
lasty dw 0
extra dw 0
actual dw 0
fails dw 0
step dw 0
cycles dw 0
wantwheel dw 0
passmsg db 'PASS PS2 hardware lifecycle/IRQ12',13,10,'$'
failmsg db 'FAIL PS2 hardware actual AX ','$'
hexbuf db '0000',13,10,'$'
.code
extrn Enable:far, Disable:far, WheelStatus:far, WheelReadDelta:far
extrn MouseGetIntVect:far
check macro value
 local okay
 inc step
 cmp ax,value
 je okay
 call bad
okay:
endm
bad proc near
 inc fails
 mov actual,ax
 push ax
 push bx
 push cx
 push dx
 push di
 mov dx,offset failmsg
 mov ah,9
 int 21h
 mov ax,actual
 mov di,offset hexbuf+3
 mov cx,4
hexloop:
 mov bx,ax
 and bx,15
 add bl,'0'
 cmp bl,'9'
 jbe hexput
 add bl,7
hexput:
 mov [di],bl
 dec di
 shr ax,1
 shr ax,1
 shr ax,1
 shr ax,1
 loop hexloop
 mov dx,offset hexbuf
 mov ah,9
 int 21h
 pop di
 pop dx
 pop cx
 pop bx
 pop ax
 ret
bad endp
MouseEvent proc far
 inc calls
 mov lastflags,ax
 mov lastx,bx
 mov lasty,cx
 mov extra,si
 or extra,di
 cmp dx,2
 je callback_ok
 inc fails
callback_ok:
 ; Real IRQ epilogue must survive an unfriendly Windows callback.
 mov ax,1234h
 mov bx,2345h
 mov cx,3456h
 mov dx,4567h
 mov si,5678h
 mov di,6789h
 mov bp,789ah
 mov ds,ax
 mov es,ax
 std
 sti
 retf
MouseEvent endp
; Inject one AUX byte through the controller, not by calling ps2_feed.
inject proc near
 push ax
 mov cx,0ffffh
waitready:
 in al,64h
 test al,3
 jz outputready
 loop waitready
 call bad
outputready:
 pushf
 cli
 mov al,0d3h
 out 64h,al
 mov cx,0ffffh
waitinput:
 in al,64h
 test al,2
 jz inputready
 loop waitinput
 call bad
inputready:
 popf
 pop ax
 out 60h,al
 push es
 mov ax,40h
 mov es,ax
 mov bx,es:[6ch]
 mov dx,2
inject_tick:
 cmp bx,es:[6ch]
 je inject_tick
 mov bx,es:[6ch]
 dec dx
 jnz inject_tick
 pop es
 ; Allow IRQ12 delivery without changing timer configuration.
 push cx
 mov cx,0ffffh
waitirq:
 in al,64h
 test al,1
 jz irqdone
 loop waitirq
 call bad
irqdone:
 pop cx
 ret
inject endp
start:
 mov ax,@data
 mov ds,ax
 mov ax,3533h
 int 21h
 mov word ptr old33,bx
 mov word ptr old33+2,es
 push ds
 xor ax,ax
 mov ds,ax
 xor dx,dx
 mov ax,2533h
 int 21h
 pop ds
 mov ax,3574h
 int 21h
 mov word ptr oldirq,bx
 mov word ptr oldirq+2,es
 in al,21h
 mov oldpic1,al
 in al,0a1h
 mov oldpic2,al
 mov cycles,2
again:
 push cs
 mov ax,offset MouseEvent
 push ax
 call Enable
 call WheelStatus
 mov wantwheel,0
 cmp ax,0103h
 jne standard
 mov wantwheel,1
 jmp short backendok
standard:
 check 3
backendok:
 xor ax,ax
 mov al,active
 check 3
 cmp active,3
 je hwactive
 jmp cleanup
hwactive:
 call MouseGetIntVect
 check 74h
 ; Repeat Enable must not overwrite saved vector or reinitialize controller.
 push cs
 mov ax,offset MouseEvent
 push ax
 call Enable
 mov calls,0
 mov extra,0ffffh
 mov al,09h
 call inject
 mov al,5
 call inject
 mov al,2
 call inject
 cmp wantwheel,0
 je packetdone
 mov al,1
 call inject
packetdone:
 mov ax,calls
 check 1
 mov ax,lastflags
 check 3
 mov ax,lastx
 check 5
 mov ax,lasty
 check -2
 mov ax,extra
 check 0
 call WheelReadDelta
 check wantwheel
 call WheelReadDelta
 check 0
 ; Queue a partial packet before disable; reset must drain it safely.
 mov al,8
 call inject
cleanup:
 call Disable
 call WheelStatus
 check 0
 xor ax,ax
 mov al,active
 check 0
 mov ax,3574h
 int 21h
 mov ax,bx
 mov dx,word ptr oldirq
 check dx
 mov ax,es
 mov dx,word ptr oldirq+2
 check dx
 in al,21h
 and al,4
 mov ah,oldpic1
 and ah,4
 cmp al,ah
 je pic1ok
 call bad
pic1ok:
 in al,0a1h
 and al,10h
 mov ah,oldpic2
 and ah,10h
 cmp al,ah
 je pic2ok
 call bad
pic2ok:
 call Disable
 call WheelStatus
 check 0
 dec cycles
 jz finished
 jmp again
finished:
 push ds
 lds dx,old33
 mov ax,2533h
 int 21h
 pop ds
 cmp fails,0
 jne failed
 mov dx,offset passmsg
 mov ah,9
 int 21h
 mov ax,4c00h
 int 21h
failed:
 mov ax,4c01h
 int 21h
end start
