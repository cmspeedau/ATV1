include $(sort $(wildcard $(BR2_EXTERNAL_ATV1_PATH)/package/*/*.mk))

# genimage 9 (this era's) shell-execs tools that its own genimage.mk
# never declares — enumerated from genimage 9's source (execl strings):
# mkdosfs+mcopy+mmd (dosfstools/mtools, already in defconfig as host
# selects it needs... which IT does not have either), genext2fs for ext
# content images, tune2fs for ext labels. Buildroot's era genimage.mk
# depends only on pkgconf+libconfuse, so wire the rest here; this file
# is included AFTER package/Makefile.in (Makefile:512), so += survives.
# Verified by 'make --eval' printing the final HOST_GENIMAGE_DEPENDENCIES.
HOST_GENIMAGE_DEPENDENCIES += host-genext2fs host-e2fsprogs
