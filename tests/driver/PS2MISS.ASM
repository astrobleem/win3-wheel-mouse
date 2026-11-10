; SPDX-License-Identifier: MIT
; EMULATOR ONLY: bounded initialization with missing AUX hardware/device.
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
reported dw 0
forceflag dw 0
oldequipment dw 0
statusmsg db ' backend status (8006 = cleanup failure) ', '$'
checks dw 0
fails dw 0
firstfail dw 0
firstactual dw 0
passmsg db 'PASS PS2 missing-device checks ', '$'
failmsg db 'FAIL PS2 missing-device checks ', '$'
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
 ; DOS PSP ES command tail: exact uppercase /FORCE switch for this fixture.
 cmp byte ptr es:[80h],7
 jb no_force
 cmp word ptr es:[81h],2f20h
 jne no_force
 cmp word ptr es:[83h],4f46h
 jne no_force
 cmp word ptr es:[85h],4352h
 jne no_force
 cmp byte ptr es:[87h],45h
 jne no_force
 mov forceflag,1
no_force:
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
 xor ax,ax
 mov es:[0cch],ax
 mov es:[0ceh],ax
 push es
 mov ax,40h
 mov es,ax
 mov ax,es:[10h]
 mov oldequipment,ax
 cmp forceflag,0
 je equipment_ready
 or word ptr es:[10h],4
equipment_ready:
 pop es
 call invoke_enable
 ; Restore BIOS equipment before examining the result or running cleanup.
 push es
 mov ax,40h
 mov es,ax
 mov ax,oldequipment
 mov es:[10h],ax
 pop es
 call WheelStatus
 mov reported,ax
 inc checks
 cmp forceflag,0
 jne require_late_failure
 cmp ax,8003h
 je status_ok
require_late_failure:
 cmp ax,8005h
 je status_ok
 cmp ax,8006h
 je status_ok
 call bad
status_ok:
 call check_untouched
 ; 8003 rejects before port I/O. DOSBox-X aux=false does not implement
 ; the controller20h query, so do not touch absent hardware in that case.
 cmp reported,8003h
 je keyboard_done
 ; After command/cleanup failure verify keyboard inhibit bit is clear.
 mov al,20h
 call ctl
 call wait_output
 in al,60h
 xor ah,ah
 and ax,10h
 check 0
keyboard_done:
 ; Release any unexpectedly active transport before restoring fixture state.
 call Disable
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
 mov dx,offset statusmsg
 mov ah,9
 int 21h
 mov ax,reported
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
