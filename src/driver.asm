; SPDX-License-Identifier: MIT
; Windows XT real-mode serial and DOS INT 33h mouse transports.
; First-party MIT candidate. No DDK macros or runtime objects are linked.
.8086
.model small
ifndef TRANSPORT
TRANSPORT equ 0 ; 0 Auto, 1 explicit serial, 2 DOS only
endif
ifndef SERIALCOM
SERIALCOM equ 1
endif
if SERIALCOM eq 2
COMBASE equ 02f8h
IVTOFF equ 02ch
PICBIT equ 008h
BDAOFF equ 2
IRQNUM equ 11
else
COMBASE equ 03f8h
IVTOFF equ 030h
PICBIT equ 010h
BDAOFF equ 0
IRQNUM equ 12
endif
.data
public active, callback, backend_status
backend_status dw 0
active db 0
callback dd 0
previous_irq dd 0
saved_bda dw 0
saved_pic db 0
saved_lcr db 0
saved_ier db 0
saved_mcr db 0
saved_div dw 0
.code
extrn dos_detect:near, dos_enable:near, dos_disable:near
extrn dec_reset:near, dec_feed:near, dec_read:near, dec_lost:near, dec_q_head:byte, dec_q_tail:byte, dec_q_count:byte, timestamp_table:byte, timestamp_oldhead:byte
public LibMain, Inquire, Enable, Disable, MouseGetIntVect, WEP
public WheelApiVersion, WheelReadDelta, WheelLostPackets, WheelReadDeltaAge, WheelStatus

; Each exported Win16 routine reserves the loader's three-byte DS fixup and
; maintains the far-frame BP marker. This is the platform calling convention.
enter_api macro
 mov ax,ds
 nop
 inc bp
 push bp
 mov bp,sp
 push ds
 mov ds,ax
 push si
 push di
endm
leave_api macro count
 pop di
 pop si
 pop ds
 pop bp
 dec bp
 retf count
endm

LibMain proc far
 mov ax,1
 retf
LibMain endp

Inquire proc far
 enter_api
 push es
 les di,[bp+6]
 mov word ptr es:[di],0ffffh
 mov word ptr es:[di+2],2
 mov word ptr es:[di+4],30
 mov word ptr es:[di+6],2
 mov word ptr es:[di+8],2
 mov word ptr es:[di+10],0
 mov word ptr es:[di+12],0
 pop es
 mov ax,14
 leave_api 4
Inquire endp

Enable proc far
 enter_api
 pushf
 cli
 mov ax,[bp+6]
 mov word ptr callback,ax
 mov ax,[bp+8]
 mov word ptr callback+2,ax
 cmp active,0
 je enable_select
 jmp enable_done
enable_select:
 call dec_reset
 mov backend_status,0
if TRANSPORT ne 1
 push es
 call dos_detect
 pop es
 cmp ax,1
 jne enable_not_dos
 call dos_enable
 jmp enable_done
enable_not_dos:
 cmp ax,0
 je enable_no_dos
 mov backend_status,8001h
 jmp enable_done
enable_no_dos:
if TRANSPORT eq 2
 mov backend_status,8002h
 jmp enable_done
endif
endif
 push es
 xor ax,ax
 mov es,ax
 mov ax,es:[IVTOFF]
 mov word ptr previous_irq,ax
 mov word ptr cs:chain_target,ax
 mov ax,es:[IVTOFF+2]
 mov word ptr previous_irq+2,ax
 mov word ptr cs:chain_target+2,ax
 mov ax,40h
 mov es,ax
 mov ax,es:[BDAOFF]
 mov saved_bda,ax
 mov word ptr es:[BDAOFF],0
 in al,21h
 and al,PICBIT
 mov saved_pic,al
 ; Disable receiver interrupts while saving/divisor programming.
 mov dx,COMBASE+3
 in al,dx
 mov saved_lcr,al
 and al,7fh
 out dx,al
 mov dx,COMBASE+1
 in al,dx
 mov saved_ier,al
 xor al,al
 out dx,al
 mov dx,COMBASE+4
 in al,dx
 mov saved_mcr,al
 xor al,al
 out dx,al
 mov dx,COMBASE+3
 mov al,82h
 out dx,al
 mov dx,COMBASE
 in al,dx
 mov byte ptr saved_div,al
 mov al,60h
 out dx,al
 inc dx
 in al,dx
 mov byte ptr saved_div+1,al
 xor al,al
 out dx,al
 mov dx,COMBASE+3
 mov al,2
 out dx,al
 call dec_reset
 xor ax,ax
 mov es,ax
 mov word ptr es:[IVTOFF],offset irq4_entry
 mov ax,cs
 mov es:[IVTOFF+2],ax
 mov active,1
 mov backend_status,0101h
 mov cx,5000
enable_delay:
 loop enable_delay
 mov dx,COMBASE+4
 mov al,0bh
 out dx,al
 mov dx,COMBASE+1
 mov al,1
 out dx,al
 in al,21h
 and al,0ffh-PICBIT
 out 21h,al
 pop es
enable_done:
 popf
 leave_api 4
Enable endp

Disable proc far
 enter_api
 pushf
 cli
 cmp active,0
 jne disable_active
 jmp disable_done
disable_active:
 cmp active,2
 jne disable_serial
 call dos_disable
 call dec_reset
 mov backend_status,0
 jmp disable_done
disable_serial:
 push es
 mov dx,COMBASE+3
 mov al,2
 out dx,al
 mov dx,COMBASE+1
 xor al,al
 out dx,al
 in al,21h
 or al,PICBIT
 out 21h,al
 xor ax,ax
 mov es,ax
 mov ax,word ptr previous_irq
 mov es:[IVTOFF],ax
 mov ax,word ptr previous_irq+2
 mov es:[IVTOFF+2],ax
 mov dx,COMBASE+3
 mov al,82h
 out dx,al
 mov dx,COMBASE
 mov al,byte ptr saved_div
 out dx,al
 inc dx
 mov al,byte ptr saved_div+1
 out dx,al
 mov dx,COMBASE+3
 mov al,saved_lcr
 and al,7fh
 out dx,al
 mov dx,COMBASE+4
 mov al,saved_mcr
 out dx,al
 mov dx,COMBASE+1
 mov al,saved_ier
 out dx,al
 mov dx,COMBASE+3
 mov al,saved_lcr
 out dx,al
 mov ax,40h
 mov es,ax
 mov ax,saved_bda
 mov es:[BDAOFF],ax
 in al,21h
 and al,0ffh-PICBIT
 or al,saved_pic
 out 21h,al
 mov active,0
 mov backend_status,0
 call dec_reset
 pop es
disable_done:
 popf
 leave_api 0
Disable endp

MouseGetIntVect proc far
 enter_api
 mov ax,0ffffh
 test backend_status,8000h
 jnz vector_done
 mov ax,IRQNUM
 cmp active,2
 jne vector_done
 mov ax,33h
vector_done:
 leave_api 0
MouseGetIntVect endp

WheelApiVersion proc far
 enter_api
 mov ax,0100h
 leave_api 0
WheelApiVersion endp

WheelReadDelta proc far
 enter_api
 push bx
 pushf
 cli
 xor ax,ax
 cmp active,0
 je read_done
 call dec_read
read_done:
 popf
 pop bx
 leave_api 0
WheelReadDelta endp

WheelLostPackets proc far
 enter_api
 pushf
 cli
 call dec_lost
 popf
 leave_api 0
WheelLostPackets endp

WEP proc far
 enter_api
 call Disable
 mov ax,1
 leave_api 2
WEP endp

; IRQ4 is exclusive to the configured mouse. A spurious/non-UART IRQ chains
; to its previous handler. The real receive path is bounded to 64 samples.
irq4_entry proc far
 push ax
 push bx
 push cx
 push dx
 push si
 push di
 push bp
 push ds
 push es
 cld
 mov ax,DGROUP
 mov ds,ax
 mov dx,COMBASE+2
 in al,dx
 test al,1
 jz irq_ours
 jmp irq_chain
irq_ours:
 mov di,64
irq_next:
 mov dx,COMBASE+5
 in al,dx
 mov ah,al
 test al,1eh
 jnz irq_sample
 test al,1
 jz irq_ack
irq_sample:
 mov dx,COMBASE
 test ah,1
 jz irq_no_byte
 in al,dx
irq_no_byte:
 ; Remember the queue head so the parallel timestamp ring advances only
 ; when dec_feed actually enqueues a wheel event. Overflow leaves it unchanged.
 mov bl,ds:dec_q_head
 mov ds:timestamp_oldhead,bl
 push di
 call dec_feed
 pop di
 ; Preserve decoder result/flags exactly while recording the event's BDA tick.
 pushf
 push ax
 push bx
 push cx
 mov al,ds:dec_q_head
 cmp al,ds:timestamp_oldhead
 je irq_stamp_done
 xor bx,bx
 mov bl,ds:timestamp_oldhead
 shl bx,1
 shl bx,1
 push es
 mov ax,40h
 mov es,ax
 mov ax,es:[006ch]
 mov word ptr ds:timestamp_table[bx],ax
 mov ax,es:[006eh]
 mov word ptr ds:timestamp_table[bx+2],ax
 pop es
irq_stamp_done:
 pop cx
 pop bx
 pop ax
 popf
 jnc irq_continue
 cmp active,0
 je irq_continue
 mov dx,2
 xor si,si
 push di
 xor di,di
 push ds
 call dword ptr callback
 cli
 pop ds
 pop di
irq_continue:
 dec di
 jnz irq_next
irq_ack:
 mov al,20h
 out 20h,al
 pop es
 pop ds
 pop bp
 pop di
 pop si
 pop dx
 pop cx
 pop bx
 pop ax
 iret
irq_chain:
 ; Preserve the interrupted register set before a far tail-chain.
 pop es
 pop ds
 pop bp
 pop di
 pop si
 pop dx
 pop cx
 pop bx
 pop ax
 jmp dword ptr cs:chain_target
irq4_entry endp

; Populating a code pointer is only used for the spurious chain. Set by the
; loader relocation to data is unavailable without a register, so the enabled
; driver writes this once while interrupts are disabled.
chain_target dd 0

; Appended after the v1 entry points to keep their code offsets stable.
WheelReadDeltaAge proc far
 enter_api
 push bx
 push cx
 push es
 pushf
 cli
 mov dx,0ffffh
 xor ax,ax
 cmp active,0
 je read_age_done
 cmp byte ptr ds:dec_q_count,0
 je read_age_done
 ; Snapshot the oldest event's 32-bit BIOS tick before consuming it.
 xor bx,bx
 mov bl,ds:dec_q_tail
 shl bx,1
 shl bx,1
 mov si,word ptr ds:timestamp_table[bx]
 mov bx,word ptr ds:timestamp_table[bx+2]
 mov ax,40h
 mov es,ax
 mov cx,es:[006ch]
 mov di,es:[006eh]
 ; Reject midnight/wrapped or otherwise out-of-range current BIOS clock.
 cmp di,0018h
 ja read_age_stale
 jb read_age_compare
 cmp cx,00b0h
 jae read_age_stale
read_age_compare:
 ; Current clock must not precede the enqueue timestamp.
 cmp di,bx
 jb read_age_stale
 ja read_age_subtract
 cmp cx,si
 jb read_age_stale
read_age_subtract:
 sub cx,si
 sbb di,bx
 ; Ages of FFFF ticks or more are intentionally reported as unknown.
 or di,di
 jnz read_age_stale
 cmp cx,0ffffh
 je read_age_stale
 mov dx,cx
 jmp read_age_pop
read_age_stale:
 mov dx,0ffffh
read_age_pop:
 call dec_read
read_age_done:
 popf
 pop es
 pop cx
 pop bx
 leave_api 0
WheelReadDeltaAge endp
WheelStatus proc far
 enter_api
 mov ax,backend_status
 leave_api 0
WheelStatus endp
end LibMain
