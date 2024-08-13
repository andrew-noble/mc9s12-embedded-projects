;**************************************************************************************
;* LAB 4 MAIN [includes LibV2.1]                                                      *
;**************************************************************************************
;* Summary:                                                                           *
;*   Function Generator                                                               *
;*                                                                                    *
;* NOTE: all instructions are 3 tabs from left                                        *
;*                                                                                    *
;* Author: ANDREW NOBLE                                                               *
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
;| Assembler Equates                                                                  |
;\------------------------------------------------------------------------------------/
; Constant values can be equated here

TSCR   EQU $0046                 ; timer system control register, controls start/stop of timer
TIOS   EQU $0040                 ; TIC TOC register, determines if output compare or input capture                  ; 
TCR2   EQU $0049                 ; timer control register 2, selects the output action resulting from successful compare
C0F    EQU $004E                 ; timer flag register, contains all timer channel flags
TIE1   EQU $004C                 ; timer interrupt enable register, enables maskable interrupts
TCNT   EQU $0044                 ; first word of timer count (low word will be grabbed auto if using 2-word commands)
TC0    EQU $0050                 ; timer channel 0 register (next memory location is low word)

;/------------------------------------------------------------------------------------\
;| Variables in RAM                                                                   |
;\------------------------------------------------------------------------------------/
; The following variables are located in unpaged ram

DEFAULT_RAM:  SECTION

;------ state variables -----
t1state:    DS.B 1                   
t2state:    DS.B 1
t3state:    DS.B 1
t4state:    DS.B 1
t5state:    DS.B 1

                          ; BTI is arbitrary unitless value used as an intermediary
                          ; through which frequency may be altered
                          ; NINT is the value that actually associates a waveform with time
                          ; all waveforms are arbitrarily defined as being 300 BTI "wide" 

NINT:       DS.B 1        ; # of interrupts/BTI, dictates the frequency of wave essentially 
CINT:       DS.B 1        ; # of interrupts remaining in the current BTI
CSEG:       DS.B 1        ; # of segments remaining in this period of wave
LSEG:       DS.B 1        ; # of BTIs left in this segment
SEGSLP:     DS.B 1        ; 16-bit segment increment/BTI (DAC counts/BTI)
VALUE:      DS.B 1        ; DAC scaling value/input (numerator of fraction of input voltage)

WAVEPTR:    DS.W 1        ; addr of 1st byte of wave data
SEGPTR:     DS.W 1        ; addr of 1st byte of wave data for next segment
INTERVAL:   DS.W 1        ; # of clock ticks between interrupts

RUN:        DS.B 1        ; boolean that triggers a waveform to be outputted
NINT_FLG:   DS.B 1        ; boolean that indicates user is currently entering NINT


DWAVE:      DS.B 1        ; boolean to tell display to display a wave name onscreen
WAVE:       DS.B 1        ; 0,1,2,3 depending on desired wave (0=nothing)

DPTR:       DS.W 1        ; "digit pointer" address of next character in mess to be read, displayed
FIRSTCH:    DS.B 1        ; boolean that is true if next character is the first of a mess

COUNT:      DS.B 1        ; # of digits successfully captured from keypad
POINTER:    DS.W 1        ; address of the next available space in buffer
BUFFER:     DS.B 3        ; storage unit for an entire keypad input pre-conversion

KEY_BUF:    DS.B 1        ; storage for a single key input, sent from keypad handler to MM
KEY_FLG:    DS.B 1


DOPTIONS:   DS.B 1
DPRMPT:     DS.B 1
DERR1:      DS.B 1
DERR2:      DS.B 1
DERR3:      DS.B 1
DBLANK:     DS.B 1
ECHO_FLG:   DS.B 1
BS_FLG:     DS.B 1

ERRTIMER:   DS.W 1

NEW_BTI:    DS.B 1
NINT_OK     DS.B 1


;/------------------------------------------------------------------------------------\
;|  Main Program Code                                                                 |
;\------------------------------------------------------------------------------------/
; Your code goes here

MyCode:       SECTION

main: 
         clr   t1state                  ; clear all state variables
         clr   t2state
         clr   t3state
         clr   t4state                  
         clr   t5state

   
loop:   
         jsr TASK_1
         jsr TASK_2
         jsr TASK_3
         jsr TASK_4
         jsr TASK_5  

         bra   loop                     ; endless horizontal loop
       
;--------------------------------------  TASK_1: Mastermind ---------------------------------
TASK_1:
         ldaa t1state
         beq  t1state0                ; init state, raises all initial prompt message flags
         deca
         beq  t1state1                ; waits for prompts to be displayed 
         deca
         beq  t1state2                ; hub state, identifies keys that are retrieved by keypad handler, ignores invalids              
         deca
         lbeq t1s3_BShandler          ; determines whether BS is a valid entry atm, then raises BS_FLG if so
         deca
         lbeq t1s4_ENThandler         ; executes ASCII->BCD->binary conv, raises err flags or loads NINT accordingly
         deca
         lbeq t1s5_digithandler       ; loads digits into buffer
         deca
         lbeq t1s6_errorwait          ; MM waits here for error message to be displayed for 1500 passes thru main
         
t1state0:                     
         movb #$01, DOPTIONS          ; initialize MM by raising the options flag
         
         clr  DPRMPT                  ; init all non-starting message flags
         clr  BS_FLG                  
         clr  ECHO_FLG
         clr  DERR1                    
         clr  DERR2
         clr  DERR3
         clr  NINT_OK
         clr  COUNT
         clr  NINT_FLG
         clr  DBLANK
         clr  RUN
         
         movb #$01, t1state
         rts
            
t1state1:                             ; MM stays in this state until all inital messages are displayed on the LCD
         tst DOPTIONS
         bne t1s1exit
         tst DPRMPT
         bne t1s1exit
                         
         movb #$02, t1state
          
t1s1exit:
         rts

;--------------
t1state2:                             ; this is MM hub state, it interrogates keys retrieved from keypadhandler
         tst  KEY_FLG                            
         beq  t1s2exit                ; if key flag is low, just rts                                                  
         ldaa KEY_BUF                 ; grab the key entered from KEY_BUF 
         
askBS:  
         cmpa #$08                    ; test for BS
         bne  askENT
         movb #$03, t1state
         bra  t1s2exit
         
askENT: 
         cmpa #$0A                    ; test for ENT
         bne  askdigit
         movb #$04, t1state
         bra  t1s2exit
         
askdigit:        
         cmpa #$30                    ; test if its a ASCII digit (between $30-$39)
         blo  t1s2exit                
         cmpa #$39
         bhi  t1s2exit                
                 
         ldab COUNT                   ; test if buffer is full, if so, ignore the digit
         cmpb #$03
         bhs  t1s2exit                ; branch if higher or equal to buffer capacity of 3
         
         movb #$05, t1state           ; finally, MM has determined that this digit can be passed to t1s7_digithandler

t1s2exit:
         clr KEY_FLG                  ; lower the key flag since the key was acknowledged by MM
         rts
; ------------------
t1s3_BShandler:
         tst  NINT_FLG               ; ignore a <BS> entry if NINT input is not active
         beq  BSexit                   
         
         tst  COUNT                   ; ignore a <BS> entry if there is nothing to backspace
         beq  BSexit                    
        
         dec  COUNT                   ; move back the active spot in buffer 
         decw POINTER
         movb #$01, BS_FLG            ; raise the BS flag for display to do its thang
         
BSexit:
         movb #$02, t1state
         rts
; ------------------         
t1s4_ENThandler:
         tst  NINT_FLG                ; if NINT input is not currently being accepted, ignore                   
         beq  ENTignoreexit
          
         tst  COUNT
         beq  ENTnodigit 
         jsr  ASCII_to_BIN             ; recall that ASCII_to_BIN returns 8-bit answer in B and error code in A
                                       ; A=1 for magtoolarge, A=2 for zeromag(x is irrelevant in these cases),A=0 noerror
                                       
         cmpa #$02                     ; raise appropriate error flags based on what ASCII_to_BIN returned in error code
         beq  ENTzeromag
         cmpa #$01 
         beq  ENTmagtoolarge
         
         stab NINT
         movb #$01, NINT_OK
         bra  ENTgoodexit
         
ENTignoreexit:                         ; used when the <ENT> ignored (while NINT_FLG=0)
         movb #$02, t1state
         rts
         
ENTnodigit:
         movb #$01, DERR3            
         bra  ENTerrexit
         
ENTzeromag:
         movb #$01, DERR2            
         bra  ENTerrexit
         
ENTmagtoolarge:
         movb #$01, DERR1            
         bra  ENTerrexit
         
ENTgoodexit:                           ; once enter has been hit, user can now press f1 or f2 again w/o ignore
         movb #$02, t1state
         clr  NINT_FLG                 ; NINT input is no longer accepted until a wave is selected
         rts

ENTerrexit: 
         movb #$06, t1state            ; move to error wait state
         rts 
;------------------
t1s5_digithandler:

         tst  NINT_FLG                 
         bne  load_buffer              ; if NINT_INPUT is high, we want to accept 0-9, if low, 0-4
         ldaa KEY_BUF                  ; (only 0-4 is valid for wave selection)
         cmpa #$34
         bhi  digitexit
         
         suba #$30                     ; convert ascii entry to simple 1, 2, 3, 4 based on wave selection
         staa WAVE                     ; store the wave code into WAVE
         movw #BUFFER, POINTER         ; set up pointer as the address of first spot in buffer
         clr  COUNT
         
         tst  RUN                      ; test if the DAC is already running, if so, we need to stop it
         bne  stopfg                     
         bra  digitexit
            
stopfg:
         clr  RUN
         
         cmpa #$00                     ; we want to additionally display the blank bottom line if 0 was hit
         beq  displayblank
         bra  digitexit

displayblank:
        movb #$01, DBLANK
        bra  digitexit                                   

load_buffer:
      
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
t1s6_errorwait:
                                       ; MM stays in this state until error messages are done displaying for 1500 passes thru main
         tst DERR1                     ; test that display is done displaying the error (whichever it may be)
         bne t1s6exit
         tst DERR2
         bne t1s6exit
         tst DERR3
         bne t1s6exit
         movb #$01, DPRMPT             ; its done displaying them, so now MM needs to redisplay NINT prompt
         movw #BUFFER, POINTER         ; reset pointer
         clr  COUNT
         movb #$01, t1state            ; move to prompt-wait state
         
t1s6exit:
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
         lbeq  t3state2        ; displays wave options prompt on top line
         deca
         lbeq  t3state3        ; displays all wave messages
         deca
         lbeq  t3state4        ; displays NINT prompt
         deca
         lbeq  t3state5        ; echo 
         deca
         lbeq  t3state6        ; backspacer 
         deca
         lbeq  t3state7        ; displays mag too large error message
         deca
         lbeq  t3state8        ; displays zero magnitude error
         deca
         lbeq  t3state9        ; displays the no digits error message
         deca 
         lbeq  t3state10       ; DC waits in this state while error messages
                               ; are displayed onscreen for 1500 passes thru main
         deca 
         lbeq  t3state11       ; blank line displayer

t3state0: 
         jsr  INITLCD          ; initialise the display
         jsr  CURSOR_ON            
         movb #$01, t3state
         movb #$01, FIRSTCH
         movw #$FFFF,ERRTIMER   ; init errtimer by inputting 1500 into it
         rts
         
t3state1:                      ; display hub state: each subtask tests a different fixedmessage boolean
         tst  DOPTIONS                
         beq  t3s1a            ; branch to next boolean check if DOPTIONS is low
         movb #$02, t3state    ; advance state var so that next round options message is displayed 
         rts
t3s1a:
         tst  DWAVE   
         beq  t3s1b	      
         movb #$03, t3state
         rts
t3s1b:   
         tst  DPRMPT
         beq  t3s1c             
         movb #$04, t3state     
         rts 
t3s1c:
         tst  ECHO_FLG
         beq  t3s1d
         movb #$05, t3state
         rts
t3s1d:
         tst  BS_FLG
         beq  t3s1e
         movb #$06, t3state
         rts
t3s1e:
         tst  DERR1
         beq  t3s1f
         movb #$07, t3state
         rts
t3s1f:
         tst  DERR2
         beq  t3s1g
         movb #$08, t3state
         rts
t3s1g:
         tst  DERR3
         beq  t3s1h
         movb #$09, t3state
         rts
t3s1h:
         tst  DBLANK
         beq  t3s1exit
         movb #$0B, t3state
         rts

t3s1exit:
         rts
         
;----------------

t3state2:                         ; this is the wave options message displayer!             
         tst  FIRSTCH             ; check if first char of a message so that cursor can be set properly
         beq  t3s2a               ; if it isn't the first character, branch to next char printing
                                  ;      because cursor is already in the correct position from last char
                                  
                                  ; if this is the first char, perform the following setup:
         ldaa #$00                ; load a with the desired cursor address for 1st message
         ldx  #MESSAGE_0          ; load x with address of first char in message
         jsr  PUTCHAR_1ST
         bra  t3s2done

t3s2a:
         jsr PUTCHAR              
                                                                       
t3s2done:
         tst  FIRSTCH             ; notice that this snippet is entered by "fall through" from t3s2a
         beq  t3s2b               ; this branch will be bypassed when PUTCHAR sets FIRSTCH back to 1 after message
                                  ; is successfully displayed
         clr  DOPTIONS            ; else, (it is done), clear the DTIME_1 and
         movb #$01, t3state       ; return to hub state

t3s2b: 
         rts
         

;-----------------
t3state3:                      ; this is the wave message displayer, displays any wave name onscreen             
         tst  FIRSTCH             
         beq  t3s3a
         ldaa WAVE

asksaw:
	       cmpa #$01             ; this decision tree decides which wave message is desired per WAVE                             
         bne  asksine7	          

         ldx  #SAW_MESS
	       movw #SAW, WAVEPTR    ; point to the address of the first byte in the appropriate wave data
	       bra  startdisp

asksine7:
	       cmpa #$02
	       bne  asksquare
	       
         ldx  #SINE7_MESS
	       movw #SINE7, WAVEPTR       
	       bra  startdisp

asksquare:
	       cmpa #$03
	       bne  asksine15
	       
         ldx  #SQUARE_MESS
	       movw #SQUARE, WAVEPTR
	       bra  startdisp

asksine15:
         ldx  #SINE15_MESS
         movw #SINE15, WAVEPTR

startdisp:
	       ldaa #$40          
         jsr  PUTCHAR_1ST
         bra  t3s3done

t3s3a:
         jsr PUTCHAR              
                                                                       
t3s3done:
         tst  FIRSTCH             
         beq  t3s3b               
                                  
         clr  DWAVE              
         movb #$01, t3state       

t3s3b: 
         rts
;-----------------
t3state4:                         ; this is the NINT prompt message displayer             
         tst  FIRSTCH             
         beq  t3s4a               
                                  
                                  
                                  
         ldaa #$55                
         ldx  #MESSAGE_1          
         jsr  PUTCHAR_1ST
         bra  t3s4done

t3s4a:
         jsr PUTCHAR              
                                                                       
t3s4done:
         tst  FIRSTCH             
         beq  t3s4b               
         ldaa #$5B
         jsr  SETADDR              ; set the cursor address to correct location for NINT entry
         movb #$01, NINT_FLG       ; start allowing entries 5-9                  
         clr  DPRMPT              
         movb #$01, t3state       

t3s4b: 
         rts
;-----------------                   
t3state5:                      ; this is the echo displayer state 
         ldx  POINTER          ; load x with the with POINTER (the address of the next avail space in buffer)
         ldab -1,x             ; load b with the character BEFORE pointer (what was just pressed)
         jsr OUTCHAR           ; OUTCHAR takes b as its character, therefore OUTCHAR'ing last digit entered
         clr ECHO_FLG
         movb #$01, t3state
         rts
;----------------                       
t3state6:
                               ; this is the Backspacer, it's only difference from TIME1 displayer
         tst  FIRSTCH          ; is that the target address is not fixed, its the current address
         beq  t3s6a               
                                                    
         jsr  GETADDR          ; this grabs the current cursor address to be the printing address
         ldx  #MESSAGE_7          
         jsr  PUTCHAR_1ST
         bra  t3s6done

t3s6a:
         jsr PUTCHAR 
                                            
t3s6done:
         tst  FIRSTCH              
         beq  t3s6b                
         clr  BS_FLG                
         movb #$01, t3state        
t3s6b: 
         rts
;----------------         
t3state7:                       ; this is the mag too large error message displayer             
         tst  FIRSTCH             
         beq  t3s7a               
                                  
                                  
                                  
         ldaa #$55                
         ldx  #MESSAGE_2          
         jsr  PUTCHAR_1ST
         bra  t3s7done

t3s7a:
         jsr PUTCHAR              
                                                                       
t3s7done:
         tst  FIRSTCH             
         beq  t3s7b               
                                                
         movb #$0A, t3state       

t3s7b: 
         rts
;----------------         
t3state8:                         ; this is the invalid mag (zero) error message displayer             
         tst  FIRSTCH             
         beq  t3s8a               
                                  
                                  
                                  
         ldaa #$55                
         ldx  #MESSAGE_3          
         jsr  PUTCHAR_1ST
         bra  t3s8done

t3s8a:
         jsr PUTCHAR              
                                                                       
t3s8done:
         tst  FIRSTCH             
         beq  t3s8b               
                                                
         movb #$0A, t3state       

t3s8b: 
         rts
         
;----------------         
t3state9:                         ; this is the no digits error message displayer             
         tst  FIRSTCH             
         beq  t3s9a               
                                  
                                  
                                  
         ldaa #$55                
         ldx  #MESSAGE_4          
         jsr  PUTCHAR_1ST
         bra  t3s9done

t3s9a:
         jsr PUTCHAR              
                                                                       
t3s9done:
         tst  FIRSTCH             
         beq  t3s9b               
                                               
         movb #$0A, t3state       

t3s9b: 
         rts        
;----------------         
t3state10:                        ; display freeze state, it causes error messages to be sustained LCD
                                  ; DH is arrested here until there have been FFFF main passes
                                  ; NOTE: it DOES NOT arrest the whole CPU, just holds disp task in state 12
                                        
         ldy  ERRTIMER            ; ERRTIMER starts with FFFF in it 
         cpy  #00
         beq  thaw
         decy
         sty  ERRTIMER
         rts
                                                 
thaw:                                
         clr  DERR1               ; error message (whichever it may be) has been displayed for 1500 passes, lower its flg!
         clr  DERR2
         clr  DERR3
         movw #$FFFF, ERRTIMER    ; reset the error message timer
         
         movb #$01, t3state       ; go back to hub
         rts
         
;-----------------                   
t3state11:                         ; this is the full blank line message displayer             
         tst  FIRSTCH             
         beq  t3s11a               
                                  
                                  
                                  
         ldaa #$40                
         ldx  #MESSAGE_6          
         jsr  PUTCHAR_1ST
         bra  t3s11done

t3s11a:
         jsr PUTCHAR              
                                                                       
t3s11done:
         tst  FIRSTCH             
         beq  t3s11b               
                                  
         clr  DBLANK              
         movb #$01, t3state       

t3s11b: 
         rts
         
; --------------------------- TASK_4: Timer Channel 0 Controller ------------------------

TASK_4:				; this task just turns the TC0 interrupt routine on and off
      ldaa t4state
      beq  t4state0                
      deca
      beq  t4state1                
      deca
      beq  t4state2
         
t4state0:                        ; init the timer interrupt channel 0
         
      bset TIOS, #$01            ; set timer channel 0 for output compare (tic/toc select register)
      bset TCR2, #$01            ; sets successful output compare response to "toggle output pin"
      bset C0F,  #$01            ; clears the channel 0 output compare flag (by writing 1 to it)                                 
      cli                        ; clears i-bit, enabling interrupts (masterswitch for all ints)
      
      movb #$01, t4state
      rts 

t4state1:                        ; "waiting for RUN" state

      tst  RUN
      beq  t4s1exit
      bset TIE1, #$01            ; set C0I bit, enables chan0 interrupts
      bset TCR2, #$01            ; set OL0 bit, specifies toggle as the interrupt action
      
      movb #$02, t4state
      
t4s1exit:                        
      rts
      
t4state2                         ; "waiting for not RUN" state
      tst  RUN
      bne  t4s2exit
      bclr TIE1, #$01            ; disable interrupts from chan0
      bclr TCR2, #$01            ; disconnect chan0 from output pin logic
      
      movb #$01, t4state
      
t4s2exit:      
      rts

;--------------------------- TASK_5: Function Generator --------------------------------

TASK_5:
      ldaa t5state
      beq  t5state0                
      deca
      beq  t5state1                
      deca
      beq  t5state2
      deca
      beq  t5state3                
      deca
      beq  t5state4
      
t5state0:
      clr DWAVE
      clr WAVE
      clr RUN
      movb #$01, t5state  
      rts
      
t5state1:                        ; waiting for wave selection by the user
      tst  WAVE
      beq  t5s1exit
      movb #$01, DWAVE		       ; if a wave have been selected, signal display controller to display its name 
      movb #$02, t5state

t5s1exit:
      rts
; ------------------         

t5state2:                        ; a new wave has been selected by user, lets grab its data preemptively
      tst  DWAVE                 ; wait until wave name is displayed
      bne  t5s2exit
      ldx  WAVEPTR               ; point to start of data for wave
      movb 0,x, CSEG             ; get number of wave segments
      movw 1,x, VALUE            ; get initial value for DAC
      movb 3,x, LSEG             ; load segment length
      movw 4,x, SEGSLP           ; load segment slope
      inx                        ; inc SEGPTR to next segment
      inx
      inx
      inx
      inx
      inx
      stx  SEGPTR                ; store incremented SEGPTR for next segment
      movb #$01, DPRMPT          ; ask display to prompt user for NINT input
      movb #$03, t5state         ; set next state

t5s2exit:
      rts
; ------------------
t5state3:                        ; wait for NINT state
      tst  NINT_OK               ; wait until a valid NINT has been entered (NINT_OK owned by MM)
      beq  t5s3exit
      clr  NINT_OK
      movb #$01, RUN
      movb #$04, t5state
      
t5s3exit:
      rts
; ------------------         
t5state4:                        ; display wave state
        tst  RUN
        beq  t5s4c               ; return to wait_for_wave state if RUN=0
        tst  NEW_BTI
        beq  t5s4e               ; do not update function generator if NEWBTI=0
        dec  LSEG                ; decrement BTIs remaining in segment counter
        bne  t5s4b               ; if not at end of segment, simply update DAC output
        dec  CSEG                ; if at end of seg, decrement segment counter
        bne  t5s4a               ; if not last segment in wave, skip reinit of wave

				                         ; program goes here at the end of a wave
        ldx  WAVEPTR             ; point to start of data for wave
        movb 0,X, CSEG           ; get number of wave segments
        inx                      ; inc SEGPTR to start of first segment
        inx
        inx
        stx  SEGPTR              ; store incremented SEGPTR
        

				                          
t5s4a:                           ; program goes here at the end of a segment
        ldx  SEGPTR              ; point to start of new segment
        movb 0,X, LSEG           ; initialize segment length counter
        movw 1,X, SEGSLP         ; load segment increment
        inx                      ; inc SEGPTR to next segment
        inx
        inx
        stx  SEGPTR              ; store incremented SEGPTR
        
				                          
t5s4b:                           ; program stays in here while writing within a segment
        ldd  VALUE               ; get current DAC input value
        addd SEGSLP              ; add SEGSLP to current DAC input value
        std  VALUE               ; store incremented DAC input value
        bra  t5s4d
        
t5s4c:  
        movb #$01, t5state       ; when RUN is cleared, start waiting for new wave
        
t5s4d:  
        clr  NEW_BTI

t5s4e:  
        rts         
;/------------------------------------------------------------------------------------\
;| Subroutines                                                                        |
;\------------------------------------------------------------------------------------/
; General purpose subroutines go here

;-------------------------- 1- byte ASCII to BIN Converter  ----------------------------
;
;  Accepts a 1-byte ASCII value in the variable BUFFER. Returns the converted result in B 
;  and an error code in A. A = 0 for no error, A = 1 for magnitude too large error, A = 2 for 
;  a zero magnitude error.

ASCII_to_BIN:
                                   
        
        pshx                       ; decrements stack twice and pushes contents of x there
	      pshy			                 ; decrements stack twice and pushes contents of y there

        des                        ; decrement stack 2 to make space for the result (1 byte)   
        des                        ; and "# of digit conversions completed" (1 byte) (SP stays here)
				                           ; stack is as so:
							                          ;- # conv completed (<SP)
							                          ;- current conversion result
							                          ;- Y preserve (high byte)
							                          ;- Y preserve (low byte)
							                          ;- X preserve (high byte)
							                          ;- X preserve (low byte)
							                          ;- RTN_h (return address to the task you're in)
							                          ;- RTN_l
							                          ;- RTN_h (return address to main)
						                          	;- RTN_l
           
        clrw 0,sp                   ; clears the 2 temporary spots in the stack
                                    
        ldx  #BUFFER                ; load x with addr of first char in buffer
        ldab 1,sp                   ; clear b
        
conv_loop:                          
                                    ; result = 10 x result
                          
        ldaa #10                    ; load accumulator b with 10
        mul                         ; multiply a and b and store in A:B (16-bit result)
        
        tsta                        ; see if mul overflowed into A (indicating input is > $FF)
        bne  TOOBIG                 ; if so, error
        stab 1,sp                   ; if not, store the non-overflowed B back into result spot in stack
        
        ldaa 0,sp                   ; load a with the current number of conversions completed
        ldab a,x                    ; load b with the next ASCII to be converted 
                                    ; (at addr: #BUFFER+conversionscompleted)
                                    
        subb #$30                   ; subtract 30 from ASCII to go ASCII-->BCD
        clra                        ; clear a (# digits converted) so it doesn't go into stack in next line
        addb 1,sp                   ; add this BCD digit to result in stack
        bcs  TOOBIG                 ; ensure that the last bit addition does not cause overflow 
                                    ; (if you had 253, 7 would overflow it, 
                                    ; but it wouldn't be caught by the other TOOBIG branch)
        
        stab 1,sp                   ; store this updated value into result spot in stack
        inc  0,sp                   ; increment the # of digits converted
        dec  COUNT                  
        beq  finish         
        bra  conv_loop                            


finish:
        cmpb #$00                   ; make sure that 0 wasnt entered, if so, trigger error
        beq  ZEROMAG
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
        puly                         ; restore y
        pulx                         ; restore x
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

;------------------- Timer Channel 0 Interrupt Service Routine --------------------------

TC0_ISR:                         ; this code is entered as a result of an interrupt,
                                 ; set up by interrupt vector below, unlike a branch or jsr
     
      dec  CINT                  ; decrement number of interrupts left in BTI
      bne  NOT_YET               ; should the OUTDACA value change?
     
     
      ldd  VALUE                 ; yes, grab the desired value and OUTDACA
                                 ; this code occurs at the beginning of a new "step"
      jsr  OUTDACA
      movb NINT, CINT            ; reset CINT
      movb #$01, NEW_BTI         ; tell fcn gen task to recalculate VALUE for next time
    
NOT_YET:                         ; check back at this time:
                                 
      ldd    TC0                 ; capture current timer count into d
      addd   INTERVAL            ; add interval to current timer count
      std    TC0                 ; store (interval + TCNT) back into d
      bset   C0F, #$01           ; clear the timer channel 0 timer output compare interrupt flag
      rti                        ; return from interrupt
     

;/------------------------------------------------------------------------------------\
;| ASCII Messages and Constant Data                                                   |
;\------------------------------------------------------------------------------------/
; Any constants can be defined here

MESSAGE_0:    DC.B  '1: SAW, 2: SINE-7, 3: SQUARE, 4: SINE-15', $00
MESSAGE_1:    DC.B  'NINT:     [1-->255]',$00
MESSAGE_2:    DC.B  'MAGNITUDE TOO LARGE', $00
MESSAGE_3:    DC.B  'INVALID MAGNITUDE  ', $00
MESSAGE_4:    DC.B  'NO DIGITS ENTERED  '  , $00
MESSAGE_6:    DC.B  '                                        ', $00  ; blanks to clear entire bottom line                     
MESSAGE_7:    DC.B  $08,$20,$08,$00                                  ; backspace sequence
BLANK_MESS:   DC.B  '                                        ', $00  ; blanks to clear entire bottom line                                    ; NINT prep
SAW_MESS:     DC.B  'SAWTOOTH WAVE       ', $00
SINE7_MESS:   DC.B  '7-SEGMENT SINE WAVE ', $00
SQUARE_MESS:  DC.B  'SQUARE WAVE         ', $00
SINE15_MESS:  DC.B  '15-SEGMENT SINE WAVE', $00

SAW:                         ; the data for a sawtooth wave (frequency when NINT=1 is 500Hz)
              
              DC.B 2         ; number of segments in sawtooth wave 
              DC.W 0         ; starting DAC value (0 V)
              DC.B 19        ; segment 1 length (BTI)
              DC.W 172      ; segment 1 slope (DAC values/BTI)
              DC.B 1
              DC.W -3276




SINE7:                       ; the data for a 7 segment sine wave (frequency when NINT=1 is 33.3Hz)
      
              DC.B 7         ; number of segments for the sine wave
              DC.W 2048      ; DAC scaling value to start (corresponds to 5V)
              DC.B 25        ; length for seg 1  
              DC.W 33        ; slope for seg 1
              DC.B 50
              DC.W 8
              DC.B 50
              DC.W -8
              DC.B 50
              DC.W -33
              DC.B 50
              DC.W -8
              DC.B 50
              DC.W -8
              DC.B 50
              DC.W 8
              DC.B 25
              DC.W 33
              
SQUARE:                      ; the data for a square wave (frequency when NINT=1 is 500Hz)
              
              DC.B 5         ; number of segments for the square wave
              DC.W 1638      ; DAC scaling value to start (corresponds to 4V)
              DC.B 0         ; length for seg 1 (BTI's)
              DC.W 1638      ; slope for seg 1 (DAC units per BTI)
              DC.B 10
              DC.W 0
              DC.B 0
              DC.W -3276
              DC.B 10
              DC.W 0
              DC.B 0
              DC.W 1638

SINE15:                 ; the data for a 15-segment sine wave (frequency when NINT=1 is 33.3Hz)

              DC.B 15 	; number of segments for SINE15
              DC.W 2048 ; initial DAC input value
              DC.B 10 	; length for segment_1
              DC.W 41 	; increment for segment_1
              DC.B 21 	; length for segment_2
              DC.W 37 	; increment for segment_2
              DC.B 21 	; length for segment_3
              DC.W 25 	; increment for segment_3
              DC.B 21 	; length for segment_4
              DC.W 9 	  ; increment for segment_4
              DC.B 21 	; length for segment_5
              DC.W -9 	; increment for segment_5
              DC.B 21 	; length for segment_6
              DC.W -25 	; increment for segment_6
              DC.B 21 	; length for segment_7
              DC.W -37 	; increment for segment_7
              DC.B 20 	; length for segment_8
              DC.W -41 	; increment for segment_8
              DC.B 21 	; length for segment_9
              DC.W -37 	; increment for segment_9
              DC.B 21 	; length for segment_10
              DC.W -25 	; increment for segment_10
              DC.B 21 	; length for segment_11
              DC.W -9 	; increment for segment_11
              DC.B 21 	; length for segment_12
              DC.W 9 	  ; increment for segment_12
              DC.B 21 	; length for segment_13
              DC.W 25 	; increment for segment_13
              DC.B 21 	; length for segment_14
              DC.W 37 	; increment for segment_14
              DC.B 10 	; length for segment_15
              DC.W 41 	; increment for segment_15
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
        
      