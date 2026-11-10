; SPDX-License-Identifier: MIT
; Synthetic INT 33h fixture drives the actual linked driver on an 8086 CPU.
.8086
.model small
.stack 4096
.data
extrn active:byte, backend_status:word, dos_wheel:byte
extrn dec_q_head:byte, dec_q_tail:byte, dec_q_count:byte, dec_lost_word:word
extrn timestamp_table:byte
old33 dd 0
mockVersion dw 0805h
mockVersionResult dw 0024h
mockSig dw 574dh
mockCap dw 1
mockMask dw 0017h
mockProc dd 12345678h
resets dw 0
exchanges dw 0
motionReads dw 0
calls dw 0
lastFlags dw 0
lastX dw 0
lastY dw 0
lastCount dw 0
lastExtra dw 0
fails dw 0
step dw 0
wheel dw 0
wanted dw 0
sum dw 0
pieces dw 0
savedFlags dw 0
initialTick dw 0
passMsg db 'PASS native driver: detect, lifecycle, motion, wheel, age, overflow, registers',13,10,'$'
failMsg db 'FAIL native driver, assertion step ','$'
hexbuf db '0000',13,10,'$'
.code
extrn Enable:far, Disable:far, WheelReadDelta:far, WheelReadDeltaAge:far
extrn WheelApiVersion:far, WheelLostPackets:far, WheelStatus:far
extrn dos_callback:far, dos_detect:near, dec_reset:near
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
 push ax
 push bx
 push cx
 push dx
 push si
 push di
 mov dx,offset failMsg
 mov ah,9
 int 21h
 mov ax,step
 mov di,offset hexbuf+3
 mov cx,4
bad_digit:
 mov bx,ax
 and bx,15
 mov dl,bl
 add dl,'0'
 cmp dl,'9'
 jbe bad_store
 add dl,7
bad_store:
 mov [di],dl
 dec di
 shr ax,1
 shr ax,1
 shr ax,1
 shr ax,1
 loop bad_digit
 mov dx,offset hexbuf
 mov ah,9
 int 21h
 pop di
 pop si
 pop dx
 pop cx
 pop bx
 pop ax
 ret
bad endp

mock33 proc far
 push ds
 push bp
 mov bp,sp
 push ax
 mov ax,@data
 mov ds,ax
 pop ax
 cmp ax,0024h
 jne mock_wheel
 mov bx,mockVersion
 mov ax,mockVersionResult
 jmp short mock_done
mock_wheel:
 cmp ax,0011h
 jne mock_exchange
 mov ax,mockSig
 mov cx,mockCap
 jmp short mock_done
mock_exchange:
 cmp ax,0014h
 jne mock_read
 inc exchanges
 xchg cx,mockMask
 xchg dx,word ptr mockProc
 push ax
 mov ax,es
 xchg ax,word ptr mockProc+2
 mov es,ax
 pop ax
 jmp short mock_done
mock_read:
 cmp ax,000bh
 jne mock_reset
 inc motionReads
 xor cx,cx
 xor dx,dx
 jmp short mock_done
mock_reset:
 or ax,ax
 jnz mock_done
 inc resets
mock_done:
 pop bp
 pop ds
 iret
mock33 endp

MouseEvent proc far
 inc calls
 mov lastFlags,ax
 mov lastX,bx
 mov lastY,cx
 mov lastCount,dx
 mov lastExtra,si
 or lastExtra,di
 ; Deliberately clobber volatile/callee registers and enable interrupts/DF.
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

enable_test proc near
 push cs
 mov ax,offset MouseEvent
 push ax
 call Enable
 ret
enable_test endp

; Input callback AX/BX/SI/DI. Check every register and flags survives.
feed proc near
 push ax
 push bx
 push cx
 push dx
 push si
 push di
 push bp
 push es
 mov cx,0abcch
 mov dx,0defdh
 mov bp,08899h
 pushf
 pop savedFlags
 call dos_callback
 pushf
 pop word ptr cs:returnedFlags
 push ax
 mov ax,ds
 mov word ptr cs:returnedDS,ax
 pop ax
 push ds
 push bp
 mov bp,sp
 ; DS should still be DGROUP even when the Windows callback changed it.
 push ax
 mov ax,@data
 mov ds,ax
 cmp word ptr cs:returnedDS,ax
 je feed_ds
 call bad
feed_ds:
 mov ax,savedFlags
 xor ax,word ptr cs:returnedFlags
 and ax,0601h
 check 0
 pop ax
 cmp ax,[bp+18]
 je feed_ax
 call bad
feed_ax:
 cmp bx,[bp+16]
 je feed_bx
 call bad
feed_bx:
 cmp cx,0abcch
 je feed_cx
 call bad
feed_cx:
 cmp dx,0defdh
 je feed_dx
 call bad
feed_dx:
 cmp si,[bp+10]
 je feed_si
 call bad
feed_si:
 cmp di,[bp+8]
 je feed_di
 call bad
feed_di:
 cmp word ptr [bp],08899h
 je feed_bp
 call bad
feed_bp:
 pop bp
 pop ds
 pop es
 pop bp
 pop di
 pop si
 pop dx
 pop cx
 pop bx
 pop ax
 ret
feed endp
returnedFlags dw 0
returnedDS dw 0

start:
 mov ax,@data
 mov ds,ax
 mov ax,3533h
 int 21h
 mov word ptr old33,bx
 mov word ptr old33+2,es
 push ds
 push cs
 pop ds
 mov dx,offset mock33
 mov ax,2533h
 int 21h
 pop ds
 call dos_detect
 check 1
 mov ax,word ptr dos_wheel
 and ax,255
 check 1
 mov mockSig,0
 call dos_detect
 check 1
 mov al,dos_wheel
 xor ah,ah
 check 0
 mov mockSig,574dh
 mov mockCap,2
 call dos_detect
 check 1
 mov al,dos_wheel
 xor ah,ah
 check 0
 mov mockVersion,0500h
 call dos_detect
 check 2
 call enable_test
 call WheelStatus
 check 8001h
 mov al,active
 xor ah,ah
 check 0
 mov mockVersion,0805h
 mov mockVersionResult,0ffffh
 call dos_detect
 check 2
 mov mockVersionResult,0024h
 mov mockCap,1
 call enable_test
 call WheelStatus
 check 0102h
 mov ax,mockMask
 check 009fh
 mov ax,motionReads
 check 1
 mov ax,exchanges
 check 1
 call enable_test
 mov ax,exchanges
 check 1
 call WheelApiVersion
 check 0100h
 ; Signed cumulative coordinates, followed by a wheel-only event.
 mov ax,3
 xor bx,bx
 mov si,10
 mov di,-4
 call feed
 mov ax,lastX
 check 10
 mov ax,lastY
 check -4
 mov ax,lastFlags
 check 3
 mov ax,lastCount
 check 2
 mov ax,lastExtra
 check 0
 mov ax,0080h
 mov bx,0100h
 call feed
 mov ax,calls
 check 1
 call WheelReadDelta
 check 1
 call WheelReadDelta
 check 0
 mov ax,1
 xor bx,bx
 mov si,12
 mov di,-9
 call feed
 mov ax,lastX
 check 2
 mov ax,lastY
 check -5
 ; Signed modulo wrap: baseline 32760 then -32760 gives +16.
 mov si,32760
 mov di,0
 mov ax,1
 call feed
 mov si,-32760
 mov ax,1
 call feed
 mov ax,lastX
 check 16
 ; All signed byte wheel values; sum and chunk range must be exact.
 mov wheel,-128
wheel_loop:
 mov bx,wheel
 mov bh,bl
 xor bl,bl
 mov ax,0080h
 call feed
 mov sum,0
 mov pieces,0
wheel_read:
 call WheelReadDelta
 or ax,ax
 jz wheel_compare
 cmp ax,-8
 jge wheel_low
 call bad
wheel_low:
 cmp ax,7
 jle wheel_high
 call bad
wheel_high:
 add sum,ax
 inc pieces
 cmp pieces,19
 jbe wheel_read
 call bad
wheel_compare:
 mov ax,sum
 cmp ax,wheel
 je wheel_correct
 call bad
wheel_correct:
 inc wheel
 cmp wheel,128
 jne wheel_loop
 ; Ring overflow drops newest, saturates, preserves queued order.
 call dec_reset
 mov cx,31
fill_loop:
 push cx
 mov bx,0100h
 mov ax,0080h
 call feed
 pop cx
 loop fill_loop
 mov bx,0ff00h
 mov ax,0080h
 call feed
 call WheelLostPackets
 check 1
 mov dec_lost_word,0ffffh
 mov bx,0100h
 mov ax,0080h
 call feed
 call WheelLostPackets
 check 0ffffh
 mov cx,31
empty_loop:
 push cx
 call WheelReadDelta
 check 1
 pop cx
 loop empty_loop
 call WheelReadDelta
 check 0
 ; Timestamp age of freshly queued event, then empty/unknown sentinel.
 call dec_reset
 mov bx,0100h
 mov ax,0080h
 call feed
 call WheelReadDeltaAge
 check 1
 mov ax,dx
 cmp ax,2
 jbe age_fresh
 call bad
age_fresh:
 call WheelReadDeltaAge
 check 0
 mov ax,dx
 check 0ffffh
 call Disable
 call WheelStatus
 check 0
 mov ax,mockMask
 check 0017h
 mov ax,word ptr mockProc
 check 5678h
 mov ax,word ptr mockProc+2
 check 1234h
 mov ax,exchanges
 check 2
 call Disable
 mov ax,exchanges
 check 2
 mov ax,resets
 check 0
 mov ax,motionReads
 check 1
 ; No advertised wheel: mask bit 7 absent and BH ignored.
 mov mockCap,0
 call enable_test
 mov ax,mockMask
 check 001fh
 call WheelStatus
 check 2
 mov bx,0100h
 mov ax,0080h
 xor si,si
 xor di,di
 call feed
 call WheelReadDelta
 check 0
 call Disable
 ; Exercise the actual serial UART/IRQ path using emulated COM1 loopback.
 ; The test must run only in a disposable emulator, not on real hardware.
 push ds
 xor ax,ax
 mov ds,ax
 xor dx,dx
 mov ax,2533h
 int 21h
 pop ds
 call enable_test
 call WheelStatus
 check 0101h
 mov calls,0
 mov lastExtra,0ffffh
 mov dx,03fch
 mov al,01bh
 out dx,al
 mov al,040h
 call send_serial
 mov al,1
 call send_serial
 mov al,0
 call send_serial
 mov al,1
 call send_serial
 mov ax,calls
 check 1
 mov ax,lastX
 check 1
 mov ax,lastY
 check 0
 mov ax,lastExtra
 check 0
 call WheelReadDelta
 check 1
 call Disable
 ; Restore original INT33 vector even after assertion failures.
 push ds
 lds dx,old33
 mov ax,2533h
 int 21h
 pop ds
 cmp fails,0
 jne failed
 mov dx,offset passMsg
 mov ah,9
 int 21h
 mov ax,4c00h
 int 21h
failed:
 mov ax,4c01h
 int 21h
; Wait for an empty transmitter, write one byte and allow receive IRQ time.
send_serial proc near
 push ax
 mov cx,0ffffh
 mov dx,03fdh
serial_wait:
 in al,dx
 test al,20h
 jnz serial_send
 loop serial_wait
 call bad
serial_send:
 pop ax
 mov dx,03f8h
 out dx,al
 push es
 mov ax,40h
 mov es,ax
 mov bx,es:[6ch]
serial_delay:
 cmp bx,es:[6ch]
 je serial_delay
 pop es
 ret
send_serial endp
end start
