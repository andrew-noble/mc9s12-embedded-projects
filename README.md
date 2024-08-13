# HCS12 Embedded Projects

This repo has a couple embedded software projects I made in college.
To date, I don't think I've been as intellectually excited as I was when I did these projects, so I have them here for posterity.

They were written for the motorola (then freescale, now NXP) MC9S12XDP512 microcontroller and I used codewarrior as an IDE. All three projects
incorporated cooperative multitasking to accomplish several disparate tasks simultaneously like including detecting keypad presses, displaying
characters to the LCD, and performing the business logic of the project like blinking led's or PID control logic.

## Hardware:

- MC9S12XDP512 microcontroller (on a Adapt9S12D development board)
- LCD display
- keypad

### LED Blinker

User could enter in desired blink rate and the program would blink the led's. Simple result, but I was in awe at the time.

### Function Generator

Program generates a user-specified function (saw, square, sine) via the Adapt9S12D's onboard 12 V, 10-pin DAC.

### Motor Controller

Program controls a brushless DC motor via PWM according to user-specified reference voltage, proportional gain, and integral gain.
The MOSFETS and other hardware weren't part of this project.
