/*
 * def.inc
 *
 *  Created: 2025/12/14 16:39:58
 *   Author: Administrator
 */ 
 .org 0x0000
    RJMP Init

.org 0x002A                ; ADC conversion complete vector
    RJMP ADC_ISR

.dseg 
.org $0100
Result_mV_L: .byte 1 ; 毫伏特值的低 8 位 (地址 $0100)
Result_mV_H: .byte 1 ; 毫伏特值的高 8 位 (地址 $0101)
Direction_Addr: .byte 1 ; 存储方向变量

.cseg
.equ CONST_5000_L = low(5000)   ; 5000的低8位: $88 (136)
.equ CONST_5000_H = high(5000)  ; 5000的高8位: $13 (19)
.equ SRAM_TEMP_ADDR = 0x0180
; 舵机定义 (16MHz 时钟, 8分频)
; 50Hz 周期 = 40000 计数
; 0度 (0.5ms) = 1000 计数
; 180度 (2.5ms) = 5000 计数
.equ SERVO_MIN = 1000
.equ SERVO_MAX = 5000
.equ STEP_SIZE = 10    ; 步进值，越小越平滑

.def R_AH = R10     ; A_High
.def R_AL = R11     ; A_Low
.def R_BH = R13     ; B_High
.def R_BL = R12     ; B_Low
.def P_0 = R14      ; Product Byte 0 (LSB)
.def P_1 = R15      ; Product Byte 1
.def P_2 = R16      ; Product Byte 2
.def P_3 = R17      ; Product Byte 3 (MSB)
.def R_TEMP = R18
.def R_MULH = R19   ; MUL 指令结果的高位
.def R_MULL = R20   ; MUL 指令结果的低位
.def DutyL = r24  ; 使用16位寄存器对来存储占空比
.def DutyH = r25
; .def Direction = r2 ; Removed to use SRAM instead