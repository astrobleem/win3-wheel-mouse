; SPDX-License-Identifier: MIT
; Actual PS/2 decoder regression: no transport I/O or INT33 calls executed.
.8086
.model small
.stack 4096
.data
public active, callback, backend_status
active db 0
callback dd 0
backend_status dw 0
extrn ps2_wheel:byte, ps2_index:byte
extrn dec_q_tail:byte, dec_q_count:byte, dec_lost_word:word, timestamp_table:byte
packet db 8,0,0,0
packet_len dw 3
packet_pos dw 0
result_flags dw 0
result_x dw 0
result_y dw 0
result_cf dw 0
checks dw 0
fails dw 0
first_failure dw 0
wheel_value dw 0
sum dw 0
pieces dw 0
remaining dw 0
fixed_tick_lo dw 0
fixed_tick_hi dw 0
pass_msg db 'PASS PS2 decoder checks ', '$'
fail_msg db 'FAIL PS2 decoder checks ', '$'
first_msg db ' first failure ', '$'
hexbuf db '0000',13,10,'$'
.code
extrn ps2_feed:near, dec_reset:near, dec_read:near
check macro value
 local okay
 inc checks
 cmp ax,value
 je okay
 inc fails
 cmp first_failure,0
 jne okay
 push ax
 mov ax,checks
 mov first_failure,ax
 pop ax
okay:
endm
; Preserve final decoder result in memory, including CF, across packet loop.
feed_packet proc near
 mov packet_pos,0
feed_next:
 mov bx,packet_pos
 mov al,packet[bx]
 call ps2_feed
 mov result_flags,ax
 mov result_x,bx
 mov result_y,cx
 mov result_cf,0
 jnc feed_no_carry
 mov result_cf,1
feed_no_carry:
 inc packet_pos
 mov ax,packet_pos
 cmp ax,packet_len
 jb feed_next
 ret
feed_packet endp
; Release both buttons using a real packet before resetting the wheel queue.
baseline proc near
 mov ps2_index,0
 mov ps2_wheel,0
 mov packet_len,3
 mov packet,8
 mov packet+1,0
 mov packet+2,0
 mov packet+3,0
 call feed_packet
 call dec_reset
 ret
baseline endp
; Every queued timestamp must equal the BIOS tick frozen by CLI in this test.
check_stamp proc near
 mov ax,word ptr timestamp_table
 check fixed_tick_lo
 mov ax,word ptr timestamp_table+2
 check fixed_tick_hi
 ret
check_stamp endp
; Drain queue, checking legacy signed chunk range and accumulating exact sum.
drain proc near
 mov sum,0
 mov pieces,0
drain_next:
 cmp dec_q_count,0
 jne drain_have
 jmp drain_done
drain_have:
 xor bx,bx
 mov bl,dec_q_tail
 shl bx,1
 shl bx,1
 mov ax,word ptr timestamp_table[bx]
 check fixed_tick_lo
 mov ax,word ptr timestamp_table[bx+2]
 check fixed_tick_hi
 call dec_read
 add sum,ax
 inc pieces
 cmp ax,-8
 jge drain_low_ok
 inc fails
 mov first_failure,0fff1h
drain_low_ok:
 cmp ax,7
 jle drain_high_ok
 inc fails
 mov first_failure,0fff2h
drain_high_ok:
 inc checks
 or ax,ax
 jz drain_zero
 jmp drain_next
drain_zero:
 inc fails
 mov first_failure,0fff3h
 jmp drain_next
drain_done:
 ret
drain endp
print_hex proc near
 mov di,offset hexbuf+3
 mov cx,4
hex_next:
 mov bx,ax
 and bx,15
 mov dl,bl
 add dl,'0'
 cmp dl,'9'
 jbe hex_store
 add dl,7
hex_store:
 mov [di],dl
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
 mov ax,40h
 mov es,ax
 mov ax,es:[6ch]
 mov fixed_tick_lo,ax
 mov ax,es:[6eh]
 mov fixed_tick_hi,ax
 call baseline
 ; Positive 9-bit maximum and negative Y convention.
 mov packet+1,255
 mov packet+2,255
 call feed_packet
 mov ax,result_flags
 check 1
 mov ax,result_cf
 check 1
 mov ax,result_x
 check 255
 mov ax,result_y
 check -255
 ; Negative 9-bit minimum, independent sign bits from header.
 mov packet,38h
 mov packet+1,0
 mov packet+2,0
 call feed_packet
 mov ax,result_x
 check -256
 mov ax,result_y
 check 256
 ; Negative one and positive one on independent axes.
 mov packet,18h
 mov packet+1,255
 mov packet+2,1
 call feed_packet
 mov ax,result_x
 check -1
 mov ax,result_y
 check -1
 ; X overflow drops only X.
 mov packet,48h
 mov packet+1,123
 mov packet+2,4
 call feed_packet
 mov ax,result_x
 check 0
 mov ax,result_y
 check -4
 ; Y overflow drops only Y.
 mov packet,88h
 call feed_packet
 mov ax,result_x
 check 123
 mov ax,result_y
 check 0
 ; Both overflow: no event, but buttons must still transition.
 mov packet,0cbh
 call feed_packet
 mov ax,result_flags
 check 000ah
 mov ax,result_cf
 check 1
 mov ax,result_x
 check 0
 mov ax,result_y
 check 0
 mov packet,8
 mov packet+1,0
 mov packet+2,0
 call feed_packet
 mov ax,result_flags
 check 0014h
 call feed_packet
 mov ax,result_cf
 check 0
 ; Separate left/right down/up, repeated hold produces no event.
 mov packet,9
 call feed_packet
 mov ax,result_flags
 check 2
 call feed_packet
 mov ax,result_cf
 check 0
 mov packet,8
 call feed_packet
 mov ax,result_flags
 check 4
 mov packet,10
 call feed_packet
 mov ax,result_flags
 check 8
 mov packet,8
 call feed_packet
 mov ax,result_flags
 check 16
 ; Invalid first bytes are ignored, next valid packet still decodes.
 mov al,0
 call ps2_feed
 mov ax,0
 mov al,ps2_index
 check 0
 mov al,7
 call ps2_feed
 mov ax,0
 mov al,ps2_index
 check 0
 mov packet+1,1
 call feed_packet
 mov ax,result_x
 check 1
 mov ax,result_cf
 check 1
 ; Three bytes are incomplete in wheel mode, fourth completes the packet.
 call baseline
 mov ps2_wheel,1
 mov packet_len,3
 call feed_packet
 mov ax,result_cf
 check 0
 xor ax,ax
 mov al,ps2_index
 check 3
 mov al,1
 call ps2_feed
 mov ax,0
 adc ax,0
 check 0
 xor ax,ax
 mov al,ps2_index
 check 0
 call dec_read
 check 1
 ; Combined motion/button/wheel delivers both paths.
 call baseline
 mov ps2_wheel,1
 mov packet_len,4
 mov packet,9
 mov packet+1,3
 mov packet+2,2
 mov packet+3,0ffh
 call feed_packet
 mov ax,result_flags
 check 3
 mov ax,result_x
 check 3
 mov ax,result_y
 check -2
 mov ax,result_cf
 check 1
 call dec_read
 check -1
 ; Exhaust every signed ID3 wheel byte, with no fabricated pointer event.
 mov wheel_value,-128
wheel_loop:
 call baseline
 mov ps2_wheel,1
 mov packet_len,4
 mov ax,wheel_value
 mov packet+3,al
 call feed_packet
 mov ax,result_cf
 check 0
 mov ax,result_flags
 check 0
 cmp wheel_value,0
 je wheel_no_stamp
 call check_stamp
wheel_no_stamp:
 call drain
 mov ax,sum
 check wheel_value
 mov ax,dec_lost_word
 check 0
 call dec_read
 check 0
 inc wheel_value
 cmp wheel_value,128
 je wheel_complete
 jmp wheel_loop
wheel_complete:
 ; Forty +1 packets: 31 accepted, nine drop-newest losses.
 call baseline
 mov ps2_wheel,1
 mov packet_len,4
 mov packet+3,1
 mov remaining,40
full_loop:
 call feed_packet
 dec remaining
 jnz full_loop
 xor ax,ax
 mov al,dec_q_count
 check 31
 mov ax,dec_lost_word
 check 9
 call check_stamp
 call drain
 mov ax,sum
 check 31
 mov ax,pieces
 check 31
 ; Saturating loss accounting.
 mov dec_lost_word,0fffeh
 mov remaining,31
fill_again:
 call feed_packet
 dec remaining
 jnz fill_again
 call feed_packet
 call feed_packet
 mov ax,dec_lost_word
 check 0ffffh
 ; Reset clears queue and loss state.
 call dec_reset
 xor ax,ax
 mov al,dec_q_count
 check 0
 mov ax,dec_lost_word
 check 0
 popf
 mov dx,offset pass_msg
 cmp fails,0
 je print_result
 mov dx,offset fail_msg
print_result:
 mov ah,9
 int 21h
 mov ax,checks
 call print_hex
 cmp fails,0
 je exit_ok
 mov dx,offset first_msg
 mov ah,9
 int 21h
 mov ax,first_failure
 call print_hex
 mov ax,4c01h
 int 21h
exit_ok:
 mov ax,4c00h
 int 21h
end start
