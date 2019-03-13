#############################################################
# Makefile Arguments
#############################################################

# BSP_DIR sets the path to the target-specific board support package.
BSP_DIR ?= $(abspath bsp)
# SRC_DIR sets the path to the program source directory
SRC_DIR ?= $(abspath src)

# The configuration defaults to Debug. Valid choices are:
#  - debug
#  - release
CONFIGURATION ?= debug

#############################################################
# BSP loading
#############################################################

# There must be a settings makefile fragment in the BSP's board directory.
ifeq ($(wildcard $(BSP_DIR)/settings.mk),)
$(error Unable to find BSP for $(TARGET), expected to find $(BSP_DIR)/settings.mk)
endif

# Include the BSP settings
include $(BSP_DIR)/settings.mk

# Check that settings.mk sets RISCV_ARCH and RISCV_ABI
ifeq ($(RISCV_ARCH),)
$(error $(BSP_DIR)/board.mk must set RISCV_ARCH, the RISC-V ISA string to target)
endif

ifeq ($(RISCV_ABI),)
$(error $(BSP_DIR)/board.mk must set RISCV_ABI, the ABI to target)
endif

ifeq ($(RISCV_CMODEL),)
RISCV_CMODEL = medany
endif

# Determines the XLEN from the toolchain tuple
ifeq ($(patsubst rv32%,rv32,$(RISCV_ARCH)),rv32)
RISCV_XLEN := 32
else ifeq ($(patsubst rv64%,rv64,$(RISCV_ARCH)),rv64)
RISCV_XLEN := 64
else
$(error Unable to determine XLEN from $(RISCV_ARCH))
endif

#############################################################
# Toolchain
#############################################################

# Allow users to select a different cross compiler.
CROSS_COMPILE ?= riscv64-unknown-elf

# If users don't specify RISCV_PATH then assume that the tools will just be in
# their path.
ifeq ($(RISCV_PATH),)
RISCV_GCC     := $(CROSS_COMPILE)-gcc
RISCV_GXX     := $(CROSS_COMPILE)-g++
RISCV_OBJDUMP := $(CROSS_COMPILE)-objdump
RISCV_OBJCOPY := $(CROSS_COMPILE)-objcopy
RISCV_GDB     := $(CROSS_COMPILE)-gdb
RISCV_AR      := $(CROSS_COMPILE)-ar
RISCV_SIZE    := $(CROSS_COMPILE)-size
else
RISCV_GCC     := $(abspath $(RISCV_PATH)/bin/$(CROSS_COMPILE)-gcc)
RISCV_GXX     := $(abspath $(RISCV_PATH)/bin/$(CROSS_COMPILE)-g++)
RISCV_OBJDUMP := $(abspath $(RISCV_PATH)/bin/$(CROSS_COMPILE)-objdump)
RISCV_OBJCOPY := $(abspath $(RISCV_PATH)/bin/$(CROSS_COMPILE)-objcopy)
RISCV_GDB     := $(abspath $(RISCV_PATH)/bin/$(CROSS_COMPILE)-gdb)
RISCV_AR      := $(abspath $(RISCV_PATH)/bin/$(CROSS_COMPILE)-ar)
RISCV_SIZE    := $(abspath $(RISCV_PATH)/bin/$(CROSS_COMPILE)-size)
PATH          := $(abspath $(RISCV_PATH)/bin):$(PATH)
endif

SEGGER_JLINK_EXE := JLinkExe
SEGGER_JLINK_GDB_SERVER := JLinkGDBServer

#############################################################
# Software Flags
#############################################################

# Set the arch, ABI, and code model
RISCV_CFLAGS   += -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -mcmodel=$(RISCV_CMODEL)
RISCV_CXXFLAGS += -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -mcmodel=$(RISCV_CMODEL)
# Prune unused functions and data
RISCV_CFLAGS   += -ffunction-sections -fdata-sections
RISCV_CXXFLAGS += -ffunction-sections -fdata-sections
# Include the Metal headers
RISCV_CFLAGS   += -I$(abspath $(BSP_DIR)/install/include/)
RISCV_CXXFLAGS += -I$(abspath $(BSP_DIR)/install/include/)

# Turn on garbage collection for unused sections
RISCV_LDFLAGS += -Wl,--gc-sections
# Turn off the C standard library
RISCV_LDFLAGS += -nostartfiles -nostdlib
# Find the archive files and linker scripts
RISCV_LDFLAGS += -L$(sort $(dir $(abspath $(filter %.a,$^)))) -T$(abspath $(filter %.lds,$^))

# Link to the relevant libraries
RISCV_LDLIBS += -Wl,--start-group -lc -lgcc -lmetal -lmetal-gloss -Wl,--end-group

# Load the configuration Makefile
CONFIGURATION_FILE = $(wildcard $(CONFIGURATION).mk)
ifeq ($(words $(CONFIGURATION_FILE)),0)
$(error Unable to find the Makefile $(CONFIGURATION).mk for CONFIGURATION=$(CONFIGURATION))
endif
include $(CONFIGURATION).mk

#############################################################
# Software
#############################################################

PROGRAM_ELF ?= $(SRC_DIR)/$(CONFIGURATION)/$(PROGRAM).elf
PROGRAM_HEX ?= $(SRC_DIR)/$(CONFIGURATION)/$(PROGRAM).hex

.PHONY: all
all: software

.PHONY: software
software: $(PROGRAM_ELF)

ifneq ($(COREIP_MEM_WIDTH),)
software: $(PROGRAM_HEX)
endif
ifneq ($(SEGGER_JLINK_OB),)
software: $(PROGRAM_HEX)
endif

PROGRAM_SRCS = $(wildcard $(SRC_DIR)/*.c) $(wildcard $(SRC_DIR)/*.h) $(wildcard $(SRC_DIR)/*.S)

$(PROGRAM_ELF): \
		$(PROGRAM_SRCS) \
		$(BSP_DIR)/install/lib/$(CONFIGURATION)/libmetal.a \
		$(BSP_DIR)/install/lib/$(CONFIGURATION)/libmetal-gloss.a \
		$(BSP_DIR)/metal.lds
	mkdir -p $(dir $@)
	$(MAKE) -C $(SRC_DIR) $(basename $(notdir $@)) \
		AR=$(RISCV_AR) \
		CC=$(RISCV_GCC) \
		CXX=$(RISCV_GXX) \
		CFLAGS="$(RISCV_CFLAGS)" \
		CXXFLAGS="$(RISCV_CXXFLAGS)" \
		LDFLAGS="$(RISCV_LDFLAGS)" \
		LDLIBS="$(RISCV_LDLIBS)"
	mv $(SRC_DIR)/$(basename $(notdir $@)) $@
	touch -c $@

	$(RISCV_SIZE) $@

ifneq ($(SEGGER_JLINK_OB),)
# If we're using Segger J-Link OB, use objcopy to create an Intel hex file for programming
$(PROGRAM_HEX): \
		$(RISCV_OBJCOPY) \
		$(PROGRAM_ELF)
	$< -O ihex $(PROGRAM_ELF) $@
endif

.PHONY: clean-software
clean-software:
	$(MAKE) -C $(SRC_DIR) clean
	rm -rf $(SRC_DIR)/$(CONFIGURATION)
.PHONY: clean
clean: clean-software
