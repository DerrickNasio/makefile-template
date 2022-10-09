# User-defined project settings
# ------------------------------------------------------------------------------

# The name of the executable to be created
PROGRAM := hello

# The compiler used
CC ?= gcc

# General compiler and preprocessor flags
COMPILE_FLAGS = -std=c11 -Wall -Wextra -g

# Additional release-specific flags
RELEASE_COMPILE_FLAGS = -D NDEBUG

# Additional debug-specific flags
DEBUG_COMPILE_FLAGS = -D DEBUG

# General linker settings, e.g. "-lmysqlclient -lz"
LINK_FLAGS = -lm

# Additional release-specific linker settings
RELEASE_LINK_FLAGS =

# Additional debug-specific linker settings
DEBUG_LINK_FLAGS =

# The directories in which source files reside.
# If not specified, all subdirectories of the current directory,
# where the makefile is, will be added recursively. 
SRC_DIRS               := 

# Extension of source files used in the project (headers excluded)
SRC_EXTS = .c .C

# Additional include paths,
# e.g. "-I/usr/include/mysql -I./include -I/usr/include -I/usr/local/include"
INCLUDES = -I $(SRC_DIRS)

# Space-separated pkg-config libraries used by this project
PKG_CONFIG_LIBS =

# Optional verbosity setting, set to false by default
KBUILD_VERBOSE = false

# Install destination directory, like a jail or mounted system
DEST_DIR = /

# Install path (bin/ is appended automatically)
INSTALL_PREFIX = usr/local


### Generally should not need to edit below this line

# Obtain the operating system for OS-specific flags
UNAME_S := $(shell uname -s)

# Shell used in this makefile
# bash is used for 'echo -en'
SHELL = /bin/bash

# Clear any built-in rules
.SUFFIXES:

# Programs for installation
INSTALL = install
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644

# Append pkg-config specific libraries if need be
ifneq ($(LIBS),)
	COMPILE_FLAGS += $(shell pkg-config --cflags $(PKG_CONFIG_LIBS))
	LINK_FLAGS += $(shell pkg-config --libs $(PKG_CONFIG_LIBS))
endif

# Verbose option, to output compile and link commands
# ------------------------------------------------------------------------------

ifndef KBUILD_VERBOSE
	KBUILD_VERBOSE = false
endif

ifeq ($(KBUILD_VERBOSE), true)
	CMD_PREFIX :=
else
	CMD_PREFIX := @
endif

export KBUILD_VERBOSE CMD_PREFIX

# Combine compiler and linker flags
# ------------------------------------------------------------------------------

release: export CC_FLAGS := $(CC_FLAGS) $(COMPILE_FLAGS) $(RELEASE_COMPILE_FLAGS)
release: export LD_FLAGS := $(LD_FLAGS) $(LINK_FLAGS) $(RELEASE_LINK_FLAGS)
debug: export CC_FLAGS := $(CC_FLAGS) $(COMPILE_FLAGS) $(DEBUG_COMPILE_FLAGS)
debug: export LD_FLAGS := $(LD_FLAGS) $(LINK_FLAGS) $(DEBUG_LINK_FLAGS)

# Build and output paths
# ------------------------------------------------------------------------------

release: export BUILD_PATH := build/release
release: export BIN_PATH := bin/release
debug: export BUILD_PATH := build/debug
debug: export BIN_PATH := bin/debug
install: export BIN_PATH := bin/release

# If the source directory is not specified,
# add recursively all subdirectories of the current directory. 
ifeq ($(SRC_DIRS),)
	SRC_DIRS := $(shell find $(SRC_DIRS) -type d)
endif

# Find all source files in the source directory,
# sorted by most recently modified
ifeq ($(UNAME_S), Darwin)
	SOURCES = $(shell find $(SRC_DIRS) -name '*$(SRC_EXTS)' \
						| sort -k 1nr | cut -f2-)
else
	SOURCES = $(shell find $(SRC_DIRS) -name '*$(SRC_EXTS)' -printf '%T@\t%p\n'\
						| sort -k 1nr | cut -f2-)
endif

# fallback in case the above fails
rwildcard = $(foreach d, $(wildcard $1*), $(call rwildcard,$d/,$2) \
						$(filter $(subst *,%,$2), $d))
ifeq ($(SOURCES),)
	SOURCES := $(call rwildcard, $(SRC_DIRS), *$(SRC_EXTS))
endif

# Set the object file names, with the source directory stripped
# from the path, and the build path prepended in its place
OBJECTS = $(SOURCES:$(SRC_DIRS)/%$(SRC_EXTS)=$(BUILD_PATH)/%.o)

# Create hidden dependency files (of the form .%.d)
# that will be used to add header dependencies
DEPENDENCIES = $(foreach f, $(OBJS), $(addprefix $(dir $(f))., $(patsubst %.o, %.d, $(notdir $(f)))))

# Macros for timing compilation
# ------------------------------------------------------------------------------

ifeq ($(UNAME_S), Darwin)
	CUR_TIME = awk 'BEGIN{srand(); print srand()}'
	TIME_FILE = $(dir $@).$(notdir $@)_time
	START_TIME = $(CUR_TIME) > $(TIME_FILE)
	END_TIME = read st < $(TIME_FILE) ; \
		$(RM) $(TIME_FILE) ; \
		st=$$((`$(CUR_TIME)` - $$st)) ; \
		echo $$st
else
	TIME_FILE = $(dir $@).$(notdir $@)_time
	START_TIME = date '+%s' > $(TIME_FILE)
	END_TIME = read st < $(TIME_FILE) ; \
		$(RM) $(TIME_FILE) ; \
		st=$$((`date '+%s'` - $$st - 86400)) ; \
		echo `date -u -d @$$st '+%H:%M:%S'`
endif

# Macros for versioning
# ------------------------------------------------------------------------------

ifndef USE_VERSION
	USE_VERSION = false
endif

# If this isn't a git repo or the repo has no tags, git describe will return non-zero
ifeq ($(shell git describe > /dev/null 2>&1 ; echo $$?), 0)
USE_VERSION := true

DESCRIBE           := $(shell git describe --match "v*" --always --tags)
STATUS             := $(shell git status --porcelain | grep " M ")
DESCRIBE_PARTS     := $(subst -, ,$(DESCRIBE))

VERSION_TAG        := $(word 1,$(DESCRIBE_PARTS))
COMMITS_SINCE_TAG  := $(word 2,$(DESCRIBE_PARTS))

VERSION            := $(subst v,,$(VERSION_TAG))
VERSION_PARTS      := $(subst ., ,$(VERSION))

MAJOR              := $(word 1,$(VERSION_PARTS))
MINOR              := $(word 2,$(VERSION_PARTS))
MICRO              := $(word 3,$(VERSION_PARTS))

NEXT_MAJOR         := $(shell echo $$(($(MAJOR)+1)))
NEXT_MINOR         := $(shell echo $$(($(MINOR)+1)))
NEXT_MICRO          = $(shell echo $$(($(MICRO)+$(COMMITS_SINCE_TAG))))

IS_DIRTY           := $(strip $(COMMITS_SINCE_TAG))$(STATUS)

ifeq ($(IS_DIRTY),)
CURRENT_VERSION_MICRO := $(MAJOR).$(MINOR).$(MICRO)
CURRENT_VERSION_MINOR := $(CURRENT_VERSION_MICRO)
CURRENT_VERSION_MAJOR := $(CURRENT_VERSION_MICRO)
else
CURRENT_VERSION_MICRO := $(MAJOR).$(MINOR).$(NEXT_MICRO)
CURRENT_VERSION_MINOR := $(MAJOR).$(NEXT_MINOR).0
CURRENT_VERSION_MAJOR := $(NEXT_MAJOR).0.0
endif

DATE                = $(shell date +'%d.%m.%Y')
TIME                = $(shell date +'%H:%M:%S')
COMMIT             := $(shell git rev-parse HEAD)
AUTHOR             := $(firstword $(subst @, ,$(shell git show --format="%aE" $(COMMIT))))
BRANCH_NAME        := $(shell git rev-parse --abbrev-ref HEAD)

TAG_MESSAGE         = "$(TIME) $(DATE) $(AUTHOR) $(BRANCH_NAME)"
COMMIT_MESSAGE     := $(shell git log --format=%B -n 1 $(COMMIT))

ifneq ($(BRANCH_NAME), main)
CURRENT_VERSION := $(CURRENT_VERSION_MICRO)-$(BRANCH_NAME)
else ifneq ($(IS_DIRTY),)
CURRENT_VERSION := $(CURRENT_VERSION_MICRO)-develop
else
CURRENT_VERSION := $(CURRENT_VERSION_MICRO)
endif

endif

# --- Version commands ---

.PHONY: version
version:
	@$(MAKE) version-micro

.PHONY: version-micro
version-micro:
	@echo "$(CURRENT_VERSION_MICRO)"

.PHONY: version-minor
version-minor:
	@echo "$(CURRENT_VERSION_MINOR)"

.PHONY: version-major
version-major:
	@echo "$(CURRENT_VERSION_MAJOR)"

# -- Meta info ---

.PHONY: tag-message
tag-message:
	@echo "$(TAG_MESSAGE)"

.PHONY: commit-message
commit-message:
	@echo "$(COMMIT_MESSAGE)"

# Standard, non-optimized release build
# ------------------------------------------------------------------------------

.PHONY: release
release: dirs
ifeq ($(USE_VERSION), true)
	@echo "Beginning release build v$(CURRENT_VERSION)"
else
	@echo "Beginning release build"
endif
	@$(START_TIME)
	@$(MAKE) all --no-print-directory
	@echo -n "Total build time: "
	@$(END_TIME)

# Debug build for gdb debugging
# ------------------------------------------------------------------------------

.PHONY: debug
debug: dirs
ifeq ($(USE_VERSION), true)
	@echo "Beginning debug build v$(CURRENT_VERSION)"
else
	@echo "Beginning debug build"
endif
	@$(START_TIME)
	@$(MAKE) all --no-print-directory
	@echo -n "Total build time: "
	@$(END_TIME)

# Create the directories used in the build
# ------------------------------------------------------------------------------

.PHONY: dirs
dirs:
	@echo "Creating directories"
	@mkdir -p $(dir $(OBJECTS))
	@mkdir -p $(BIN_PATH)

# Installs the program to the set destination
# ------------------------------------------------------------------------------

.PHONY: install
install:
	@echo "Installing to $(DEST_DIR)$(INSTALL_PREFIX)/bin"
	@$(INSTALL_PROGRAM) $(BIN_PATH)/$(PROGRAM) $(DEST_DIR)$(INSTALL_PREFIX)/bin

# Uninstalls the program
# ------------------------------------------------------------------------------

.PHONY: uninstall
uninstall:
	@echo "Removing $(DEST_DIR)$(INSTALL_PREFIX)/bin/$(PROGRAM)"
	@$(RM) $(DEST_DIR)$(INSTALL_PREFIX)/bin/$(PROGRAM)

# Removes all build files
# ------------------------------------------------------------------------------

.PHONY: clean
clean:
	@echo "Deleting $(PROGRAM) symlink"
	@$(RM) $(PROGRAM)
	@echo "Deleting directories"
	@$(RM) -r build
	@$(RM) -r bin

# Main rule, checks the executable and symlinks to the output
# ------------------------------------------------------------------------------

all: $(BIN_PATH)/$(PROGRAM)
	@echo "Making symlink: $(PROGRAM) -> $<"
	@$(RM) $(PROGRAM)
	@ln -s $(BIN_PATH)/$(PROGRAM) $(PROGRAM)
	@echo "Type ./$(PROGRAM) to execute the program."

# Link the executable
# ------------------------------------------------------------------------------

$(BIN_PATH)/$(PROGRAM): $(OBJECTS)
	@echo "Linking: $@"
	@$(START_TIME)
	$(CMD_PREFIX)$(CC) $(OBJECTS) $(LDFLAGS) -o $@
	@echo -en "\t Link time: "
	@$(END_TIME)

# Add dependency files, if they exist
-include $(DEPENDENCIES)

# Source file rules
# After the first compilation they will be joined with the rules from the
# dependency files to provide header dependencies
# ------------------------------------------------------------------------------

$(BUILD_PATH)/%.o: $(SRC_DIRS)/%$(SRC_EXTS)
	@echo "Compiling: $< -> $@"
	@$(START_TIME)
	$(CMD_PREFIX)$(CC) $(CFLAGS) $(INCLUDES) -MP -MMD -c $< -o $@
	@echo -en "\t Compile time: "
	@$(END_TIME)

# Show help message
# ------------------------------------------------------------------------------

HELP_TEXT = Usage: make [TARGET]\n\
	Available targets:\n\
	all            - build with default configuration\n\
	clean          - remove compiled objects and the executable\n\
	commit-message - display the commit message of a commit\n\
					 (if the source directory is a git repo)\n\
	debug          - perform a debug build\n\
	dirs           - create the necessary directories\n\
	help           - print this message\n\
	install        - install a published executable\n\
	release        - perform a standard release build for publishing\n\
	show           - show variables (for debug use only)\n\
	tag-message    - show the time and author of a commit\n\
					 (if the source directory is a git repo)\n\
	uninstall      - uninstall the installed executable\n\
	version        - display the version number of the current build\n\

.PHONY: help
help:
	@echo $(HELP_TEXT)

# Show variables. Meant for debug use
# ------------------------------------------------------------------------------

SHOW_VARIABLES = Displaying build variables...\n\
	PROGRAM         : $(PROGRAM)\n\
	VERSION         : $(CURRENT_VERSION_MICRO)\n\
	COMPILER        : $(CC)\n\
	COMPILE_FLAGS   : $(CC_FLAGS)\n\
	LINK_FLAGS      : $(LD_FLAGS)\n\
	SRC_DIRS        : $(SRC_DIRS)\n\
	SOURCES         : $(SOURCES)\n\
	OBJECTS         : $(OBJECTS)\n\
	DEPENDENCIES    : $(DEPENDENCIES)\n\
	PKG_CONFIG_LIBS : $(PKG_CONFIG_LIBS)\n\

.PHONY: show
show:
	@echo $(SHOW_VARIABLES)