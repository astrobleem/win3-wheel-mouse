; SPDX-License-Identifier: MIT
; EMULATOR ONLY: direct-driver refusals and retry recovery on AT AUX hardware.
.8086
.model small
.stack 4096
.data
extrn active:byte
old33 dd 0
oldirq dd 0
oldpic1 db 0
oldpic2 db 0
savedctrl db 0
stubcalls dw 0
checks dw 0
fails dw 0
firstfail dw 0
firstactual dw 0
passmsg db 'PASS PS2 refusal/retry checks ', '$'
failmsg db 'FAIL PS2 refusal/retry checks ', '$'
firstmsg db ' first failure ', '$'
actualmsg db ' actual AX ', '$'
hexbuf db '0000',13,10,'$'
.code
extrn Enable:far, Disable:far, WheelStatus:far
check macro value
 local okay
 inc checks
 cmp ax,value
 je okay
 call bad
okay:
endm
bad proc near
 inc fails
 cmp firstfail,0
 jne bad_done
 mov firstactual,ax
 push ax
 mov ax,checks
 mov firstfail,ax
 pop ax
bad_done:
 ret
bad endp
resident proc far
 ; A non-IRET first opcode means resident, but it must never be called.
 push ax
 inc stubcalls
 pop ax
 iret
resident endp
MouseEvent proc far
 retf
MouseEvent endp
; Waits are bounded, preserve command AL and flag failures as setup failures.
wait_input proc near
 push ax
 push cx
 mov cx,0ffffh
input_poll:
 in al,64h
 test al,2
 jz input_ready
 loop input_poll
 call bad
input_ready:
 pop cx
 pop ax
 ret
wait_input endp
ctl proc near
 call wait_input
 out 64h,al
 call wait_input
 ret
ctl endp
data_out proc near
 call wait_input
 out 60h,al
 call wait_input
 ret
data_out endp
wait_output proc near
 push cx
 mov cx,0ffffh
output_poll:
 in al,64h
 test al,1
 jnz output_ready
 loop output_poll
 call bad
output_ready:
 pop cx
 ret
wait_output endp
invoke_enable proc near
 push cs
 mov ax,offset MouseEvent
 push ax
 call Enable
 ret
invoke_enable endp
; Check unchanged IRQ12 vector and entire PIC masks after each refusal.
check_untouched proc near
 push es
 xor ax,ax
 mov es,ax
 mov ax,es:[1d0h]
 mov dx,word ptr oldirq
 check dx
 mov ax,es:[1d2h]
 mov dx,word ptr oldirq+2
 check dx
 xor ax,ax
 in al,21h
 xor dx,dx
 mov dl,oldpic1
 check dx
 xor ax,ax
 in al,0a1h
 mov dl,oldpic2
 check dx
 xor ax,ax
 mov al,active
 check 0
 pop es
 ret
check_untouched endp
print_hex proc near
 mov di,offset hexbuf+3
 mov cx,4
hex_next:
 mov bx,ax
 and bx,15
 add bl,'0'
 cmp bl,'9'
 jbe hex_store
 add bl,7
hex_store:
 mov [di],bl
 dec di
 shr ax,1
 shr ax,1
 shr ax,1
 shr ax,1
 loop hex_next
 mov dx,offset hexbuf
 mov ah,9
 int 21h
 ret
print_hex endp
start:
 mov ax,@data
 mov ds,ax
 pushf
 cli
 xor ax,ax
 mov es,ax
 mov ax,es:[0cch]
 mov word ptr old33,ax
 mov ax,es:[0ceh]
 mov word ptr old33+2,ax
 mov ax,es:[1d0h]
 mov word ptr oldirq,ax
 mov ax,es:[1d2h]
 mov word ptr oldirq+2,ax
 in al,21h
 mov oldpic1,al
 in al,0a1h
 mov oldpic2,al
 ; Snapshot controller byte before the fixture changes AUX enable state.
 mov al,20h
 call ctl
 call wait_output
 in al,60h
 mov savedctrl,al
 ; Native fixture requires keyboard on, AUX off at startup.
 and ax,30h
 check 20h
 ; Install a real non-IRET INT33 stub: direct driver must refuse without calls.
 mov word ptr es:[0cch],offset resident
 mov ax,cs
 mov es:[0ceh],ax
 call invoke_enable
 call WheelStatus
 check 8007h
 mov ax,stubcalls
 check 0
 call check_untouched
 ; Remove INT33 for the remaining direct-port tests.
 xor ax,ax
 mov es,ax
 mov es:[0cch],ax
 mov es:[0ceh],ax
 ; Inject keyboard data while IF=0 so BIOS cannot consume it.
 mov al,0d2h
 call ctl
 mov al,1eh
 call data_out
 call wait_output
 and ax,21h
 check 1
 call invoke_enable
 call WheelStatus
 check 8004h
 call check_untouched
 ; Reading status does not consume data; OBF must still be keyboard data.
 in al,64h
 xor ah,ah
 and ax,21h
 check 1
 in al,60h
 xor ah,ah
 check 1eh
 ; AUX already enabled: refusal must not touch the vector or either PIC.
 mov al,0a8h
 call ctl
 call invoke_enable
 call WheelStatus
 check 8004h
 call check_untouched
 mov al,20h
 call ctl
 call wait_output
 in al,60h
 xor ah,ah
 and ax,30h
 check 0
 ; Reestablish the baseline, then retry must succeed after both refusals.
 mov al,60h
 call ctl
 mov al,savedctrl
 call data_out
 in al,64h
 xor ah,ah
 and ax,1
 check 0
 mov al,20h
 call ctl
 call wait_output
 in al,60h
 xor ah,ah
 and ax,30h
 check 20h
 call invoke_enable
 call WheelStatus
 and ax,0feffh
 check 3
 xor ax,ax
 mov al,active
 check 3
 call Disable
 call WheelStatus
 check 0
 call check_untouched
 ; Restore fixture-owned state before restoring IF or printing via DOS.
 mov al,60h
 call ctl
 mov al,savedctrl
 call data_out
 xor ax,ax
 mov es,ax
 mov ax,word ptr old33
 mov es:[0cch],ax
 mov ax,word ptr old33+2
 mov es:[0ceh],ax
 popf
 mov dx,offset passmsg
 cmp fails,0
 je print_result
 mov dx,offset failmsg
print_result:
 mov ah,9
 int 21h
 mov ax,checks
 call print_hex
 cmp fails,0
 je exit_ok
 mov dx,offset firstmsg
 mov ah,9
 int 21h
 mov ax,firstfail
 call print_hex
 mov dx,offset actualmsg
 mov ah,9
 int 21h
 mov ax,firstactual
 call print_hex
 mov ax,4c01h
 int 21h
exit_ok:
 mov ax,4c00h
 int 21h
end start
