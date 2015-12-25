########################################
# Find which compilers are installed.
#

VOLT ?= $(shell which volt)


########################################
# Basic settings.
#

VFLAGS ?= --internal-perf
LDFLAGS ?=
TARGET ?= battery


########################################
# Setting up the source.
#

include sources.mk
OBJ = $(patsubst src/%.volt, $(OBJ_DIR)/%.bc, $(SRC))


########################################
# Targets.
#

all: $(TARGET)

$(TARGET): $(SRC) GNUmakefile
	@echo "  VOLT   $(TARGET)"
	@$(VOLT) -I src $(VFLAGS) $(LDFLAGS) -o $(TARGET) $(SRC)

run: all
	@./$(TARGET)

debug: all
	@gdb --args ./$(TARGET)

clean:
	@rm -rf $(TARGET) .obj

.PHONY: all run debug clean
