/*
 * functions.asm
 *
 *  Created: 2025/12/14 16:41:30
 *   Author: Administrator
 */ 
 ; ***************************************************************
; 子程序: Mul16x16_32
; 执行 (R10:R11) x (R13:R12) -> (R17:R16:R15:R14)
; ***************************************************************
Mul16x16_32:
    ; 1. 保存工作寄存器 R18 (R_TEMP) 和 SREG
    PUSH R18
    IN R18, SREG
    PUSH R18

    ; 初始化 32 位乘积为零 (R17:R16:R15:R14 = 0)
    CLR R14
    CLR R15
    CLR R16
    CLR R17

; -------------------------------------------------------------------
; Step 1: P0 = AL x BL (R11 x R12)
; -------------------------------------------------------------------
    MUL R11, R12      ; R11 x R12 -> R1:R0
    MOV R14, R0       ; P_0 = P0_L
    MOV R15, R1       ; P_1 = P0_H

; -------------------------------------------------------------------
; Step 2: P1 = AL x BH (R11 x R13)
; -------------------------------------------------------------------
    MUL R11, R13      ; R11 x R13 -> R1:R0
    MOV R20, R0       ; 临时保存低 8 位
    MOV R19, R1       ; 临时保存高 8 位

    ; 累加到 P_1:P_2:R16:R15（右移 8 位）
    ADD R15, R20      ; P_1 = P_1 + P1_L
    CLR R18
    ADC R16, R19      ; P_2 = P_2 + P1_H + Carry
    ADC R17, R18      ; P_3 = P_3 + 0 + Carry

; -------------------------------------------------------------------
; Step 3: P2 = AH x BL (R10 x R12)
; -------------------------------------------------------------------
    MUL R10, R12      ; R10 x R12 -> R1:R0
    MOV R20, R0       ; 临时保存低 8 位
    MOV R19, R1       ; 临时保存高 8 位

    ; 累加到 P_1:P_2:R16:R15（右移 8 位）
    ADD R15, R20      ; P_1 = P_1 + P2_L
    CLR R18
    ADC R16, R19      ; P_2 = P_2 + P2_H + Carry
    ADC R17, R18      ; P_3 = P_3 + 0 + Carry

; -------------------------------------------------------------------
; Step 4: P3 = AH x BH (R10 x R13)
; -------------------------------------------------------------------
    MUL R10, R13      ; R10 x R13 -> R1:R0
    MOV R20, R0       ; 临时保存低 8 位
    MOV R19, R1       ; 临时保存高 8 位

    ; 累加到 P_2:P_3（高 16 位）
    ADD R16, R20      ; P_2 = P_2 + P3_L
    ADC R17, R19      ; P_3 = P_3 + P3_H + Carry

; -------------------------------------------------------------------
; Step 5: 恢复寄存器并返回
; -------------------------------------------------------------------
    POP R18           ; 恢复 SREG
    OUT SREG, R18
    POP R18           ; 恢复 R_TEMP
    ldi  r18, 10
    RET


; R16:R15即为mV值

convert:
; =================================
; 输入：R25:R24 = mV值
; 输出：
;   R21 = 千位
;   R22 = 百位
;   R23 = 十位
;   R20 = 个位
; =================================
    PUSH R28
    PUSH R29
    
    CLR R21
    CLR R22
    CLR R23
    CLR R20
    
    MOV R28, R24        ; R28 = 低位
    MOV R29, R25        ; R29 = 高位

; -------- 千位：除以1000 --------
Thousand_Loop:
    ; 检查是否 >= 1000
    MOV R18, R28
    MOV R19, R29
    SUBI R18, low(1000)
    SBCI R19, high(1000)
    BRCS Hundred_Start   ; 如果借位（小于1000），跳出
    
    ; 做实际的减法
    SUBI R28, low(1000)
    SBCI R29, high(1000)
    INC R21
    RJMP Thousand_Loop


; -------- 百位：除以100 --------
Hundred_Start:
    ; R28:R29 现在 < 1000，保留高字节，使用 16 位减法

Hundred_Loop:
    ; 如果高字节非零，则一定 >=256 >=100，可直接减
    CPI R29, 0
    BRNE Hundred_Sub_Exec
    ; 否则比较低字节是否 >= 100
    CPI R28, 100
    BRLO Ten_Start

Hundred_Sub_Exec:
    ; SUBI/SBCI 实现 16 位减 100（SBIW 立即数范围受限）
    SUBI R28, 100
    SBCI R29, 0
    INC R22
    RJMP Hundred_Loop


; -------- 十位：除以10 --------
Ten_Start:
    ; 使用 16 位比较/减法以保留高字节信息
    CPI R29, 0
    BRNE Ten_Sub_Exec
    CPI R28, 10
    BRLO Ones_Copy

Ten_Sub_Exec:
    ; 使用 SUBI/SBCI 做 16 位减 10
    SUBI R28, 10
    SBCI R29, 0
    INC R23
    RJMP Ten_Start

; -------- 个位 --------
Ones_Copy:
    MOV R20, R28
    
    POP R29
    POP R28
RET

; =================================
; 显示 4 位十进制数
; 使用 R21 R22 R23 R20
; =================================
Display_4Digits:
    LDI R16, 0b00001000    ; 千位
    OUT PORTC, R16
    LDI ZH, high(SEG_TABLE * 2)
    LDI ZL, low(SEG_TABLE * 2)   
    ADD ZL, R21         ; 千位数据
    LPM R16, Z          ; 读取段码  
    ; 千位的小数点常亮：清除 DP 位 (bit5 -> mask 0xDF)
    ANDI R16, 0xFB
    OUT PORTD, R16      ; 输出段码
    RCALL Delay_s    ; 短暂延时
	LDI R16, 0x00 
    OUT PORTC, R16     ; 消隐

	LDI R16, 0b00000100    ; 百位
    OUT PORTC, R16
    LDI ZH, high(SEG_TABLE * 2)
    LDI ZL, low(SEG_TABLE * 2)  
    ADD ZL, R22         ; 百位数据
    LPM R16, Z          ; 读取段码  
    OUT PORTD, R16      ; 输出段码
    RCALL Delay_s    ; 短暂延时
	LDI R16, 0x00 
    OUT PORTC, R16     ; 消隐

	LDI R16, 0b00000010    ; 十位
    OUT PORTC, R16
    LDI ZH, high(SEG_TABLE * 2)
    LDI ZL, low(SEG_TABLE * 2)   
    ADD ZL, R23         ; 十位数据
    LPM R16, Z          ; 读取段码  
    OUT PORTD, R16      ; 输出段码
    RCALL Delay_s    ; 短暂延时
	LDI R16, 0x00 
    OUT PORTC, R16     ; 消隐

	LDI R16, 0b00000001    ; 个位
    OUT PORTC, R16
    LDI ZH, high(SEG_TABLE * 2)
    LDI ZL, low(SEG_TABLE * 2) 
    ADD ZL, R20         ; 个位数据
    LPM R16, Z          ; 读取段码  
    OUT PORTD, R16      ; 输出段码
    RCALL Delay_s    ; 短暂延时
	LDI R16, 0x00 
    OUT PORTC, R16     ; 消隐
	RET


; =================================
; 控制风扇转速
; =================================
Fans:
    ; 保存寄存器
    PUSH R16
    PUSH R17

    ; 从 R10:R11 获取 ADC 值 (R10=高位, R11=低位)
    MOV R16, R11    ; R16 = 低 8 位
    MOV R17, R10    ; R17 = 高 2 位

    ; 将 10 位 ADC 值右移 2 位，转换为 8 位值 (0-255)
    LSR R17
    ROR R16
    LSR R17
    ROR R16

    ; -----------------------------------------------------
    ; 线性映射: 将 0-255 映射到 40-255
    ; 公式: Output = 40 + (Input * 215 / 256)
    ; -----------------------------------------------------
    
    LDI R17, 215    ; 加载乘数 215 (即 255 - 40)
    MUL R16, R17    ; R1:R0 = R16 * 215
    
    MOV R16, R1     ; 取高字节，相当于除以 256
    
    LDI R17, 40     ; 加载偏移量 40 (最小值)
    ADD R16, R17    ; 加上偏移量，结果范围变为 40-254

    ; 更新 OCR2A 寄存器
    STS OCR2A, R16

    ; 恢复寄存器
    POP R17
    POP R16
    RET

.equ inner_count = 200    ; 16-bit counter max
Delay_s:
    PUSH R16
    PUSH R24
    PUSH R25
    ; outer loop = 62 iterations
    ldi  r16, 62             ; outer counter
OuterLoop:
    ; load inner 16-bit counter
    ldi  r25, high(inner_count)
    ldi  r24, low(inner_count)
InnerLoop:
    sbiw r24, 1              ; 2 cycles
    brne InnerLoop           ; 2 cycles if jump, 1 if exit
    dec  r16                 ; 1 cycle
    brne OuterLoop           ; 2 cycles if jump
    POP R25
    POP R24
    POP R16
	ret

Delay:
    PUSH R19
    PUSH R20
    ldi  r19, 50
L2: ldi  r20, 255
L3: dec  r20
    brne L3
    dec  r19
    brne L2
    POP R20
    POP R19
    ret
