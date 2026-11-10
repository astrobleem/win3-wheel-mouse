; SPDX-License-Identifier: MIT
; Direct PS/2 AUX/IRQ12 transport, independent of DOS mouse services.
; Supported baseline: enabled keyboard, disabled AUX interface, no resident
; mouse driver. Both devices are inhibited before reading controller replies.
; Pending output is left untouched. The mouse is initialized to defaults and
; reset to ID 0 on release; private settings of an earlier owner are NOT kept.
.8086
.model small
.data
public ps2_enable, ps2_disable, ps2_feed, ps2_wheel, ps2_index
extrn active:byte, callback:dword, backend_status:word
extrn wheel_enqueue:near
ps2_wheel db 0
ps2_index db 0
ps2_packet db 4 dup (0)
ps2_buttons db 0
ps2_command db 0
ps2_pic1 db 0
ps2_pic2 db 0
ps2_oldirq dd 0
ps2_owned db 0
ps2_timeout dw 8
.code
; Long conditionals remain 8086 instructions, including error exits.
ljc macro target
 local skip
 jnc skip
 jmp target
skip:
endm
ljnz macro target
 local skip
 jz skip
 jmp target
skip:
endm
ljz macro target
 local skip
 jnz skip
 jmp target
skip:
endm
; CF failure, AX=8003 absent, 8004 busy, 8005 command error, 8006 cleanup error.
; Caller saves flags and keeps CLI. BIOS equipment check precedes port I/O.
ps2_enable proc near
 push es
 mov ps2_owned,0
 mov ps2_wheel,0
 mov ps2_index,0
 mov ps2_buttons,0
 mov ax,0c000h
 push ds
 int 15h
 pop ds
 ljc ps2_absent
 cmp ah,0
 ljnz ps2_absent
 ; C0 feature byte 1 bit6 means second PIC, not mouse presence.
 test byte ptr es:[bx+5],40h
 ljz ps2_absent
 push ds
 int 11h
 pop ds
 test ax,4
 ljz ps2_absent
 ; AD prevents a keyboard scan byte racing the controller-byte reply.
 ; The supported cold-boot baseline has its keyboard interface enabled.
 mov al,0adh
 call ps2_ctl
 ljc ps2_keyboard_failed
 call ps2_wait_input
 ljc ps2_keyboard_failed
 in al,64h
 test al,1
 ljnz ps2_keyboard_busy
 mov al,20h
 call ps2_ctl
 ljc ps2_keyboard_failed
 call ps2_control_reply
 ljc ps2_keyboard_failed
 and al,0efh
 mov ps2_command,al
 test al,20h
 ljz ps2_keyboard_busy
 mov ps2_owned,1
 ; Snapshot IRQ12 and mask bits before any mouse command.
 in al,21h
 and al,4
 mov ps2_pic1,al
 in al,0a1h
 and al,10h
 mov ps2_pic2,al
 in al,0a1h
 or al,10h
 out 0a1h,al
 xor ax,ax
 mov es,ax
 mov ax,es:[01d0h]
 mov word ptr ps2_oldirq,ax
 mov word ptr cs:ps2_chain,ax
 mov ax,es:[01d2h]
 mov word ptr ps2_oldirq+2,ax
 mov word ptr cs:ps2_chain+2,ax
 mov ps2_owned,2
 mov al,ps2_command
 or al,10h
 and al,0ddh
 call ps2_write_control
 ljc ps2_rollback
 ; An inhibited mouse may still have a buffered stream packet. Stop it and
 ; drain AUX bytes only. Reset provides an unambiguous AA,00 protocol baseline.
 call ps2_stop
 ljc ps2_rollback
 call ps2_reset
 ljc ps2_rollback
 mov al,200
 call ps2_rate
 ljc ps2_rollback
 mov al,100
 call ps2_rate
 ljc ps2_rollback
 mov al,80
 call ps2_rate
 ljc ps2_rollback
 mov al,0f2h
 call ps2_send
 ljc ps2_rollback
 call ps2_aux_reply
 ljc ps2_rollback
 cmp al,3
 je ps2_has_wheel
 or al,al
 ljnz ps2_rollback
 jmp short ps2_configure
ps2_has_wheel:
 mov ps2_wheel,1
ps2_configure:
 mov al,100
 call ps2_rate
 ljc ps2_rollback
 xor ax,ax
 mov es,ax
 mov word ptr es:[01d0h],offset ps2_irq
 mov ax,cs
 mov es:[01d2h],ax
 mov active,3
 mov backend_status,3
 cmp ps2_wheel,0
 je ps2_enable_stream
 or backend_status,0100h
ps2_enable_stream:
 mov al,0f4h
 call ps2_send
 ljc ps2_rollback
 mov al,ps2_command
 and al,0dfh
 or al,2
 call ps2_write_control
 ljc ps2_rollback
 in al,0a1h
 and al,0efh
 out 0a1h,al
 in al,21h
 and al,0fbh
 out 21h,al
 pop es
 clc
 ret
ps2_rollback:
 call ps2_disable
 ljc ps2_cleanup_failed
ps2_failed:
 mov ax,8005h
 jmp short ps2_error
ps2_keyboard_failed:
 mov al,0aeh
 call ps2_ctl
 ljc ps2_cleanup_failed
 call ps2_wait_input
 ljc ps2_cleanup_failed
 jmp short ps2_failed
ps2_keyboard_busy:
 mov al,0aeh
 call ps2_ctl
 ljc ps2_cleanup_failed
 call ps2_wait_input
 ljc ps2_cleanup_failed
 mov ax,8004h
 jmp short ps2_error
ps2_cleanup_failed:
 mov ax,8006h
 jmp short ps2_error
ps2_absent:
 mov ax,8003h
ps2_error:
 pop es
 stc
 ret
ps2_enable endp

; Always restore interrupt vectors/controller/PIC. Device reset is best effort
; and a failure is returned, never represented as successful restoration.
ps2_disable proc near
 push es
 push bp
 xor bp,bp
 mov active,0
 cmp ps2_owned,0
 ljz ps2_restore_done
 cmp ps2_owned,2
 jne ps2_restore_controller
 in al,0a1h
 or al,10h
 out 0a1h,al
 mov al,ps2_command
 or al,10h
 and al,0ddh
 call ps2_write_control
 jc ps2_restore_bad
 call ps2_stop
 jc ps2_restore_bad
 call ps2_reset
 jnc ps2_restore_vector
ps2_restore_bad:
 inc bp
ps2_restore_vector:
 xor ax,ax
 mov es,ax
 mov ax,word ptr ps2_oldirq
 mov es:[01d0h],ax
 mov ax,word ptr ps2_oldirq+2
 mov es:[01d2h],ax
 in al,0a1h
 and al,0efh
 or al,ps2_pic2
 out 0a1h,al
 in al,21h
 and al,0fbh
 or al,ps2_pic1
 out 21h,al
ps2_restore_controller:
 mov al,ps2_command
 call ps2_write_control
 jnc ps2_restore_done
 inc bp
ps2_restore_done:
 mov ps2_owned,0
 mov ps2_index,0
 mov ps2_wheel,0
 or bp,bp
 pop bp
 pop es
 jz ps2_restore_ok
 stc
 ret
ps2_restore_ok:
 clc
 ret
ps2_disable endp

; F5 may be preceded by an incomplete streaming packet. Bound every read and
; the entire drain. Never consume keyboard data. Follow with FF/BAT checking.
ps2_stop proc near
 push bx
 push cx
 mov bh,3
 mov ps2_timeout,1
ps2_stop_send:
 xor bl,bl
 mov al,0d4h
 call ps2_ctl
 jc ps2_stop_done
 mov al,0f5h
 call ps2_data
 jc ps2_stop_done
 mov cx,32
ps2_stop_drain:
 call ps2_aux_reply
 jc ps2_stop_quiet
 cmp al,0fah
 jne ps2_stop_resend
 mov bl,1
 jmp short ps2_stop_next
ps2_stop_resend:
 cmp al,0feh
 jne ps2_stop_next
 dec bh
 jnz ps2_stop_send
 stc
 jmp short ps2_stop_done
ps2_stop_next:
 loop ps2_stop_drain
 stc
 jmp short ps2_stop_done
ps2_stop_quiet:
 ; An FA-valued movement byte is not sufficient. Drain until a whole quiet
 ; timer interval so the real F5 ACK cannot leak into FF's response stream.
 in al,64h
 test al,1
 jnz ps2_stop_bad
 or bl,bl
 jz ps2_stop_bad
 clc
 jmp short ps2_stop_done
ps2_stop_bad:
 stc
ps2_stop_done:
 mov ps2_timeout,8
 pop cx
 pop bx
 ret
ps2_stop endp
ps2_reset proc near
 mov al,0ffh
 call ps2_send
 jc ps2_reset_done
 ; PIT-based BAT deadline: about two seconds at the normal BIOS timer rate.
 mov ps2_timeout,80
 call ps2_aux_reply
 mov ps2_timeout,8
 jc ps2_reset_done
 cmp al,0aah
 jne ps2_reset_bad
 call ps2_aux_reply
 jc ps2_reset_done
 or al,al
 jnz ps2_reset_bad
 clc
 ret
ps2_reset_bad:
 stc
ps2_reset_done:
 ret
ps2_reset endp

; Fixed 65535-poll limits work even when IF=0 / BIOS ticks cannot advance.
ps2_wait_input proc near
 push cx
 mov cx,0ffffh
ps2_input_loop:
 in al,64h
 test al,2
 jz ps2_input_ok
 loop ps2_input_loop
 pop cx
 stc
 ret
ps2_input_ok:
 pop cx
 clc
 ret
ps2_wait_input endp
ps2_ctl proc near
 push ax
 call ps2_wait_input
 pop ax
 jc ps2_ctl_done
 out 64h,al
ps2_ctl_done:
 ret
ps2_ctl endp
ps2_data proc near
 push ax
 call ps2_wait_input
 pop ax
 jc ps2_data_done
 out 60h,al
ps2_data_done:
 ret
ps2_data endp
ps2_write_control proc near
 push ax
 mov al,60h
 call ps2_ctl
 pop ax
 jc ps2_write_done
 call ps2_data
ps2_write_done:
 ret
ps2_write_control endp
ps2_control_reply proc near
 push cx
 mov cx,0ffffh
ps2_ctrl_poll:
 in al,64h
 test al,1
 jnz ps2_ctrl_ready
 loop ps2_ctrl_poll
 jmp short ps2_ctrl_bad
ps2_ctrl_ready:
 test al,0e0h
 jnz ps2_ctrl_bad
 in al,60h
 pop cx
 clc
 ret
ps2_ctrl_bad:
 pop cx
 stc
 ret
ps2_control_reply endp
ps2_aux_reply proc near
 push bx
 push cx
 push dx
 push si
 call ps2_clock
 mov bx,ax
 mov dx,ps2_timeout
 mov si,0ffffh
 mov cx,64
ps2_aux_poll:
 in al,64h
 test al,1
 jz ps2_aux_wait
 test al,20h
 jz ps2_aux_bad
 test al,0c0h
 jnz ps2_aux_bad
 in al,60h
 pop si
 pop dx
 pop cx
 pop bx
 clc
 ret
ps2_aux_wait:
 ; Latch/read timer 0 without changing its mode or divisor. Count rollover
 ; in the down-counter (mode 3 wraps each half-period, mode 2 each period).
 call ps2_clock
 cmp ax,bx
 jbe ps2_aux_tick
 dec dx
 jz ps2_aux_bad
ps2_aux_tick:
 mov bx,ax
 dec si
 jnz ps2_aux_poll
 loop ps2_aux_poll
 ; A broken/stopped PIT must not hang Windows either.
ps2_aux_bad:
 pop si
 pop dx
 pop cx
 pop bx
 stc
 ret
ps2_aux_reply endp
ps2_clock proc near
 mov al,0
 out 43h,al
 in al,40h
 mov ah,al
 in al,40h
 xchg al,ah
 ret
ps2_clock endp
ps2_send proc near
 push bx
 mov bl,al
 mov bh,3
ps2_send_retry:
 mov al,0d4h
 call ps2_ctl
 jc ps2_send_done
 mov al,bl
 call ps2_data
 jc ps2_send_done
 call ps2_aux_reply
 jc ps2_send_done
 cmp al,0fah
 je ps2_send_ok
 cmp al,0feh
 jne ps2_send_bad
 dec bh
 jnz ps2_send_retry
ps2_send_bad:
 stc
 jmp short ps2_send_done
ps2_send_ok:
 clc
ps2_send_done:
 pop bx
 ret
ps2_send endp
ps2_rate proc near
 push ax
 mov al,0f3h
 call ps2_send
 pop ax
 jc ps2_rate_done
 call ps2_send
ps2_rate_done:
 ret
ps2_rate endp

; AL byte -> CF completed normal mouse event, AX event mask, BX dx, CX dy.
; Wheel-only packets queue data but do not fabricate a Windows mouse event.
ps2_feed proc near
 xor bx,bx
 mov bl,ps2_index
 or bl,bl
 jnz ps2_feed_store
 test al,8
 ljz ps2_feed_none
ps2_feed_store:
 mov ps2_packet[bx],al
 inc bl
 mov ps2_index,bl
 mov al,3
 add al,ps2_wheel
 cmp bl,al
 jnb ps2_feed_length
 jmp ps2_feed_none
ps2_feed_length:
 mov ps2_index,0
 cmp ps2_wheel,0
 je ps2_motion
 mov al,ps2_packet+3
 cbw
 call wheel_enqueue
ps2_motion:
 xor bx,bx
 mov bl,ps2_packet+1
 test ps2_packet,10h
 jz ps2_x_positive
 mov bh,0ffh
ps2_x_positive:
 xor cx,cx
 mov cl,ps2_packet+2
 test ps2_packet,20h
 jz ps2_y_positive
 mov ch,0ffh
ps2_y_positive:
 neg cx
 ; Overflow invalidates displacement, not button changes or wheel data.
 test ps2_packet,40h
 jz ps2_no_x_overflow
 xor bx,bx
ps2_no_x_overflow:
 test ps2_packet,80h
 jz ps2_no_y_overflow
 xor cx,cx
ps2_no_y_overflow:
 xor ax,ax
 mov dl,ps2_packet
 and dl,3
 mov dh,dl
 xor dl,ps2_buttons
 mov ps2_buttons,dh
 test dl,1
 jz ps2_right
 or ax,2
 test dh,1
 jnz ps2_right
 xor ax,6
ps2_right:
 test dl,2
 jz ps2_moved
 or ax,8
 test dh,2
 jnz ps2_moved
 xor ax,18h
ps2_moved:
 mov dx,bx
 or dx,cx
 jz ps2_event
 or ax,1
ps2_event:
 or ax,ax
 ljz ps2_feed_none
 stc
 ret
ps2_feed_none:
 clc
 ret
ps2_feed endp

ps2_irq proc far
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
 in al,64h
 test al,1
 jz ps2_irq_chain
 test al,20h
 jz ps2_irq_chain
 mov ah,al
 in al,60h
 test ah,0c0h
 jnz ps2_irq_bad
 cmp active,3
 jne ps2_irq_ack
 call ps2_feed
 jnc ps2_irq_ack
 mov dx,2
 xor si,si
 xor di,di
 push ds
 call dword ptr callback
 cli
 pop ds
 jmp short ps2_irq_ack
ps2_irq_bad:
 mov ps2_index,0
ps2_irq_ack:
 mov al,20h
 out 0a0h,al
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
ps2_irq_chain:
 pop es
 pop ds
 pop bp
 pop di
 pop si
 pop dx
 pop cx
 pop bx
 pop ax
 jmp dword ptr cs:ps2_chain
ps2_irq endp
ps2_chain dd 0
end
