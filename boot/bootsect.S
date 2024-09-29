!
! SYS_SIZE is the number of clicks (16 bytes) to be loaded.
! 0x3000 is 0x30000 bytes = 196kB, more than enough for current
! versions of linux
!
#include <linux/config.h>
SYSSIZE = DEF_SYSSIZE
!
!	bootsect.s		(C) 1991 Linus Torvalds
!	modified by Drew Eckhardt
!
! bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
! iself out of the way to address 0x90000, and jumps there.
!
! It then loads 'setup' directly after itself (0x90200), and the system
! at 0x10000, using BIOS interrupts. 
!
! NOTE! currently system is at most 8*65536 bytes long. This should be no
! problem, even in the future. I want to keep it simple. This 512 kB
! kernel size should be enough, especially as this doesn't contain the
! buffer cache as in minix
!
! The loader has been made as simple as possible, and continuos
! read errors will result in a unbreakable loop. Reboot by hand. It
! loads pretty fast by getting whole sectors at a time whenever possible.

.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

SETUPLEN = 4				! nr of setup-sectors
BOOTSEG  = 0x07c0			! original address of boot-sector
INITSEG  = DEF_INITSEG			! we move boot here - out of the way
SETUPSEG = DEF_SETUPSEG			! setup starts here
SYSSEG   = DEF_SYSSEG			! system loaded at 0x10000 (65536).
ENDSEG   = SYSSEG + SYSSIZE		! where to stop loading

! ROOT_DEV & SWAP_DEV are now written by "build".
ROOT_DEV = 0
SWAP_DEV = 0

entry start
start:
	mov	ax,#BOOTSEG 			; bootsect把自己移动到0x9000:0x0000的位置
	mov	ds,ax
	mov	ax,#INITSEG
	mov	es,ax
	mov	cx,#256
	sub	si,si
	sub	di,di
	rep							; 重复执行cx次，每次从si复制到di一个字，每次cx减一，si和di自增
	movw						
	jmpi	go,INITSEG

go:	mov	ax,cs		
	mov	dx,#0xfef4	! arbitrary value >>512 - disk parm size 

	mov	ds,ax
	mov	es,ax
	;push	ax		; 推到bios的栈里，bios的栈地址是0xffd6

	mov	ss,ax		! put stack at 0x9ff00 - 12 = 0x9fef4.
	mov	sp,dx		; 设置新栈到ss:sp = 0x9000:0xfef4 = 0x9fef4
					; 实际上这里已经把栈段都修改了，刚刚push到bios的栈段里面的ax的值再pop出来就不对了，
					; 所以选择注释65行的push ax，放到设置好了栈段后，再push
					; 这是linus犯的错
	push	ax
/*
 *	Many BIOS's default disk parameter tables will not 
 *	recognize multi-sector reads beyond the maximum sector number
 *	specified in the default diskette parameter tables - this may
 *	mean 7 sectors in some cases.
 *	Since single sector reads are slow and out of the question,
 *	we must take care of this by creating new parameter tables
 *	(for the first disk) in RAM.  We will set the maximum sector
 *	count to 18 - the most we will encounter on an HD 1.44.  
 *
 *	High doesn't hurt.  Low does.
 *
 *	Segments are as follows: ds=es=ss=cs - INITSEG,
 *		fs = 0, gs = parameter table segment
 */
/*
	BIOS 设置的中断 0x1E 实际上并不是一个中断，其对应中断向量的地方被放置了软驱参数表的地址。
	该中断向量位于内存 0x1E * 4 = 0x78 处。这段代码首先从内存 0x0000:0x0078 处指向原软驱参数表的指针，
	然后从该指针指向的地址复制到 0x9000:0xfef4 处，然后修改表中偏移 4 处的每磁道最大扇区数为 18。
	表长 12 字节。
*/

	push	#0			; 置段寄存器 fs = 0
	pop	fs
	mov	bx,#0x78		! fs:bx is parameter table address
	seg fs				; 指令 seg fs 表示其下一条语句的操作数在 fs 段中
	lgs	si,(bx)			! gs:si is source ; gs:si = fs:[bx]，在0x0000:0x0078这个物理地址上去取一个地址，高16位送入gs，低16位送入si

	mov	di,dx			! es:di is destination
	mov	cx,#6			! copy 12 bytes ; es:di = 0x9000:0xfef4
	cld

	rep
	seg gs
	movw

	mov	di,dx
	movb	4(di),*18		! patch sector count ;修改每个磁道的扇区数 es:di = *(0x9000:0xfef4 + 4) = 0x12

	seg fs
	mov	(bx),di			; 0x0000:0x0078 = 0xfef4 修改中断向量表0x1E所存的指针为0x9000:0xfef4
	seg fs
	mov	2(bx),es		

	pop	ax				; 弹出栈中的数据到ax中，
	mov	fs,ax
	mov	gs,ax
	
	xor	ah,ah			! reset FDC 
	xor	dl,dl			; AH = 0，DL = 0，使0号软盘复位
	int 	0x13	

! load the setup-sectors directly after the bootblock.
! Note that 'es' is already set up.
! 在 bootsect 程序块后紧根着加载 setup 模块的代码数据。
! 注意 es 已经设置好了。（在移动代码时 es 已经指向目的段地址处 0x9000）。

load_setup:
	xor	dx, dx			! drive 0, head 0				; DH/DL = 磁头号/驱动器号
	mov	cx,#0x0002		! sector 2, track 0				; CX中的0~5位代表扇区号，CX中的6~15位代表柱面号（其中，CL的6~7为柱面数的高两位，CH存低8位）
	mov	bx,#0x0200		! address = 512, in INITSEG		; ES:BX = 数据缓冲区地址，即在bootsect后面紧跟着的扇区
	mov	ax,#0x0200+SETUPLEN	! service 2, nr of sectors 	; 读磁盘扇区，读SETUPLEN=4，读4个扇区
	int	0x13			! read it
	jnc	ok_load_setup		! ok - continue				; 都成功了跳转，读不成功打印错误后继续读

	push	ax			! dump error code
	call	print_nl
	mov	bp, sp
	call	print_hex
	pop	ax	
	
	xor	dl, dl			! reset FDC
	xor	ah, ah
	int	0x13
	j	load_setup

ok_load_setup:

! Get disk drive parameters, specifically nr of sectors/track
	; 假设当前ax = 00000000，bx = 00000004，cx = 00094f12，dx = 00000101，es = 0x9000，di = 0000efde
	; bl = 4， 表示磁盘1.44M大小
	; cl[7:6] ch = 00 0100 1111，表示最大柱面（磁道）号，那么这里的柱面数是79
	; cl[5:0] = 1 0010，表示扇区数，那么这里的扇区数是18
	; dh，表示最大磁头数，那么这里的最大磁头数是1，那么就有两个磁头
	; dl，表示驱动器数量，那么这里的驱动器数量为1
	; 计算一下这个软盘的总容量
	; 一个1.44M的软盘，它有80个磁道，每个磁道有18个扇区，两面都可以存储数据。我们这样计算它的容量：80×18×2×512≈1440KB≈1.44MB

	xor	dl,dl
	mov	ah,#0x08		! AH=8 is get drive parameters
	int	0x13
	xor	ch,ch
	seg cs
	mov	sectors,cx		; 保存扇区数到sectors标号处
	mov	ax,#INITSEG		; 因为上面取磁盘参数0x13中断改了 es 值，这里重新改回0x9000
	mov	es,ax

! Print some inane message
/*
	下面利用 BIOS INT 0x10 功能 0x03 和 0x13 来显示信息：“'Loading'+回车+换行”，显示包括
	回车和换行控制字符在内共 9 个字符。
	BIOS 中断 0x10 功能号 ah = 0x03，读光标位置。
	输入：bh = 页号
	返回：ch = 扫描开始线；cl = 扫描结束线；dh = 行号(0x00 顶端)；dl = 列号(0x00 最左边)。

	BIOS 中断 0x10 功能号 ah = 0x13，显示字符串。
	输入：al = 放置光标的方式及规定属性。0x01-表示使用 bl 中的属性值，光标停在字符串结尾处。
	bh = 显示页面号；bl = 字符属性；dh = 行号；dl = 列号。cx = 显示的字符串字符数。
	es:bp 此寄存器对指向要显示的字符串起始位置处。
 */

	mov	ah,#0x03		! read cursor pos
	xor	bh,bh
	int	0x10
	
	mov	cx,#9
	mov	bx,#0x0007		! page 0, attribute 7 (normal)
	mov	bp,#msg1
	mov	ax,#0x1301		! write string, move cursor
	int	0x10

! ok, we've written the message, now
! we want to load the system (at 0x10000)
	; 现在开始将 system 模块加载到 0x10000（64KB）开始处。
	; 注意! 目前的内核系统最大长度限制为(8*65536)(512KB)字节
	; 估计早期设计内核的时候觉得内核长度不会超过512k，所以才把system模块搬到了0x10000这个位置

	mov	ax,#SYSSEG	; SYSSEG = 0x1000
	mov	es,ax		! segment of 0x010000
	call	read_it		; 读磁盘上 system 模块，es 为输入参数。
	call	kill_motor	; 关闭驱动器马达，这样就可以知道驱动器的状态了。
	call	print_nl	; print new line

! After that we check which root-device to use. If the device is
! defined (!= 0), nothing is done and the given device is used.
! Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
! on the number of sectors that the BIOS reports currently.

	seg cs
	mov	ax,root_dev
	or	ax,ax
	jne	root_defined
	seg cs
	mov	bx,sectors
	mov	ax,#0x0208		! /dev/ps0 - 1.2Mb
	cmp	bx,#15
	je	root_defined
	mov	ax,#0x021c		! /dev/PS0 - 1.44Mb
	cmp	bx,#18
	je	root_defined
undef_root:
	jmp undef_root
root_defined:
	seg cs
	mov	root_dev,ax

! after that (everyting loaded), we jump to
! the setup-routine loaded directly after
! the bootblock:

	jmpi	0,SETUPSEG

! This routine loads the system at address 0x10000, making sure
! no 64kB boundaries are crossed. We try to load it as fast as
! possible, loading whole tracks whenever we can.
!
! in:	es - starting address segment (normally 0x1000)
!
sread:	.word 1+SETUPLEN	! sectors read of current track
head:	.word 0			! current head
track:	.word 0			! current track

read_it:
	mov ax,es
	test ax,#0x0fff
die:	jne die			! es must be at 64kB boundary
	xor bx,bx		! bx is starting address within segment
rp_read:
	mov ax,es
	cmp ax,#ENDSEG		! have we loaded all yet?
	jb ok1_read
	ret
ok1_read:
	seg cs
	mov ax,sectors
	sub ax,sread
	mov cx,ax
	shl cx,#9
	add cx,bx
	jnc ok2_read
	je ok2_read
	xor ax,ax
	sub ax,bx
	shr ax,#9
ok2_read:
	call read_track
	mov cx,ax
	add ax,sread
	seg cs
	cmp ax,sectors
	jne ok3_read
	mov ax,#1
	sub ax,head
	jne ok4_read
	inc track
ok4_read:
	mov head,ax
	xor ax,ax
ok3_read:
	mov sread,ax
	shl cx,#9
	add bx,cx
	jnc rp_read
	mov ax,es
	add ah,#0x10
	mov es,ax
	xor bx,bx
	jmp rp_read

read_track:
	pusha
	pusha	
	mov	ax, #0xe2e 	! loading... message 2e = .
	mov	bx, #7
 	int	0x10
	popa		

	mov dx,track
	mov cx,sread
	inc cx
	mov ch,dl
	mov dx,head
	mov dh,dl
	and dx,#0x0100
	mov ah,#2
	
	push	dx				! save for error dump
	push	cx
	push	bx
	push	ax

	int 0x13
	jc bad_rt
	add	sp, #8   	
	popa
	ret

bad_rt:	push	ax				! save error code
	call	print_all			! ah = error, al = read
	
	
	xor ah,ah
	xor dl,dl
	int 0x13
	

	add	sp, #10
	popa	
	jmp read_track

/*
 *	print_all is for debugging purposes.  
 *	It will print out all of the registers.  The assumption is that this is
 *	called from a routine, with a stack frame like
 *	dx 
 *	cx
 *	bx
 *	ax
 *	error
 *	ret <- sp
 *
*/
 
print_all:
	mov	cx, #5		! error code + 4 registers
	mov	bp, sp	

print_loop:
	push	cx		! save count left
	call	print_nl	! nl for readability
	jae	no_reg		! see if register name is needed
	
	mov	ax, #0xe05 + 0x41 - 1
	sub	al, cl
	int	0x10

	mov	al, #0x58 	! X
	int	0x10

	mov	al, #0x3a 	! :
	int	0x10

no_reg:
	add	bp, #2		! next register
	call	print_hex	! print it
	pop	cx
	loop	print_loop
	ret

print_nl:
	mov	ax, #0xe0d	! CR
	int	0x10
	mov	al, #0xa	! LF
	int 	0x10
	ret

/*
 *	print_hex is for debugging purposes, and prints the word
 *	pointed to by ss:bp in hexadecmial.
*/

print_hex:
	mov	cx, #4		! 4 hex digits
	mov	dx, (bp)	! load word into dx
print_digit:
	rol	dx, #4		! rotate so that lowest 4 bits are used
	mov	ah, #0xe	
	mov	al, dl		! mask off so we have only next nibble
	and	al, #0xf
	add	al, #0x30	! convert to 0 based digit, '0'
	cmp	al, #0x39	! check for overflow
	jbe	good_digit
	add	al, #0x41 - 0x30 - 0xa 	! 'A' - '0' - 0xa

good_digit:
	int	0x10
	loop	print_digit
	ret


/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
kill_motor:
	push dx
	mov dx,#0x3f2
	xor al, al
	outb
	pop dx
	ret

sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "Loading"

.org 506
swap_dev:
	.word SWAP_DEV
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss:

