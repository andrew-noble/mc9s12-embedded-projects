;**************************************************************************************
;* Lab 3 Project Main [includes LibV2.1]                                              *
;**************************************************************************************
;* Summary:                                                                           *
;*   - I/O-capable LED blinker with cooperative multitasking.                         *
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
              XREF  INITKEY, LKEY_FLG, GETCHAR, CLRSCREEN
              XREF  LCDTEMPLATE, UPDATELCD_L1, UPDATELCD_L2
              XREF  LVREF_BUF, LVACT_BUF, LERR_BUF,LEFF_BUF, LKP_BUF, LKI_BUF
              XREF  Entry, ISR_KEYPAD
            
;/------------------------------------------------------------------------------------\
;| Assembler Equates                                                                  |
;\------------------------------------------------------------------------------------/
; Constant values can be equated here


;----- TIMING and PATTERN Equates -------
 
PORTP         EQU   $0258              ; port LEDs are plugged into
DDRP          EQU   $025A              ; "Data Direction Register" for port P (determines whether port
                                       ; P isused for output or input, set for output, clr for input)

G_LED_1       EQU   %00010000          ; green LED pin for LED pair_1
R_LED_1       EQU   %00100000          ; red LED pin for LED pair_1
LED_MSK_1     EQU   %00110000          ; mask for changing both LEDS in pair 1 simultaneously
G_LED_2       EQU   %01000000          
R_LED_2       EQU   %10000000          
LED_MSK_2     EQU   %11000000          


;/------------------------------------------------------------------------------------\
;| Variables in RAM                                                                   |
;\------------------------------------------------------------------------------------/
; The following variables are located in unpaged ram

DEFAULT_RAM:  SECTION

;------ state variables -----
t1state:      DS.B 1                   
t2state:      DS.B 1
t3state:      DS.B 1
t4state:      DS.B 1
t5state:      DS.B 1
t6state:      DS.B 1
t7state:      DS.B 1

;------ MM (inter-task) variables ---------
F1_FLG:       DS.B 1                   ; this variable signals that MM is dealing with f1 (ignore f2 presses)
F2_FLG:       DS.B 1                   ; MUST be stored adjacent like this, due to tstw F1_FLG later on

DTIME_1:      DS.B 1                   ; booleans for telling display to display fixed messages
DTIME_2:      DS.B 1
PRMPT1:       DS.B 1                   
PRMPT2:       DS.B 1
ERR1:         DS.B 1
ERR2:         DS.B 1
ERR3:         DS.B 1
FPREP:        DS.B 1                                      
                                       
BS_FLG:       DS.B 1                   ; booleans for telling display to BS or echo a digit
ECHO_FLG:     DS.B 1
            
COUNT:        DS.B 1                   ; # of digits successfully captured from keypad
POINTER:      DS.W 1                   ; address of the next available space in buffer
BUFFER:       DS.B 5                   ; storage unit for an entire keypad input pre-conversion

KEY_BUF:      DS.B 1                   ; storage for a single key input, sent from keypad handler to MM
KEY_FLG:      DS.B 1

DPTR:         DS.W 1                   ; "digit pointer" address of next character in mess to be read, displayed
FIRSTCH:      DS.B 1                   ; boolean that is true if next character is the first of a mess

ERRTIMER:     DS.W 1                   ; this contains a timer for error messages to be displayed


DONE_1:       DS.B 1                   ; variables used by timing and pattern tasks
TICKS_1:      DS.W 1
COUNT_1:      DS.W 1
ON_1          DS.B 1                   ; LED interrupt boolean

DONE_2:       DS.B 1
TICKS_2:      DS.W 1
COUNT_2:      DS.W 1
ON_2          DS.B 1

;/------------------------------------------------------------------------------------\
;|  Main Program Code                                                                 |
;\------------------------------------------------------------------------------------/

MyCode:       SECTION

main:   
         clr   t1state                  ; clear all state variables
         clr   t2state
         clr   t3state
         clr   t4state                  
         clr   t5state
         clr   t6state
                        
loop:      
         jsr   TASK_1                   
         jsr   TASK_2                   
         jsr   TASK_3
         jsr   TASK_4
         jsr   TASK_5
         jsr   TASK_6
         jsr   TASK_7
         jsr   DELAY_1ms

         bra   loop                     ; endless loop

;--------------------------------------  TASK_1: Mastermind ---------------------------------
TASK_1:
         ldaa t1state
         beq  t1state0                ; init state, raises all initial prompt message flags
         deca
         beq  t1state1                ; waits for prompts to be displayed 
         deca
         beq  t1state2                ; hub state, identifies keys that are retrieved by keypad handler, ignores invalids
         deca
         lbeq t1s3_f1handler          ; determines if f1 is valid press, then raises, F1_FLG and FPREP display flag
         deca
         lbeq t1s4_f2handler              
         deca
         lbeq t1s5_BShandler          ; determines whether BS is a valid entry atm, then raises BS_FLG if so
         deca
         lbeq t1s6_ENThandler         ; executes ASCII->BCD->binary conv, raises err flags or loads ticks accordingly
         deca
         lbeq t1s7_digithandler       ; loads digits into buffer
         deca
         lbeq t1s8_errorwait          ; MM waits here for error message to be displayed for 1500 passes thru main
         
t1state0:

                                      ; initialize MM by raising all starting messages flags
         movb #$01, DTIME_1         
         movb #$01, DTIME_2
         movb #$01, PRMPT1
         movb #$01, PRMPT2
         
         clr  BS_FLG                  ; init all non-starting message flags
         clr  ECHO_FLG
         clr  FPREP
         clr  ERR1                    
         clr  ERR2
         clr  ERR3
         
         clr   COUNT                  ; init count and F flags
         
         movb #$01, t1state
         rts
            
t1state1:                             ; MM stays in this state until all inital messages are displayed on the LCD
         tst DTIME_1
         bne t1s1exit
         tst DTIME_2
         bne t1s1exit
         tst PRMPT1
         bne t1s1exit
         tst PRMPT2
         bne t1s1exit
         clr F1_FLG                   ; inits F flags and clears them after an error
         clr F2_FLG                   
         
         movb #$02, t1state
          
t1s1exit:
         rts

;--------------
t1state2:                             ; this is MM hub state, it interrogates keys retrieved from keypadhandler
         ldaa KEY_FLG         
         cmpa #$01                    
         bne  t1s2exit                ; if key flag is low, just rts                                                  
         ldaa KEY_BUF                 ; grab the key entered from KEY_BUF
         
         cmpa #$F1                    ; test if the key in key_buf is a f1 key
         bne  askF2
         movb #$03, t1state           ; if F1 key was entered, branch to its handler state
         bra  t1s2exit
         
askF2:         
         cmpa #$F2                    ; test for f2
         bne  askBS
         movb #$04, t1state
         bra  t1s2exit
         
askBS:  
         cmpa #$08                    ; test for BS
         bne  askENT
         movb #$05, t1state
         bra  t1s2exit
         
askENT: 
         cmpa #$0A                    ; test for ENT
         bne  askdigit
         movb #$06, t1state
         bra  t1s2exit
         
askdigit:        
         cmpa #$30                    ; test if its a ASCII digit (between $30-$39)
         blo  t1s2exit                
         cmpa #$39
         bhi  t1s2exit                
                 
         ldab COUNT                   ; test if buffer is full, if so, ignore the digit
         cmpb #$05
         bhs  t1s2exit
         
         movb #$07, t1state           ; finally, MM has determined that this digit can be passed to t1s7_digithandler

t1s2exit:
         clr KEY_FLG                  ; lower the key flag since the key was acknowledged by MM
         rts
         
; ---------------
t1s3_f1handler:                       
         tstw F1_FLG                  ; we want to ignore f1 presses if EITHER of the F key sequences is already active
         bne  f1exit                  ; the "w" in "tstw" tests M:M+1, so both F1_FLG and F2_FLG 
                      
         clr  COUNT                   ; tells display to clear current digits and set POINTER back to
         movw #BUFFER, POINTER        ; the top of BUFFER
         
         movb #$01, F1_FLG
         movb #$01, FPREP
         clr  ON_1                    ; stop the LEDs
                  
f1exit:
         
         movb #$02, t1state           ; go back to hub
         rts
; ---------------        
t1s4_f2handler:
         tstw F1_FLG                  ; if either F1_FLG or F2_FLG high, ignore F2 presses
         bne  f2exit                   
            
         clr  COUNT                  
         movw #BUFFER, POINTER
         
         movb #$01, F2_FLG
         movb #$01, FPREP
         clr  ON_2
                  
f2exit:
         movb #$02, t1state            
         rts
;------------------
t1s5_BShandler:
         tstw F1_FLG                   ; ignore a <BS> entry if neither of the F keys have been pressed
         beq  BSexit                   
         
         tst  COUNT                    ; ignore a <BS> entry if there is nothing to backspace
         beq  BSexit                    
        
         dec  COUNT                    ; move back in 
         decw POINTER
         movb #$01, BS_FLG             ; raise the BS flag for display to do its thang
         
BSexit:
         movb #$02, t1state
         rts
; ------------------         
t1s6_ENThandler:
         tstw F1_FLG                   
         beq  ENTgoodexit
          
         tst  COUNT
         beq  ENTnodigit 
         jsr  ASCII_to_BIN             ; recall that ASCII_to_BIN returns 16-bit answer in x and error code in A
                                       ; A=1 for magtoolarge, A=2 for zeromag(x is irrelevant in these cases),A=0 noerror
                                       
         cmpa #$02                     ; raise appropriate error flags based on what ASCII_to_BIN returned in error code
         beq  ENTzeromag
         cmpa #$01 
         beq  ENTmagtoolarge
         
         tst  F1_FLG                   ; assign new period to appropriate set of leds
         beq  setLED2
         stx  TICKS_1
         stx  COUNT_1
         movb #$01, ON_1
         bra  ENTgoodexit
         
setLED2:
         stx  TICKS_2
         stx  COUNT_2
         movb #$01, ON_2
         bra  ENTgoodexit         
         
ENTnodigit:
         movb #$01, ERR3            
         bra  ENTerrexit
         
ENTzeromag:
         movb #$01, ERR2            
         bra  ENTerrexit
         
ENTmagtoolarge:
         movb #$01, ERR1            
         bra  ENTerrexit
         
ENTgoodexit:                           ; once enter has been hit, user can now press f1 or f2 again w/o ignore
         clr  F1_FLG
         clr  F2_FLG
         movb #$02, t1state
         rts

ENTerrexit: 
         movb #$08, t1state            ; move to error wait state
         rts 
;------------------
t1s7_digithandler:

         tstw F1_FLG                   ; test if BOTH (!!!) F1 or F2 flags are up, if neither, ignore the digit
         beq  digitexit                ; (MM ignores digit presses if neither F's have been hit)
         ldx  POINTER

         ldaa KEY_BUF                  ; load the key collected by keypadhandler into a
         staa 0, x                     ; store whats in a (KEY_BUF) into adress location x (which is the first spot in buffer)          
         inc  COUNT
         incw POINTER                   
         movb #$01, ECHO_FLG           ; raise the echo_flg to tell display to echo this digit
                         
digitexit:
         movb #$02, t1state
         rts
;------------------                  
t1s8_errorwait:
                                       ; MM stays in this state until error messages are done displaying for 1500 passes thru main
         tst ERR1                      ; test that display is done displaying the error (whichever it may be)
         bne t1s8exit
         tst ERR2
         bne t1s8exit
         tst ERR3
         bne t1s8exit
         movb #$01, PRMPT1             ; its done displaying them, so now MM needs to redisplay all prompts
         movb #$01, PRMPT2
         movb #$01, t1state            ; move to prompt-wait state
         
t1s8exit:
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
                             
;--------------------------  TASK_3: Display Handler (displays messages requested by MM) ------------------

TASK_3: 
         ldaa  t3state          
         lbeq  t3state0         ; init state
         deca
         lbeq  t3state1         ; hub state that tests to see if anything needs to be displayed
         deca
         lbeq  t3state2         ; displays "TIME1:"
         deca
         lbeq  t3state3         ; displays "TIME2:"
         deca
         lbeq  t3state4         ; displays "ENTER <F1> TO INPUT LED1 PERIOD"
         deca
         lbeq  t3state5         ; displays "ENTER <F2> TO INPUT LED1 PERIOD"
         deca
         lbeq  t3state6         ; displays "ERROR: MAGNITUDE TOO LARGE" (for either row)
         deca
         lbeq  t3state7         ; displays "ERROR: ZERO MAGNITUDE INAPPROPRIATE" (for either row)
         deca
         lbeq  t3state8         ; displays "ERROR: NO DIGITS ENTERED" (for either row)
         deca
         lbeq  t3state9         ; echos by displaying the last digit pressed
         deca
         lbeq  t3state10        ; performs a backspace by displaying a blank space on the last cursor location
         deca
         lbeq  t3state11        ; displays a set of blanks associated with a f1/f2 press
         deca
         lbeq  t3state12
         deca
         lbeq  t3state13        ; DH waits in this state while error messages are displayed onscreen for 1500 passes thru main

t3state0: 
         jsr INITLCD            ; initialise the display
         jsr CURSOR_ON            
         movb #$01, t3state
         movb #$01, FIRSTCH
         movw #1500,ERRTIMER    ; init errtimer by inputting 1500 into it
         rts
         
t3state1:                       ; display hub state: each subtask tests a different fixedmessage boolean
         tst DTIME_1                
         beq  t3s1a             ; branch to next boolean check if DTIME_1 is low
         movb #$02, t3state     ; advance state var so that next round TIME_1 message is displayed 
         rts
t3s1a:   
         tst DTIME_2
         beq  t3s1b             ; branch to next boolean check if DTIME_2 is low
         movb #$03, t3state     ; advance state var so that next round TIME_2 message is displayed
         rts

t3s1b:
         tst PRMPT1   
         beq  t3s1c               
         movb #$04, t3state
         rts
 
t3s1c:
         tst PRMPT2
         beq  t3s1d
         movb #$05, t3state
         rts
         
t3s1d:                            ; checks if magtoolarge error message needs to be displayed
         tst ERR1          
         beq  t3s1e
         movb #$06, t3state       ; change to magtoolarge error message display state if ERR1 is high
         rts
                                  
t3s1e:   
         tst ERR2                 ; checks if zeromag error message needs to be displayed
         beq  t3s1f
         movb #$07, t3state
         rts
         
t3s1f:                            ; checks if nodigit error message needs to be displayed
         tst ERR3          
         beq  t3s1g
         movb #$08, t3state
         rts
         
t3s1g:   
         tst  ECHO_FLG            ; checks if an echo needs to happen
         beq  t3s1h
         movb #$09, t3state
         rts         

t3s1h:   
         tst  BS_FLG              ; checks if BS needs to happen
         beq  t3s1i
         movb #$0A, t3state
         rts
         
t3s1i:   
         tst  FPREP              ; checks if the F1/F2 blank space message needs to be displayed
         beq  t3exit 
         movb #$0B, t3state
         
t3exit:
         rts
                 
;--------------          
         
t3state2:                         ; this is the TIME1 message displayer!             
         tst  FIRSTCH             ; check if first char of a message so that cursor can be set properly
         beq  t3s2a               ; if it isn't the first character, branch to next char printing
                                  ;      because cursor is already in the correct position from last char
                                  
                                  ; if this is the first char, perform the following setup:
         ldaa #$00                ; load a with the desired cursor address for 1st message
         ldx  #MESSAGE_1          ; load x with address of first char in message
         jsr  PUTCHAR_1ST
         bra  t3s2done

t3s2a:
         jsr PUTCHAR              
                                   
                                            
t3s2done:
         tst  FIRSTCH              ; notice that this snippet is entered by "fall through" from t3s6a
         beq  t3s2b                ; this branch will be bypassed when PUTCHAR sets FIRSTCH back to 1 after message
                                   ; is successfully displayed
         clr  DTIME_1              ; else, (it is done), clear the DTIME_1 and
         movb #$01, t3state        ; return to hub state

t3s2b: 
         rts         

;------------
t3state3:                         ; this is the TIME2 message displayer (same as time 1)
         tst FIRSTCH                
         beq  t3s3a               
                                  
                                  
                                  
         ldaa #$40                
         ldx  #MESSAGE_2          
         jsr  PUTCHAR_1ST
         bra  t3s3done

t3s3a:
         jsr PUTCHAR 
                                            
t3s3done:
         tst  FIRSTCH              
         beq  t3s3b                
         clr  DTIME_2
         ldaa #$28                 
         jsr  SETADDR               
         movb #$01, t3state        

t3s3b: 
         rts
         
;------------         
t3state4:                          ; this is the <f1> message displayer (same as time1)
         tst FIRSTCH                
         beq  t3s4a               
                                  
                                  
                                  
         ldaa #$0E                
         ldx  #MESSAGE_3          
         jsr  PUTCHAR_1ST
         bra  t3s4done

t3s4a:
         jsr PUTCHAR 
                                            
t3s4done:
         tst  FIRSTCH              
         beq  t3s4b                
         clr  PRMPT1               
         movb #$01, t3state        

t3s4b: 
         rts
                  
;------------
t3state5:                                ; this is the <F2> message displayer (same as TIME1)
         tst FIRSTCH                
         beq  t3s5a               
                                                    
         ldaa #$4E                
         ldx  #MESSAGE_4          
         jsr  PUTCHAR_1ST
         bra  t3s5done

t3s5a:
         jsr PUTCHAR 
                                            
t3s5done:
         tst  FIRSTCH              
         beq  t3s5b                
         clr  PRMPT2               
         movb #$01, t3state        

t3s5b: 
         rts 
;-------------
t3state6:                               ; this is the magtoolarge error message displayer (displays on either line!) 
         tst FIRSTCH                
         beq  t3s6a
         ldx  #MESSAGE_5
                                                                                                        
         tst  F2_FLG                    ; this tst determines if ERR1 message is needed for line 2
         bne  ERR1_LINE2
                                   
         ldaa #$08                      ; if not, then it must be needed for line 1, so set cursor on top line
         jsr  PUTCHAR_1ST
         bra  t3s6done

ERR1_LINE2:         
         ldaa #$48                      ; if it is needed for line 2, set cursor on bottom line
         jsr  PUTCHAR_1ST
         bra  t3s6done
         
t3s6a:
         jsr PUTCHAR 
                                            
t3s6done:
         tst  FIRSTCH                   
         beq  t3s6b                     ; the error flag is not cleared here, its cleared in the errwait                      
         movb #$0D, t3state             

t3s6b: 
         rts
;---------------
t3state7:                               ; this is the zeromag error message displayer (displays on either line!) 
         tst FIRSTCH                    ; same structure as t3state6
         beq  t3s7a
         ldx  #MESSAGE_6
                                                                                                        
         tst  F2_FLG                         
         bne  ERR2_LINE2
                                   
         ldaa #$08                           
         jsr  PUTCHAR_1ST
         bra  t3s7done

ERR2_LINE2:         
         ldaa #$48                           
         jsr  PUTCHAR_1ST
         bra  t3s7done
         
t3s7a:
         jsr PUTCHAR 
                                            
t3s7done:
         tst  FIRSTCH                   
         beq  t3s7b                                                                        
         movb #$0D, t3state            

t3s7b: 
         rts      
;---------------
t3state8:                               ; this is the nodigit error message displayer (displays on either line!) 
         tst FIRSTCH                    ; same structure as t3state6
         beq  t3s8a
         ldx  #MESSAGE_7
                                                                                                        
         tst  F2_FLG                         
         bne  ERR3_LINE2
                                   
         ldaa #$08                           
         jsr  PUTCHAR_1ST
         bra  t3s8done

ERR3_LINE2:         
         ldaa #$48                           
         jsr  PUTCHAR_1ST
         bra  t3s8done
         
t3s8a:
         jsr PUTCHAR 
                                            
t3s8done:
         tst  FIRSTCH                   
         beq  t3s8b                                          
         movb #$0D, t3state             

t3s8b: 
         rts    
;----------------                        
t3state9:                               ; this is the echo displayer state 
         ldx  POINTER                   ; load x with the with POINTER (the address of the next avail space in buffer)
         ldab -1,x                      ; load b with the character BEFORE pointer (what was just pressed)
         jsr OUTCHAR                    ; OUTCHAR takes b as its character, therefore OUTCHAR'ing last digit entered
         clr ECHO_FLG
         movb #$01, t3state
         rts
;----------------                       
t3state10:
                                        ; this is the Backspacer, it's only difference from TIME1 displayer
         tst FIRSTCH                    ; is that the target address is not fixed, its the current address
         beq  t3s10a               
                                                    
         jsr  GETADDR                   ; this grabs the current cursor address to be the printing address
         ldx  #MESSAGE_0          
         jsr  PUTCHAR_1ST
         bra  t3s10done

t3s10a:
         jsr PUTCHAR 
                                            
t3s10done:
         tst  FIRSTCH              
         beq  t3s10b                
         clr  BS_FLG                
         movb #$01, t3state        

t3s10b: 
         rts          
;----------------
t3state11:                              ; this is the FPREP message displayer
                                        ; it clears current digits displayed and sets cursor appropriately                
         tst  FIRSTCH                
         beq  t3s11a
         ldx  #MESSAGE_8
                                                                                                        
         tst  F2_FLG                         
         bne  FPREP_LINE2
                                   
         ldaa #$08                           
         jsr  PUTCHAR_1ST
         bra  t3s11done

FPREP_LINE2:         
         ldaa #$48                           
         jsr  PUTCHAR_1ST
         bra  t3s11done
              
t3s11a:
         jsr PUTCHAR 
                                            
t3s11done:
         tst  FIRSTCH                    
         beq  t3s11b                                                                                                       
         clr  FPREP
         
         tst  F2_FLG                     ; below code places the cursor on appropriate line based on F1/F2_FLG
         bne  SETCURS_LINE2
         ldaa #$08
         jsr  SETADDR
         movb #$01, t3state                    
         bra  t3s11b
         
SETCURS_LINE2:
         ldaa #$48                      
         jsr SETADDR
         movb #$01, t3state  
t3s11b: 
         rts
;----------------
t3state12:                              ; this is the error clearing message displayer
                                        ; it clears error messages                
         tst  FIRSTCH                
         beq  t3s12a
         ldx  #MESSAGE_9
                                                                                                        
         tst  F2_FLG                         
         bne  ERRCLR_LINE2
                                   
         ldaa #$08                           
         jsr  PUTCHAR_1ST
         bra  t3s12done

ERRCLR_LINE2:         
         ldaa #$48                           
         jsr  PUTCHAR_1ST
         bra  t3s12done
              
t3s12a:
         jsr PUTCHAR 
                                            
t3s12done:
         tst  FIRSTCH                    
         beq  t3s12b                                                                                                       
         movb #$01, t3state             ; go back to hub
         
t3s12b: 
         rts

;--------------------
t3state13:                              ; display freeze state, it causes error messages to be sustained LCD
                                        ; DH is arrested here until there have been 1500 main passes
                                        ; NOTE: it DOES NOT arrest the whole CPU, just holds disp task in state 12
                                        
         ldy  ERRTIMER                  ; ERRTIMER starts with 1500 in it 
         cpy  #00
         beq  thaw
         decy
         sty  ERRTIMER
         rts
                                                 
thaw:                                
         clr  ERR1                      ; error message (whichever it may be) has been displayed for 1500 passes, lower its flg!
         clr  ERR2
         clr  ERR3
         movw #1500, ERRTIMER           ; reset the error message timer
         movb #$0C,   t3state           ; now print the error clearing message
         rts
         
;-------------------------------------- TASK_4: Pattern 1 -------------------------------------------
TASK_4:
        ldaa t4state                      ; load accumulator a with t4state
        beq  t4state0                     ; beq branches if z-flag is set
        deca                              
        beq  t4state1
        deca 
        beq  t4state2
        deca 
        beq  t4state3
        deca 
        beq  t4state4
        deca 
        lbeq t4state5
        deca 
        lbeq t4state6
        deca 
        lbeq t4state7
        
        
t4state0:                               ; init state
        
        bset DDRP,LED_MSK_1             ; DDRP (data direction register port P) sets port 
                                        ; P pins to output per LED_MSK_1
        bclr PORTP,LED_MSK_1            ; turn off LED pair 1              
        clr  ON_1
        clr  DONE_1
                                        
        movb #$01,t4state               ; recall that mov actually copies to, doesn't move
        rts
;----------        
t4state1:                               ; this is the LED off state
                                        ; pattern 1 stays here while digits are being entered by user
                                        ; i.e., pattern 1 stays here while F1_FLG is high
        bclr PORTP, LED_MSK_1
        tst  ON_1                       ; only ON_1 needs to be high to transition state
        beq  exit_t4s1
        movb #$02, t4state
        
exit_t4s1:
        rts
;----------
t4state2:                               ; first blinking state

        bset PORTP,G_LED_1
        tst  ON_1                       ; sequentially test ON_1 and DONE_1
        beq  halt_t4s2                  ; if ON_1 is low, go to LED off state
        
        tst  DONE_1                     
        beq  exit_t4s2                  ; if not done with timing, just stay in state
        movb #$03,t4state               ; if F1_FLG is low and DONE is high, move to next state
        bra  exit_t4s2
         
halt_t4s2:
        movb #$01, t4state               
             
exit_t4s2:
        rts
;----------        
t4state3:
        bclr PORTP,LED_MSK_1
        tst  ON_1                     
        beq  halt_t4s3                  
        
        tst  DONE_1                     
        beq  exit_t4s3                  
        movb #$04,t4state               
        bra  exit_t4s3
         
halt_t4s3:
        movb #$01, t4state               
             
exit_t4s3:
        rts        
;----------        
t4state4:
        bset PORTP,R_LED_1
        tst  ON_1                     
        beq  halt_t4s4                  
        
        tst  DONE_1                     
        beq  exit_t4s4                  
        movb #$05,t4state               
        bra  exit_t4s4
         
halt_t4s4:
        movb #$01, t4state               
             
exit_t4s4:
        rts
;----------                
t4state5:
        bclr PORTP,LED_MSK_1
        tst  ON_1                     
        beq  halt_t4s5                  
        
        tst  DONE_1                     
        beq  exit_t4s5                  
        movb #$06,t4state               
        bra  exit_t4s5
         
halt_t4s5:
        movb #$01, t4state               
             
exit_t4s5:
        rts
;----------               
t4state6:
        bset PORTP,LED_MSK_1
        tst  ON_1                     
        beq  halt_t4s6                  
        
        tst  DONE_1                     
        beq  exit_t4s6                  
        movb #$07,t4state               
        bra  exit_t4s6
         
halt_t4s6:
        movb #$01, t4state               
             
exit_t4s6:
        rts
;----------                
t4state7:
        bclr PORTP,LED_MSK_1
        tst  ON_1                     
        beq  halt_t4s7                  
        
        tst  DONE_1                     
        beq  exit_t4s7                  
        movb #$02,t4state               
        bra  exit_t4s7
         
halt_t4s7:
        movb #$01, t4state               
             
exit_t4s7:
        rts         
;------------------------------------ TASK_5: TIMING 1 ---------------------------------------------

TASK_5:
        ldaa t5state                       ; this task dictates how many passes thru main to happen
        beq  t5state0                      ; before the first led pair changes states
        deca
        beq  t5state1
               
t5state0:
        movb #$01, t5state                 
        rts
        
t5state1:
        tst  DONE_1
        beq  t5s1a
        movw TICKS_1,COUNT_1               ; if DONE_1 is high, reset COUNT_1 to TICKS_1 
        clr  DONE_1
        
t5s1a:
        decw COUNT_1                       ; decrements COUNT_1 then rts
        bne  exit_t5s1                     ; when COUNT_1 is depleted, set DONE_1
        movb #$01, DONE_1

exit_t5s1:
      rts                        

       
;-------------------- TASK_6: Pattern 2 (functionally identical to Pattern 1) --------------------
TASK_6:                       
        ldaa t6state                      
        beq  t6state0                     
        deca 
        beq  t6state1
        deca 
        beq  t6state2
        deca 
        beq  t6state3
        deca 
        beq  t6state4
        deca 
        beq  t6state5
        deca 
        lbeq t6state6
        deca
        lbeq t6state7
        
t6state0:

        bset DDRP,LED_MSK_2
        bclr PORTP,LED_MSK_2             
        clr  ON_2
        clr  DONE_2
                                                     
        movb #$01,t6state               
        rts
;-----------------        
t6state1:                               ; this is the LED off state
                                        ; pattern 2 stays here while digits are being entered by user
                                        
        bclr PORTP, LED_MSK_2
        tst  ON_2                       ; only ON_2 needs to be high to get out
        beq  exit_t6s1
        movb #$02, t6state
        
exit_t6s1:
        rts
;-----------------        
t6state2:
        bset PORTP,G_LED_2
        tst  ON_2                     
        beq  halt_t6s2                  
        
        tst  DONE_2                     
        beq  exit_t6s2                  
        movb #$03,t6state               
        bra  exit_t6s2
         
halt_t6s2:
        movb #$01, t6state               
             
exit_t6s2:
        rts
;-----------------        
t6state3:
        bclr PORTP,G_LED_2
        tst  ON_2                     
        beq  halt_t6s3                  
        
        tst  DONE_2                     
        beq  exit_t6s3                  
        movb #$04,t6state               
        bra  exit_t6s3
         
halt_t6s3:
        movb #$01, t6state               
             
exit_t6s3:
        rts        
;-----------------        
t6state4:
        bset PORTP,R_LED_2
        tst  ON_2                     
        beq  halt_t6s4                  
        
        tst  DONE_2                     
        beq  exit_t6s4                  
        movb #$05,t6state               
        bra  exit_t6s4
         
halt_t6s4:
        movb #$01, t6state               
             
exit_t6s4:
        rts

exits_t6s4:
        rts
;-----------------                
t6state5:
        bclr PORTP,R_LED_2
        tst  ON_2                     
        beq  halt_t6s5                  
        
        tst  DONE_2                     
        beq  exit_t6s5                  
        movb #$06,t6state               
        bra  exit_t6s5
         
halt_t6s5:
        movb #$01, t6state               
             
exit_t6s5:
        rts
;-----------------               
t6state6:
        bset PORTP,LED_MSK_2
        tst  ON_2                     
        beq  halt_t6s6                  
        
        tst  DONE_2                     
        beq  exit_t6s6                  
        movb #$07,t6state               
        bra  exit_t6s6
         
halt_t6s6:
        movb #$01, t6state               
             
exit_t6s6:
        rts
;-----------------                
t6state7:
        bclr PORTP,LED_MSK_2
        tst  ON_2                     
        beq  halt_t6s7                  
        
        tst  DONE_2                     
        beq  exit_t6s7                  
        movb #$02,t6state               
        bra  exit_t6s7
         
halt_t6s7:
        movb #$01, t6state               
             
exit_t6s7:
        rts         
        
        
;---------------------------- TASK_7: Timing 2 (functionally identical to timing 1) -------------------

TASK_7:
        ldaa t7state
        beq  t7state0
        deca
        beq  t7state1
        
t7state0:
        movb #$01,t7state
        rts
        
t7state1:
        tst  DONE_2
        beq  t7s1
        movw TICKS_2,COUNT_2
        clr  DONE_2
        
t7s1:
        decw COUNT_2
        bne  exit_t7s1
        movb #$01,DONE_2

exit_t7s1:
        rts         
;/------------------------------------------------------------------------------------\
;| Subroutines                                                                        |
;\------------------------------------------------------------------------------------/
; General purpose subroutines go here

;-------------------------- 2-byte ASCII to BIN Converter  ----------------------------
;
;  Accepts a 2-byte ASCII value in the variable BUFFER. Returns the converted result in X 
;  and an error code in A. A = 0 for no error, A = 1 for magnitude too large error, A = 2 for 
;  a zero magnitude error.

ASCII_to_BIN:
                                   ; before jsr, x should have the buffer to be converted
        
        pshb                       ; decrements stack once and pushes contents of b there
        pshy                       ; decrements stack twice and pushes contents of y there

        des                        ; decrement stack 3 to make space for the result (2 byte)   
        des                        ; and for "# of digit conversions completed" (1 byte) SP stays here 
        des                        ; stack is as so:
        
							                          ;- # conv completed (<SP)
							                          ;- current conversion result (high byte)
						                            ;- current conversion result (low byte)
						                            ;- Y preserve (high byte)
							                          ;- Y preserve (low byte)
							                          ;- B reserve
							                          ;- RTN_h (return address to the task you're in)
							                          ;- RTN_l
							                          ;- RTN_h (return address to main)
						  	                        ;- RTN_l
        
        clr  sp                     ; clears the 3 temporary spots in the stack
        clrw 1,sp                        
        ldx  #BUFFER                ; load x with addr of first char in buffer
        ldd 1,sp                    ; init d, clearing any residual stuff that was on it
        
conv_loop:                          
                                    ; result = 10 x result
                          
        ldy  #10                    ; load register y with 10
        emul                        ; multiply y and d and store in Y:D (32-bit result)
        
        tsty                        ; see if emul overflowed into Y (indicating input is > $FFFF)
        bne  TOOBIG                 ; if so, error
        std  1,sp                   ; if not, store the non-overflowed D back into RESULT spot in stack
        
        ldaa 0,sp                   ; load a with the current number of conversions completed
        ldab a,x                    ; load b with the next ASCII to be converted 
                                    ; (at addr: #BUFFER+conversionscompleted)
                                    
        subb #$30                   ; subtract 30 from ASCII to go ASCII-->BCD
        clra                        ; clear a (# digits converted) so it doesn't go into stack in next line
        addd 1,sp                   ; add this BCD digit to result in stack
        bcs  TOOBIG                 ; ensure that the last bit addition does not cause overflow 
                                    ; (if you had 65,533, 7 would overflow it, 
                                    ; but it wouldn't be caught by the other TOOBIG branch)
        
        std  1,sp                   ; store this updated value into RESULT spot in stack
        inc  0,sp                   ; increment the # of digits converted
        dec  COUNT                  
        beq  finish         
        bra  conv_loop                            


finish:
        cpd  #$0000                 ; make sure that 0 wasnt entered, if so, trigger error
        beq  ZEROMAG
        tfr  d,x                    ; store the ultimate result into x
        clra                        ; clear a to indicate "no error"
        bra  exit_conv
        
TOOBIG:
        ldaa #$01
        bra exit_conv        

ZEROMAG:
        ldaa #$02       

exit_conv:
        ins                          ; move sp off of the temporary result and "# conversions" spaces
        ins
        ins
        puly                         ; restore y
        pulb                         ; restore b
        rts        

;------------------  PUTCHAR_1ST sets up the cursor location for the first character --------        
PUTCHAR_1ST:

        stx DPTR                        ; stx stores x (which is currently the addr of first char in mess)
                                        ;         in DPTR, (ldx stores something in x (they're inverses))
        jsr SETADDR                     ; sets cursor location as the contents of a (a was determined before the jsr)
        clr FIRSTCH                     

        ;note: putchar is entered from putchar_1st during the first pass through, then gets branched directly

;------------------  putchar increments the DPTR to the next char in mess then displays that new char ---------        
PUTCHAR:
        
        ldx  DPTR                       ; store contents of x in the Digit Pointer (sets DPTR to the addr of next char)
        ldab 0,x                        ; loads b with x to set the condition codes
        beq  DONE                       ; branch to done when ASCII null is landed on by DPTR
        inx                             ; increment x to move to the next character
        stx  DPTR                       ; store this incremented value to set move to the next char in mess
        jsr  OUTCHAR                    ; print this next character
        rts
        
DONE:   
        movb #$01, FIRSTCH              ; sets FIRSTCH high for the start of the next message
        rts
       
;------------------  delays 1 ms  ---------------------------------------------------------------------------        
DELAY_1ms:
        ldy   #$0584
INNER:                                 ; inside loop
        cpy   #0
        beq   EXIT
        dey
        bra   INNER
EXIT:
        rts                            ; exit DELAY_1ms

;/------------------------------------------------------------------------------------\
;| ASCII Messages and Constant Data                                                   |
;\------------------------------------------------------------------------------------/
; Any constants can be defined here

MESSAGE_1: DC.B  'TIME1 =', $00
MESSAGE_2: DC.B  'TIME2 =', $00
MESSAGE_3: DC.B  '<F1> to update LED1 period', $00      ; the $00 is ASCII null, declares end of message
MESSAGE_4: DC.B  '<F2> to update LED2 period', $00
MESSAGE_5: DC.B  'ERROR: MAGNITUDE TOO LARGE      ', $00          ; DC means declare constant, this stuff cannot be changed in the script
MESSAGE_6: DC.B  'ZERO MAGNITUDE INNAPROPRIATE    ', $00
MESSAGE_7: DC.B  'ERROR: NO DIGITS ENTERED        ', $00
MESSAGE_8: DC.B  '     ', $00
MESSAGE_9: DC.B  '                                ', $00          ; 32 blank spots to clear all that is right of TIME1/TIME2
MESSAGE_0: DC.B  $08,$20,$08,$00                                                                  ; backspace character sequence
;/------------------------------------------------------------------------------------\
;| Vectors                                                                            |
;\------------------------------------------------------------------------------------/
; Add interrupt and reset vectors here

        ORG   $FFFE                    ; reset vector address
        DC.W  Entry
        ORG   $FFCE                    ; Key Wakeup interrupt vector address [Port J]
        DC.W  ISR_KEYPAD
