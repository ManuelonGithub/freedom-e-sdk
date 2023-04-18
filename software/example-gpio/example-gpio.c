/* Copyright 2023 ManuelonGithub */
/* SPDX-License-Identifier: MIT license */

#include <metal/gpio.h>
#include <metal/cpu.h>

#define IN_PIN	2
#define OUT_PIN	5

struct metal_cpu* cpu;	// global because delay needs it, but needs it initialized already

void delay_ticks(unsigned long ticks)
{	
	unsigned long mtime = (unsigned long)metal_cpu_get_mtime(cpu);	// discard top 32-bits
	unsigned long delay_tks = mtime + ticks;

	if (delay_tks < mtime) {
		// handling mtime overflowing back to 0
		while ((unsigned long)metal_cpu_get_mtime(cpu) > 0) {}
	}

	while (delay_tks > (unsigned long)metal_cpu_get_mtime(cpu)) {}
}

// This macro will translate milliseconds to ticks
#define delay_ms(ms) delay_ticks((MTIME_RATE_HZ_DEF * ms / 1000UL))

int main(void)
{
	// this snippet is required for the delay function to work.
	// if the timer interrupt controller isn't initialized then 
	// metal_cpu_get_mtime() will always return 0
	cpu = metal_cpu_get(metal_cpu_get_current_hartid());
	metal_interrupt_init(metal_cpu_timer_interrupt_controller(cpu));

	// GPIO initialization
	struct metal_gpio* gpio = metal_gpio_get_device(0);
	
	// initializing output pin
	metal_gpio_enable_output(gpio, OUT_PIN);	// enables output function
	metal_gpio_disable_input(gpio, OUT_PIN);	// disable input function
	metal_gpio_disable_pinmux(gpio, OUT_PIN);	// Disables HW IO function mux

	// initializing input pin
	metal_gpio_enable_input(gpio, IN_PIN);		// enables output function
	metal_gpio_disable_output(gpio, IN_PIN);	// disable input function
	metal_gpio_disable_pinmux(gpio, IN_PIN);	// Disables HW IO function mux

	while(1) {
		unsigned long toggle_delay = 1000;

		if (metal_gpio_get_input_pin(gpio, IN_PIN)) {
			// holding the input high will cause the pin toggling below to be faster
			toggle_delay = 250;
		}

		metal_gpio_set_pin(gpio, OUT_PIN, 1);
		delay_ms(toggle_delay);
		metal_gpio_set_pin(gpio, OUT_PIN, 0);
		delay_ms(toggle_delay);
	}
}