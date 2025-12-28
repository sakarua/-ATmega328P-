
.include "def.inc"
.include "functions.asm"
LDI r16, high(RAMEND)
OUT SPH, r16
LDI r16, low(RAMEND)
OUT SPL, r16
Init:
	LDI R16, 0xFF
	OUT DDRD, R16   //set PORTD as output, with initial output value all 0's
	LDI R16, 0x0F   // PC0-PC3 Output (Display), PC4 Input (ADC)
	OUT DDRC, R16   //set PORTC direction
	sbi DDRB, 3
    sbi DDRB, 1
	;---------------- Timer2: Fast PWM ----------------
    ; Mode 3: Fast PWM, TOP=0xFF
    ; WGM00=1, WGM01=1
    ; Output: Clear OC2B on Compare Match (Non-inverting)
    ; COM0B1=1
    ldi r16, (1<<COM2A1) | (1<<WGM21) | (1<<WGM20)
    sts TCCR2A, r16

    ; Prescaler = 64
    ; CS01=1, CS00=1
    ldi r16, (1<<CS22)
    sts TCCR2B, r16

    ; Initial Duty = 0
    ldi r16, 40
    sts OCR2A, r16
    ; ---------------- Timer1 配置 (模式 14) ----------------
    ; 模式 14: Fast PWM, TOP = ICR1
    ; COM1A1:1 (非反相), WGM11:1
    ldi r16, (1<<COM1A1) | (1<<WGM11)
    sts TCCR1A, r16

    ; WGM13:1, WGM12:1 (模式14), CS11:1 (8分频)
    ldi r16, (1<<WGM13) | (1<<WGM12) | (1<<CS11)
    sts TCCR1B, r16

    ; 设置 TOP 值定义频率为 50Hz (16MHz / (8 * 50) = 40000)
    ldi r16, high(40000)
    sts ICR1H, r16
    ldi r16, low(40000)
    sts ICR1L, r16

    ; 初始位置
    ldi DutyH, high(SERVO_MIN)
    ldi DutyL, low(SERVO_MIN)
    LDI R16, 0
    STS Direction_Addr, R16
	;------------------------------------------------------
	//LDI R16, 1<<ADC0D
	//STS DIDR0, R16    //Disable digital input buffer on PORTC:0 (saving power) 
	LDI R16, 0x8F   
	STS ADCSRA, R16 //ADC enalbe, conversion not started, single conversion mode(auto trigger disabled), interrupt disable, system clk diveded by 128 as ADC clock
	LDI R16, 0x44   // ADC4 (PC4) selected, AVCC reference
	STS ADMUX, R16   //use AVCC as reference voltage, connect channel 4 to ADC
	SEI

Start_first_conversion:
	LDS  R16, ADCSRA
	ORI  R16, 1<<ADSC
	STS ADCSRA,R16  //start conversion
    
Main_loop:
    sts OCR1AH, DutyH
    sts OCR1AL, DutyL

    ; --- 数码管显示刷新 ---
    ; 从 SRAM 读取最新的电压值
    LDS R24, Result_mV_L
    LDS R25, Result_mV_H
    RCALL convert           ; 转换电压值为 4 位数字 (R21, R22, R23, R20)
    RCALL Display_4Digits   ; 刷新数码管显示 (耗时约 12ms)

    ; rcall Delay ; 移除额外的延时，因为 Display_4Digits 已经提供了足够的延时

    ; --- 逻辑判断 ---
    LDS R16, Direction_Addr
    TST R16
    breq Increment
    rjmp Decrement

Increment:
    adiw DutyL, STEP_SIZE
    ; 比较是否达到最大值
    ldi r16, high(SERVO_MAX)
    cpi DutyL, low(SERVO_MAX)
    cpc DutyH, r16
    brlo Main_loop
    LDI R16, 1
    STS Direction_Addr, R16
    rjmp Main_loop

Decrement:
    sbiw DutyL, STEP_SIZE
    ; 比较是否达到最小值
    ldi r16, high(SERVO_MIN)
    cpi DutyL, low(SERVO_MIN)
    cpc DutyH, r16
    brsh Main_loop
    LDI R16, 0
    STS Direction_Addr, R16
    RJMP Main_loop  

ADC_ISR:
    ; [新增] 保护 SREG 和冲突的寄存器
    PUSH R16
    IN R16, SREG
    PUSH R16        ; 保存 SREG
    PUSH R20
    PUSH R21
    PUSH R22

    ; 读取 ADC，先读 ADCL 再读 ADCH
    LDS R0, ADCL
    LDS R1, ADCH

	//准备乘法运算：ADC_Value * 5000
    LDI R21, CONST_5000_L ; R21 = 5000_L
    LDI R22, CONST_5000_H ; R22 = 5000_H
	MOV R11, R0       ; R_AL = R0 (ADCL)
    MOV R10, R1       ; R_AH = R1 (ADCH)

    MOV R12, R21      ; R_BL = R21 (CONST_5000_L)
    MOV R13, R22      ; R_BH = R22 (CONST_5000_H)

	rcall Mul16x16_32
; 右移10位
    LDI R20, 10
ShiftLoop:
    LSR R17
    ROR R16
    ROR R15
    ROR R14
    DEC R20
    BRNE ShiftLoop
    ; 右移10位后，16位有效数据在R15:R14中
    ; [修改] 删除了覆盖 R24/R25 (DutyL/H) 的指令
    STS Result_mV_L, R14  ; 低8位
    STS Result_mV_H, R15  ; 高8位
; 此时R16:R15为mV值

;*****************************************************
; 显示及风扇控制部分模块
;*****************************************************
	RCALL Fans
;*****************************************************
; 开始下一次转换
;*****************************************************
    LDS R16, ADCSRA
    ORI R16, 1<<ADSC
    STS ADCSRA, R16
    
    ; [新增] 恢复寄存器
    POP R22
    POP R21
    POP R20
    POP R16         ; 弹出 SREG 值
    OUT SREG, R16   ; 恢复 SREG
    POP R16         ; 恢复 R16
    RETI
    RETI

.cseg
SEG_TABLE:
    .db 0b00010100 , 0b11010111 , 0b01001100 , 0b01000101 , 0b10000111 , 0b00100101 , 0b00100100 , 0b01010111 , 0b00000100 , 0b00000101