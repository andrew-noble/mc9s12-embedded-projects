;**************************************************************************************
;* Lab 5 Main [includes LibV2.2]                                                      *
;**************************************************************************************
;* Summary:                                                                           *
;*   Proportional plus integral controller to regulate a brushless DC motor, complete *                                                               
;*   with user-entered proportional and integral scaling constants and input voltage. *
;*                                                                                    *
;*   The control loop is executed using timer channel 0 interrupts every 0.2 ms and   *
;*   LCD is updated with values every 0.5 seconds. All other tasks handle user        *
;*   interface and input.                                                             *
;*                                                                                    *
;*                                                                                    *                                                                     *
;*                                                                                    *                                                                                      
;* Author: Andrew Noble                                                               *
;*   Cal Poly University                                                              *
;*   Winter 2020                                                                      *
;*                                                                                    *
;* Revision History:                                                                  *
;*   -                                                                                *
;*                                                                                    *
;* ToDo:                                                                              *
;*   -                                                                                *
;**************************************************************************************

;/------------------------------------------------------------------------------------\
;| Include all associated files                                                       |
;\------------------------------------------------------------------------------------/
; The following are external files to be included during assembly


;/------------------------------------------------------------------------------------\
;| External Definitions                                                               |
;\------------------------------------------------------------------------------------/
; All labels that are referenced by the linker need an external definition

              XDEF  main

;/------------------------------------------------------------------------------------\
;| External References                                                                |
;\------------------------------------------------------------------------------------/
; All labels from other files must have an external reference

              XREF  ENABLE_MOTOR, DISABLE_MOTOR
              XREF  STARTUP_MOTOR, UPDATE_MOTOR, CURRENT_MOTOR
              XREF  STARTUP_PWM, STARTUP_ATD0, STARTUP_ATD1
              XREF  OUTDACA, OUTDACB
              XREF  STARTUP_ENCODER, READ_ENCODER
              XREF  INITLCD, SETADDR, GETADDR, CURSOR_ON, CURSOR_OFF, DISP_OFF
              XREF  OUTCHAR, OUTCHAR_AT, OUTSTRING, OUTSTRING_AT
              XREF  INITKEY, LKEY_FLG, GETCHAR
              XREF  LCDTEMPLATE, UPDATELCD_L1, UPDATELCD_L2
              XREF  LVREF_BUF, LVACT_BUF, LERR_BUF,LEFF_BUF, LKP_BUF, LKI_BUF
              XREF  Entry, ISR_KEYPAD
            
;/------------------------------------------------------------------------------------\
;/------------------------------------------------------------------------------------\
;| Assembler Equates                                                                  |
;\------------------------------------------------------------------------------------/
; Constant values can be equated here

TSCR          EQU $0046      ; timer system control register, controls start/stop of timer
TIOS          EQU $0040      ; TIC TOC register, determines if output compare or input capture                  ; 
TCR2          EQU $0049      ; timer control register 2, selects the output action resulting from 
                             ; successful output compare
C0F           EQU $004E      ; timer flag register, contains all timer channel flags
TIE1          EQU $004C      ; timer interrupt enable register, enables maskable interrupts
TCNT          EQU $0044      ; first word of timer count (low word will be grabbed auto if using 
                             ; 2-word commands)
TC0           EQU $0050      ; timer channel 0 register (next memory location is low word)

INTERVAL      EQU $4E20     ; set the interrupt rate to 2ms (4E20 = 20000)



;/------------------------------------------------------------------------------------\
;| Variables in RAM                                                                   |
;\------------------------------------------------------------------------------------/
; The following variables are located in unpaged ram

DEFAULT_RAM:  SECTION

; State Variables

t1state        DS.B 1
t2state        DS.B 1
t3state        DS.B 1
t4state        DS.B 1

;TC0_ISR/Control Variables:

OL:            DS.B 1            ; variable that indicates open-loop operation
                                
theta_old:     DS.W 1            ; previous encoder reading that future encoder readings 
                                 ; are measured from (its their datum)
                                
Vref:          DS.W 1            ; binary form of user-inputted reference voltage
Ki1024:        DS.W 1            ; binary forms of user inputted 1024*K values
Kp1024:        DS.W 1

Vact:          DS.W 1            ; (binary) copies of calculated parameters
Err:           DS.W 1
Eff:           DS.W 1

Vact_disp:     DS.W 1            ; (binary) copies of the calculated values to be displayed
Err_disp:      DS.W 1            ; needed to ensure that the displayed values are consistent
Eff_disp:      DS.W 1            ; (non disp values change too fast for display to update)

disp_ctr:      DS.B 1            ; 1 byte counter variable used to trigger display updates every ~0.5s

esum_old:      DS.W 1            ; previous error summation to which new error is added

; General Variables

RUN:           DS.B 1             ; dictates whether motor is running or not
D_ON:          DS.B 1             ; dictates whether screen updating is active or not                    
KP_FLG:        DS.B 1             ; booleans that indicate whether Ki or Kp or Vref entry is active
KI_FLG:        DS.B 1
VREF_FLG:      DS.B 1
SIGN_FLG:      DS.B 1             ; boolean true if <+> or <-> has already been entered for Vref
CURSOR_SAVE:   DS.B 1             ; spot to save the cursor location

; Display Booleans

D_UPDATE_L1:   DS.B 1
D_UPDATE_L2:   DS.B 1
D_ECHO:        DS.B 1
D_BS:          DS.B 1
D_VrefPREP:    DS.B 1
D_KPREP:       DS.B 1
D_OL_tog:      DS.B 1
D_RUN_tog:     DS.B 1
D_ON_tog:      DS.B 1
D_INIT_STATUS  DS.B 1

; Display Variables

DPTR:          DS.W 1        ; "digit pointer" address of next character in mess to be read, displayed
FIRSTCH:       DS.B 1        ; boolean that is true if next character is the first of a mess

; Key Variables

COUNT:         DS.B 1        ; # of digits successfully captured from keypad
POINTER:       DS.W 1        ; address of the next available space in buffer
BUFFER:        DS.B 6        ; storage unit for an entire keypad input pre-conversion

KEY_BUF:       DS.B 1        ; storage for a single key input, sent from keypad handler to MM
KEY_FLG:       DS.B 1

;/------------------------------------------------------------------------------------\
;|  Main Program Code                                                                 |
;\------------------------------------------------------------------------------------/
; Your code goes here

MyCode:       SECTION

main:   
      clr t1state
      clr t2state
      clr t3state
      clr t4state
  

loop: 
      jsr TASK_1
      jsr TASK_2
      jsr TASK_3
      jsr TASK_4
      
      bra loop
         
;--------------------------------------  TASK_1: Mastermind ---------------------------------
TASK_1:
         ldaa t1state
         beq  t1state0                ; init state, raises all initial prompt message flags
         deca
         lbeq  t1state1                ; waits for prompts to be displayed 
         deca
         lbeq  t1state2                ; hub state, identifies keys that are retrieved by keypad handler, ignores invalids              
         deca
                                      ; each handler determines whether their respective key needs
                                      ; to be ignored. If not, appropriate actions are taken
                                      
         lbeq  t1s3_Ahandler       
         deca                         
         lbeq  t1s4_Bhandler
         deca
         lbeq  t1s5_Chandler
         deca
         lbeq  t1s6_Dhandler
         deca
         lbeq  t1s7_Ehandler
         deca
         lbeq  t1s8_Fhandler
         deca
         lbeq t1s9_BShandler          ; determines whether BS is a valid entry atm, then raises BS_FLG if so
         deca
         lbeq t1s10_ENThandler        ; executes ASCII->BCD->binary conv, updates values and flags accordingly
         deca
         lbeq t1s11_plushandler      
         deca
         lbeq t1s12_neghandler       
         deca
         lbeq t1s13_digithandler      ; loads digits into buffer

         
t1state0:                     

         movb #$20,LVREF_BUF          ; init L1 lib display buffers to display 0
         movb #$30,LVREF_BUF+1
         movb #$20,LVREF_BUF+2
         movb #$20,LVREF_BUF+3
         
         movb #$20,LVACT_BUF
         movb #$30,LVACT_BUF+1
         movb #$20,LVACT_BUF+2
         movb #$20,LVACT_BUF+3
                     
         movb #$20,LERR_BUF
         movb #$30,LERR_BUF+1
         movb #$20,LERR_BUF+2
         movb #$20,LERR_BUF+3
         
         movb #$20,LEFF_BUF
         movb #$30,LEFF_BUF+1
         movb #$20,LERR_BUF+2
         movb #$20,LERR_BUF+3
         
         movb #$37,LKP_BUF            ; init LKP_BUF to show 717
         movb #$31,LKP_BUF+1
         movb #$37,LKP_BUF+2
         movb #$20,LKP_BUF+3
         movb #$20,LKP_BUF+4
         
         movb #$32,LKI_BUF            ; init LKI_BUF to show 230
         movb #$33,LKI_BUF+1
         movb #$30,LKI_BUF+2
         movb #$20,LKI_BUF+3
         movb #$20,LKI_BUF+4
         
         movb #$01,D_INIT_STATUS      ; raise flag to init the condition indicator
         
         clr  D_UPDATE_L1
         clr  D_UPDATE_L2
         clr  D_ON_tog                ; init alot of stuff
         clr  D_RUN_tog                  
         clr  D_OL_tog
         clr  D_KPREP                    
         clr  D_VrefPREP
         clr  D_BS
         clr  D_ECHO
         clr  KP_FLG
         clr  KI_FLG
         clr  VREF_FLG
         clr  disp_ctr
         clrw esum_old
         clrw Vref
         clrw Vact
         clrw Err
         clrw Eff
         clrw Vact_disp
         clrw Err_disp
         clrw Eff_disp
         clr  OL
         clr  RUN
         movb #$01, D_ON
         clr  COUNT
         clr  SIGN_FLG              ; init buffer
         clrw BUFFER
         clrw BUFFER+2
         clrw BUFFER+4
         movw #717, Kp1024
         movw #230, Ki1024
         jsr  STARTUP_ENCODER
         jsr  STARTUP_PWM
         jsr  STARTUP_MOTOR
         
         jsr  READ_ENCODER          ; initialize theta_old to the current encoder count
         std  theta_old             ; this is important for giving future encoder readings a datum

         movb #$01, t1state
         rts
            
t1state1:                             ; MM stays in this state until all inital messages are displayed on the LCD
         tst D_UPDATE_L1
         bne t1s1exit
         tst D_UPDATE_L2
         bne t1s1exit
         tst D_INIT_STATUS
         bne t1s1exit                
         movb #$02, t1state
          
t1s1exit:
         rts

;--------------
t1state2:                             ; this is MM hub state, it interrogates keys retrieved from keypadhandler
         tst  KEY_FLG                            
         beq  t1s2exit                ; if key flag is low, just rts                                                  
         ldaa KEY_BUF                 ; grab the key entered from KEY_BUF 

askA:  
         cmpa #$41                    ; test for A
         bne  askB
         movb #$03, t1state
         bra  t1s2exit
         
askB: 
         cmpa #$42                    ; test for ENT
         bne  askC
         movb #$04, t1state
         bra  t1s2exit         
askC:  
         cmpa #$43                    ; test for A
         bne  askD
         movb #$05, t1state
         bra  t1s2exit
         
askD: 
         cmpa #$44                    ; test for ENT
         bne  askE
         movb #$06, t1state
         bra  t1s2exit 

askE:  
         cmpa #$45                     ; test for A
         bne  askF
         movb #$07, t1state
         bra  t1s2exit
         
askF: 
         cmpa #$46                     ; test for ENT
         bne  askBS                    
         movb #$08, t1state
         bra  t1s2exit 

askBS:  
         cmpa #$08                     ; test for BS
         bne  askENT
         movb #$09, t1state
         bra  t1s2exit
         
askENT: 
         cmpa #$0A                     ; test for ENT
         bne  askplus
         movb #$0A, t1state
         bra  t1s2exit
         
askplus:                              ; test for <+>
         cmpa #$F1                    ; F1 key corresponds to <+> for this lab
         bne  askneg
         movb #$0B, t1state
         bra  t1s2exit
askneg:                               ; test for <->
         cmpa #$F2                    ; F2 key corresponds to <-> for this lab
         bne  askdigit
         movb #$C, t1state
         bra  t1s2exit
         
askdigit:        
         cmpa #$30                    ; test if its a ASCII digit (between $30-$39)
         blo  t1s2exit                
         cmpa #$39
         bhi  t1s2exit                
         
         movb #$D, t1state           ; finally, MM has determined that this digit can be passed to t1s7_digithandler

t1s2exit:
         clr KEY_FLG                  ; lower the key flag since the key was acknowledged by MM
         rts
         
;----------------         
t1s3_Ahandler:                        ; <A> toggles run, turning motor on and off
        
         tstw KP_FLG                  ; accept <A> iff both KI_FLG and KP_FLG are low
         bne  Aexit                   ; (tstw tests them both since they're neighbors in RAM)                    
        
         tst  RUN
         bne  STOP
         movb #$01, RUN               ; set run
         jsr  ENABLE_MOTOR
         clr  esum_old                ; we must clear old error sum so that it does not 
                                      ; affect this new run
         bra  Aexit
         
STOP:
         clr RUN
         jsr DISABLE_MOTOR
             
Aexit:
         movb #$01, D_RUN_tog         ; toggle run on the display
         movb #$02, t1state
         rts
         
;----------------         
t1s4_Bhandler:                        ; <B> toggles the screen on and off.
                                      ; <B> is always accepted
                                       
         movb #$01, D_ON_tog         ; toggle display indicator on display

         tst  D_ON
         bne  freeze_disp
         movb #$01, D_ON             ; tell display to start updating
         bra  Bexit
         
freeze_disp:
         clr  D_ON                   ; freeze display
         
Bexit:
         movb #$02, t1state
         rts
         
;----------------         
t1s5_Chandler:                        ; <C> prompts user to change Vref
        
         tstw KP_FLG                  ; accept <C> iff KI_FLG and KP_FLG and VREF_FLG are low
         bne  Cexit
         tst  VREF_FLG                                       
         bne  Cexit
         
         movw #BUFFER, POINTER        ; set up pointer as the address of first spot in buffer
         clr  COUNT
          
         movb #$01, D_VrefPREP        ; tell display to prep for Vref entry
         movb #$01, VREF_FLG          ; raise Vref flag
         
         
Cexit:
         movb #$02, t1state
         rts
;----------------         
t1s6_Dhandler:                        ; <D> turns off motor and prompts user to change Kp 
        
         tstw KP_FLG                  ; accept <D> iff KI_FLG and KP_FLG and VREF_FLG are low
         bne  Dexit
         tst  VREF_FLG                                       
         bne  Dexit
         
         movw #BUFFER, POINTER        ; set up pointer as the address of first spot in buffer
         clr  COUNT
         movb #$01, D_KPREP           ; tell display to prep for K entry
         movb #$01, KP_FLG            ; raise KP_FLG                    
         movb #$01, SIGN_FLG          ; prevent sign entry in K field
         movb #$01, D_RUN_tog
         clr  RUN                     ; stop the motor
                                 
Dexit:
         movb #$02, t1state
         rts
         
;----------------         
t1s7_Ehandler:                        ; <E> turns off motor and prompts user to change Ki
        
         tstw KP_FLG                  ; accept <D> iff KI_FLG and KP_FLG and VREF_FLG are low
         bne  Eexit
         tst  VREF_FLG                                       
         bne  Eexit
         
         movw #BUFFER, POINTER        ; set up pointer as the address of first spot in buffer
         clr  COUNT
         movb #$01, D_KPREP           ; tell display to prep for K entry
         movb #$01, KI_FLG            ; raise KI_FLG
         movb #$01, SIGN_FLG          ; prevent sign entry in K field 
         movb #$01, D_RUN_tog
         clr  RUN                     ; stop the motor
                                 
Eexit:
         movb #$02, t1state
         rts

;----------------         
t1s8_Fhandler:                        ; <F> toggles open-loop mode
        
         tstw KP_FLG                  ; accept <D> iff KI_FLG and KP_FLG and VREF_FLG are low
         bne  Fexit
         tst  VREF_FLG                                       
         bne  Fexit
         
         
         tst  OL
         beq  open_the_loop
         clr  OL                     
         bra  t1s8a
         
open_the_loop:

         movb #$01, OL                ; set OL var
         clrw Ki1024                  ; clear Ki input value           
         movb #$30,LKI_BUF            ; change Ki library buffer to display 0
         movb #$20,LKI_BUF+1
         movb #$20,LKI_BUF+2          
         movb #$20,LKI_BUF+3
         movb #$20,LKI_BUF+4

t1s8a:
         movb #$01, D_OL_tog          ; tell display to toggle CL indicator
         movb #$01, D_UPDATE_L2
                                          
Fexit:
        
         movb #$02, t1state           ; return to hub
         rts
; ------------------
t1s9_BShandler:
                          
         tst  COUNT                   ; ignore a <BS> entry if there is nothing to backspace
         beq  BSexit                  ; (this also ignores <BS> if no entry flags are up)  
        
         movb #$01, D_BS              ; raise the BS flag for display to do its thang
         
BSexit:
         movb #$02, t1state
         rts
; ------------------         
t1s10_ENThandler:

         tstw KP_FLG                  ; only accepts <ENT> if one of the three entry flags is up
         bne  t1s10a                 
         tst  VREF_FLG
         beq  ENTignoreexit           ; if all three entry flags are down, ignore the <ENT>
         
t1s10a:          
         tst  COUNT
         beq  ENTexit                 ; exit immediately if no digits were there to be entered
                   
         jsr  ASCII_to_BIN            ; convert entry to binary

         tstw KP_FLG                  ; test for what is being updated
         beq  Vref_update
         
         tst  KP_FLG                  ; test if its KP
         beq  KI_update
         
KP_update:         
         stx  Kp1024                  ; must be Kp
         clrw LKP_BUF                 ; clear LKP_BUF before new numbers added
         clrw LKP_BUF+2
         clr  LKP_BUF+4
         
         tfr  x, d
         ldy  #LKP_BUF                ; load library buffer with new value for screen update 
         jsr  BIN_to_ASCII
         bra  ENTexit
         
Vref_update:
                                       
         stx  Vref                    ; store binary result from ASCII_to_BIN in Vref
         clrw LVREF_BUF               ; clear LVREF_BUF before new numbers added
         clrw LVREF_BUF+2
         
         tfr  x, d                    ; below code loads library buffer with new LCD value
         ldy  #LVREF_BUF                  
         jsr  BIN_to_ASCII
         bra  ENTexit
         
KI_update:
         stx  Ki1024                  ; store binary result in in Ki1024
         clrw LKI_BUF                 ; clear LKI_BUF before new numbers added
         clrw LKI_BUF+2
         clr  LKI_BUF+4
         
         tfr  x, d                    ; below code loads library buffer with new LCD value
         ldy  #LKI_BUF                  
         jsr  BIN_to_ASCII
         bra  ENTexit
         
ENTignoreexit:                        ; used when the <ENT> ignored
         movb #$02, t1state
         rts         
                                
ENTexit:
         movb #$02, t1state
         movb #$01, D_UPDATE_L1       ; update screen with with entry (or lack of entry)
         movb #$01, D_UPDATE_L2       ; restore L2 template (this then updates L2)
         clr  esum_old                ; we must clear old error sum so that it does not affect new
         clr  COUNT
         clrw KP_FLG                  
         clr  VREF_FLG
         clr  SIGN_FLG
         rts
;------------------
t1s11_plushandler:
         
         tst SIGN_FLG
         bne plusexit                  ; ignore <+> if VREF_FLG = 0 or SIGN_FLG = 1
         tst VREF_FLG
         beq plusexit
         
         
         ldx  POINTER                  ; load the plus into first spot of buffer
         ldaa #$2B                  
         staa 0, x                                
         inc  COUNT                    
         incw POINTER
         movb #$01, SIGN_FLG                   
         movb #$01, D_ECHO             
         
         
plusexit:
         movb #$02, t1state
         rts
;------------------
t1s12_neghandler:
         
         tst SIGN_FLG
         bne negexit                   ; ignore <-> if VREF_FLG = 0 or SIGN_FLG = 1
         tst VREF_FLG
         beq negexit
         
         
         ldx  POINTER                  ; load the negative sign into first spot of buffer
         ldaa #$2D                  
         staa 0, x                                
         inc  COUNT                    
         incw POINTER
         movb #$01, SIGN_FLG                   
         movb #$01, D_ECHO             
         
         
negexit:
         movb #$02, t1state
         rts         
;------------------
t1s13_digithandler:

         ldab COUNT
         tstw KP_FLG                  ; only accepts digits if one of the three entry flags is up
         bne  K_limit                 ; also directs digits to repective buffer loading        
         tst  VREF_FLG                ; protocol based on Vref or K entry
         bne  VREF_limit
         beq  digitexit                
                                   
K_limit:                             
         cmpb #$05                    ; K's can hold 5 (no sign), so BUFFER capacity is 5
         bhs  digitexit               ; ignore digit if buffer is full
         bra  digit_load 

                                      
                                      
VREF_limit:
         movb #$01, SIGN_FLG          ; if user enters a digit, they can no longer enter a sign
             
                                      ; if a sign has been used in Vref entry, we need to
                                      ; limit BUFFER to 4 chars (sign and 3 digits), otherwise
                                      ; we need to limit it to 3 characters (3 digits)

         ldx  #BUFFER                 ; test if the first char in BUFFER is a digit
         ldaa 0,x                   
         cmpa #$30                    
         blo  VREF_4_limit                
         cmpa #$39
         bhi  VREF_4_limit
         
         cmpb #$03                    ; if first char in buffer is digit, then limit to 3
         bhs  digitexit
         bra  digit_load
         
VREF_4_limit:                         ; if its not, it must be a <+> or <->, so limit is 4, not 3
         cmpb #$04
         bhs  digitexit         

digit_load:                                  
         ldx  POINTER
         ldaa KEY_BUF                  ; load the key collected by keypadhandler into a
         staa 0, x                     ; store whats in a (KEY_BUF) into adress location x           
         inc  COUNT                    ; (which is the first spot in buffer)
         incw POINTER                   
         movb #$01, D_ECHO             ; raise the echo_flg to tell display to echo this digit 
                         
digitexit:
         movb #$02, t1state
         rts
         
;------------------  TASK_2: Keypad Handler (inits, checks for keypad entries then alerts MM) ----------

TASK_2:
         ldaa t2state
         beq  t2state0
         deca
         beq  t2state1
         deca
         beq  t2state2
        
t2state0:        
         jsr  INITKEY           ; initialize the keypad
         clr  KEY_BUF
         clr  KEY_FLG
         movb #$01, t2state
         rts
        
t2state1:                        ; this state checks for key presses
         tst  LKEY_FLG           ; LKEY_FLG is the "key available flag," is high when a char is avail, low when not
         beq  t2exit                ; move on if there is not character to be collected from getchar
         jsr  GETCHAR            ; GETCHAR retrieves entered char and return it in accum b 
         stab KEY_BUF            ; store b (entered char) in KEY_BUF
         movb #$01, KEY_FLG      ; key flag alerts mastermind that there is a character ready to be displayed
         movb #$02, t2state
         rts      
                   
t2state2:                        ; this task waits for mastermind to acknowledge the KEY_FLG raised in state 1
         tst  KEY_FLG            ; mastermind will lower KEY_FLG when it acknowledges it
         bne  t2exit               ; wait longer if mastermind has not acknowledged KEY_FLG (KEY_FLG =1 still)
         movb #$01, t2state      ; MM lowered KEY_FLG, so we can return to state 1 for next key   

t2exit:    
         rts  
;---------------------------- TASK_3: Display Controller ---------------------------------

TASK_3: 
         ldaa t3state          
         beq  t3state0         ; init state
         deca
         beq  t3state1         ; hub state that tests to see if anything needs to be displayed
         deca
         lbeq  t3state2        ; toggles run/stop onscreen
         deca
         lbeq  t3state3        ; toggles D_ON/D_OFF onscreen
         deca
         lbeq  t3state4        ; toggles OL/CL onscreen
         deca
         lbeq  t3state5        ; clears and updates line 1 fields
         deca
         lbeq  t3state6        ; updates line 2 and updates line 1 fields
         deca
         lbeq  t3state7        ; prepares screen for Vref entry
         deca
         lbeq  t3state8        ; prepares screen for Ki or Kp entry
         deca
         lbeq  t3state9        ; Echo
         deca
         lbeq  t3state10       ; backspacer 
         deca
         lbeq  t3state11       ; displays starting RUN/CL/D_ON status 
         
t3state0: 
         jsr  INITLCD          ; initialise the display
         jsr  CURSOR_ON
         jsr  LCDTEMPLATE
         jsr  UPDATELCD_L1
         jsr  UPDATELCD_L2            
         movb #$01, t3state
         movb #$01, FIRSTCH
         rts
         
t3state1:                      ; display hub state: each subtask tests a different message boolean
         tst  D_RUN_tog                
         beq  t3s1a            ; branch to next boolean check if D_RUN_tog is low
         movb #$02, t3state    ; advance state var so that next round options message is displayed 
         rts
t3s1a:
         tst  D_ON_tog   
         beq  t3s1b	      
         movb #$03, t3state
         rts
t3s1b:   
         tst  D_OL_tog
         beq  t3s1c             
         movb #$04, t3state     
         rts 
t3s1c:
         tst  D_UPDATE_L1
         beq  t3s1d
         movb #$05, t3state
         rts
t3s1d:
         tst  D_UPDATE_L2
         beq  t3s1e
         movb #$06, t3state
         rts
t3s1e:
         tst  D_KPREP
         beq  t3s1f
         movb #$07, t3state
         rts
t3s1f:
         tst  D_VrefPREP
         beq  t3s1g
         movb #$08, t3state
         rts
t3s1g:
         tst  D_ECHO
         beq  t3s1h
         movb #$09, t3state
         rts
t3s1h:
         tst  D_BS
         beq  t3s1i
         movb #$0A, t3state
         rts
t3s1i:
         tst  D_INIT_STATUS
         beq  t3s1exit
         movb #$0B, t3state
         rts

t3s1exit:
         rts
         
;----------------
t3state2:                         
                                  ; this is the RUN/STP indicator toggler             
         tst  FIRSTCH             ; check if first char of a message so that cursor can be set properly
         beq  t3s2b               ; if it isn't the first character, branch to next char printing
                                  ; because cursor is already in the correct position from last char
                                  
         jsr  GETADDR             ; remember the location of the cursor
         staa CURSOR_SAVE                         
                                  
                                  
                                  ; if this is the first char, perform the following setup:
         ldaa #$5C                ; load a with the desired cursor address for 1st char
         
         
                                  ; now determine if toggle to STOP or toggle to RUN is needed
         tst  RUN                 
         beq  tog_to_STP
         ldx  #RUN_MESS           ; load x with addr of first char in appropriate mess
         bra  t3s2a
         
tog_to_STP:         
         ldx  #STP_MESS           ; load x with addr of first char in appropriate mess

t3s2a:
         jsr  PUTCHAR_1ST
         bra  t3s2done

t3s2b:
         jsr PUTCHAR              
                                                                       
t3s2done:
         tst  FIRSTCH             ; notice that this snippet is entered by "fall through" from t3s2a
         beq  t3s2c               ; this branch will be bypassed when PUTCHAR sets FIRSTCH back to 1 after message
                                  ; is successfully displayed
         clr  D_RUN_tog           ; else, (it is done), clear the display boolean
         ldaa CURSOR_SAVE         ; return cursor to where it was
         jsr  SETADDR
         
         movb #$01, t3state       ; return to hub state

t3s2c: 
         rts
         
;----------------
t3state3:                         ; this is the D_ON/D_OFF indicator toggler
                                  ; it is very similar in structure to t3s2             
         tst  FIRSTCH             
         beq  t3s3b               
         jsr  GETADDR             ; remember the location of the cursor
         staa CURSOR_SAVE
         
                         
         ldaa #$63                
         tst  D_ON                 
         beq  tog_to_OFF
         ldx  #D_ON_MESS           
         bra  t3s3a
         
tog_to_OFF:         
         ldx  #D_OFF_MESS           

t3s3a:
         jsr  PUTCHAR_1ST
         bra  t3s3done

t3s3b:
         jsr PUTCHAR              
                                                                       
t3s3done:
         tst  FIRSTCH             
         beq  t3s3c                                        
         clr  D_ON_tog
         
         ldaa CURSOR_SAVE         ; return cursor to where it was
         jsr  SETADDR            
         movb #$01, t3state       

t3s3c: 
         rts
;----------------
t3state4:                         ; this is the OL/CL indicator toggler
                                  ; it is very similar in structure to t3s2             
         tst  FIRSTCH             
         beq  t3s4b               
                         
         ldaa #$60                

         tst  OL                 
         beq  tog_to_CL
         ldx  #OL_MESS           
         bra  t3s4a
         
tog_to_CL:         
         ldx  #CL_MESS           

t3s4a:
         jsr  PUTCHAR_1ST
         bra  t3s4done

t3s4b:
         jsr PUTCHAR              
                                                                       
t3s4done:
         tst  FIRSTCH             
         beq  t3s4c                                        
         clr  D_OL_tog
         ldaa #$01                 ; hide cursor under and underscore
         jsr  SETADDR            
         movb #$01, t3state       

t3s4c: 
         rts
;----------------
t3state5:                          ; this state both prepares (clears) fields on L1
                                   ; then calls UPDATELCD_L1 to update the fields
                               
         tst  FIRSTCH          
         beq  t3s5a
         jsr  GETADDR              ; remember the location of the cursor
         staa CURSOR_SAVE               
                                                    
         ldaa #$00             
         ldx  #VRESTORE_MESS          
         jsr  PUTCHAR_1ST
         bra  t3s5done

t3s5a:
         jsr PUTCHAR 
                                            
t3s5done:
         tst  FIRSTCH              
         lbeq  t3s5b
         
         movb #$20,LVREF_BUF          ; clear current library buffers
         movb #$20,LVREF_BUF+1
         movb #$20,LVREF_BUF+2
         movb #$20,LVREF_BUF+3
         
         movb #$20,LVACT_BUF
         movb #$20,LVACT_BUF+1
         movb #$20,LVACT_BUF+2
         movb #$20,LVACT_BUF+3
                     
         movb #$20,LERR_BUF
         movb #$20,LERR_BUF+1
         movb #$20,LERR_BUF+2
         movb #$20,LERR_BUF+3
         
         movb #$20,LEFF_BUF
         movb #$20,LEFF_BUF+1
         movb #$20,LEFF_BUF+2
         movb #$20,LEFF_BUF+3
         
         ldd Vref                  ; fill LCD update library buffers with current calc disp values
         ldy #LVREF_BUF
         jsr BIN_to_ASCII
         
         ldd Vact_disp
         ldy #LVACT_BUF
         jsr BIN_to_ASCII
         
         ldd Err_disp
         ldy #LERR_BUF
         jsr BIN_to_ASCII
         
         ldd Eff_disp
         ldy #LEFF_BUF
         jsr BIN_to_ASCII
         
         jsr UPDATELCD_L1         ; now update the fields since clear is complete
         clr D_UPDATE_L1
         
         ldaa CURSOR_SAVE         ; return cursor to where it was
         jsr  SETADDR 
                                          
         movb #$01, t3state        
t3s5b: 
         rts                       
                          
;----------------
t3state6:                          ; this state both prepares (clears) fields on L2
                                   ; then calls UPDATELCD_L2 to update the fields
                                
         tst  FIRSTCH          
         beq  t3s6a               
                                                    
         ldaa #$40             
         ldx  #KRESTORE_MESS          
         jsr  PUTCHAR_1ST
         bra  t3s6done

t3s6a:
         jsr PUTCHAR 
                                            
t3s6done:
         tst  FIRSTCH              
         beq  t3s6b                
                                   ; now update the fields since clear is complete
         jsr  UPDATELCD_L2          
         clr  D_UPDATE_L2
         
         ldaa #$01                 ; hide cursor under underscore
         jsr  SETADDR 
                         
         movb #$01, t3state        
t3s6b: 
         rts
          
;---------------
t3state7:                           ; this is the KPREP displayer, it prepares either the   
         tst  FIRSTCH               ; Ki or Kp fields for user input and puts the cursor
         beq  t3s7a                 ; where it needs to go
         ldx  #KPREP_MESS
                                                                                                        
         tst  KI_FLG                         
         bne  Ki_prep
                                   
         ldaa #$48                           
         jsr  PUTCHAR_1ST
         bra  t3s7done

Ki_prep:         
         ldaa #$56                           
         jsr  PUTCHAR_1ST
         bra  t3s7done
         
t3s7a:
         jsr PUTCHAR 
                                            
t3s7done:
         tst  FIRSTCH                   
         beq  t3s7c
         
         tst  KI_FLG                ; determine correct cursor spot based on Ki/Kp
         bne  Ki_cursor
         ldaa #$48
         jsr  SETADDR
         bra  t3s7b
         
Ki_cursor:
         ldaa #$56
         jsr SETADDR         
         
t3s7b:         
         clr  D_KPREP                                                                        
         movb #$01, t3state            

t3s7c: 
         rts
          
;------------
t3state8:                         ; this is the Vref prep message displayer
         tst  FIRSTCH                
         beq  t3s8a               
                        
         ldaa #$40                
         ldx  #VREFPREP_MESS          
         jsr  PUTCHAR_1ST
         bra  t3s8done

t3s8a:
         jsr PUTCHAR 
                                            
t3s8done:
         tst  FIRSTCH              
         beq  t3s8b                
         clr  D_VrefPREP
         
         ldaa #$4B                 ; place cursor for user entry
         jsr  SETADDR               
         movb #$01, t3state        

t3s8b: 
         rts
         
;-----------------                   
t3state9:                      ; this is the echo displayer state 
         ldx  POINTER          ; load x with the with POINTER (the address of the next avail space in buffer)
         ldab -1,x             ; load b with the character BEFORE pointer (what was just pressed)
         jsr OUTCHAR           ; OUTCHAR takes b as its character, therefore OUTCHAR'ing last digit entered
         clr D_ECHO
         movb #$01, t3state
         rts
;----------------                       
t3state10:
                               ; this is the Backspacer, it displays a fixed sequence of ASCII
         tst  FIRSTCH          ; the write address is the current cursor address
         beq  t3s10a              
                                                    
         jsr  GETADDR          ; this grabs the current cursor address to be the printing address
         ldx  #BS_MESS          
         jsr  PUTCHAR_1ST
         bra  t3s10done

t3s10a:
         jsr PUTCHAR 
                                            
t3s10done:
         tst  FIRSTCH              
         beq  t3s10b                
                  
         ldaa COUNT             ; if we just cleared the first character, <+>/<-> entry needs re-enabling
         cmpa #$01
         bne  BS_finish
         clr  SIGN_FLG
         
BS_sign: 
         clr  SIGN_FLG          ; if it was, we need to lowert the sign flag
         
BS_finish:         
         clr  D_BS
         dec  COUNT             ; move back the active spot in buffer 
         decw POINTER                
         movb #$01, t3state        
t3s10b: 
         rts
;----------------                       
t3state11:                     ; displays starting RUN/CL/D_ON status
                               
         tst  FIRSTCH          
         beq  t3s11a               
                                                    
         ldaa #$5C             
         ldx  #STATUS_MESS          
         jsr  PUTCHAR_1ST
         bra  t3s11done

t3s11a:
         jsr PUTCHAR 
                                            
t3s11done:
         tst  FIRSTCH              
         beq  t3s11b                
         clr  D_INIT_STATUS
         
         ldaa #$01                 ; hide cursor under underscore
         jsr  SETADDR
                         
         movb #$01, t3state        
t3s11b: 
         rts
         
;--------------------------- TASK_4: Timer Channel 0 Controller ------------------------

TASK_4:			                    	; this task just turns the TC0 interrupt routine on
      ldaa t4state
      beq  t4state0                
      deca
      beq  t4state1                
         
t4state0:                        ; enable interrupts
         
      bset TIOS, #$01            ; set timer channel 0 for output compare (tic/toc select register)
      bset TCR2, #$01            ; sets successful output compare response to "toggle output pin"
      bset C0F,  #$01            ; clears the channel 0 output compare flag (by writing 1 to it)                                 
      cli                        ; clears i-bit, enabling interrupts (masterswitch for all ints)
      bset TIE1, #$01            ; set C0I bit, enables chan0 interrupts
      bset TCR2, #$01            ; set OL0 bit, specifies toggle as the interrupt action
      ldd  TCNT
      addd INTERVAL
      std  TC0

      movb #$01, t4state
      rts 

t4state1:                        ; stub
      rts
              
;/------------------------------------------------------------------------------------\
;| Subroutines                                                                        |
;\------------------------------------------------------------------------------------/
; General purpose subroutines go here

;--------------------------------------------------------------------------------------
;---------------------------- Timer Channel 0 Interrupt Service Routine ---------------
;--------------------------------------------------------------------------------------
;
; This ISR executes a PI (proportional plus integral) control loop. Every 2ms, this ISR 
; reads the Vact from the optical encoder, compares it to Vref to produce an error ("e") term.
;  This e term is then multiplied by proportional and integral constants to produce a new 
; PWM (pulse width modulation") value with which the motor voltage is updated. Refer to the 
; program documentation for a comprehensive block diagram. 
;
; Several set checks and saturations occur here, sometimes using subroutine SDBA, they are:
;
;              - set check and saturation following multiplication of error and Kp/Ki
;              - SDBA subroutine call to effectively perform an integral using esum_old
;              - SDBA call to combine integral and proportional terms
;              - saturation to limit PWM value to -650<a*<650 (650 hardcoded in library)
;
;  
; Additionally, a radix point shift is used to increase the resolution of incoming Kp/Ki
; user inputs. User inputs 1024*(the desired K), which is then divided by 1024, increasing 
; the resolution.
;
; The stack is used on multiple occasions for temporary storage. 
;

TC0_ISR:

      jsr  READ_ENCODER        ; read current value of the encoder to get theta_new in D
      tfr  d,y                 ; make a copy of theta_new in y

      subd theta_old           ; subtract theta_old from theta_new (we just read this)
                               ; technically we divide by 1 BTI here but 1 BTI = 1, so do nothing
                               ; BTI's are a less useful concept in this lab because
                               ; interrupts per BTI is fixed at 1 (unlike lab4)
                               
      sty  theta_old           ; store the current encoder reading in theta_old for next time
      
      std  Vact                ; save Vact calculated value
      ldx  Vref
      
      tst  OL
      bne  OL_mode
      subx Vact                ; calculate error by subtracting Vact from Vref

OL_mode:                       ; skip the Vref-Vact calculation for OL mode

      stx  Err                 ; save error value for future use with integral term        

proportional:

      ldd   Err 
      ldy   Kp1024             ; grab the user-inputted 1024 * Kp value
      emuls                    ; multiply by error, D*Y -> Y:D
      ldx   #1024               
      edivs                    ; (Y:D)/X -> Y, Remainder -> D

      bvc Kpe_done             ; proportional term overflow check and saturation 
      bmi p_toobig
      ldy #$8000               ; edivs result too negative for 16-bits, clamp to $8000
      bra Kpe_done
      
p_toobig:
      ldy #$7FFF               ; edivs result too positive for 16-bits, clamp to $7FFF
Kpe_done:
      pshy                     ; store Kp*e on stack to be SDBA'ed with Ki*e later

integral:



      ldd Err                  ; grab the error value into d
                               ; (note: sp is now on Kp*e)
      
                               ; here, again, we technically divide by dt, which is 1 BTI
                               ; but since theres an interrupt each BTI, BTI=1 so no action
                               ; is needed
                               
      ldy esum_old             ; grab the previous "integral" (sum) of error w/resp to time
      jsr SDBA                 ; add old error to new error, D+Y->D
      std esum_old             ; save the integral value for use in the next interrupt

      ldy   Ki1024             ; grab the user-inputted 1024*Ki value
      emuls                    ; multiply by error integral, D*Y -> Y:D
      ldx   #1024 
      edivs                    ; divide e*1024*Ki by 1024, (Y:D)/X -> Y, Remainder -> D

      bvc a_calc               ; integral term overflow check and saturation 
      bmi i_toobig
      ldy #$8000               ; edivs result too negative for 16-bits, clamp to $8000
      bra a_calc

i_toobig:
      ldy #$7FFF               ; edivs result exceeds 16-bits, clamp to $7FFF

a_calc:
      puld                     ; pull previously calc'ed Kp*e value off stack into d
      jsr   SDBA               ; call signed double byte adder (Kp*e is in D, esum*Ki*e is in Y)
                               ; so "a" from block diagram is now in D
                                       
                               ; perform a --> a* saturation
      cpd  #650                ; using signed branches here since a can be negative
      bgt  a_toobig
      cpd  #$FD76
      bgt  eff_calc
      ldd  #$FD76              ; clamp to -650
      bra  eff_calc
      
a_toobig:
      ldd #650                 ; clamp to 650
      
      
eff_calc:
      pshd                     ; preserve the a* value on stack while eff is calced
      
      tst  RUN                 ; if run is 0, Eff = 0
      beq  zero_eff

      ldy #100                 ; if run = 1, eff needs to be calced
      emuls
      ldx #650
      edivs
      sty Eff
      bra pwm_update
      
zero_eff:
      clrw Eff
      
pwm_update:                    ; now we have a* value from block diagram, need to update pwm
      
      puld                     ; restore the a* value after eff calc
      jsr UPDATE_MOTOR         ; update the motor with a*/650, the fractional duty cycle
      
      
      ldd   Vact               ; this is the DAC operation used to output vact to oscilloscope
      ldy   #13
      emuls
      addd  #2048
      jsr   OUTDACA                                                   
                               ; reset the TCO routine counter, advance display counter:
      tst  D_ON                ; for disp update to occur, D_ON = 1, 256 interrupts have occured
      beq  no_Dupdate
      inc  disp_ctr
      bne  no_Dupdate          ; this branch is triggered every time disp_ctr wraps 256->0
      
      movw Vact, Vact_disp     ; load a current, consistent set of calc'ed values into the 
      movw Err, Err_disp       ; display values
      movw Eff, Eff_disp
      movb #$01, D_UPDATE_L1
      
no_Dupdate:
                                 
      ldd  TC0                 ; capture current timer count into d
      addd #INTERVAL           ; add interval to current timer count
      std  TC0                 ; store (interval + TC0) back into d
      bset C0F, #$01           ; clear the timer channel 0 timer output compare int flag
      rti                      ; return from interrupt
      
;-------------------------------------------------------------------------------------------
;----------------------------------- Displayer Subroutine ----------------------------------
;-------------------------------------------------------------------------------------------             
;
; This subroutine displays messaged to the LCD, one at a time. It has two parts: PUTCHAR_1ST
; performs some setup in placing the cursor in the correct spot. PUTCHAR places subsequent digits.
;

PUTCHAR_1ST:                            

        stx DPTR              ; stx stores x (which is currently the addr of first char in mess)
                              ;         in DPTR, (ldx stores something in x (they're inverses))
        jsr SETADDR           ; sets cursor location as the contents of a (a was determined before the jsr)
        clr FIRSTCH                     

        ;note: putchar is entered from putchar_1st during the first pass through, then gets branched directly
        
PUTCHAR:
        
        ldx  DPTR             ; store contents of x in the Digit Pointer (sets DPTR to the addr of next char)
        ldab 0,x              ; loads b with x to set the condition codes
        beq  DONE             ; branch to done when ASCII null is landed on by DPTR
        inx                   ; increment x to move to the next character
        stx  DPTR             ; store this incremented value to set move to the next char in mess
        jsr  OUTCHAR          ; print this next character
        rts
        
DONE:   
        movb #$01, FIRSTCH              ; sets FIRSTCH high for the start of the next message
        rts
;-------------------------------------------------------------------------------------------        
;------------------------------ Saturated Double-Byte Adder --------------------------------
;-------------------------------------------------------------------------------------------
;                                                                                     
; This subroutine accepts 16-bit signed numbers in D & Y and returns the saturated sum
; in D. The sum is clamped to either 32,767 if there is positive overflow, or -32,768 
; if there is negative overflow.                                                      
;                                                                                     
; Input:                                                                              
;         - 16-bit signed number in D                                                 
;         - 16-bit signed number in Y                                                 
;                                                                                     
; Output:                                                                             
;          - saturated sum in D                                                       
;-------------------------------------------------------------------------------------------

SDBA:          

      pshx                       ; preserve x in the stack (decs twice then stores x there)
      pshy                       ; preserve y in the stack (decs twice then stores y there)

                                 ; there is only potential for over/underflow if two negative
                                 ; or two positive numbers are being added to eachother
                                 ; over/underflow occurs if
                                 ;      - two neg numbers become "positive" 
                                 ;      - two pos become "negative"
                                 ; if its 1 pos, 1 negative, no potential for overflow
                                 ; because the result mag will be between the two addends mags
                
      addd 0,sp                  ; add d (which was on stack) to D and store in D
      bvc  SDBAexit                  ; if no overflow occured, result is good to go
                                      
      tsta                            
      bmi  overflow              ; if a is negative, the result is too positive for 16 bits
      
                                 ; addends are neg and became positive, so underflow occurred
      ldd  #$8000                ; clamp result to -32,768 ("saturated")
      bra  SDBAexit
       
overflow:
      ldd  #$7FFF                ; clamp the result to 32,767 ("saturated")

SDBAexit:
      puly                       ; restore y
      pulx                       ; restore b
      rts        
;-------------------------------------------------------------------------------------------
;------------------------------ 16-bit Binary to ASCII converter ---------------------------
;-------------------------------------------------------------------------------------------
;
;  Inputs: 
;           - 16-bit signed binary number in D
;           - address of output buffer in Y
;  Outputs:
;
;           - ASCII digits arranged in output buffer with the topmost digit 
;             corresponding to the leftmost digit to be displayed, with the exception
;             that a single space of room at the top of the output buffer 
;             is left for "-" in case the number is negative (this extra space is left 
;             blank in the case of a positive number).
;           - number of digits returned in A
;
; Algorithm:
;
;   Divide number by 10, the remainder is a BCD result digit, quotient gets re-divided by 10
;       ---> continue until quotient = 0
;
; Stack Layout before conv_loop: 
;
;               - empty (<SP) (we're about to put top copy of # of conv completed here)
;               - empty
;               - y, x, Return addresses (may be multiple (also RTN_l, RTN_h))  
;   
; Stack Layout at unload_loop (# conv completed gets replaced to top of stack after each conv):
;
;               - # conv completed [result digits get slotted underneath]
;               - Nth result digit (up to 5 result digits) (most significant place) (<SP)
;               - 2nd result digit
;               - 1st result digit (least significant place)
;               - # conv completed
;               - y, x, return addresses (may be multiple (also RTN_l, RTN_h))

BIN_to_ASCII:

      pshx
      pshb
      des                 
      des                 ; make spots for 2 copies of digit count
      
      clrw 0, sp          ; init # of conv completed to 0 
      
      cpd  #$00           ; first test if negative
      blt  negative
      ;movb #$20, 0, y     ; if positive, move a blank space into top buffer spot 
      bra  convert_loop 
      
negative:
      movb #$2D, 0, y     ; if the number is negative, move a neg sign into top buffer spot
      incy                ; move one spot forward in the destination buffer
      pshd                ; need to take twos compliment of the number to prepare for conversion
      negw 0,sp           ; because we want to convert the positive number now that - is applied
      puld      
      
convert_loop:

      ldx #10
      idiv              ; divides 16-bit unsigned in D by 16-bit unsigned in x, returns quotient in X,
                        ; and the remainder in D. Radix pt assumed to be to the right of 0
                        ; (since D is being divided by 10, B cannot possibly overflow into A,
                        ; the remainder is effectively in B, then)
                         
      addd #$30         ; convert the BCD remainder to ASCII
      
      pula              ; grab # of conv completed off stack
      pshb              ; push the remainder (result digit) onto stack
      inca              ; increment # of conv completed
      psha              ; push the # of conv completed back onto stack
      
      tfr  x,d          ; put the quotient into d for next loop around
      tstx
      bne  convert_loop
      
      pula              ; grab # of conv digits
      tfr  a,b          ; make a copy of the # of digits converted  
      staa b,sp         ; store it under the digits on the stack
      
unload_loop:

      pulb              ; unload the digit from stack into correct BUFFER_OUT spot
      stab 0, y
      incy
      deca              ; decrement the # digits conv
      bne  unload_loop  ; if all digits unloaded, done
            
      pula              ; pull the bottom copy of # of digits converted into a
      pulb
      pulx
      rts
      
;-------------------------------------------------------------------------------------------
;-------------------------- 16-bit ASCII to BIN Converter (Modified from Lab 3)  -----------
;-------------------------------------------------------------------------------------------
; ** highly specialized for lab 5 ** (use lab 3 for general purposes)
;
; This subroutine accepts a 16-bit ASCII string in BUFFER and returns the saturated result in 
; x. However, since the nature of lab 5 means large negative numbers cannot be entered 
; (only large positives)*,
; it will only saturate to 32,767 and not -32,768. The subroutine tests
; when a leading "-" exists and negates the result. It also tests if there is a leading "+" or
; no leading sign (in which the value returned will be positive).
;
; * this is because the only field that allows negative numbers, Vref, is limited to 3 digits, 
; so we couldnt possibly have underflow, mag negative number is -999
;
; Inputs:
;         - 16-bit ASCII string in BUFFER
;
; Outputs:
;         - saturated result in X 
;
; Algorithm: 
;
; Result = 10*Result + next BCD digit
;
; Stack Layout:
        
							   ;- # conv completed (<SP)
							   ;- current conversion result (high byte)
						     ;- current conversion result (low byte)
						     ;- neg indicator boolean (negative if true)
						     ;- Y preserve (high byte)
							   ;- Y preserve (low byte)
							   ;- A preserve
							   ;- B preserve
							   ;- RTN_h (return address to the task you're in)
							   ;- RTN_l
							   ;- RTN_h (return address to main)
						  	 ;- RTN_l

ASCII_to_BIN:
        
        pshd                       ; decrements stack once and pushes contents of d there
        pshy                       ; decrements stack twice and pushes contents of y there

        des                        ; decrement stack 3 to make space for the result (2 byte)   
        des                        ; and for "# of digit conversions completed" (1 byte) SP stays here 
        des                        ; and for neg boolean
        des                        
        
        clrw sp                    ; clears the 4 temporary spots in the stack
        clrw 2,sp
                               
        ldx  #BUFFER               ; load x with addr of first char in buffer
        ldaa 0,x                   ; load a with the first character in BUFFER
        
        cmpa #$2D                  ; first test if negative ($F2 = <->)
        bne  positive
        movb #$01,3,sp             ; number has leading negative sign, so set neg boolean
        inc  0,sp                  ; increment # of conversions completed bc the sign is
        dec  COUNT                 ; basically a char
        bra  init_d             
      
positive:                          ; positive numbers can be indicated with either a 
                                   ; leading + or nothing! So we need to decide whether the
                                   ; number itself starts on 1st buffer spot or second
                                   
        clr  3,sp                  ; clear neg boolean since its definitely positive
        cmpa #$2B                  ; is the first character a <+>?
        bne  init_d                ; if not, proceed with conversion of char 1
        inc  0,sp                  ; if it is, we want to start conv on second character (after +)
        dec  COUNT

init_d:
        ldd  1,sp                  ; init d to 0
                
conv_loop:                          
                                   ; result = 10 x result
                          
        ldy  #10                   ; load register y with 10
        emul                       ; multiply y and d and store in Y:D (32-bit result)
        
        tsty                       ; ensure that the result in d did not overflow past $FFFF
        bne  TOOBIG                ; if it did, saturate
        cpd  #$7FFF                ; check if the number is higher than 32,767  
        bhi  TOOBIG                ; if so, saturate the number
        std  1,sp                  ; if not, store the non-overflowed D back into RESULT spot in stack
        
        ldaa 0,sp                  ; load a with the current number of conversions completed
        ldab a,x                   ; load b with the next ASCII to be converted 
                                   ; (at addr: #BUFFER+#conversionscompleted)
                                    
        subb #$30                  ; subtract 30 from ASCII to go ASCII-->BCD
        clra                       ; clear a (# digits converted) so it doesn't go into stack in next line
        addd 1,sp                  ; add result in stack to this BCD digit
        bvs  TOOBIG                ; ensure that the last bit addition does not cause overflow 
                                   ; (if you had 32,532 on this last pass, 7 would overflow it, 
                                   ; but it wouldn't be caught by the other TOOBIG branches)
        
        std  1,sp                  ; store this updated value into RESULT spot in stack
        inc  0,sp                  ; increment the # of digits converted
        dec  COUNT                  
        beq  finish         
        bra  conv_loop                            
        
TOOBIG:
        ldx #$7FFF                  ; clamp result to 32,767
        bra exit_conv
                     
finish:
        tfr  d,x                    ; store the ultimate result into x
        tst  3,sp                   ; was a negative number entered? (neg flg in stack set)
        beq  exit_conv              ; if not, just exit
        negx                        ; if so, we need to negate the result
        
exit_conv:        
        ins                          ; move sp off of the temporary result and "# conversions" spaces
        ins
        ins
        ins
        puly                         ; restore y
        puld                         ; restore d
        rts        
                
;/------------------------------------------------------------------------------------\
;| ASCII Messages and Constant Data                                                   |
;\------------------------------------------------------------------------------------/
; Any constants can be defined here

KPREP_MESS:      DC.B  '     ', $00                          ; prepares LCD for Kp or Ki entry
VREFPREP_MESS:   DC.B  'New V_ref:                 ',$00     ; prepares LCD for V_ref entry
D_ON_MESS:       DC.B  'D_ON ', $00                          ; used to toggle Display indicator
D_OFF_MESS:      DC.B  'D_OFF', $00
OL_MESS:         DC.B  'OL', $00                             ; used to toggle OL indicator
CL_MESS:         DC.B  'CL', $00
RUN_MESS:        DC.B  'RUN', $00                            ; used to toggle run indicator
STP_MESS:        DC.B  'STP', $00
BS_MESS:         DC.B  $08,$20,$08,$00                       ; backspace sequence
STATUS_MESS:     DC.B  'STP CL D_ON', $00                    ; starting status message
KRESTORE_MESS:   DC.B  '1024*KP=      1024*KI=      ', $00   ; clears old K values
VRESTORE_MESS:   DC.B  'V_ref=     V_act=     Err=     Eff=    %',$00   ; clears old L1
;/------------------------------------------------------------------------------------\
;| Vectors                                                                            |
;\------------------------------------------------------------------------------------/
; Add interrupt and reset vectors here

        ORG   $FFFE                    ; reset vector address
        DC.W  Entry
        ORG   $FFCE                    ; Key Wakeup interrupt vector address [Port J]
        DC.W  ISR_KEYPAD
        ORG   $FFEE
        DC.W  TC0_ISR
