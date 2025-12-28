
.include "def.inc"
.include "functions.asm"
LDI r16, high(RAMEND)
out SPH, r16
LDI r16, low(RAMEND)
out SPL, r16
Init:
	ldi R16, 0xFF
	out DDRD, R16   //设置 PORTD 为输出，初始输出值全为 0
	ldi R16, 0x0F   // PC0-PC3 输出 (显示), PC4 输入 (ADC)
	out DDRC, R16   //设置 PORTC 方向
	sbi DDRB, 3
    sbi DDRB, 1
	;---------------- Timer2 配置 (快速PWM) ----------------
    ; Mode 3: Fast PWM, TOP=0xFF
    ; WGM20=1, WGM21=1
    ; output: Clear OC2A on Compare Match (非反向)
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
    ; ---------------- Timer1 配置 (快速PWM) ----------------
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
    STS ADC_Channel_Flag, R16 ; 初始化 ADC 通道标志为 0
	;------------------------------------------------------
	//LDI R16, 1<<ADC0D
	//STS DIDR0, R16    //禁用 PORTC:0 上的数字输入缓冲器 (省电) 
	LDI R16, 0x8F   
	STS ADCSRA, R16 //ADC 使能，转换未开始，单次转换模式(自动触发禁用)，中断禁用，系统时钟 128 分频作为 ADC 时钟
	LDI R16, 0x44   // 选择 ADC4 (PC4)，AVCC 参考
	STS ADMUX, R16   //使用 AVCC 作为参考电压，连接通道 4 到 ADC
	SEI

Start_first_conversion:
	LDS  R16, ADCSRA
	ORI  R16, 1<<ADSC
	STS ADCSRA,R16  //开始转换
    
Main_loop:
    ; --- 数码管显示刷新 ---
    ; 从 SRAM 读取最新的电压值
    LDS R24, Result_mV_L
    LDS R25, Result_mV_H
    RCALL convert           ; 转换电压值为 4 位数字 (R21, R22, R23, R20)
    RCALL Display_4Digits   ; 刷新数码管显示 (耗时约 12ms)

    RJMP Main_loop  

ADC_ISR:
    ; [新增] 保护 SREG 和冲突的寄存器
    PUSH R16
    IN R16, SREG
    PUSH R16        ; 保存 SREG
    PUSH R20
    PUSH R21
    PUSH R22
    PUSH R17        ; 保护 R17 (Fans 和 Mul 使用)
    PUSH R15        ; 保护 R15 (Mul 使用)
    PUSH R14        ; 保护 R14 (Mul 使用)

    ; 读取 ADC，先读 ADCL 再读 ADCH
    LDS R0, ADCL
    LDS R1, ADCH
    MOV R11, R0       ; R_AL = R0 (ADCL)
    MOV R10, R1       ; R_AH = R1 (ADCH)

    ; 检查当前通道
    LDS R16, ADC_Channel_Flag
    CPI R16, 0
    BREQ Handle_ADC4_Fan
    RJMP Handle_ADC5_Servo

Handle_ADC4_Fan:
    ; -------------------------------------------------
    ; 通道 4: 风扇控制 + 电压显示
    ; -------------------------------------------------
    
    ; 1. 调用风扇控制 (使用 R10:R11)
    RCALL Fans

    ; 2. 计算电压值 (ADC * 5000)
    LDI R21, CONST_5000_L ; R21 = 5000_L
    LDI R22, CONST_5000_H ; R22 = 5000_H
    MOV R12, R21      ; R_BL = R21
    MOV R13, R22      ; R_BH = R22

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
    
    ; 保存结果到 SRAM
    STS Result_mV_L, R14  ; 低8位
    STS Result_mV_H, R15  ; 高8位

    ; 3. 切换到 ADC5 (Servo)
    LDI R16, 0x45   ; ADC5, AVCC
    STS ADMUX, R16
    LDI R16, 1
    STS ADC_Channel_Flag, R16
    RJMP ADC_ISR_Exit

Handle_ADC5_Servo:
    ; -------------------------------------------------
    ; 通道 5: 舵机控制
    ; -------------------------------------------------
    ; 算法: Servo_PWM = 1000 + (ADC * 4)
    ; R10:R11 是 ADC 值 (0-1023)
    
    ; 左移 2 位 (x4)
    LSL R11
    ROL R10
    LSL R11
    ROL R10
    
    ; 加上 1000 (SERVO_MIN)
    LDI R16, low(1000)
    ADD R11, R16
    LDI R16, high(1000)
    ADC R10, R16
    
    ; 更新 OCR1A (舵机 PWM)
    STS OCR1AH, R10
    STS OCR1AL, R11
    
    ; 切换到 ADC4 (Fan)
    LDI R16, 0x44   ; ADC4, AVCC
    STS ADMUX, R16
    LDI R16, 0
    STS ADC_Channel_Flag, R16
    RJMP ADC_ISR_Exit

ADC_ISR_Exit:
;*****************************************************
; 开始下一次转换
;*****************************************************
    LDS R16, ADCSRA
    ORI R16, 1<<ADSC
    STS ADCSRA, R16
    
    ; [新增] 恢复寄存器
    POP R14
    POP R15
    POP R17
    POP R22
    POP R21
    POP R20
    POP R16         ; 弹出 SREG 值
    out SREG, R16   ; 恢复 SREG
    POP R16         ; 恢复 R16
    RETI
    RETI

.cseg
SEG_TABLE:
    .db 0b00010100 , 0b11010111 , 0b01001100 , 0b01000101 , 0b10000111 , 0b00100101 , 0b00100100 , 0b01010111 , 0b00000100 , 0b00000101