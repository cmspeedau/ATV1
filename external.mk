include $(sort $(wildcard $(BR2_EXTERNAL_ATV1_PATH)/package/*/*.mk))

# genimage 9 (this era's) shell-execs tools that its own genimage.mk
# never declares — enumerated from genimage 9's source (execl strings):
# mkdosfs+mcopy+mmd (dosfstools/mtools), genext2fs for ext content
# images, tune2fs for ext labels. Era genimage.mk depends only on
# pkgconf+libconfuse, so the rest is appended here (+= survives: this
# file is included after package/Makefile.in; verified by make --eval).
# CAUTION learned the hard way: this era only INSTANTIATES a package's
# rules when its .config symbol is enabled — a dependency on a package
# nobody selected is a phantom. Hence genext2fs is also selected in the
# defconfig, and tools/container-build.sh prebuilds all four host tools
# explicitly before the main make.
HOST_GENIMAGE_DEPENDENCIES += host-genext2fs host-e2fsprogs
