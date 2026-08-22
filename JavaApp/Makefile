# Prerequisite variables
SOURCEDIR := src
OUTPUTDIR := build

SOURCES := $(shell find $(SOURCEDIR) -type f -name '*.java' ! -path '$(SOURCEDIR)/lwjgl341_patch/*')
CLASSES := $(SOURCES:$(SOURCEDIR)/%.java=$(OUTPUTDIR)/%.class)
LWJGL341_PATCH_SOURCES := $(shell find $(SOURCEDIR)/lwjgl341_patch -type f -name '*.java' 2>/dev/null)
LWJGL341_PATCH_CLASSES := $(LWJGL341_PATCH_SOURCES:$(SOURCEDIR)/lwjgl341_patch/%.java=$(OUTPUTDIR)/lwjgl341_patch/%.class)
LWJGL_LIBS := $(wildcard libs/lwjgl/*.jar) $(wildcard libs/lwjgl341/*.jar)

TARGETS := $(shell find $(SOURCEDIR) -mindepth 1 -maxdepth 1 -type d ! -name 'lwjgl341_patch')
TARGETS := $(TARGETS:$(SOURCEDIR)/%=$(OUTPUTDIR)/%.jar)

# Add all jars to classpath and allow compiling with private API
JCFLAGS := -cp "$(subst $() $(),:,$(wildcard $(SOURCEDIR)/*/):$(wildcard libs/*/*.jar))" -XDignore.symbol.file

all: $(TARGETS) $(OUTPUTDIR)/lwjgl341.jar
	
# Sometimes the CI produces empty class file resulting in broken jar, so we check and abort here
check_empty_classes:
	@set -e
	@echo "Checking for empty class files"
	$(eval EMPTY_CLASSES := $(shell find $(OUTPUTDIR) -name '*.class' -size 0))
	@if [ -n "$(EMPTY_CLASSES)" ]; then \
		echo "Error: found empty class files in $@: $(EMPTY_CLASSES)"; \
		exit 1; \
	fi

# Rules for building java class
$(CLASSES): $(OUTPUTDIR)/%.class: $(SOURCEDIR)/%.java
	@set -e
	$(eval TARGET=$(word 2, $(subst /, ,$@)))
	@mkdir -p $(OUTPUTDIR)/classes
	@mkdir -p $(dir $@)
	@echo "Compiling $<"
	@$(BOOTJDK)/javac $(JCFLAGS) -d $(OUTPUTDIR)/classes $<
	@destination="$(dir $@)"; \
	 mkdir -p "$$destination"; \
	 for class_file in $(@:$(OUTPUTDIR)/$(TARGET)/%.class=$(OUTPUTDIR)/classes/%*.class); do \
		cp "$$class_file" "$$destination"; \
	 done

$(LWJGL341_PATCH_CLASSES): $(OUTPUTDIR)/lwjgl341_patch/%.class: $(SOURCEDIR)/lwjgl341_patch/%.java
	@set -e
	@mkdir -p $(OUTPUTDIR)/lwjgl341_patch
	@echo "Compiling LWJGL 3.4.1 compatibility patch $<"
	@$(BOOTJDK)/javac -cp "$(subst $() $(),:,$(wildcard libs/lwjgl341/*.jar))" -d $(OUTPUTDIR)/lwjgl341_patch $<

$(OUTPUTDIR)/launcher.jar: $(CLASSES) check_empty_classes
	@set -e
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cf $@ -C $(basename $@) .

$(OUTPUTDIR)/lwjgl.jar: $(CLASSES) $(wildcard libs/lwjgl/*.jar) check_empty_classes
	@set -e
	@echo "Creating $@"
	@rm -rf $(OUTPUTDIR)/lwjgl_lib
	@mkdir -p $(OUTPUTDIR)/lwjgl_lib
	@cd $(OUTPUTDIR)/lwjgl_lib && find ../../libs/lwjgl -name 'lwjgl*.jar' -exec $(BOOTJDK)/jar -xf {} \; && rm -rf META-INF
	# The shared iOS GLFW bridge exposes the 3.4 IME callbacks so new Minecraft
	# can link against them. Keep those nine pure-Java callback types in the
	# 3.3 bundle too; otherwise merely reflecting GLFW's fields makes 1.21.x
	# fail class initialization with GLFWPreeditCallbackI missing.
	@rm -rf $(OUTPUTDIR)/lwjgl_ime_compat
	@mkdir -p $(OUTPUTDIR)/lwjgl_ime_compat
	@cd $(OUTPUTDIR)/lwjgl_ime_compat && $(BOOTJDK)/jar -xf ../../libs/lwjgl341/lwjgl-glfw.jar
	@cp $(OUTPUTDIR)/lwjgl_ime_compat/org/lwjgl/glfw/GLFWPreedit*.class $(OUTPUTDIR)/lwjgl_lib/org/lwjgl/glfw/
	@cp $(OUTPUTDIR)/lwjgl_ime_compat/org/lwjgl/glfw/GLFWIMEStatus*.class $(OUTPUTDIR)/lwjgl_lib/org/lwjgl/glfw/
	@cp -R $(OUTPUTDIR)/lwjgl/* $(OUTPUTDIR)/lwjgl_lib/
	@$(BOOTJDK)/jar -cf $@ -C $(OUTPUTDIR)/lwjgl_lib .

$(OUTPUTDIR)/lwjgl341.jar: $(CLASSES) $(LWJGL341_PATCH_CLASSES) $(LWJGL_LIBS) check_empty_classes
	@set -e
	@echo "Creating $@"
	@rm -rf $(OUTPUTDIR)/lwjgl341_lib
	@mkdir -p $(OUTPUTDIR)/lwjgl341_lib
	@cd $(OUTPUTDIR)/lwjgl341_lib && find ../../libs/lwjgl -name 'lwjgl*.jar' -exec $(BOOTJDK)/jar -xf {} \; && rm -rf META-INF
	@cd $(OUTPUTDIR)/lwjgl341_lib && find ../../libs/lwjgl341 -name 'lwjgl*.jar' -exec $(BOOTJDK)/jar -xf {} \; && rm -rf META-INF
	@cp -R $(OUTPUTDIR)/lwjgl/* $(OUTPUTDIR)/lwjgl341_lib/
	@cp -R $(OUTPUTDIR)/lwjgl341_patch/* $(OUTPUTDIR)/lwjgl341_lib/
	@$(BOOTJDK)/jar -cf $@ -C $(OUTPUTDIR)/lwjgl341_lib .

$(OUTPUTDIR)/patchjna_agent.jar: $(CLASSES)
	@set -e
	@mv $(basename $@)/com/sun/jna/Platform.class $(basename $@)/com/sun/jna/Platform.class.patch
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cfm $@ $(SOURCEDIR)/patchjna_agent.txt -C $(basename $@) .

clean:
	rm -rf $(OUTPUTDIR)

.SUFFIXES: .java
.PHONY: all clean
