; SPDX-License-Identifier: MIT
; DOS mouse adapter. No driver reset, range/ratio change, UART or PIC access.
; Real-mode Microsoft-compatible INT 33h v6.26+ and CuteMouse Wheel API.
.8086
.model small
.data
public dos_wheel, dos_oldmask, dos_oldproc, dos_callback, wheel_enqueue
public dos_detect, dos_enable, dos_disable
extrn active:byte, callback:dword, backend_status:word
extrn dec_q_head:byte, dec_q_count:byte, dec_queue:byte, dec_lost_word:word
extrn timestamp_table:byte
dos_wheel db 0
dos_oldmask dw 0
dos_oldproc dd 0
dos_lastx dw 0
dos_lasty dw 0
.code
; AX=0 absent, 1 compatible, 2 resident but unsupported. No reset.
dos_detect proc near
 push es
 xor ax,ax
 mov es,ax
 les bx,es:[0cch]
 mov ax,es
 or ax,bx
 jz detect_absent
 cmp byte ptr es:[bx],0cfh
 je detect_absent
 mov ax,0024h
 xor bx,bx
 push ds
 int 33h
 pop ds
 cmp ax,0ffffh
 je detect_unknown
 cmp bx,0626h
 jb detect_unknown
 mov dos_wheel,0
 mov ax,0011h
 xor cx,cx
 push ds
 int 33h
 pop ds
 cmp ax,574dh
 jne detect_ready
 test cx,1
 jz detect_ready
 mov dos_wheel,1
detect_ready:
 mov ax,1
 jmp short detect_done
detect_absent:
 xor ax,ax
 jmp short detect_done
detect_unknown:
 mov ax,2
detect_done:
 pop es
 ret
dos_detect endp

; Caller serializes Enable/Disable with CLI and preserves lasting flags.
dos_enable proc near
 push es
 ; Discard pre-Windows motion. AX=0Bh clears mickey counters, not wheel data.
 mov ax,000bh
 push ds
 int 33h
 pop ds
 mov dos_lastx,0
 mov dos_lasty,0
 push cs
 pop es
 mov dx,offset dos_callback
 mov cx,001fh
 mov backend_status,2
 cmp dos_wheel,0
 je enable_mask
 or cx,0080h
 or backend_status,0100h
enable_mask:
 mov active,2
 mov ax,0014h
 push ds
 int 33h
 pop ds
 mov dos_oldmask,cx
 mov word ptr dos_oldproc,dx
 mov word ptr dos_oldproc+2,es
 pop es
 ret
dos_enable endp

dos_disable proc near
 push es
 ; Disable ingress before exchanging, then restore the exact original pair.
 mov active,0
 mov cx,dos_oldmask
 les dx,dos_oldproc
 mov ax,0014h
 push ds
 int 33h
 pop ds
 pop es
 ret
dos_disable endp

; AX is a signed wheel count, -128..127. Split it into legacy API chunks.
; Only a successfully inserted chunk gets a timestamp. Drop-newest overflow
; counts lost chunks (saturating), while maintaining event order and direction.
wheel_enqueue proc near
 push es
 mov si,ax
 mov ax,40h
 mov es,ax
enqueue_next:
 or si,si
 jz enqueue_done
 mov ax,si
 cmp ax,7
 jle enqueue_negative
 mov ax,7
 jmp short enqueue_chunk
enqueue_negative:
 cmp ax,-8
 jge enqueue_chunk
 mov ax,-8
enqueue_chunk:
 sub si,ax
 cmp byte ptr ds:dec_q_count,31
 jae enqueue_lost
 xor bx,bx
 mov bl,ds:dec_q_head
 mov ds:dec_queue[bx],al
 mov dx,bx
 shl bx,1
 shl bx,1
 mov ax,es:[6ch]
 mov word ptr ds:timestamp_table[bx],ax
 mov ax,es:[6eh]
 mov word ptr ds:timestamp_table[bx+2],ax
 mov bx,dx
 inc bl
 and bl,31
 mov ds:dec_q_head,bl
 inc byte ptr ds:dec_q_count
 jmp short enqueue_next
enqueue_lost:
 cmp word ptr ds:dec_lost_word,0ffffh
 je enqueue_next
 inc word ptr ds:dec_lost_word
 jmp short enqueue_next
enqueue_done:
 pop es
 ret
wheel_enqueue endp

; Callback registers are saved before establishing DGROUP. No Windows USER
; work happens here, and no DOS/mouse call is made from the callback. SI/DI
; are cumulative mickeys. Subtract modulo 65536, updating even on wheel-only
; input. No other program may consume AX=0Bh/27h counters while Windows owns
; this backend. CX/DX scaled absolute coordinates are deliberately ignored.
dos_callback proc far
 pushf
 cli
 push ax
 push bx
 push cx
 push dx
 push si
 push di
 push bp
 push ds
 push es
 mov bp,sp
 cld
 mov ax,DGROUP
 mov ds,ax
 cmp active,2
 jne callback_done
 cmp dos_wheel,0
 je callback_motion
 test word ptr [bp+16],0080h
 jz callback_motion
 mov al,byte ptr [bp+15]
 cbw
 call wheel_enqueue
callback_motion:
 mov bx,[bp+8]
 mov cx,[bp+6]
 mov dx,bx
 sub bx,dos_lastx
 mov dos_lastx,dx
 mov dx,cx
 sub cx,dos_lasty
 mov dos_lasty,dx
 mov ax,[bp+16]
 and ax,001eh
 mov dx,bx
 or dx,cx
 jz callback_buttons
 or ax,1
callback_buttons:
 or ax,ax
 jz callback_done
 mov dx,2
 xor si,si
 xor di,di
 push bp
 push ds
 call dword ptr callback
 cli
 pop ds
 pop bp
callback_done:
 pop es
 pop ds
 pop bp
 pop di
 pop si
 pop dx
 pop cx
 pop bx
 pop ax
 popf
 retf
dos_callback endp
end
