CC 				:= gcc
CFLAGS 	 		:= -std=c99 -Werror -Wall -Wextra -Wshadow -Wpedantic
CPPFLAGS 		:= -MMD -MP
LDLIBS 	 		:= -lm
LDFLAGS 		:= 
INCLUDES 		:= -Isrc

REL_CFLAGS  	:= -O2
REL_CPPFLAGS 	:= -DNDEBUG
REL_LDLIBS 		:=
REL_LDFLAGS 	:=
REL_INCLUDES 	:=

DBG_CFLAGS 		:= -O0 -g -fsanitize=undefined,address -fno-omit-frame-pointer
DBG_CPPFLAGS 	:= -DDEBUG
DBG_LDLIBS 		:= 
DBG_LDFLAGS 	:= -fsanitize=undefined,address -fno-omit-frame-pointer
DBG_INCLUDES 	:=

BIN 			:= lang

SRC_DIR 		:= src
BIN_DIR 		:= bin

DBG_BIN_DIR 	:= $(BIN_DIR)/debug
DBG_OBJ_DIR 	:= $(DBG_BIN_DIR)/obj
DBG_BIN  		:= $(DBG_BIN_DIR)/${BIN}

REL_BIN_DIR 	:= $(BIN_DIR)/release
REL_OBJ_DIR 	:= $(REL_BIN_DIR)/obj
REL_BIN 		:= $(REL_BIN_DIR)/${BIN}

SRC 			:= $(shell find src -name '*.c')

DBG_OBJ 		:= $(patsubst src/%.c, $(DBG_OBJ_DIR)/%.o, $(SRC))
DBG_DEPS 		:= $(DBG_OBJ:.o=.d)

REL_OBJ 		:= $(patsubst src/%.c, $(REL_OBJ_DIR)/%.o, $(SRC))
REL_DEPS 		:= $(REL_OBJ:.o=.d)

default: debug

all: debug release

--make-dirs:
	@mkdir -p $(BIN_DIR)
	@mkdir -p $(DBG_BIN_DIR)
	@mkdir -p $(REL_BIN_DIR)
	@mkdir -p $(DBG_OBJ_DIR)
	@mkdir -p $(REL_OBJ_DIR)

release: --make-dirs $(REL_BIN)

$(REL_BIN): $(REL_OBJ)
	@echo Linking RELEASE - $(REL_BIN)
	@$(CC) $(REL_OBJ) $(LDLIBS) $(REL_LDLIBS) $(LDFLAGS) $(REL_LDFLAGS) -o $@

$(REL_OBJ_DIR)/%.o: src/%.c
	@mkdir -p $(dir $@)
	@echo Compiling RELEASE - $<
	@$(CC) $(CPPFLAGS) $(REL_CPPFLAGS) $(CFLAGS) $(REL_CFLAGS) $(INCLUDES) $(REL_INCLUDES) -c $< -o $@

debug: --make-dirs $(DBG_BIN)

$(DBG_BIN): $(DBG_OBJ)
	@echo Linking DEBUG - $(DBG_BIN)
	@$(CC) $(DBG_OBJ) $(LDLIBS) $(DBG_LDLIBS) $(LDFLAGS) $(DBG_LDFLAGS) -o $@

$(DBG_OBJ_DIR)/%.o: src/%.c
	@mkdir -p $(dir $@)
	@echo Compiling DEBUG - $<
	@$(CC) $(CPPFLAGS) $(DBG_CPPFLAGS) $(CFLAGS) $(DBG_CFLAGS) $(INCLUDES) $(DBG_INCLUDES) -c $< -o $@

release-run: release
	@echo Running RELEASE
	@./$(REL_BIN)

debug-run: debug
	@echo Running DEBUG
	@./$(DBG_BIN)

run: debug-run

debug-gdb: debug
	@echo Runnig DEBUG under GDB
	@gdb -ex run ./$(DBG_BIN)

clean:
	@echo Cleaning directories
	@rm -rf $(BIN_DIR)

.PHONY: release debug release-run debug-run run all clean

-include $(DBG_DEPS)
-include $(REL_DEPS)
